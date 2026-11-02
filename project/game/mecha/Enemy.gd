extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")
const SOUND_LIFETIME = 25
const BODY_LIFETIME = 35

# Stuck watchdog, the last resort after the unstick moves in the steering
# section. stuck_timer counts while the NPC wants to move but either barely
# moves or makes no progress (_steer_blocked).
#  1. Soft reset (STUCK_RESET_TIME): clear going_to_position so the behaviour
#     picks a fresh target on the next tick.
#  2. Hard relocate (STUCK_RELOCATE_TIME): if it is STILL stuck and off
#     screen, ask the host scene for a safe position and teleport there.
#     Catches NPCs that ended up outside the navmesh. An NPC the player can
#     see is never teleported; it keeps trying to unstick instead.
const STUCK_VELOCITY_THRESHOLD := 50.0
const STUCK_RESET_TIME := 8.0
const STUCK_RELOCATE_TIME := 15.0
## An NPC within this distance (px) of the camera's view counts as on screen.
const ON_SCREEN_MARGIN := 400.0
const SCRIPTED_THROTTLE_TIME := 0.6
var stuck_timer: float = 0.0

var wait_for_map_sync = .1

# World-space direction the NPC is steering in (see Context Steering).
var chosen_dir = Vector2()

var going_to_position = false
var logic
var engage_distance = 2000 #How far to see other mechas
var senses = {
	"sounds": [],
	"bodies": [],
}
var valid_target = false
var current_target = false
var is_locking = false
var most_recent_attacker = false
var last_attack_position = false
var under_fire_timer = 0.0
var personality: Personality = null
var preferred_combat_range: float = 2000.0
var combat_style: String = "balanced"
var combat_behaviour: String = "default"
# Target leading. compute_lead_point() aims ahead of a moving target using the
# average muzzle speed of the equipped direct-fire weapons, scaled by this
# NPC's skill. ai_aim_point is set per-frame by the combat behaviour and read
# by navigate_to_target for weapon/body rotation; null = aim at the target.
var ai_aim_point = null
var scripted := false
var scripted_destination = null
var scripted_aim = null
var ai_projectile_speed := 0.0    # avg direct-fire muzzle speed (0 = don't lead)
var ai_lead_accuracy := 0.55      # 0 = aim at current pos, 1 = perfect intercept
var relationships = {}  # { mecha_ref: { "hostility": float, "is_traitor": bool } }


func _ready():
	super()

	steering_setup()

	logic = LOGIC.new()
	if Debug.get_setting("ai_behaviour"):
		logic.setup(Debug.get_setting("ai_behaviour"))
	else:
		logic.setup(combat_behaviour)
		
	if Debug.get_setting("draw_debug_lines"):
		$NavigationAgent2D.debug_enabled = true
	else:
		$NavigationAgent2D.debug_enabled = false
	


func _physics_process(dt):
	if paused:
		return
	
	if is_dead:
		return
	
	super(dt)
	
	if is_stunned():
		return
	
	# Thinking LOD: see is_thinking_frame(). think_dt is the game time since
	# the last thinking frame.
	_think_dt += dt
	var thinking := scripted or is_thinking_frame()
	var think_dt := _think_dt
	if thinking:
		_think_dt = 0.0

	if not scripted and thinking:
		update_senses(think_dt)

	wait_for_map_sync = max(wait_for_map_sync - dt, 0)
	if scripted:
		_drive_scripted(dt)
	elif not wait_for_map_sync and not is_dead:
		if thinking:
			# Fresh each think; the combat behaviour re-sets it while engaging.
			ai_aim_point = null
			var before := global_position
			logic.update(self)
			logic.run(self, think_dt)
			_coast_velocity = velocity if global_position != before else Vector2.ZERO
		elif _coast_velocity != Vector2.ZERO:
			# Between thinking frames, keep going the way it was going.
			move(_coast_velocity)

	# Stuck watchdog. Only fires when the NPC is actively trying to reach a
	# position (going_to_position == true) but stays near still or makes no
	# progress. NPCs that are still on purpose (alert/ambush/observing) don't
	# set going_to_position, and NPCs in a fight move slowly on purpose
	# (turning tanks, holding range), so neither is reset or teleported.
	if not scripted and going_to_position and not _combat_target() \
			and (velocity.length() < STUCK_VELOCITY_THRESHOLD or _steer_blocked):
		stuck_timer += dt
		# Tier 1: soft reset — clear going_to_position so behaviour re-targets.
		# If the behaviour re-sets it next tick and we still don't move, the
		# timer keeps climbing toward Tier 2.
		if stuck_timer >= STUCK_RESET_TIME and stuck_timer < STUCK_RELOCATE_TIME:
			going_to_position = false
		# Tier 2: hard relocate, off screen only.
		elif stuck_timer >= STUCK_RELOCATE_TIME:
			if is_on_screen():
				stuck_timer = STUCK_RESET_TIME
			else:
				if arena and arena.has_method("get_safe_position"):
					push_warning("[Enemy] " + mecha_name + " hard-relocated after being stuck for " + str(STUCK_RELOCATE_TIME) + "s")
					global_position = arena.get_safe_position()
					if has_node("NavigationAgent2D"):
						$NavigationAgent2D.target_position = global_position
				going_to_position = false
				valid_target = false
				stuck_timer = 0.0
				_reset_unstick()
	else:
		stuck_timer = 0.0
		if not going_to_position:
			_steer_blocked = false

	if is_locking:
		update_enemy_locking(dt, valid_target)
		
	if Debug.get_setting("enemy_state"):
		var state = logic.get_current_state()
		$Debug/StateLabel.text = str(state) if state else "?"
		$Debug/StateLabel.visible = true
	else:
		$Debug/StateLabel.visible = false
	
	under_fire_timer = max(under_fire_timer - dt, 0)


# Debug overlay (Debug setting "draw_debug_lines"): per slot, hard danger in
# red and soft cost in orange, the desired heading in grey, the steering
# direction in white, an active unstick direction in cyan and the rest of the
# planned route in green.
func _draw():
	if not Debug.get_setting("draw_debug_lines") or _steer_hard.is_empty():
		return
	var back := -global_rotation
	for i in STEER_SLOTS:
		var d: Vector2 = _slot_dirs[i].rotated(back)
		var inner := d * _steer_self_radius
		if _steer_hard[i] > 0.0:
			draw_line(inner, inner + d * _steer_range * _steer_hard[i], Color.RED, 6.0)
		if _steer_soft[i] > 0.0:
			draw_line(inner, inner + d * _steer_range * minf(_steer_soft[i], 1.0), Color.ORANGE, 3.0)
	draw_line(Vector2.ZERO, _steer_desired.rotated(back) * 400.0, Color.DARK_GRAY, 4.0)
	draw_line(Vector2.ZERO, chosen_dir.rotated(back) * 500.0, Color.WHITE, 5.0)
	if _unstick_time > 0.0:
		draw_line(Vector2.ZERO, _unstick_dir.rotated(back) * 300.0, Color.CYAN, 4.0)
	if not _route.is_empty():
		var line := PackedVector2Array([Vector2.ZERO])
		for k in range(_route_index, _route.size()):
			line.append(to_local(_route[k]))
		draw_polyline(line, Color.GREEN, 4.0)


func setup(arena_ref, design_data, _name):
	arena = arena_ref
	if _name and typeof(_name) == TYPE_STRING:
		mecha_name = _name
	else:
		mecha_name = "Mecha " + str(randi()%2000)

	set_parts_from_design(design_data)

	if design_data.has("personality") and design_data["personality"] is Personality:
		personality = design_data["personality"]
	if personality == null:
		personality = Personality.new()

	if design_data.has("combat_behaviour") and typeof(design_data["combat_behaviour"]) == TYPE_STRING:
		var new_behaviour = design_data["combat_behaviour"]
		# _ready() already set up logic with the fallback since add_child() fires
		# before setup(). Only rebuild when the design actually names a different
		# behaviour and no Debug override is forcing one — avoids a wasted second
		# setup() (and AI-chain alloc) for the common "default" case.
		if new_behaviour != combat_behaviour and not Debug.get_setting("ai_behaviour"):
			logic.setup(new_behaviour)
		combat_behaviour = new_behaviour

	_analyze_build()


func _analyze_build():
	var ranges := []
	for weapon_key in ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]:
		var weapon = build[weapon_key]
		if weapon == null:
			continue
		var r = weapon.get("ai_engage_range")
		if r != null and r > 0:
			ranges.append(r)

	if ranges.size() > 0:
		var total := 0.0
		for r in ranges:
			total += r
		preferred_combat_range = total / ranges.size()

	# Determine style from range
	if preferred_combat_range >= 3000:
		combat_style = "sniper"
	elif preferred_combat_range <= 1300:
		combat_style = "brawler"
	else:
		combat_style = "balanced"

	# Override: if any weapon is indirect fire, go artillery
	for weapon_key in ["shoulder_weapon_left", "shoulder_weapon_right"]:
		var weapon = build[weapon_key]
		if weapon and weapon.get("is_indirect_fire"):
			combat_style = "artillery"
			break

	# Cache leading data: average direct-fire muzzle speed + a skill factor.
	# combat_style is finalized above, so accuracy can key off it.
	var speeds := []
	for weapon_key in ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]:
		var ms = _read_muzzle_speed(build[weapon_key])
		if ms > 0.0:
			speeds.append(ms)
	if speeds.size() > 0:
		var total := 0.0
		for s in speeds:
			total += s
		ai_projectile_speed = total / speeds.size()
	ai_lead_accuracy = _compute_lead_accuracy()


# Reads a projectile scene's muzzle_speed without side effects: instantiate()
# builds the node but does not run _ready/_physics_process, so we can read the
# exported default and free it immediately. Returns 0 for melee / indirect /
# speed-less projectiles, which disables leading for that weapon.
func _read_muzzle_speed(weapon) -> float:
	if weapon == null or weapon.is_melee or weapon.get("is_indirect_fire"):
		return 0.0
	var scene = weapon.get("projectile")
	if scene == null or not (scene is PackedScene):
		return 0.0
	var inst = scene.instantiate()
	var ms = inst.get("muzzle_speed")
	inst.free()
	if ms == null:
		return 0.0
	return float(ms)


# How well this NPC leads a moving target. Sharpshooter styles and disciplined
# personalities lead cleanly; brawlers barely bother.
func _compute_lead_accuracy() -> float:
	var acc := 0.55
	match combat_style:
		"sniper": acc = 0.95
		"brawler": acc = 0.4
		"artillery": acc = 0.5
	if personality:
		match personality.type:
			Personality.Type.PROFESSIONAL: acc += 0.2
			Personality.Type.HUNTER: acc += 0.1
	return clampf(acc, 0.0, 1.0)


func get_relationship(target) -> Dictionary:
	if relationships.has(target):
		return relationships[target]
	return { "hostility": 0.0, "is_traitor": false }


func add_hostility(target, amount: float):
	if not relationships.has(target):
		relationships[target] = { "hostility": 0.0, "is_traitor": false }
	relationships[target].hostility = clampf(relationships[target].hostility + amount, 0.0, 1.0)


func mark_traitor(target):
	if not relationships.has(target):
		relationships[target] = { "hostility": 0.0, "is_traitor": false }
	relationships[target].hostility = 1.0
	relationships[target].is_traitor = true


# Seeds an initial-sight relationship with personality-driven baseline hostility,
# so NPC factions naturally clash without being provoked first. No-op if the
# relationship already exists (preserves combat history).
func _seed_relationship(target):
	if relationships.has(target):
		return
	if not is_instance_valid(target) or target == self:
		return
	# Player gets no seeded hostility — they earn it by shooting first.
	if target.has_method("is_player") and target.is_player():
		relationships[target] = { "hostility": 0.0, "is_traitor": false }
		return
	# NPC-to-NPC: target needs a personality for the matrix lookup.
	if not (target.get("personality") is Personality):
		relationships[target] = { "hostility": 0.0, "is_traitor": false }
		return

	var base = _initial_hostility_toward(target.personality)
	# Small randf jitter so identical matchups don't all play out the same.
	var seeded = clampf(base + randf_range(-0.1, 0.1), 0.0, 1.0)
	relationships[target] = { "hostility": seeded, "is_traitor": false }


# Personality matchup matrix (self → other) for first-sight hostility.
# Asymmetric on purpose: a Hunter wants to hunt a Scavenger, but the Scavenger
# doesn't necessarily want to fight back. Same-type pairs are 0 (kin).
func _initial_hostility_toward(other_personality: Personality) -> float:
	var self_t = personality.type
	var other_t = other_personality.type
	if self_t == other_t:
		return 0.0  # kin recognition

	var T = Personality.Type
	match self_t:
		T.SCAVENGER:
			return 0.0  # passive — never picks fights
		T.GUARDIAN:
			match other_t:
				T.HUNTER: return 0.2  # wild and unpredictable
				T.RAT: return 0.5     # cleanse the vermin
				_: return 0.0
		T.PROFESSIONAL:
			match other_t:
				T.RAT: return 0.1     # mild distaste
				_: return 0.0
		T.HUNTER:
			match other_t:
				T.SCAVENGER: return 0.3  # easy prey
				T.GUARDIAN: return 0.2
				T.PROFESSIONAL: return 0.2
				T.RAT: return 0.4
				_: return 0.0
		T.RAT:
			match other_t:
				T.SCAVENGER: return 0.4  # easy prey
				T.PROFESSIONAL: return 0.1
				_: return 0.0
		_:
			return 0.0


func should_attack(target) -> bool:
	if not is_instance_valid(target):
		return false

	var rel = get_relationship(target)

	# Always attack traitors — they flagged then shot us
	if rel.is_traitor:
		return true

	# Target is flagged/exposed — personality decides
	if target.is_exposed:
		# Betrayal tendency: high treachery + low loyalty = more willing to break the code.
		# Range 0.0 (never betray) to 1.0 (always betray).
		var betrayal = clampf(personality.treachery - personality.loyalty, 0.0, 1.0)

		match personality.type:
			Personality.Type.RAT:
				return true  # identity trait — always opportunistic
			Personality.Type.HUNTER:
				# Normally needs provocation; betrayal lowers the bar.
				return rel.hostility > (0.3 - betrayal * 0.3)
			Personality.Type.SCAVENGER:
				# Normally avoids; only a very treacherous scavenger betrays.
				return betrayal > 0.7
			Personality.Type.GUARDIAN:
				# Respects flags by default; loyalty holds them back.
				# A disloyal guardian (low loyalty, some treachery) can break the code.
				return betrayal > 0.8
			Personality.Type.PROFESSIONAL:
				# Normally needs clear hostility; betrayal makes them more opportunistic.
				return rel.hostility > (0.5 - betrayal * 0.4)
			_:
				return betrayal > 0.8  # unknown type — respect flag unless very treacherous

	# Not flagged — normal engagement rules
	return should_engage(target)


func should_engage(target: Mecha) -> bool:
	if not is_instance_valid(target):
		return false

	var my_threat = estimate_threat_level()
	var their_threat = target.estimate_threat_level()
	var difference = their_threat - my_threat  # positive = they're stronger

	# Courage determines how much stronger the target can be before we bail
	# courage 0.0 -> only fight if we're stronger (difference < 0)
	# courage 0.5 -> fight if roughly even (difference < 0.25)
	# courage 1.0 -> fight anyone (difference < 0.5)
	var threshold = personality.courage * 0.5

	# Aggression shifts the threshold further
	threshold += personality.aggression * 0.2

	# Greed: a weakened target looks like an easy kill / easy loot.
	# Weakness 0.0 (full hp) contributes nothing; weakness 1.0 (near dead) gives full greed bonus.
	if target.max_hp > 0:
		var weakness = clampf(1.0 - (float(target.hp) / float(target.max_hp)), 0.0, 1.0)
		threshold += personality.greed * weakness * 0.3

	# Hostility: seeded personality grudges + accumulated provocations push us
	# toward engaging. 0.0 = no influence; 1.0 (provoked/traitor) = +0.3 threshold.
	var rel = get_relationship(target)
	threshold += rel.hostility * 0.3

	return difference < threshold


#AI METHODS

func heard_sound(sound_data):
	senses.sounds.append({
		"volume_type": sound_data.volume_type,
		"type": sound_data.type,
		"position": sound_data.position,
		"lifetime": SOUND_LIFETIME,
		"source": sound_data.source,
	})


func update_senses(dt):
	#Tick down sounds
	var to_remove = []
	for sound in senses.sounds:
		sound.lifetime -= dt
		if sound.lifetime <= 0:
			to_remove.append(sound)
	for sound in to_remove:
		senses.sounds.erase(sound)
	
	#Tick down unseen bodies
	to_remove = []
	for data in senses.bodies:
		if data.is_seen:
			data.is_seen = false
			data.lifetime = BODY_LIFETIME
		else:
			data.lifetime -= dt
			if data.lifetime <= 0:
				to_remove.append(data)
	for data in to_remove:
		senses.bodies.erase(data)
	
	#Check for nearby bodies
	var own_sight_mult = MapSenses.sight_mult(self)
	for target in arena.get_mechas():
		if target == self:
			continue
		var distance = position.distance_to(target.position)
		var thermal_range_mult = 1.0
		if target.has_method("get_thermal_signature"):
			# Cold targets detected at 60% range, hot targets at 140%
			thermal_range_mult = lerp(0.6, 1.4, target.get_thermal_signature())
		
		# Foliage over the target, or over us, shortens the range; building
		# walls block sight completely (see MapSenses). Cheapest checks first:
		# the foliage and wall checks only run for targets in range.
		var effective_engage_distance = engage_distance * thermal_range_mult * own_sight_mult
		if distance <= effective_engage_distance \
				and distance <= effective_engage_distance * MapSenses.detection_mult(target) \
				and not MapSenses.walls_between(get_world_2d(), global_position, target.global_position):
			var found = false
			for data in senses.bodies:
				if data.body == target:
					data.is_seen = true
					data.last_position = target.global_position
					found = true
					break
			if not found:
				senses.bodies.append({
					"body": target,
					"last_position": target.global_position,
					"is_seen": true,
					"lifetime": BODY_LIFETIME,
				})
				# First-time sight: seed personality-based hostility so factions
				# clash naturally instead of waiting to be provoked.
				_seed_relationship(target)
	

func get_most_recent_loud_noise():
	return get_recent_noise("volume_type", "loud")


func get_most_recent_quiet_noise():
	return get_recent_noise("volume_type", "quiet")


func get_recent_noise(var_type, var_value):
	var recent_noise = false
	var biggest_lifetime = -99999999
	for sound in senses.sounds:
		if sound[var_type] == var_value and sound.lifetime > biggest_lifetime:
			recent_noise = sound
			biggest_lifetime = sound.lifetime
	
	return recent_noise

#COMBAT METHODS

# Threat-based target selection. Candidates are still gated by
# should_attack (flag/traitor/personality code); the score only ranks
# among permissible targets. The under-fire bonus dominates proximity so
# someone actively shooting us displaces a passive duel partner.
const TARGET_SWITCH_MARGIN := 0.75       # challenger must beat current by this
const TARGET_SWITCH_COOLDOWN_MS := 1500  # min time between voluntary switches
const TARGET_REEVAL_INTERVAL_MS := 300   # rescan rate while already engaged
var _last_target_eval_ms := -100000
var _last_target_switch_ms := -100000


func _threat_score(target, distance, eng_distance) -> float:
	# Proximity: 1.0 point-blank, fading to 0.0 at engage range
	var score: float = clampf(1.0 - distance / max(eng_distance, 1.0), 0.0, 1.0)
	# Actively shooting us right now — dominant signal (fixes flanking blindness)
	if under_fire_timer > 0 and target == most_recent_attacker:
		score += 2.0
	# Accumulated grudge (0..1; built +0.25 per shot received, faction-seeded)
	score += get_relationship(target).hostility
	return score


func check_for_targets(eng_distance, max_shooting_distance):
	#Drop the current target if gone, dead, or out of range
	if valid_target and is_instance_valid(valid_target):
		if valid_target.is_dead or position.distance_to(valid_target.position) > max_shooting_distance:
			valid_target = false
	else:
		valid_target = false

	# While engaged, only rescan for better threats at an interval —
	# should_attack -> estimate_threat_level is too heavy for every frame.
	# When seeking (no target), scan every call, as before.
	var now = Time.get_ticks_msec()
	if valid_target and now - _last_target_eval_ms < TARGET_REEVAL_INTERVAL_MS:
		return
	_last_target_eval_ms = now

	#Find the highest-threat permissible target (mechas and Entities)
	var best = null
	var best_score := -1.0
	for target in arena.get_mechas() + _get_entities():
		if target == self or not is_instance_valid(target) or target.is_dead:
			continue
		var distance = position.distance_to(target.position)
		if distance > eng_distance:
			continue
		# Entities are monsters: always fair game, no flags or grudges.
		if not target.is_in_group("entity") and not should_attack(target):
			continue
		var score = _threat_score(target, distance, eng_distance)
		if score > best_score:
			best_score = score
			best = target

	if best == null:
		return

	if not valid_target:
		valid_target = best
		_last_target_switch_ms = now
	elif best != valid_target:
		# Switch only on a clear threat margin, rate-limited so two
		# attackers can't ping-pong our attention every rescan.
		var cur_score = _threat_score(valid_target, position.distance_to(valid_target.position), eng_distance)
		if best_score >= cur_score + TARGET_SWITCH_MARGIN \
				and now - _last_target_switch_ms >= TARGET_SWITCH_COOLDOWN_MS:
			valid_target = best
			_last_target_switch_ms = now


func _get_entities() -> Array:
	if arena and arena.has_method("get_entities"):
		return arena.get_entities()
	return []


# An Entity's bite or acid (EntityAttack): react as to being shot. Shots
# report themselves through _on_nearby_projectile_area_entered instead.
func on_attacked_by(attacker) -> void:
	if not is_instance_valid(attacker):
		return
	under_fire_timer = 0.5
	most_recent_attacker = attacker
	last_attack_position = attacker.global_position


func shoot_weapons(target):
	try_to_shoot("arm_weapon_left", target)
	try_to_shoot("arm_weapon_right", target)
	try_to_shoot("shoulder_weapon_left", target)
	try_to_shoot("shoulder_weapon_right", target)


func try_to_shoot(weapon_name, target):
	var node = get_weapon_part(weapon_name)
	if node:
		if node.can_reload() == "yes" and node.is_clip_empty() and not node.is_reloading():
			node.reload()
		elif node.can_shoot():
			if can_see_target(target):
				shoot(weapon_name)


func can_see_target(target):
	if target and is_instance_valid(target):
		var space_state = get_world_2d().direct_space_state
		# Vehicles don't block sight; building walls do.
		var ray = PhysicsRayQueryParameters2D.create(position, target.position, MapSenses.SIGHT_MASK)
		ray.exclude = [self]
		var result = space_state.intersect_ray(ray)
		if result:
			return (result.collider == target)
		return false
	return false


# Predicted intercept point for leading a moving target with our average
# projectile speed, scaled by this NPC's skill (ai_lead_accuracy). Falls back
# to the target's current position when we can't or shouldn't lead. Bullet drag
# is ignored, so this slightly over-leads slow/draggy rounds — acceptable.
func compute_lead_point(target) -> Vector2:
	if not is_instance_valid(target):
		return global_position
	var tpos = target.global_position
	if ai_projectile_speed <= 0.0 or ai_lead_accuracy <= 0.0:
		return tpos
	var tvel = Vector2.ZERO
	if "velocity" in target:
		tvel = target.velocity
	if tvel == Vector2.ZERO:
		return tpos
	# Iterative intercept — converges in a few steps.
	var t := 0.0
	for i in 3:
		t = global_position.distance_to(tpos + tvel * t) / ai_projectile_speed
	var full_lead = tpos + tvel * t
	return tpos + (full_lead - tpos) * ai_lead_accuracy


# Navigation

#Assumes enemy has a valid target
func random_targeting_pos(min_dist, max_dist):
	var rand_pos = Vector2()
	var angle = randf_range(0, 2.0*PI)
	var direction = Vector2(cos(angle), sin(angle)).normalized()
	var rand_radius = randf_range(min_dist, max_dist)
	rand_pos = valid_target.position + direction * rand_radius
	
	return rand_pos


func set_scripted(value: bool) -> void:
	scripted = value
	scripted_destination = null
	scripted_aim = null
	going_to_position = false
	stuck_timer = 0.0
	if value:
		paused = false
		valid_target = false
		current_target = false
		is_locking = false


func walk_to(point) -> void:
	scripted_destination = point


func stop_walking() -> void:
	scripted_destination = null
	going_to_position = false


func _drive_scripted(dt) -> void:
	ai_aim_point = scripted_aim
	if scripted_destination == null:
		going_to_position = false
		apply_movement(dt, Vector2.ZERO)
		if scripted_aim != null:
			apply_rotation_by_point(dt, scripted_aim, false)
		return
	NavAgent.target_position = scripted_destination
	going_to_position = true
	if throttle < 1.0:
		increase_throttle(false, dt / SCRIPTED_THROTTLE_TIME)
	navigate_to_target(dt)


func get_navigation_path():
	return NavAgent.get_nav_path()


func navigate_to_target(dt,direction:=0.0, wander := 0.0, sprint := false):
	#Forward when direction = 0, Backwards when direction = 1, 
	#Clockwise when direction = -0.5, Anticlockwise when direction = 0.5
	if going_to_position:
		var pos := global_position
		var goal: Vector2 = NavAgent.target_position
		# In a fight the NPC moves relative to its foe; otherwise it follows a
		# planned route on long trips (see Routes).
		var foe = _combat_target()
		var target: Vector2 = NavAgent.get_next_path_position() if foe else _route_next(goal, dt)
		var dir := (target - pos).normalized()
		var heading := dir.rotated(PI * direction)
		if foe and wander > 0.0:
			# Approach or back off at the angle `wander` gives (its dot product
			# with the straight line), on the side it has committed to: the
			# NPC circles its foe instead of moving on a line (see Orbit).
			heading = heading.rotated(_orbit_side * acos(clampf(wander, 0.0, 1.0)))
			set_interest(heading, 0.0)
		else:
			set_interest(heading, wander)
		# valid_target is either a mecha Object or the sentinel `false` —
		# truthiness check only; Object != bool is a runtime error in GDScript 4.
		var engaged: bool = true if valid_target else false
		var interval := STEER_NEAR_INTERVAL if engaged or is_near_player() else STEER_FAR_INTERVAL
		_update_car_burst(dt)
		var frame := Engine.get_physics_frames()
		if _steer_hard.is_empty() or frame - _steer_built_frame >= interval:
			_steer_built_frame = frame
			_build_context()
		_track_progress(dt, foe != null)
		choose_direction(dt)
		_update_orbit(dt, foe)
		var want_sprint := sprint or _car_burst_time > 0.0 or _cruise_sprint(goal, foe)
		if want_sprint:
			is_sprinting = true
		elif is_sprinting:
			stop_sprinting(chosen_dir)
		# Tanks steer by world direction; other chassis move relative to the
		# body, so they get the direction in the body's frame.
		var move_dir: Vector2 = chosen_dir if movement_type == "tank" else chosen_dir.rotated(-global_rotation)
		apply_movement(dt, move_dir)
		_update_dashes(dt, foe, direction)
		if ai_aim_point != null:
			apply_rotation_by_point(dt, ai_aim_point, false)
		elif valid_target and is_instance_valid(valid_target) and can_see_target(valid_target):
			apply_rotation_by_point(dt, valid_target.position, false)
		else:
			apply_rotation_by_point(dt, target, false)


func get_target_navigation_pos():
	if going_to_position:
		return NavAgent.get_final_location()
	return false

#Gets an randomly (uniformed) position within a circle
func get_random_point_on_radius(pos : Vector2, radius : float):
	var r = radius * sqrt(randf())
	var angle = 2*PI*randf()
	return Vector2(pos.x + r * cos(angle), pos.y + r * sin(angle))


func _on_NavigationAgent2D_navigation_finished():
	going_to_position = false


func _on_NavigationAgent2D_target_reached():
	going_to_position = false

#-------- Thinking LOD

# NPCs more than THINK_FULL_DISTANCE from the player update their senses and
# run their behaviour every FAR_THINK_INTERVAL physics frames, with the time
# since their last think as dt. In between they keep moving with their last
# velocity, so motion stays smooth; aiming, decisions and shooting wait for
# the next think. Near the player (on screen and round it) every frame thinks.
const THINK_FULL_DISTANCE := 4000.0
const FAR_THINK_INTERVAL := 3
var _think_offset := randi() % FAR_THINK_INTERVAL
var _think_dt := 0.0
var _coast_velocity := Vector2.ZERO


func is_near_player() -> bool:
	if arena == null or not ("player" in arena):
		return false
	var p = arena.player
	return p != null and is_instance_valid(p) \
		and global_position.distance_to(p.global_position) < THINK_FULL_DISTANCE


func is_thinking_frame() -> bool:
	return think_interval(is_near_player()) == 1 \
		or (Engine.get_physics_frames() + _think_offset) % FAR_THINK_INTERVAL == 0


static func think_interval(near_player: bool) -> int:
	return 1 if near_player else FAR_THINK_INTERVAL


# Whether the NPC is in or near the current camera's view.
func is_on_screen() -> bool:
	if not is_inside_tree():
		return false
	var vp := get_viewport()
	var view := vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return view.grow(ON_SCREEN_MARGIN).has_point(global_position)


#-------- Context Steering

# Each steering update fills a context map of STEER_SLOTS directions round
# the mecha:
#   interest  how well each direction leads where the behaviour wants to go
#             (the dot product with the desired heading)
#   hard      how close something the mecha must not walk into is that way
#             (1 = touching, 0 = beyond the look-ahead range)
#   soft      what it costs to go that way: pushing through a vehicle, or
#             walking through a building it doesn't need to enter
# Obstacles are projected onto every slot their outline covers, grown by the
# mecha's own radius, so a car between two slot directions still blocks the
# slots its body overlaps, and a gap narrower than the mecha stays shut.
#
# Sources (no physics rays on maps with a VehicleField and BuildingField):
#   - Vehicles, from the VehicleField. A vehicle is hard when pushing it
#     would leave this mecha less than HARD_PUSH_FRACTION of its speed, or
#     when it jammed (it didn't move when this NPC pushed it). Otherwise it is
#     soft, costing (1 - speed kept) * push_aversion(): light builds go round
#     cars, heavy builds push through them. A tank pays TRAMPLE_COST_MULT of
#     that for a vehicle it can drive over.
#   - Other mechas, hard, where they will be in MECHA_PREDICT_TIME s. The
#     mecha this NPC is fighting is left out.
#   - Buildings, from the BuildingField, soft (BUILDING_COST). Except the
#     building the NPC is in, the one its destination is in and the one its
#     target is in: those it means to go into.
#   - Any other static body (hand-made props, walls on older maps). One
#     shape query every STATIC_PROBE_INTERVAL frames looks for them; only
#     when one is near does each slot cast the mecha's circle along itself.
#     When the circle already touches one, only the directions into it
#     (against the contact normal) are blocked.
#
# Choosing: slots whose hard danger is more than HARD_TOLERANCE above the
# lowest are ruled out (with every way blocked, the least blocked wins).
# Each other slot scores interest - soft - hard * HARD_COST, plus
# COMMIT_BONUS for staying near the last choice and UNSTICK_BONUS toward an
# unstick direction (see Unstick). The best slot is refined between its
# neighbours, and chosen_dir turns toward it at no more than the turn rate,
# so the NPC picks a side round an obstacle and keeps it.
#
# The map is rebuilt every STEER_NEAR_INTERVAL physics frames near the
# player or when engaged, and every STEER_FAR_INTERVAL frames otherwise,
# staggered per NPC. The choice itself runs on every steering update.
const STEER_SLOTS := 24
## Look-ahead: this many seconds of travel at full speed, clamped.
## Vehicles are only looked for within VEHICLE_RANGE_MAX of that: they are
## many in a street, and a rebuild comes round before the NPC gets there.
const STEER_LOOK_TIME := 1.6
const STEER_RANGE_MIN := 500.0
const STEER_RANGE_MAX := 900.0
const VEHICLE_RANGE_MAX := 650.0
## Push mass and aversion follow the mecha's weight (cargo changes it); they
## are refreshed every this many physics frames.
const WEIGHT_REFRESH_INTERVAL := 120
## Clearance (px) kept between the mecha's outline and an obstacle.
const STEER_MARGIN := 20.0
## The mecha's own radius is its outline's furthest point times this.
const SELF_RADIUS_SCALE := 0.85
const STEER_NEAR_INTERVAL := 6
const STEER_FAR_INTERVAL := 30
const HARD_TOLERANCE := 0.3
const HARD_COST := 1.0
const COMMIT_BONUS := 0.15
## Turn rate (rad/s) of chosen_dir; tanks turn slower.
const STEER_TURN_RATE := 6.0
const STEER_TURN_RATE_TANK := 3.0
## Pushing a vehicle that would leave less than this fraction of the mecha's
## speed is not an option.
const HARD_PUSH_FRACTION := 0.35
## push_aversion() runs from MAX at AVERSION_LIGHT_WEIGHT down to MIN at
## AVERSION_HEAVY_WEIGHT.
const PUSH_AVERSION_MAX := 2.0
const PUSH_AVERSION_MIN := 0.7
const AVERSION_LIGHT_WEIGHT := 45.0
const AVERSION_HEAVY_WEIGHT := 80.0
const TRAMPLE_COST_MULT := 0.5
const BUILDING_COST := 0.55
const MECHA_PREDICT_TIME := 0.4
## Radius (px) assumed for another mecha.
const OTHER_MECHA_RADIUS := 110.0
## Seconds a jammed vehicle stays hard for this NPC.
const JAM_TIME := 4.0
const STATIC_PROBE_INTERVAL := 30
## Static bodies are found by casting a circle this fraction of the steering
## radius, so the NPC can pass close to a wall without already touching it.
const STATIC_CAST_SCALE := 0.8
const MARK_SOFT := 0
const MARK_HARD := 1
const MARK_CAR := 2
const STATIC_MASK := MapSenses.NON_WALL_MASK & ~MapSenses.VEHICLE_MASK

var _slot_dirs: Array[Vector2] = []
var _slot_angles := PackedFloat32Array()
var _steer_hard := PackedFloat32Array()
var _steer_soft := PackedFloat32Array()
# Per slot, how near a car is that way (0 = none in range).
var _steer_car := PackedFloat32Array()
var _steer_desired := Vector2.ZERO
var _steer_built_frame := -100000
var _steer_range := STEER_RANGE_MAX
var _steer_self_radius := 0.0
var _steer_last_choice := Vector2.ZERO
var _steer_pusher_mass := 0.0
var _steer_aversion := 1.0
var _steer_weight_frame := -100000
# Vehicle index -> Time.get_ticks_msec() until which it counts as jammed.
var _jammed := {}
var _static_probe_frame := -100000
var _static_near := false
var _static_exclude: Array[RID] = []
var _static_shape: CircleShape2D = null
var _vehicle_field: VehicleField = null
var _building_field: BuildingField = null


func steering_setup():
	_slot_dirs.clear()
	_slot_angles.resize(STEER_SLOTS)
	_steer_hard.resize(STEER_SLOTS)
	_steer_soft.resize(STEER_SLOTS)
	_steer_car.resize(STEER_SLOTS)
	_steer_hard.fill(0.0)
	_steer_soft.fill(0.0)
	_steer_car.fill(0.0)
	for i in STEER_SLOTS:
		var angle := i * TAU / STEER_SLOTS
		_slot_angles[i] = angle
		_slot_dirs.append(Vector2.from_angle(angle))
	# Spread map rebuilds so NPCs don't all rebuild on the same frame.
	_steer_built_frame = Engine.get_physics_frames() - randi() % STEER_NEAR_INTERVAL


# Sets the desired heading. `target` is a world direction (or a falsy value to
# keep facing forward). `wander` shapes the interest round it as a ring at
# that dot product; the heading is the interest-weighted sum, as before.
func set_interest(target, wander):
	var sum := Vector2.ZERO
	var goal: Vector2 = target if target else transform.y
	for i in STEER_SLOTS:
		var d := _slot_dirs[i].dot(goal)
		if target and wander != 0.0:
			d = 1.0 - absf(d - wander)
		sum += _slot_dirs[i] * maxf(0.0, d)
	_steer_desired = sum.normalized() if sum.length_squared() > 0.0001 else goal.normalized()


# How much this mecha minds pushing things, from its weight.
func push_aversion() -> float:
	var t := inverse_lerp(AVERSION_LIGHT_WEIGHT, AVERSION_HEAVY_WEIGHT, get_total_weight())
	return lerpf(PUSH_AVERSION_MAX, PUSH_AVERSION_MIN, clampf(t, 0.0, 1.0))


# Steering radius: most of the furthest point of the mecha's collision
# outline from its centre.
func get_steer_radius() -> float:
	if _steer_self_radius <= 0.0:
		var r := 0.0
		for c in get_children():
			if c is CollisionPolygon2D and not c.disabled:
				for p in c.polygon:
					r = maxf(r, (c.position + p * c.scale).length())
		_steer_self_radius = r * SELF_RADIUS_SCALE if r > 0.0 else 100.0
	return _steer_self_radius


func _build_context() -> void:
	_steer_hard.fill(0.0)
	_steer_soft.fill(0.0)
	_steer_car.fill(0.0)
	get_steer_radius()
	_steer_range = clampf(max_speed * STEER_LOOK_TIME, STEER_RANGE_MIN, STEER_RANGE_MAX)
	var frame := Engine.get_physics_frames()
	if frame - _steer_weight_frame >= WEIGHT_REFRESH_INTERVAL:
		_steer_weight_frame = frame
		_steer_pusher_mass = VehicleField.mecha_mass(self)
		_steer_aversion = push_aversion()
	if not is_instance_valid(_vehicle_field):
		_vehicle_field = VehicleField.find(self)
	if not is_instance_valid(_building_field):
		_building_field = BuildingField.find(self)
	if _vehicle_field:
		_add_vehicles()
	_add_mechas()
	if _building_field:
		_add_buildings()
	_add_static_bodies()
	if Debug.get_setting("draw_debug_lines"):
		queue_redraw()


func _add_vehicles() -> void:
	var pos := global_position
	var pusher := _steer_pusher_mass
	var aversion := _steer_aversion
	var tank: bool = movement_type == "tank"
	var now := Time.get_ticks_msec()
	var grow := _steer_self_radius + STEER_MARGIN
	var reach := minf(_steer_range, VEHICLE_RANGE_MAX)
	var max_mass := _vehicle_field.trample_max_mass
	# A sprinting mecha passes over cars (Mecha._update_car_collision).
	var over_cars: bool = is_sprinting
	# Cost per vehicle mass (the few sprite variants share a handful of
	# masses); -1 marks a vehicle that is hard for this mecha.
	var costs := {}
	var data := _vehicle_field.steering_obstacles(pos, reach + grow)
	var stride := VehicleField.STEER_STRIDE
	for k in range(0, data.size(), stride):
		var centre := Vector2(data[k], data[k + 1])
		var length := data[k + 3]
		var width := data[k + 4]
		var mass := data[k + 5]
		var index := int(data[k + 6])
		var car := mass <= max_mass
		if car and over_cars:
			continue
		var cost: float = costs.get(mass, -2.0)
		if cost == -2.0:
			var kept := VehicleField.push_speed_fraction(pusher, mass)
			if tank and mass <= max_mass:
				cost = (1.0 - kept) * aversion * TRAMPLE_COST_MULT
			elif kept < HARD_PUSH_FRACTION:
				cost = -1.0
			else:
				cost = (1.0 - kept) * aversion
			costs[mass] = cost
		var hard := cost < 0.0
		if not _jammed.is_empty() and now < int(_jammed.get(index, 0)):
			hard = true
		var dist := centre.distance_to(pos)
		if dist - length * 0.5 - grow > reach:
			continue
		if dist - length * 0.5 - grow > _steer_self_radius * 2.0:
			# Far off: one circle round the whole vehicle is close enough.
			_project_circle(centre, Vector2(length, width).length() * 0.5, hard, cost, car)
			continue
		# Close: the vehicle as one to three circles along its length.
		var n := clampi(roundi(length / maxf(width, 1.0)), 1, 3)
		var seg := length / n
		var r := Vector2(seg * 0.5, width * 0.5).length()
		var axis := Vector2.from_angle(data[k + 2])
		for c in n:
			_project_circle(centre + axis * (seg * (c + 0.5) - length * 0.5), r, hard, cost, car)


func _add_mechas() -> void:
	if arena == null or not arena.has_method("get_mechas"):
		return
	var pos := global_position
	var reach := _steer_range + _steer_self_radius + OTHER_MECHA_RADIUS
	for m in arena.get_mechas():
		if m == self or not is_instance_valid(m) or m.is_dead:
			continue
		if is_same(m, valid_target) or is_same(m, current_target):
			continue
		var at: Vector2 = m.global_position + m.velocity * MECHA_PREDICT_TIME
		if at.distance_squared_to(pos) > reach * reach:
			continue
		_project_circle(at, OTHER_MECHA_RADIUS, true, 0.0)


func _add_buildings() -> void:
	var field := _building_field
	var pos := global_position
	var skip := {}
	var own := field.building_at(pos)
	if own >= 0:
		skip[own] = true
	if going_to_position:
		var goal := field.building_at(NavAgent.target_position)
		if goal >= 0:
			skip[goal] = true
	for t in [valid_target, current_target]:
		if t and is_instance_valid(t):
			var b := field.building_at(t.global_position)
			if b >= 0:
				skip[b] = true
	var grow := _steer_self_radius + STEER_MARGIN
	for b in field.buildings_within(pos, _steer_range + grow):
		if skip.has(b):
			continue
		var dist := field.distance_to_building(b, pos)
		var clearance := dist - grow
		if clearance > _steer_range:
			continue
		var poly := field.global_polygon(b)
		var centre := Vector2.ZERO
		for p in poly:
			centre += p
		centre /= poly.size()
		var ref := (centre - pos).angle()
		var lo := 0.0
		var hi := 0.0
		for p in poly:
			var a := angle_difference(ref, (p - pos).angle())
			lo = minf(lo, a)
			hi = maxf(hi, a)
		var inflate := asin(clampf(grow / maxf(dist, 1.0), 0.0, 1.0))
		var prox := 1.0 - clampf(clearance / _steer_range, 0.0, 1.0)
		_mark(ref + (lo + hi) * 0.5, (hi - lo) * 0.5 + inflate, MARK_SOFT,
				BUILDING_COST * (0.4 + 0.6 * prox))


# Hand-made static bodies: one probe every STATIC_PROBE_INTERVAL frames; when
# something static is near, the mecha's circle is cast along each slot.
func _add_static_bodies() -> void:
	var space := get_world_2d().direct_space_state
	var frame := Engine.get_physics_frames()
	if _static_shape == null:
		_static_shape = CircleShape2D.new()
	if frame - _static_probe_frame >= STATIC_PROBE_INTERVAL:
		_static_probe_frame = frame
		_static_near = false
		_static_exclude.clear()
		_static_exclude.append(get_rid())
		_static_shape.radius = _steer_range + _steer_self_radius
		var probe := PhysicsShapeQueryParameters2D.new()
		probe.shape = _static_shape
		probe.transform = Transform2D(0.0, global_position)
		probe.collision_mask = STATIC_MASK
		for hit in space.intersect_shape(probe, 32):
			var col: Object = hit.collider
			if col is StaticBody2D or col is TileMapLayer:
				_static_near = true
			else:
				_static_exclude.append(hit.rid)
	if not _static_near:
		return
	_static_shape.radius = _steer_self_radius * STATIC_CAST_SCALE
	var cast := PhysicsShapeQueryParameters2D.new()
	cast.shape = _static_shape
	cast.transform = Transform2D(0.0, global_position)
	cast.collision_mask = STATIC_MASK
	cast.exclude = _static_exclude
	# Already touching something: a cast in any direction stops at once, so
	# only the directions into it are blocked (from the contact normal).
	var touching := space.get_rest_info(cast)
	if not touching.is_empty():
		var normal: Vector2 = touching.normal
		for i in STEER_SLOTS:
			if _slot_dirs[i].dot(normal) < 0.2:
				_steer_hard[i] = 1.0
		return
	for i in STEER_SLOTS:
		cast.motion = _slot_dirs[i] * _steer_range
		var safe: float = space.cast_motion(cast)[0]
		if safe < 1.0:
			_steer_hard[i] = maxf(_steer_hard[i], 1.0 - safe)


# Projects a circle obstacle (global centre, radius) onto the slots.
func _project_circle(centre: Vector2, radius: float, hard: bool, cost: float, car := false) -> void:
	var rel := centre - global_position
	var dist := rel.length()
	var reach := radius + _steer_self_radius + STEER_MARGIN
	var clearance := dist - reach
	if clearance > _steer_range:
		return
	var prox := 1.0 - clampf(clearance / _steer_range, 0.0, 1.0)
	var half := PI * 0.5 if dist <= reach else asin(reach / dist)
	if hard:
		_mark(rel.angle(), half, MARK_HARD, prox)
	elif cost > 0.0:
		_mark(rel.angle(), half, MARK_SOFT, cost * (0.4 + 0.6 * prox))
	if car:
		_mark(rel.angle(), half, MARK_CAR, prox)


# Raises hard danger, soft cost or car nearness (`kind`) to `value` on every
# slot whose direction lies within bearing ± half. Grown by the mecha's
# radius, an obstacle in range always spans more than one slot step, so none
# falls between slots; a narrower one still marks its nearest slot.
func _mark(bearing: float, half: float, kind: int, value: float) -> void:
	var step := TAU / STEER_SLOTS
	var first := ceili((bearing - half) / step)
	var last := floori((bearing + half) / step)
	if last < first:
		first = roundi(bearing / step)
		last = first
	if last - first >= STEER_SLOTS:
		first = 0
		last = STEER_SLOTS - 1
	for k in range(first, last + 1):
		var i := posmod(k, STEER_SLOTS)
		if kind == MARK_HARD:
			_steer_hard[i] = maxf(_steer_hard[i], value)
		elif kind == MARK_SOFT:
			_steer_soft[i] = maxf(_steer_soft[i], value)
		else:
			_steer_car[i] = maxf(_steer_car[i], value)


func choose_direction(dt := 0.0):
	var min_hard := INF
	for i in STEER_SLOTS:
		min_hard = minf(min_hard, _steer_hard[i])
	var scores := PackedFloat32Array()
	scores.resize(STEER_SLOTS)
	var best := -1
	for i in STEER_SLOTS:
		if _steer_hard[i] > min_hard + HARD_TOLERANCE:
			scores[i] = -INF
			continue
		var d := _slot_dirs[i]
		var s := d.dot(_steer_desired) - _steer_soft[i] - _steer_hard[i] * HARD_COST
		s += COMMIT_BONUS * maxf(0.0, d.dot(_steer_last_choice))
		if _unstick_time > 0.0:
			s += UNSTICK_BONUS * maxf(0.0, d.dot(_unstick_dir))
		scores[i] = s
		if best < 0 or s > scores[best]:
			best = i

	# Refine between the neighbours (a parabola through the three scores).
	var angle := _slot_angles[best]
	var sl := scores[posmod(best - 1, STEER_SLOTS)]
	var sr := scores[posmod(best + 1, STEER_SLOTS)]
	if is_finite(sl) and is_finite(sr):
		var denom := sl - 2.0 * scores[best] + sr
		if denom < -0.0001:
			angle += clampf(0.5 * (sl - sr) / denom, -0.5, 0.5) * TAU / STEER_SLOTS
	var target := Vector2.from_angle(angle)
	_steer_last_choice = target

	if chosen_dir == Vector2.ZERO or dt <= 0.0:
		chosen_dir = target
	else:
		var rate := STEER_TURN_RATE_TANK if movement_type == "tank" else STEER_TURN_RATE
		chosen_dir = Vector2.from_angle(rotate_toward(chosen_dir.angle(), angle, rate * dt))
	if Debug.get_setting("draw_debug_lines"):
		queue_redraw()


#-------- Unstick

# _track_progress() watches how far the NPC actually moves along its desired
# heading against how far it should, in PROGRESS_SAMPLE s chunks. When the
# last PROGRESS_CHUNKS chunks together show less than PROGRESS_MIN of the
# expected distance, the NPC is blocked (_steer_blocked) and escalates:
#   1. The vehicle it last pushed counts as jammed (hard) for JAM_TIME s. If
#      that was a car, it sprints over it (see Car burst); otherwise it
#      commits to the more open side for UNSTICK_SIDE_TIME s.
#   2. Blocked again within UNSTICK_RESET_TIME s: stuck on a car, it dashes
#      through it (destroying it); otherwise it dashes back if it can, backs
#      off for UNSTICK_BACK_TIME s, then tries the other side. Either way it
#      plans its route again.
# Progress is only judged while the NPC keeps wanting to go the same way (its
# heading turns less than PROGRESS_MAX_TURN across the window), and not at
# all while it has a foe in range: kiting in and out isn't being stuck.
# A window with good progress clears the escalation. The stuck watchdog in
# _physics_process is the last resort.
const PROGRESS_SAMPLE := 0.5
const PROGRESS_CHUNKS := 3
const PROGRESS_MIN := 0.25
## Expected distance (px) under which a window doesn't count (the NPC is
## meant to be slow, for example holding its kite range).
const PROGRESS_MIN_EXPECTED := 120.0
## A chunk in which the desired heading turned more than this isn't judged.
const PROGRESS_MAX_TURN := PI / 4.0
const UNSTICK_BONUS := 1.0
const UNSTICK_SIDE_TIME := 1.5
const UNSTICK_BACK_TIME := 0.8
const UNSTICK_RESET_TIME := 4.0
## Tanks reach this fraction of max_speed (wheels factor and tank gearing).
const TANK_SPEED_FACTOR := 0.4

var _steer_blocked := false
var _progress_has_pos := false
var _progress_heading := Vector2.ZERO
var _progress_last_pos := Vector2.ZERO
var _progress_done := 0.0
var _progress_expected := 0.0
var _progress_time := 0.0
var _progress_chunks: Array[Vector2] = []
var _progress_headings: Array[Vector2] = []
var _unstick_stage := 0
var _unstick_dir := Vector2.ZERO
var _unstick_time := 0.0
var _unstick_back_time := 0.0
var _unstick_side := 1.0
var _unstick_since := 0.0


func _reset_unstick() -> void:
	_steer_blocked = false
	_unstick_stage = 0
	_unstick_time = 0.0
	_unstick_back_time = 0.0
	_progress_chunks.clear()
	_progress_headings.clear()
	_progress_has_pos = false


func _track_progress(dt: float, in_combat := false) -> void:
	_unstick_since += dt
	if in_combat:
		# In a fight the NPC moves in and out and round its foe on purpose;
		# a blocked way is handled by changing its orbit side (see Orbit).
		_steer_blocked = false
		_progress_chunks.clear()
		_progress_headings.clear()
		_progress_has_pos = false
		_progress_done = 0.0
		_progress_expected = 0.0
		_progress_time = 0.0
		return
	if _unstick_back_time > 0.0:
		_unstick_back_time -= dt
		if _unstick_back_time <= 0.0:
			_set_unstick_side(-_unstick_side, UNSTICK_SIDE_TIME)
	elif _unstick_time > 0.0:
		_unstick_time -= dt
	if _progress_time == 0.0:
		_progress_heading = _steer_desired
	if _progress_has_pos:
		_progress_done += (global_position - _progress_last_pos).dot(_steer_desired)
	_progress_last_pos = global_position
	_progress_has_pos = true
	var speed: float = max_speed * throttle
	if movement_type == "tank":
		# A tank only drives at speed once its chassis faces the way it wants
		# to go (Mecha.apply_movement: speed scales with that dot product
		# cubed), so it isn't stuck while it turns on the spot.
		var facing: Vector2 = tank_move_target.rotated(deg_to_rad(270.0)).normalized()
		speed *= TANK_SPEED_FACTOR * pow(maxf(facing.dot(_steer_desired), 0.0), 3.0)
	_progress_expected += speed * dt
	_progress_time += dt
	if _progress_time < PROGRESS_SAMPLE:
		return
	if _unstick_time > 0.0 or _unstick_back_time > 0.0 \
			or absf(_progress_heading.angle_to(_steer_desired)) > PROGRESS_MAX_TURN:
		# Don't judge progress during an unstick move, or when the NPC changed
		# where it wants to go during the chunk (kiting in and out, changing
		# its orbit side): it wasn't trying to go one way.
		_progress_chunks.clear()
		_progress_done = 0.0
		_progress_expected = 0.0
		_progress_time = 0.0
		return
	# A window only counts while the NPC keeps wanting to go the same way.
	if not _progress_headings.is_empty() \
			and absf(_progress_headings[-1].angle_to(_progress_heading)) > PROGRESS_MAX_TURN:
		_progress_chunks.clear()
		_progress_headings.clear()
	_progress_chunks.append(Vector2(_progress_done, _progress_expected))
	_progress_headings.append(_progress_heading)
	_progress_done = 0.0
	_progress_expected = 0.0
	_progress_time = 0.0
	if _progress_chunks.size() > PROGRESS_CHUNKS:
		_progress_chunks.pop_front()
		_progress_headings.pop_front()
	if _progress_chunks.size() < PROGRESS_CHUNKS:
		return
	var total := Vector2.ZERO
	for c in _progress_chunks:
		total += c
	if total.y < PROGRESS_MIN_EXPECTED:
		_steer_blocked = false
		return
	if total.x >= total.y * PROGRESS_MIN or _trampling():
		_steer_blocked = false
		if _unstick_time <= 0.0 and _unstick_back_time <= 0.0:
			_unstick_stage = 0
		return
	_steer_blocked = true
	_progress_chunks.clear()
	_progress_headings.clear()
	_on_blocked()


# A tank pushing a vehicle it can drive over is getting somewhere: it will be
# over it in a moment (VehicleField.trample_time).
func _trampling() -> bool:
	if movement_type != "tank" or not is_instance_valid(_vehicle_field):
		return false
	var pushed := _vehicle_field.last_pushed_by(self, true)
	return pushed >= 0 and (_vehicle_field.can_trample(pushed) or _vehicle_field.is_trampled(pushed))


func _on_blocked() -> void:
	if _unstick_since > UNSTICK_RESET_TIME:
		_unstick_stage = 0
	_unstick_since = 0.0
	_unstick_stage += 1
	var car_jam := false
	if is_instance_valid(_vehicle_field):
		var pushed := _vehicle_field.last_pushed_by(self)
		if pushed >= 0:
			_jammed[pushed] = Time.get_ticks_msec() + int(JAM_TIME * 1000.0)
			car_jam = _vehicle_field.is_car(pushed)
	# Rebuild now so a newly jammed vehicle counts straight away, and route
	# the trip whatever its length.
	_steer_built_frame = -100000
	_route_force = ROUTE_FORCE_TIME
	_route_replan = true
	if car_jam and _unstick_stage == 1 and _can_burst():
		# Stuck on a car: sprint over it.
		_start_car_burst()
		return
	if car_jam and _unstick_stage >= 2 and try_dash(_steer_desired):
		# Still stuck on a car: dash through it (a dash destroys a car).
		_route_replan = true
		return
	if _unstick_stage == 1:
		_set_unstick_side(_open_side(), UNSTICK_SIDE_TIME)
	else:
		_unstick_dir = -_steer_desired
		_unstick_time = UNSTICK_BACK_TIME
		_unstick_back_time = UNSTICK_BACK_TIME
		try_dash(_unstick_dir)
		_route_replan = true


func _set_unstick_side(side: float, seconds: float) -> void:
	_unstick_side = side
	_unstick_dir = _steer_desired.rotated(side * deg_to_rad(70.0))
	_unstick_time = seconds


# 1.0 (clockwise) or -1.0, whichever side of the desired heading has less
# danger and cost.
func _open_side() -> float:
	var right := 0.0
	var left := 0.0
	for i in STEER_SLOTS:
		var a := angle_difference(_steer_desired.angle(), _slot_angles[i])
		var w := _steer_hard[i] * 2.0 + _steer_soft[i]
		if a > deg_to_rad(20.0) and a < deg_to_rad(130.0):
			right += w
		elif a < -deg_to_rad(20.0) and a > -deg_to_rad(130.0):
			left += w
	if is_equal_approx(right, left):
		return _unstick_side
	return 1.0 if right < left else -1.0


#-------- Routes

# On maps with a BuildingField route grid, an NPC heading somewhere more than
# ROUTE_MIN_DISTANCE away follows a planned route (BuildingField.find_route):
# along streets and open ground, round building blocks and parked rows. It
# heads for one route point at a time and moves on to the next when within
# ROUTE_REACH of it or past it. It plans again when its goal moves more than
# ROUTE_REPLAN_MOVE, every ROUTE_REPLAN_TIME seconds, and after a bad stuck.
# Shorter trips, and maps without the grid, go straight (local steering
# still goes round what's in the way), except for ROUTE_FORCE_TIME s after the
# NPC is judged blocked: then it routes even a short trip, which takes it
# round walls and barriers that local steering can't see past.
const ROUTE_MIN_DISTANCE := 2000.0
const ROUTE_REACH := 350.0
const ROUTE_REPLAN_MOVE := 1000.0
const ROUTE_REPLAN_TIME := 15.0
const ROUTE_FORCE_TIME := 6.0

var _route := PackedVector2Array()
var _route_index := 0
var _route_goal := Vector2.INF
var _route_age := 0.0
var _route_replan := false
var _route_force := 0.0


func _route_next(goal: Vector2, dt: float) -> Vector2:
	if not is_instance_valid(_building_field):
		_building_field = BuildingField.find(self)
	var field := _building_field
	if field == null or not field.routes_ready():
		return NavAgent.get_next_path_position()
	var pos := global_position
	_route_force = maxf(_route_force - dt, 0.0)
	var short := ROUTE_REACH if _route_force > 0.0 else ROUTE_MIN_DISTANCE
	if pos.distance_to(goal) < short:
		_route.clear()
		return goal
	_route_age += dt
	if _route.is_empty() or _route_replan or _route_age > ROUTE_REPLAN_TIME \
			or _route_goal.distance_to(goal) > ROUTE_REPLAN_MOVE:
		var route := field.find_route(pos, goal)
		if not route.is_empty():
			_route = route
			_route_index = 0
			_route_goal = goal
			_route_age = 0.0
			_route_replan = false
	if _route.is_empty():
		return goal
	while _route_index < _route.size() - 1:
		var point := _route[_route_index]
		var past := (point - pos).dot(_route[_route_index + 1] - point) < 0.0
		if pos.distance_to(point) > ROUTE_REACH and not past:
			break
		_route_index += 1
	return _route[_route_index]


#-------- Orbit

# In a fight the behaviours approach or back off with a `wander` value: the
# dot product between the way to move and the straight line to the foe.
# navigate_to_target() turns the line by that angle to one side, so the NPC
# circles and strafes round its foe. The side holds for ORBIT_MIN_TIME to
# ORBIT_MAX_TIME s, then may change; it changes at once when that way is
# blocked.
const COMBAT_RANGE := 3500.0
const ORBIT_MIN_TIME := 2.5
const ORBIT_MAX_TIME := 5.0
const ORBIT_BLOCKED_DANGER := 0.6

var _orbit_side := 1.0 if randf() < 0.5 else -1.0
var _orbit_time := 0.0


# The mecha or Entity this NPC is fighting, if it is within COMBAT_RANGE.
func _combat_target():
	for t in [current_target, valid_target]:
		if t and is_instance_valid(t) and not ("is_dead" in t and t.is_dead) \
				and global_position.distance_squared_to(t.global_position) < COMBAT_RANGE * COMBAT_RANGE:
			return t
	return null


func _update_orbit(dt: float, foe) -> void:
	if not foe:
		return
	_orbit_time -= dt
	var ahead := posmod(roundi(_steer_desired.angle() / (TAU / STEER_SLOTS)), STEER_SLOTS)
	var blocked := _steer_hard[ahead] > ORBIT_BLOCKED_DANGER
	if blocked and _orbit_time < ORBIT_MAX_TIME - 1.0:
		_orbit_side = -_orbit_side
		_orbit_time = randf_range(ORBIT_MIN_TIME, ORBIT_MAX_TIME)
	elif _orbit_time <= 0.0:
		if randf() < 0.6:
			_orbit_side = -_orbit_side
		_orbit_time = randf_range(ORBIT_MIN_TIME, ORBIT_MAX_TIME)


#-------- Sprint and dash

# Cruise sprint: on a long trip with no foe near, a cool NPC sprints while
# the way ahead is clear. It starts below SPRINT_HEAT_START of its overheat
# temperature and stops above SPRINT_HEAT_STOP, near its goal, or when
# something is in the way.
#
# Dashes, at most one every DASH_MIN_INTERVAL s and only below DASH_HEAT_MAX:
#   - Dodge: when a shot comes near (the NearbyProjectile area), sometimes
#     dash to the side away from its line. Better pilots (higher
#     ai_lead_accuracy) dodge more often.
#   - Escape: when properly stuck (second unstick stage), dash the unstick
#     way.
#   - Gap close: a brawler approaching a foe well outside its range
#     sometimes dashes in.
# Mecha.dash() takes a straight direction (forward, back, left or right) in
# the body's frame for legs and in world space otherwise; try_dash() picks
# the one nearest the wanted world direction.
const SPRINT_MIN_DISTANCE := 2500.0
const SPRINT_HEAT_START := 0.45
const SPRINT_HEAT_STOP := 0.65
const DASH_MIN_INTERVAL := 2.5
const DASH_HEAT_MAX := 0.6
const DODGE_CHANCE_MIN := 0.15
const DODGE_CHANCE_MAX := 0.5
## Chance per second that a brawler closing in dashes.
const GAP_CLOSE_RATE := 0.35

var _cruising := false
var _last_dash_ms := -100000


# Hottest of internal and external temperature, as a fraction of overheat.
func heat_ratio() -> float:
	if overheat_temp <= 0.0:
		return 0.0
	return maxf(internal_temp, external_temp) / overheat_temp


func _cruise_sprint(goal: Vector2, foe) -> bool:
	if foe or scripted or build.thruster == null:
		_cruising = false
		return false
	var dist := global_position.distance_to(goal)
	var ahead := posmod(roundi(chosen_dir.angle() / (TAU / STEER_SLOTS)), STEER_SLOTS)
	var clear := _steer_hard[ahead] < 0.1 and _steer_soft[ahead] < 0.2
	var heat := heat_ratio()
	if _cruising:
		if heat > SPRINT_HEAT_STOP or dist < SPRINT_MIN_DISTANCE * 0.6 or not clear:
			_cruising = false
	elif heat < SPRINT_HEAT_START and dist > SPRINT_MIN_DISTANCE and clear \
			and absf(chosen_dir.angle_to(_steer_desired)) < deg_to_rad(25.0):
		_cruising = true
	return _cruising


func _update_dashes(dt: float, foe, direction: float) -> void:
	if not foe or combat_style != "brawler" or direction != 0.0:
		return
	var gap := global_position.distance_to(foe.global_position)
	if gap > preferred_combat_range * 1.5 and randf() < GAP_CLOSE_RATE * dt:
		try_dash(chosen_dir)


# Dashes as close to `world_dir` as Mecha.dash() allows. Returns whether it
# dashed.
func try_dash(world_dir: Vector2) -> bool:
	if world_dir == Vector2.ZERO or build.thruster == null or scripted or is_dead or is_stunned():
		return false
	if Time.get_ticks_msec() - _last_dash_ms < int(DASH_MIN_INTERVAL * 1000.0):
		return false
	if heat_ratio() > DASH_HEAT_MAX or has_status("freezing"):
		return false
	var d := world_dir.rotated(-global_rotation) if movement_type == "relative" else world_dir
	var cardinal := Vector2(signf(d.x), 0.0) if absf(d.x) > absf(d.y) else Vector2(0.0, signf(d.y))
	var dir_name = get_dir_name(cardinal)
	if typeof(dir_name) != TYPE_STRING or dash_cooldown[dir_name] > 0.0:
		return false
	dash(cardinal)
	_last_dash_ms = Time.get_ticks_msec()
	return true


# Car burst: a sprinting mecha passes over cars, so an NPC facing a wall of
# cars (cars in CAR_WALL_SLOTS of the slots within CAR_WALL_ANGLE of its
# heading, nothing harder in front), or stuck on a car, sprints for
# CAR_BURST_TIME s if it is cool enough.
const CAR_BURST_TIME := 1.2
const CAR_NEAR := 0.4
const CAR_WALL_ANGLE := PI / 3.0
const CAR_WALL_SLOTS := 7

var _car_burst_time := 0.0


func _can_burst() -> bool:
	return build.thruster != null and not scripted and heat_ratio() < SPRINT_HEAT_STOP


func _car_wall_ahead() -> bool:
	var step := TAU / STEER_SLOTS
	var ahead := posmod(roundi(_steer_desired.angle() / step), STEER_SLOTS)
	if _steer_car[ahead] < CAR_NEAR or _steer_hard[ahead] > 0.3:
		return false
	var span := ceili(CAR_WALL_ANGLE / step)
	var count := 0
	for k in range(-span, span + 1):
		if _steer_car[posmod(ahead + k, STEER_SLOTS)] >= CAR_NEAR:
			count += 1
	return count >= CAR_WALL_SLOTS


func _update_car_burst(dt: float) -> void:
	if _car_burst_time > 0.0:
		_car_burst_time -= dt
	elif _can_burst() and _car_wall_ahead():
		_start_car_burst()


func _start_car_burst() -> void:
	_car_burst_time = CAR_BURST_TIME
	# Sprint from this frame, and rebuild the map without the cars.
	is_sprinting = true
	_steer_built_frame = -100000


# A shot coming near: maybe dash to the side, away from its line.
func _try_dodge(from: Vector2) -> void:
	if is_dead or scripted or not going_to_position:
		return
	var chance := lerpf(DODGE_CHANCE_MIN, DODGE_CHANCE_MAX, clampf(ai_lead_accuracy, 0.0, 1.0))
	if randf() >= chance:
		return
	var line := (global_position - from).normalized()
	var side := line.orthogonal()
	# Dodge to the side with less in the way.
	var right := posmod(roundi(side.angle() / (TAU / STEER_SLOTS)), STEER_SLOTS)
	var left := posmod(roundi((-side).angle() / (TAU / STEER_SLOTS)), STEER_SLOTS)
	if _steer_hard.size() == STEER_SLOTS and _steer_hard[left] < _steer_hard[right]:
		side = -side
	try_dash(side)


func _on_nearby_projectile_area_entered(area):
	if area.original_mecha_info and \
	   area.original_mecha_info.name != mecha_name and\
	   is_instance_valid(area.original_mecha_info.body):
		var attacker = area.original_mecha_info.body
		under_fire_timer = 0.5
		most_recent_attacker = attacker
		last_attack_position = attacker.global_position
		_try_dodge(attacker.global_position)

		# Build hostility — 4 shots = max hostility
		add_hostility(attacker, 0.25)

		# Betrayal: if we're flagged and they shoot us, mark them traitor
		if is_exposed and not get_relationship(attacker).is_traitor:
			mark_traitor(attacker)
