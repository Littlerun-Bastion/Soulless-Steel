extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")
const SOUND_LIFETIME = 25
const BODY_LIFETIME = 35
## How long (s) a body this NPC saw stays a live sight contact after the last
## senses update that saw it (see update_senses).
const SIGHT_CONTACT_TTL = 0.5
## An NPC sees a body nobody's light falls on only within this distance (px)
## all round, as the player does (Player.VIEW_PERIPHERAL). Its own light
## lights what is in its cone (Illumination.is_lit), so with the light on it
## sees there too. Placeholder.
const PERIPHERAL_SIGHT = 400.0

# Stuck watchdog, the last resort after the unstick moves in the steering
# section. stuck_timer counts while the NPC wants to move but either barely
# moves or makes no progress (_steer_blocked).
#  1. Soft reset, once, as stuck_timer passes STUCK_RESET_TIME: clear
#     going_to_position so the behaviour picks a fresh target on the next
#     tick, and the blocked flag, so that target is judged on its own (the
#     steering only judges progress on a heading held for a while, so a flag
#     left over would never clear).
#  2. Hard relocate (STUCK_RELOCATE_TIME): if it is STILL stuck and off
#     screen, ask the host scene for a safe position and teleport there.
#     Catches NPCs that ended up outside the navmesh. An NPC the player can
#     see is never teleported: its count starts over, so it gets another
#     soft reset and keeps trying to unstick.
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
## What this NPC knows (NPCKnowledge): bodies through its contact store,
## sounds, where it took fire from, its own state.
var knowledge := NPCKnowledge.new()
## Where to stand (Positioning) and when to fire (FireController): the
## tactics every intent shares.
var positioning := Positioning.new()
var fire := FireController.new()
## Weapon slot -> its role for the fire controller (see _weapon_role).
var _weapon_roles := {}
## Sounds heard, with lifetimes. The same Array as knowledge.sounds.
var senses = {
	"sounds": [],
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
## Whether the behaviour switches the illuminator by intent
## (BaseBehaviour.wants_illuminator). False for NPC code that switches it
## itself.
var auto_illuminator := true
## An illuminator setting is held this long (s) before the behaviour may
## change it again, unless the NPC is hit or Flags. Placeholder.
const ILLUMINATOR_HOLD_TIME := 3.0
var _illuminator_hold := 0.0
## Panic (NPCKnowledge.panic): how much of the lead it takes away, the aim
## bloom (degrees) it adds at full panic, and above what panic the barks use
## their panicked lines. Placeholders.
const PANIC_LEAD_LOSS := 0.5
const PANIC_BLOOM := 2.0
const PANIC_BARK := 0.6
## The Flag: the chance per point of negative reputation that an NPC ignores
## the player's Flag, and its cap; the treachery window (s) after a Flag
## raised by choice comes down; the hostility a witness gains toward whoever
## shoots a Flagged mech (Guardians more). Placeholders.
const FLAG_IGNORE_PER_REPUTATION := 0.01
const FLAG_IGNORE_MAX := 0.8
const TREACHERY_WINDOW := 10.0
const WITNESS_HOSTILITY := 0.25
const WITNESS_HOSTILITY_GUARDIAN := 0.5
## A seen mine is kept clear of by its trigger reach plus this (px).
const MINE_AVOID_MARGIN := 60.0


func _ready():
	super()

	# The NPC's memory ages with its thinking time (update_senses), not with
	# every physics frame, and lasts longer than the player's HUD fade.
	contacts_auto_advance = false
	contacts.ghost_time = BODY_LIFETIME
	knowledge.setup(self)
	knowledge.sounds = senses.sounds
	fire.setup(self)
	flagged.connect(func(): _illuminator_hold = 0.0)
	# What frightens an NPC (NPCKnowledge.raise_panic), and its own Flag
	# events for the log.
	component_damaged.connect(func(_p, _c, _hp, _max): knowledge.raise_panic(knowledge.PANIC_HIT))
	component_destroyed_alert.connect(func(_p, _c): knowledge.raise_panic(knowledge.PANIC_COMPONENT_LOST))
	swept.connect(_on_swept)
	device_destroyed.connect(_on_device_lost)
	flag_raised.connect(func(_m, voluntary, _by): AICombatLog.record_flag("raised_voluntary" if voluntary else "raised_emergency"))

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

	took_damage.connect(_on_took_damage_for_barks)
	for node in [$ArmWeaponLeft, $ArmWeaponRight, $ShoulderWeaponLeft, $ShoulderWeaponRight]:
		if node.has_signal("reloading_signal"):
			node.reloading_signal.connect(_on_weapon_reloading_for_barks)



func _physics_process(dt):
	if paused or is_dead:
		return
	# Physics LOD (see lod_tier): a far NPC runs its whole step, the Mecha
	# base included, every step_interval() frames; the skipped frames' time
	# is folded into dt and their distance into its moves (Mecha._step_scale).
	var interval := step_interval()
	if interval > 1 and (Engine.get_physics_frames() + _think_offset) % interval != 0:
		_step_dt += dt
		return
	_step_scale = float(interval)
	_physics_frame(dt + _step_dt)
	_step_dt = 0.0
	_step_scale = 1.0


# One physics step of the NPC: the Mecha base, then its senses and thinking
# on thinking frames, coasting on the others.
func _physics_frame(dt):
	super._physics_process(dt)

	if is_stunned():
		return

	# Thinking LOD: see is_thinking_frame(). think_dt is the game time since
	# the last thinking frame.
	_think_dt += dt
	var thinking := scripted or is_thinking_frame()
	var think_dt := _think_dt
	if thinking:
		_think_dt = 0.0

	# The think-time probe (AICombatLog, Debug setting "ai_log"): senses,
	# intent scoring, behaviour and illuminator of one thinking frame. The
	# frame profiler counts the same under "npc_think", and the drive (a
	# scripted walker, or the coasting between thinks) under "npc_drive".
	var probing := thinking and AICombatLog.enabled()
	var probe_start := Time.get_ticks_usec() if probing else 0
	var profile_start := FrameProfiler.start()

	if scripted:
		contacts.advance(dt)
	elif thinking:
		var senses_start := FrameProfiler.start()
		update_senses(think_dt)
		FrameProfiler.add("npc_senses", senses_start)
		positioning.tick(think_dt)
		# Squadmates' callouts that are due land now.
		if knowledge.squad != null:
			knowledge.squad.deliver()

	wait_for_map_sync = max(wait_for_map_sync - dt, 0)
	if scripted:
		_drive_scripted(dt)
		if probing:
			AICombatLog.record_think(Time.get_ticks_usec() - probe_start, "scripted")
		FrameProfiler.add("npc_drive", profile_start)
	elif not wait_for_map_sync and not is_dead:
		if thinking:
			# Fresh each think; the combat behaviour re-sets it while engaging.
			ai_aim_point = null
			recheck_flagged_target()
			var before := global_position
			var scores_start := FrameProfiler.start()
			logic.update(self)
			FrameProfiler.add("npc_scores", scores_start)
			var behaviour_start := FrameProfiler.start()
			logic.run(self, think_dt)
			FrameProfiler.add("npc_behaviour", behaviour_start)
			_update_illuminator(think_dt)
			_coast_velocity = velocity if global_position != before else Vector2.ZERO
			_watch_barks(think_dt)
			_watch_lock_warning()
			_tick_companion(think_dt)
			_tick_provocation(think_dt)
			_tick_sweep_back(think_dt)
			if probing:
				AICombatLog.record_think(Time.get_ticks_usec() - probe_start, "near" if is_near_player() else "far")
			FrameProfiler.add("npc_think", profile_start)
		elif _coast_velocity != Vector2.ZERO:
			# Between thinking frames, keep going the way it was going.
			move(_coast_velocity)
			FrameProfiler.add("npc_drive", profile_start)

	# Stuck watchdog. Only fires when the NPC is actively trying to reach a
	# position (going_to_position == true) but stays near still or makes no
	# progress. NPCs that are still on purpose (alert/ambush/observing) don't
	# set going_to_position, and NPCs in a fight move slowly on purpose
	# (turning tanks, holding range), so neither is reset or teleported.
	if not scripted and going_to_position and not _combat_target() \
			and (velocity.length() < STUCK_VELOCITY_THRESHOLD or _steer_blocked):
		var was_stuck := stuck_timer
		stuck_timer += dt
		# Tier 1: soft reset, once. If the behaviour's fresh target still
		# doesn't move it, the timer keeps climbing toward Tier 2.
		if was_stuck < STUCK_RESET_TIME and stuck_timer >= STUCK_RESET_TIME:
			AICombatLog.record_stuck(self, "soft reset")
			going_to_position = false
			_steer_blocked = false
		# Tier 2: hard relocate, off screen only.
		elif stuck_timer >= STUCK_RELOCATE_TIME:
			if is_on_screen():
				stuck_timer = 0.0
			else:
				if arena and arena.has_method("get_safe_position"):
					push_warning("[Enemy] " + mecha_name + " hard-relocated after being stuck for " + str(STUCK_RELOCATE_TIME) + "s")
					AICombatLog.record_stuck(self, "teleported")
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
	elif is_instance_valid(lock_search_target):
		update_enemy_locking(dt, lock_search_target)
	elif lock_search_target != null:
		lock_search_target = null
		
	if Debug.get_setting("enemy_state"):
		var state = logic.get_current_state()
		var text: String = str(state) if state else "?"
		if Debug.get_setting("ai_overlay"):
			text += _overlay_text()
		$Debug/StateLabel.text = text
		$Debug/StateLabel.visible = true
	else:
		$Debug/StateLabel.visible = false
	if Debug.get_setting("ai_overlay") and thinking:
		queue_redraw()
	
	under_fire_timer = max(under_fire_timer - dt, 0)


# Debug overlay (Debug setting "draw_debug_lines"): per slot, hard danger in
# red and soft cost in orange, the desired heading in grey, the steering
# direction in white, an active unstick direction in cyan and the rest of the
# planned route in green.
func _draw():
	if Debug.get_setting("ai_overlay"):
		_draw_ai_overlay()
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


# AI overlay (Debug setting "ai_overlay"): a line to the target, white while
# in sight; once out of sight, a yellow line to where it was last seen or
# heard, with a cross there; and a grey line to where the NPC is heading.
func _draw_ai_overlay() -> void:
	var t = current_target if current_target and is_instance_valid(current_target) else valid_target
	if t and is_instance_valid(t):
		if is_seeing(t):
			draw_line(Vector2.ZERO, to_local(t.global_position), Color.WHITE, 3.0)
		else:
			var p := to_local(get_target_position(t))
			draw_dashed_line(Vector2.ZERO, p, Color.YELLOW, 3.0, 40.0)
			draw_line(p + Vector2(-60, -60), p + Vector2(60, 60), Color.YELLOW, 5.0)
			draw_line(p + Vector2(-60, 60), p + Vector2(60, -60), Color.YELLOW, 5.0)
	if going_to_position:
		draw_line(Vector2.ZERO, to_local(NavAgent.target_position), Color(0.6, 0.6, 0.6, 0.6), 2.0)
	# The position picker: its candidates as dots, brighter the better they
	# scored, and the chosen point as a ring.
	if not positioning.candidates.is_empty():
		var best: float = positioning.candidates[0].score
		var worst: float = positioning.candidates[positioning.candidates.size() - 1].score
		for entry in positioning.candidates:
			var share: float = 1.0 if best <= worst else (float(entry.score) - worst) / (best - worst)
			draw_circle(to_local(entry.position), 10.0, Color(0.5, 1.0, 0.5, 0.25 + 0.75 * share))
	if positioning.has_pick():
		draw_arc(to_local(positioning.pick_position()), 40.0, 0.0, TAU, 24, Color(0.5, 1.0, 0.5, 0.9), 4.0)


# Extra lines for the state label with the AI overlay on: the top intent
# scores, the illuminator, then the target, how far away it is believed to
# be, and whether it is in sight.
## The ai_overlay's detail lines (the label's text after the intent), for
## other debug views (ObserverOverlay's think tags).
func overlay_text() -> String:
	return _overlay_text()


func _overlay_text() -> String:
	var text := ""
	if not logic.last_scores.is_empty():
		var parts := PackedStringArray()
		for pair in logic.last_scores:
			parts.append("%s %.2f" % [pair[0], pair[1]])
		text += "\n" + " ".join(parts)
	text += "\nlit" if illuminator_on else "\ndark"
	text += " panic %.2f" % knowledge.panic
	if is_lowering_flag():
		text += " flag lowering"
	elif flag_up:
		text += " flag " + ("voluntary" if flag_voluntary else "emergency")
	var traitors := 0
	for rel in relationships.values():
		if rel.is_traitor:
			traitors += 1
	if traitors > 0 or not knowledge.flag_memory.is_empty():
		text += "\ntraitors %d, flags seen %d" % [traitors, knowledge.flag_memory.size()]
	if not knowledge.known_mines.is_empty():
		text += "\nmines %d" % knowledge.known_mines.size()
	var squad = knowledge.squad
	if squad != null:
		if squad.is_player_led():
			text += "\nbuddy %s, order %s" % [squad.role_of(self), squad.order]
		else:
			text += "\nsquad %s %s%s" % [squad.tag if not squad.anonymous else "anon", squad.role_of(self), " leader" if squad.is_leader(self) else ""]
	elif _offered:
		text += "\noffered"
	if not knowledge.local_leads.is_empty() or knowledge.swept_count > 0 or knowledge.avoids(global_position, INF):
		text += "\nleads %d, swept %d%s" % [knowledge.local_leads.size(), knowledge.swept_count,
				", avoiding" if knowledge.avoids(global_position, INF) else ""]
	var t = current_target if current_target and is_instance_valid(current_target) else valid_target
	if not t or not is_instance_valid(t):
		return text
	var who: String = t.mecha_name if "mecha_name" in t else str(t.name)
	var metres := global_position.distance_to(get_target_position(t)) / MapSenses.PX_PER_METRE
	var sight := "seen" if is_seeing(t) else "lost %.0fs" % time_unseen(t)
	return text + "\n%s %.0fm %s" % [who, metres, sight]


func setup(arena_ref, design_data, _name):
	arena = arena_ref
	if _name and typeof(_name) == TYPE_STRING:
		mecha_name = _name
	else:
		mecha_name = CallsignGenerator.random()

	set_parts_from_design(design_data)

	if design_data.has("personality") and design_data["personality"] is Personality:
		personality = design_data["personality"]
	if personality == null:
		personality = Personality.new()

	# A named NPC brings its callsign and is never Anonymous; the rest get a
	# callsign when they join Local and may be Anonymous.
	if design_data.get("callsign") is String:
		callsign = design_data["callsign"]
	else:
		var chance := HUNTER_ANONYMOUS_CHANCE if personality.type == Personality.Type.HUNTER else ANONYMOUS_CHANCE
		is_anonymous = randf() < chance

	# Whether this pilot respects the player's Flag: rolled once, by the
	# player's reputation; a Rat never does.
	var ignore_chance := clampf(-float(PlayerProgress.get_reputation()) * FLAG_IGNORE_PER_REPUTATION, 0.0, FLAG_IGNORE_MAX)
	knowledge.ignores_player_flag = personality.type == Personality.Type.RAT or randf() < ignore_chance
	if knowledge.ignores_player_flag and personality.type != Personality.Type.RAT:
		AICombatLog.record_flag("ignored")

	# Witnessing attacks (treachery, shooting a Flagged mech) and the Flag's
	# own events, for the log.
	var local = _local_pilots()
	if local != null and not local.attack_noted.is_connected(_on_attack_witnessed):
		local.attack_noted.connect(_on_attack_witnessed)
	# Local's messages: help calls and loot shouts are leads (NPCKnowledge).
	if local != null and not local.message.is_connected(_on_local_message):
		local.message.connect(_on_local_message)

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
	# Preferred range: the average ai_engage_range of the direct-fire weapons.
	# Lock-on and indirect-fire weapons only count when there is nothing else:
	# they reach further than the guns the NPC actually fights with.
	var ranges := []
	var support_ranges := []
	for weapon_key in ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]:
		var weapon = build[weapon_key]
		if weapon == null:
			continue
		var r = weapon.get("ai_engage_range")
		if r != null and r > 0:
			if weapon.requires_lock or weapon.get("is_indirect_fire"):
				support_ranges.append(r)
			else:
				ranges.append(r)
	if ranges.is_empty():
		ranges = support_ranges

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

	_weapon_ap.clear()
	_weapon_roles.clear()
	for weapon_key in WEAPON_SLOTS:
		_weapon_ap[weapon_key] = _read_armor_pen(build[weapon_key])
		# An underpowered energy weapon is one it can't use (no role).
		_weapon_roles[weapon_key] = "" if is_weapon_underpowered(weapon_key) else _weapon_role(build[weapon_key])


# Weapons that came off with their part (Mecha.lose_part) have no role: the
# fire controller and blind fire leave them be.
func _on_weapons_lost(slots: Array) -> void:
	for slot in slots:
		_weapon_roles[slot] = ""
		_weapon_ap[slot] = 0


# A weapon's role for the fire controller: "" (none), "melee", "gun" (the
# plain firing path), "smoke" (the smoke launcher, tap_self), "mine" (a mine
# layer), "lock" (lock-on), "skillshot" (a line or rect designator: cannon,
# laser), "indirect" (mortar, MLRS, howitzer) or "aoe" (a direct-fire circle
# designator: rockets, grenades).
func _weapon_role(weapon) -> String:
	if weapon == null:
		return ""
	if weapon.is_melee:
		return "melee"
	if weapon.get("tap_self") == true:
		return "smoke"
	if weapon.requires_lock:
		return "lock"
	if not weapon.has_designator():
		return "gun"
	if _projectile_is_mine(weapon):
		return "mine"
	if weapon.designator == "line" or weapon.designator == "rect":
		return "skillshot"
	if weapon.get("is_indirect_fire"):
		return "indirect"
	return "aoe"


# Whether a weapon's round is a mine (mine.gd), read the way the muzzle
# speed is: instantiated once, never readied.
func _projectile_is_mine(weapon) -> bool:
	var scene = weapon.get("projectile")
	if scene == null or not (scene is PackedScene):
		return false
	var inst = scene.instantiate()
	var mine: bool = "trigger_radius" in inst and "arm_time" in inst
	inst.free()
	return mine


# The best armour pen among this NPC's guns (0 with none): how many walls
# its direct fire can get through.
func best_armor_pen() -> int:
	var best := 0
	for slot in WEAPON_SLOTS:
		best = maxi(best, int(_weapon_ap.get(slot, 0)))
	return best


# The map's building field, if it has one (cached).
func get_building_field() -> BuildingField:
	if not is_instance_valid(_building_field):
		_building_field = BuildingField.find(self)
	return _building_field


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


# The armour pen of a weapon's round, read the same way as its muzzle speed.
# 0 for weapons that never fire blind: melee, lock-on and indirect fire.
func _read_armor_pen(weapon) -> int:
	if weapon == null or weapon.is_melee or weapon.requires_lock or weapon.get("is_indirect_fire"):
		return 0
	var scene = weapon.get("projectile")
	if scene == null or not (scene is PackedScene):
		return 0
	var inst = scene.instantiate()
	var ap = inst.get("armor_pen")
	inst.free()
	return 0 if ap == null else int(ap)


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
	# A squadmate starts with no grudge, whatever its type.
	if knowledge.squad != null and knowledge.squad.is_in(target):
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
	# Suspicion: a pilot with no name shows up as more of a threat.
	if target.get("is_anonymous") == true:
		seeded = clampf(seeded + SUSPICION_ANONYMOUS, 0.0, 1.0)
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
	# Never a squadmate, nor the leader it follows.
	if knowledge.squad != null and knowledge.squad.is_in(target):
		return false

	var rel = get_relationship(target)

	# Always attack traitors — they flagged then shot us
	if rel.is_traitor:
		return true

	# Target's Flag is up — personality decides
	if target.is_flagged() and not ignores_flag_of(target):
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


# Whether this NPC treats `target`'s Flag as if it weren't there: the
# player's, when the reputation roll said so (or for a Rat).
func ignores_flag_of(target) -> bool:
	return knowledge.ignores_player_flag and target.has_method("is_player") and target.is_player()


# Whether this NPC saw `body` raise its Flag by choice (NPCKnowledge).
func saw_flag_raised(body) -> bool:
	return knowledge.saw_flag_raised(body)


# Another mecha's attack (LocalPilots.attack_noted): treachery and shooting
# a Flagged mech are judged by whoever saw it. A mech this NPC saw raise its
# Flag by choice that lowers it and attacks anyone in the NPC's sight (or
# the NPC itself) is a traitor for good; anyone seen shooting a Flagged mech
# earns hostility, Guardians' the most.
func _on_attack_witnessed(attacker, victim) -> void:
	if scripted or is_dead or attacker == self or not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	# The player answering this NPC's help call: shooting the foe it called
	# about, within HELP_WINDOW (an offer may follow, _consider_offer).
	if _help_foe != null and is_same(victim, _help_foe) and attacker.has_method("is_player") and attacker.is_player() \
			and knowledge.now() - _help_called_at <= HELP_WINDOW:
		_help_answered = true
	if not (is_seeing(attacker) or is_seeing(victim) or victim == self):
		return
	# Answering a help call and seeing the caller hit: whoever hits it is
	# the one it came for.
	if logic.behaviour != null and logic.behaviour.has_method("helping") \
			and is_same(victim, logic.behaviour.helping()) and not (knowledge.squad != null and knowledge.squad.is_in(attacker)):
		add_hostility(attacker, HELP_HOSTILITY)
	# A Guardian that sees a pilot it has nothing against attacked may stand
	# with it: it joins that pilot's squad (CombatScene.buddy_up).
	if personality.type == Personality.Type.GUARDIAN and knowledge.squad == null and not _joined \
			and victim != self and "knowledge" in victim and is_seeing(victim) \
			and get_relationship(victim).hostility <= STANDING_HOSTILITY and get_relationship(attacker).hostility > 0.0 \
			and randf() < GUARDIAN_JOIN_CHANCE and arena is Node and arena.has_method("buddy_up"):
		_joined = true
		if arena.buddy_up(self, victim):
			AICombatLog.record_squad("joined_npc")
			bark("buddy_accept", victim)
	var rel = get_relationship(attacker)
	if not rel.is_traitor and knowledge.flag_lowered_recently(attacker, TREACHERY_WINDOW):
		mark_traitor(attacker)
		AICombatLog.record_flag("traitor")
		bark("traitor", attacker)
	if victim != self and victim.get("flag_up") == true and not rel.is_traitor:
		var amount := WITNESS_HOSTILITY_GUARDIAN if personality.type == Personality.Type.GUARDIAN else WITNESS_HOSTILITY
		add_hostility(attacker, amount)


# How big `target`'s squad is as far as Local shows (its tag on the
# roster): 1 for a pilot with no tag, or an Anonymous one.
func known_squad_size(target) -> int:
	var tag = target.get("squad_tag")
	if not (tag is String) or tag == "" or target.get("is_anonymous") == true:
		return 1
	var local = _local_pilots()
	return maxi(local.count_tag(tag), 1) if local != null else 1


# `target` is a mecha, or a decoy passing for one (Decoy).
func should_engage(target) -> bool:
	if not is_instance_valid(target):
		return false

	var my_threat = estimate_threat_level()
	# A tagged squad's size is on Local's roster: its members count for more.
	var their_threat = target.estimate_threat_level() * (1.0 + SQUAD_THREAT_PER_MEMBER * maxi(known_squad_size(target) - 1, 0))
	var difference = their_threat - my_threat  # positive = they're stronger

	# Courage determines how much stronger the target can be before we bail
	# courage 0.0 -> only fight if we're stronger (difference < 0)
	# courage 0.5 -> fight if roughly even (difference < 0.25)
	# courage 1.0 -> fight anyone (difference < 0.5)
	var threshold = personality.courage * 0.5

	# Aggression shifts the threshold further
	threshold += personality.aggression * 0.2

	# Greed: a weakened target looks like an easy kill / easy loot.
	# Weakness 0.0 (whole) contributes nothing; weakness 1.0 (near dead) gives full greed bonus.
	var weakness := 1.0 - _wholeness(target)
	threshold += personality.greed * weakness * 0.3

	# Hostility: seeded personality grudges + accumulated provocations push us
	# toward engaging. 0.0 = no influence; 1.0 (provoked/traitor) = +0.3 threshold.
	var rel = get_relationship(target)
	threshold += rel.hostility * 0.3

	return difference < threshold


# How whole `body` is, 0 to 1: a mecha's armour and components
# (NPCKnowledge._structural_health), anything else's hp (an Entity, a decoy).
func _wholeness(body) -> float:
	if body is Mecha:
		return NPCKnowledge._structural_health(body)
	var top = body.get("max_hp")
	if (top is float or top is int) and top > 0:
		return clampf(float(body.get("hp")) / float(top), 0.0, 1.0)
	return 1.0


#AI METHODS

func heard_sound(sound_data):
	# A car alarm (CombatScene._on_car_alarm) is heard like any sound; what
	# it is worth is the behaviour's call (cares_about_alarms). A Scavenger
	# keeps away from the car.
	# Any other loud sound from something it can't see is a sound wedge, and
	# the NPC goes by its estimate point (Mecha.note_sound_from); the car is
	# where it is, and so is a sound marked "exact" (its own device, lost).
	var heard_at: Vector2 = sound_data.position
	if sound_data.type == "car_alarm":
		if personality != null and personality.type == Personality.Type.SCAVENGER:
			knowledge.set_avoid(sound_data.position)
		bark("heard_alarm")
	elif sound_data.volume_type == "loud" and sound_data.source != self and not sound_data.get("exact", false):
		heard_at = note_sound_from(sound_data.source, sound_data.position)
	senses.sounds.append({
		"volume_type": sound_data.volume_type,
		"type": sound_data.type,
		"position": heard_at,
		"lifetime": SOUND_LIFETIME,
		"source": sound_data.source,
	})


# Whether a car alarm is a lead for this NPC: Hunters and the greedy go to
# see; Scavengers keep away (heard_sound); nobody else cares.
func cares_about_alarms() -> bool:
	if personality == null:
		return false
	return personality.type == Personality.Type.HUNTER \
			or (personality.type != Personality.Type.SCAVENGER and personality.greed > ALARM_GREED)


# The newest loud noise this NPC acts on: a car alarm only if it cares
# about them (cares_about_alarms).
func get_loud_lead():
	var recent = get_most_recent_loud_noise()
	if recent and recent.type == "car_alarm" and not cares_about_alarms():
		var best = false
		var best_lifetime := -INF
		for sound in senses.sounds:
			if sound.volume_type == "loud" and sound.type != "car_alarm" and sound.lifetime > best_lifetime:
				best = sound
				best_lifetime = sound.lifetime
		return best
	return recent


# A Local message (LocalPilots.message): someone else's help call or loot
# shout becomes a lead at a blurred position (NPCKnowledge.heard_local).
func _on_local_message(entry: Dictionary) -> void:
	if scripted or is_dead or is_same(entry.get("sender"), self):
		return
	var lead := knowledge.heard_local(entry)
	if not lead.is_empty():
		AICombatLog.record_info("lead_" + lead.kind)


# A sweep found this NPC (Mecha.swept): it knows when, not from where. It
# frightens (panic) and makes it suspicious of everyone in sight; a
# Scavenger keeps away from the spot it was swept on; a Hunter sweeps back,
# all round, on its next think (_tick_sweep_back). Never from inside the
# signal: the sweeper's cooldown isn't set until its sweep is over, so two
# Hunters sweeping back at once would call each other without end.
func _on_swept() -> void:
	knowledge.raise_panic(knowledge.PANIC_SWEPT)
	knowledge.noted_sweep()
	bark("swept")
	if scripted:
		return
	for body in knowledge.seen_bodies():
		if not body.is_in_group("entity") and not (knowledge.squad != null and knowledge.squad.is_in(body)):
			add_hostility(body, SWEPT_SUSPICION)
	var type = personality.type if personality else Personality.Type.PROFESSIONAL
	if type == Personality.Type.SCAVENGER:
		knowledge.set_avoid(global_position)
		going_to_position = false
	elif type == Personality.Type.HUNTER:
		_sweep_back_due = true


# A Hunter's sweep back, once its sweep is ready and not within
# SWEEP_BACK_COOLDOWN of the last one (two Hunters would otherwise trade
# sweeps every cooldown and cook themselves).
func _tick_sweep_back(_dt: float) -> void:
	if not _sweep_back_due:
		return
	if knowledge.now() - _swept_back_at < SWEEP_BACK_COOLDOWN:
		_sweep_back_due = false
		return
	if not fire.can_sweep():
		return
	_sweep_back_due = false
	_swept_back_at = knowledge.now()
	fire.sweep(get_facing(), SWEEP_BACK_WIDTH)
	AICombatLog.record_info("swept_back")


# One of its devices was shot (Mecha.device_destroyed): only a mecha does
# that, so somebody was there. A loud lead at the device, to investigate.
func _on_device_lost(device) -> void:
	knowledge.raise_panic(knowledge.PANIC_DEVICE_LOST)
	if scripted or not is_instance_valid(device):
		return
	heard_sound({"volume_type": "loud", "type": "device", "position": device.global_position, "source": null, "exact": true})
	bark("device_destroyed")


# The behaviour chooses the illuminator for its intent
# (BaseBehaviour.illuminator_mode): off, steady on, or flashing. A steady
# light comes on at once and stays on at least ILLUMINATOR_HOLD_TIME s, so it
# doesn't flicker between intents; being hit or Flagging ends the hold.
# Flashing (light discipline) follows the fight instead (_flash_step). See
# Mecha.set_illuminator.
func _update_illuminator(dt := 0.0) -> void:
	if not auto_illuminator or logic.behaviour == null:
		return
	_illuminator_hold = maxf(_illuminator_hold - dt, 0.0)
	if not logic.behaviour.has_method("illuminator_mode"):
		return
	var mode: String = logic.behaviour.illuminator_mode(self, str(logic.get_current_state()))
	if mode == "flash":
		var lit := _flash_step(dt)
		if lit != illuminator_on:
			set_illuminator(lit)
		_illuminator_hold = 0.0
		return
	_flash_reset()
	var wanted := mode == "on"
	if wanted == illuminator_on or (not wanted and _illuminator_hold > 0.0):
		return
	set_illuminator(wanted)
	_illuminator_hold = ILLUMINATOR_HOLD_TIME if wanted else 0.0


# LIGHT DISCIPLINE (skill 0.5 and over: BaseBehaviour.illuminator_mode
# "flash"). The light comes on to get visual on the target and goes off after
# each burst: on until it has visual, at most FLASH_MAX s; then off once a
# burst of fire ends (no shot for FLASH_BURST_GAP s), or at FLASH_MAX with no
# visual; dark for FLASH_REST s; then on again for the next. Placeholders.
const FLASH_MAX := 2.0
const FLASH_REST := 1.0
const FLASH_BURST_GAP := 0.3
var _flash_time := 0.0
var _flash_rest := 0.0
var _flash_fired := false


# One think of the flash cycle; returns whether the light is on.
func _flash_step(dt: float) -> bool:
	if _flash_rest > 0.0:
		_flash_rest = maxf(_flash_rest - dt, 0.0)
		return false
	_flash_time += dt
	var target = current_target if is_instance_valid(current_target) else valid_target
	var seen: bool = is_instance_valid(target) and is_seeing(target)
	var shooting: bool = knowledge.now() - fire.last_shot_time <= FLASH_BURST_GAP
	if shooting:
		_flash_fired = true
	var burst_over: bool = _flash_fired and not shooting
	var no_visual: bool = _flash_time >= FLASH_MAX and not seen and not _flash_fired
	if burst_over or no_visual:
		_flash_time = 0.0
		_flash_fired = false
		_flash_rest = FLASH_REST
		return false
	return true


func _flash_reset() -> void:
	_flash_time = 0.0
	_flash_rest = 0.0
	_flash_fired = false


# Ages what the NPC knows by `dt` (its thinking time), then looks for
# bodies in sight. A body in sight becomes a live sight contact; one that
# drops out of sight stays as a ghost where it was last seen or heard,
# until the store drops it (BODY_LIFETIME).
## A wall ray between this NPC and a body is cast again only after this many
## physics frames (a mecha moves a few px a frame; the ray's answer holds).
const SIGHT_RECHECK_FRAMES := 3
## ... and at once when either end moved further than this (px) since.
const SIGHT_RECHECK_MOVE := 40.0

# The bodies every NPC looks at (mechas and Entities, then the decoys still
# out there), gathered once per physics frame for all of them. Each NPC
# leaves its own decoys out as it looks (update_senses).
static var _sense_bodies: Array = []
static var _sense_decoys: Array = []
static var _sense_bodies_frame := -1
# Body instance id -> [frame of the last wall ray, blocked].
var _sight_cache := {}


func _sense_candidates() -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _sense_bodies_frame:
		_sense_bodies_frame = frame
		_sense_bodies = arena.get_mechas() + _get_entities()
		_sense_decoys = get_tree().get_nodes_in_group("decoy").filter(func(d): return not d.is_gone())
	return _sense_bodies


# Whether a wall (or smoke) blocks the line to `target`, the ray cast at most
# every SIGHT_RECHECK_FRAMES frames per target; smoke is checked every time
# (clouds grow and go).
func _sight_to_blocked(target) -> bool:
	var frame := Engine.get_physics_frames()
	var id: int = target.get_instance_id()
	var from := global_position
	var to: Vector2 = target.global_position
	var entry = _sight_cache.get(id)
	# The ray is cast again after SIGHT_RECHECK_FRAMES, or at once when either
	# end has moved more than SIGHT_RECHECK_MOVE px since it was cast (a dash,
	# a knockback, a test moving a mecha): a few frames of ordinary walking
	# never move that far.
	if entry == null or frame - int(entry[0]) >= SIGHT_RECHECK_FRAMES \
			or from.distance_squared_to(entry[2]) > SIGHT_RECHECK_MOVE * SIGHT_RECHECK_MOVE \
			or to.distance_squared_to(entry[3]) > SIGHT_RECHECK_MOVE * SIGHT_RECHECK_MOVE:
		entry = [frame, MapSenses.walls_between(get_world_2d(), from, to), from, to]
		_sight_cache[id] = entry
	if entry[1]:
		return true
	return MapSenses.smoke_between(from, to)


func update_senses(dt):
	contacts.advance(dt)
	knowledge.age(dt)

	# Look for mechas and Entities in sight; a decoy looks like a mecha.
	# Nothing past the sight circle (Mecha.sight_radius) is seen.
	var own_sight_mult = MapSenses.sight_mult(self)
	var max_reach: float = sight_radius() * own_sight_mult
	var max_reach_sq := max_reach * max_reach
	for target in _sense_candidates():
		if target == self:
			continue
		_look_at(target, max_reach_sq, own_sight_mult)
	for decoy in _sense_decoys:
		if decoy.owner_mecha != self:
			_look_at(decoy, max_reach_sq, own_sight_mult)
	knowledge.end_sight_update()
	# Mines near, with the one roll to miss each; panic for the frame; the
	# aim it allows.
	var fleeing: bool = str(logic.get_current_state()) == "flee"
	var spotted: Array = knowledge.spot_mines(is_sprinting or fleeing)
	if not spotted.is_empty():
		bark("mine_spotted")
		positioning.request()
	knowledge.tick_panic(dt, under_fire_timer > 0.0, _hostiles_seen(), has_status("overheating"))
	extra_bloom = knowledge.panic * PANIC_BLOOM


# One body of the senses update: in the sight circle (the cheap
# squared-distance test first), then foliage, light and walls, it is seen. The
# head's IR sensor (IRSensing) works anywhere in the circle, foliage and
# darkness or not: a body at least as hot as its IR identification is seen,
# as a lit one is; one at least as hot as its IR sensitivity that isn't seen
# otherwise is tracked by its heat (NPCKnowledge.sensed_heat: where it is,
# live, not seen). A mecha whose illuminator is on within the circle gives
# itself away (NPCKnowledge.noticed_light, Illumination.in_light_range).
#
# Past the circle only a Fisher whose harpoon is in this NPC is seen (it's on
# the end of the tether).
func _look_at(target, max_reach_sq: float, own_sight_mult: float) -> void:
	if not is_instance_valid(target):
		return
	var far := position.distance_squared_to(target.position) > max_reach_sq
	# The cheap tests first, before even the (string-keyed) is_dead look-up:
	# past the circle, only a tether can give a body away.
	if far and not target.has_method("is_tethered_to"):
		return
	if "is_dead" in target and target.is_dead:
		return
	var velocity_seen: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
	if target.has_method("is_tethered_to") and target.is_tethered_to(self):
		knowledge.see(target, target.global_position, velocity_seen)
		return
	if far:
		return
	var light := Illumination.in_light_range(self, target)
	var heat := IRSensing.level(self, target)
	if heat == IRSensing.IDENTIFIED:
		knowledge.see(target, target.global_position, velocity_seen)
		return
	if _sees_by_eye(target, own_sight_mult):
		return
	if heat == IRSensing.SENSED:
		var track: Dictionary = knowledge.sensed_heat(target, target.global_position, velocity_seen)
		if float(track.get("since", -1.0)) == contacts.now:
			bark("contact_unknown")
	if light:
		knowledge.noticed_light(target, target.global_position, velocity_seen)


# Whether the NPC sees `target` by sight alone (in the circle, foliage, light,
# walls), and if so records it.
func _sees_by_eye(target, own_sight_mult: float) -> bool:
	var distance = position.distance_to(target.position)

	# The sight circle, shortened by foliage over the target or over us; a
	# body's heat matters only to the IR sensor, never to the eye. Inside it,
	# a target an illuminator lights (anyone's, ours included) is seen through
	# walls and all round (Illumination.seen_lit), and an unlit one only
	# within PERIPHERAL_SIGHT with no wall or smoke between (MapSenses).
	# Our own light needs no cone test of its own here: an unlit target in
	# our cone is one its shadow ray found behind a wall, or in another
	# building. Cheapest checks first: the foliage and sight checks only run
	# for targets in range.
	var reach: float = sight_radius() * own_sight_mult
	if distance > reach or distance > reach * MapSenses.detection_mult(target):
		return false
	if not Illumination.seen_lit(self, target):
		if distance > PERIPHERAL_SIGHT or _sight_to_blocked(target):
			return false
	knowledge.see(target, target.global_position, target.velocity if "velocity" in target else Vector2.ZERO)
	return true


# How many living mechas in sight this NPC holds a grudge against or was
# last attacked by.
func _hostiles_seen() -> int:
	var count := 0
	for body in knowledge.seen_bodies():
		if body.is_in_group("entity"):
			count += 1
		elif is_same(body, most_recent_attacker) or get_relationship(body).hostility > 0.0:
			count += 1
	return count


# Records that `body` gave itself away at `pos` (its round came from there),
# and returns the contact.
func _remember(body, pos: Vector2) -> Dictionary:
	return knowledge.heard_shot(body, pos)


# What this NPC knows about `target`, as a read-only view, or {} if it has
# never perceived it or has forgotten it: last_position (where it was last
# seen or heard), is_seen (in sight at the last senses update), unseen_time
# (seconds since last_position was fresh) and velocity (as last seen).
func perceived(target) -> Dictionary:
	if not knowledge.knows(target):
		return {}
	return {
		"last_position": knowledge.position_of(target),
		"is_seen": knowledge.is_seen(target),
		"unseen_time": knowledge.age_of(target),
		"velocity": knowledge.velocity_of(target),
	}


# Whether `target` was in sight at the last senses update. A scripted NPC
# has no senses and is treated as seeing everything.
func is_seeing(target) -> bool:
	if scripted:
		return is_instance_valid(target)
	return knowledge.is_seen(target)


# Where this NPC believes `target` is: its real position while in sight,
# otherwise where it was last seen or heard. With no contact on it at all,
# the NPC's own position: it never reads a position it hasn't perceived.
func get_target_position(target) -> Vector2:
	if not is_instance_valid(target):
		return global_position
	if scripted:
		return target.global_position
	return knowledge.position_of(target)


# Seconds since this NPC last saw or heard `target` (INF if it doesn't know
# it).
func time_unseen(target) -> float:
	if scripted:
		return 0.0
	return knowledge.age_of(target)


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


# LOCKING
#
# An NPC locks by the same rules as the player (Mecha: the sight circle,
# smoke, the lock rate, ECM, the target's warning), but it has no reticle to
# drag over a hidden mech, so it may only look for a lock toward a reason:
#   - a wedge (shot, sound or lock) whose sector and band the target is
#     really in (ContactStore.wedge_contains);
#   - any other contact it has that isn't a live track (a ghost, an alarm, a
#     shot or sound it placed, a squadmate's callout), or a Local lead,
#     within LOCK_SEARCH_RADIUS of the target.
# With no live track on the target, it first searches for
# lerp(LOCK_SEARCH_SLOW, LOCK_SEARCH_FAST, skill) s, LOCK_SEARCH_JITTER either
# way and within LOCK_SEARCH_FAST..LOCK_SEARCH_SLOW, and nothing shows to
# anyone while it does. Then it locks, and each second its reticle slips off
# with chance lerp(LOCK_SLIP_UNSKILLED, LOCK_SLIP_SKILLED, skill): the
# progress goes back to 0 and it carries on, with no new search. With a live
# track (LIVE_TRACK_SOURCES: it knows where to put the reticle) there is no
# search and no slip, and no reason is needed.

## Placeholders.
const LOCK_SEARCH_RADIUS := 600.0
const LOCK_SEARCH_SLOW := 5.0
const LOCK_SEARCH_FAST := 2.0
const LOCK_SEARCH_JITTER := 0.5
const LOCK_SLIP_UNSKILLED := 0.10
const LOCK_SLIP_SKILLED := 0.02
## The contact sources that follow a body live: a reticle can be put on it.
const LIVE_TRACK_SOURCES := ["sight", "ir", "light", "ward", "drone", "seeker", "flare", "biosensor", "lock"]

# Seconds of lock search left, or -1 while not searching.
var _lock_search := -1.0
## A mech it looks for a lock on with no target of its own: one inside a
## reason's area (a shot wedge at skill 0.7, identify's lock search, a lock
## back). The lock rules above still decide; while it has a valid_target,
## that is what it locks.
var lock_search_target = null

## Skill (Personality.skill, 0.5 with none) sets how long the NPC takes to
## act on a new track or wedge: lerp(REACTION_SLOW, REACTION_FAST, skill) s.
## Placeholders.
const REACTION_SLOW := 1.5
const REACTION_FAST := 0.3
## From this skill on, a shot wedge (fired on from beyond visual) starts a
## lock search on whoever is inside it at once. Placeholder.
const SKILL_LOCK_ON_WEDGE := 0.7


func skill() -> float:
	return personality.skill if personality != null else 0.5


# Someone locking it (Mecha.lock_warning): a lock_warning bark when a lock
# begins, and panic (NPCKnowledge.PANIC_LOCKED) once it is made, once per
# lock wedge. What it does about it is identify's (BaseBehaviour).
var _warned_since := -INF
var _locked_since := -INF


func _watch_lock_warning() -> void:
	var warning := lock_warning()
	if warning.is_empty():
		return
	var since: float = float(warning.wedge.get("since", 0.0))
	if since != _warned_since:
		_warned_since = since
		bark("lock_warning")
	if warning.state == "locked" and since != _locked_since:
		_locked_since = since
		knowledge.raise_panic(knowledge.PANIC_LOCKED)


func reaction_delay() -> float:
	return lerpf(REACTION_SLOW, REACTION_FAST, skill())


# A lock it just made (Mecha._advance_lock).
func _on_lock_made(_target) -> void:
	bark("locked_on")


func update_enemy_locking(dt, target):
	var valid: bool = target and is_instance_valid(target) and can_start_lock(target)
	var live := valid and has_live_track(target)
	if not valid or not (live or lock_reason_for(target)):
		_lock_search = -1.0
		_reset_locking()
		if is_same(target, lock_search_target):
			lock_search_target = null
		return
	if locking_to and not is_same(locking_to.mecha, target):
		_reset_locking()
		_lock_search = -1.0
	if not locking_to:
		if not live:
			if _lock_search < 0.0:
				_lock_search = lock_search_time()
			_lock_search -= dt
			if _lock_search > 0.0:
				return
		_lock_search = -1.0
		locking_to = {"progress": 0.0, "mecha": target}
	elif not live and randf() < lock_slip_chance() * dt:
		locking_to.progress = 0.0
	_advance_lock(dt)


## Whether a live contact follows `body` (LIVE_TRACK_SOURCES).
func has_live_track(body) -> bool:
	for contact in contacts.query({"body": body, "live": true}):
		if contact.source in LIVE_TRACK_SOURCES:
			return true
	return false


## Whether the NPC has a reason to look for a lock on `target` (see above).
func lock_reason_for(target) -> bool:
	var at: Vector2 = target.global_position
	for wedge in contacts.wedges():
		if ContactStore.wedge_contains(wedge, at):
			return true
	var radius_sq := LOCK_SEARCH_RADIUS * LOCK_SEARCH_RADIUS
	for contact in contacts.view():
		if contact.live and contact.source in LIVE_TRACK_SOURCES:
			continue
		if Vector2(contact.position).distance_squared_to(at) <= radius_sq:
			return true
	for lead in knowledge.local_leads:
		var spot = lead.get("position")
		if spot is Vector2 and spot.distance_squared_to(at) <= radius_sq:
			return true
	return false


## How long (s) this NPC searches before a lock starts (see above).
func lock_search_time() -> float:
	var skill_level := personality.skill if personality != null else 0.5
	var mean := lerpf(LOCK_SEARCH_SLOW, LOCK_SEARCH_FAST, skill_level)
	return clampf(mean + randf_range(-LOCK_SEARCH_JITTER, LOCK_SEARCH_JITTER), LOCK_SEARCH_FAST, LOCK_SEARCH_SLOW)


## The chance a second that its reticle slips off a target it has no live
## track on (see above).
func lock_slip_chance() -> float:
	var skill_level := personality.skill if personality != null else 0.5
	return lerpf(LOCK_SLIP_UNSKILLED, LOCK_SLIP_SKILLED, skill_level)


## Whether a lock-on round from `slot` can reach the locked target: an
## indirect one (VLS) comes down from above; a direct one counts as AP 0
## against walls, so any wall on the way would stop it, and it is held.
func lock_shot_clear(slot: String) -> bool:
	var weapon = build.get(slot)
	var target = get_locked_to()
	if not weapon or not target:
		return false
	if weapon.get("is_indirect_fire"):
		return true
	return not MapSenses.walls_between(get_world_2d(), global_position, target.global_position)

#COMBAT METHODS

# Threat-based target selection. Candidates are still gated by
# should_attack (flag/traitor/personality code); the score only ranks
# among permissible targets. The under-fire bonus dominates proximity so
# someone actively shooting us displaces a passive duel partner.
const TARGET_SWITCH_MARGIN := 0.75       # challenger must beat current by this
const TARGET_SWITCH_COOLDOWN_MS := 1500  # min time between voluntary switches
const TARGET_REEVAL_INTERVAL_MS := 300   # rescan rate while already engaged
## Seconds an NPC keeps a target it can neither see nor hear before it gives
## up on it.
const TARGET_MEMORY_TIME := 12.0
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


# Picks the target to fight from what this NPC perceives (see update_senses):
# a new target must be in sight, be shooting at it right now, or be a mecha
# whose illuminator gives it away within a screen of it (the player sees
# that cone on screen too); a body known only by its heat (an UNKNOWN IR
# track) isn't one. The current target is kept
# while it is remembered, even out of sight (and tracked exactly while its
# heat is sensed), until it hasn't been seen, heard or sensed for
# TARGET_MEMORY_TIME s, dies, or is further than max_shooting_distance from
# where it was last known to be.
func check_for_targets(eng_distance, max_shooting_distance):
	if valid_target and is_instance_valid(valid_target) and not valid_target.is_dead:
		if time_unseen(valid_target) > TARGET_MEMORY_TIME \
				or position.distance_to(get_target_position(valid_target)) > max_shooting_distance:
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
	for target in _candidate_targets():
		if not scripted and not knowledge.knows(target):
			continue
		if not scripted and not is_same(target, valid_target) and knowledge.known_only_by_heat(target):
			continue
		var distance = position.distance_to(get_target_position(target))
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
		positioning.request()
		_call_contact(best)
	elif best != valid_target:
		# Switch only on a clear threat margin, rate-limited so two
		# attackers can't ping-pong our attention every rescan.
		var cur_score = _threat_score(valid_target, position.distance_to(get_target_position(valid_target)), eng_distance)
		if best_score >= cur_score + TARGET_SWITCH_MARGIN \
				and now - _last_target_switch_ms >= TARGET_SWITCH_COOLDOWN_MS:
			valid_target = best
			_last_target_switch_ms = now
			positioning.request()


# A new target is called out to the squad (Squad.share_contact): a "contact"
# bark, and the contact lands in squadmates' stores after Squad.SHARE_DELAY.
func _call_contact(target) -> void:
	var squad = knowledge.squad
	if squad == null or scripted:
		return
	squad.share_contact(self, target, get_target_position(target))
	squad.callout(self, "contact", target)


# A squadmate died (Squad.on_member_died): panic, a "man down" bark, and the
# behaviour judges what to do about it (BaseBehaviour.on_mate_died).
func on_squadmate_died(member, killer, was_leader: bool) -> void:
	if is_dead:
		return
	knowledge.raise_panic(knowledge.PANIC_SQUADMATE_LOST)
	bark("man_down", member)
	if logic.behaviour and logic.behaviour.has_method("on_mate_died"):
		logic.behaviour.on_mate_died(self, member, killer, was_leader)


# Run every think: a target that is Flagged gets should_attack again. If this
# NPC shouldn't attack it now, it drops it and stops firing, but keeps it in
# its senses and contacts, so it stays wary of it; check_for_targets won't
# pick it again while should_attack says no. If it still should (a Rat, a
# traitor), it keeps it and holds fire until the grace window ends
# (holds_fire_at).
func recheck_flagged_target() -> void:
	for target in [current_target, valid_target]:
		if not is_instance_valid(target) or target.get("flag_up") != true or target.get("is_dead") == true:
			continue
		if should_attack(target):
			continue
		if is_same(valid_target, target):
			valid_target = false
		if is_same(current_target, target):
			current_target = false
		if is_same(locked_to, target):
			locked_to = false
			lock_timer = 0.0
		for slot in WEAPON_SLOTS:
			stop_shooting(slot)


# Whether this NPC holds its fire at `target`: it is in the Flag's grace
# window, when no damage counts.
func holds_fire_at(target) -> bool:
	return is_instance_valid(target) and target.has_method("is_in_flag_grace") and target.is_in_flag_grace()


# Mechas and Entities this NPC could pick as a new target: those in sight,
# and whoever is shooting at it right now. A scripted NPC has no senses and
# may pick anything.
func _candidate_targets() -> Array:
	var found := []
	if scripted:
		for target in arena.get_mechas() + _get_entities():
			if target != self and is_instance_valid(target) and not target.is_dead:
				found.append(target)
		return found
	found = knowledge.seen_bodies()
	if under_fire_timer > 0 and is_instance_valid(most_recent_attacker) \
			and not most_recent_attacker.is_dead and not found.has(most_recent_attacker):
		found.append(most_recent_attacker)
	# Mechas whose illuminator gives them away within a screen of it.
	for body in knowledge.light_bodies():
		if not found.has(body):
			found.append(body)
	# Squadmates' callouts (Squad.share_contact), and never a squadmate or
	# the squad's leader.
	var squad = knowledge.squad
	if squad != null:
		for body in knowledge.squad_bodies():
			if not found.has(body):
				found.append(body)
		found = found.filter(func(b): return not squad.is_in(b))
	return found


func _get_entities() -> Array:
	if arena and arena.has_method("get_entities"):
		return arena.get_entities()
	return []


# Other mechas' decoys still out there (Decoy): NPC sight takes them for
# mechas. Its own are left out.
func _get_decoys() -> Array:
	return get_tree().get_nodes_in_group("decoy").filter(
			func(d): return d.owner_mecha != self and not d.is_gone())


# A round from `attacker`, fired from `fired_from`, came close or hit: the
# NPC is under fire, and believes the shot came from where it makes it out
# to (Mecha.note_round_from: exactly if it sees the shooter, else its shot
# wedge's estimate point). Who fired still counts for its threat score and
# hostility (most_recent_attacker); where is the guess. Returns the guess.
func _took_round(attacker, fired_from: Vector2) -> Vector2:
	under_fire_timer = 0.5
	most_recent_attacker = attacker
	var unseen := not is_in_sight(attacker)
	var guess := note_round_from(attacker, fired_from)
	last_attack_position = guess
	if not scripted:
		_remember(attacker, guess)
		knowledge.took_fire_from(guess)
		positioning.request()
		# A skilled pilot fired on from beyond visual looks for a lock along
		# the shot wedge at once (the lock rules hold: the shooter must be in
		# the wedge and the circle).
		# A Rat never locks: a lock would give it away.
		var rat: bool = personality != null and personality.type == Personality.Type.RAT
		if unseen and not rat and skill() >= SKILL_LOCK_ON_WEDGE and attacker is Mecha \
				and not is_instance_valid(lock_search_target):
			lock_search_target = attacker
	return guess


func _on_round_hit(shooter, fired_from: Vector2) -> void:
	_took_round(shooter, fired_from)


# An Entity's bite or acid (EntityAttack): react as to being shot, knowing
# where it is (it is on top of the NPC). Rounds report themselves through
# _on_nearby_projectile_area_entered and hits (_took_round) instead.
func on_attacked_by(attacker) -> void:
	if not is_instance_valid(attacker):
		return
	under_fire_timer = 0.5
	most_recent_attacker = attacker
	last_attack_position = attacker.global_position
	_remember(attacker, attacker.global_position)
	knowledge.took_fire_from(attacker.global_position)
	_illuminator_hold = 0.0
	positioning.request()


const WEAPON_SLOTS := ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]

# Weapon slot -> the armour pen of its round; 0 for weapons that never fire
# blind (melee, lock-on and indirect fire).
var _weapon_ap := {}


# Blind fire at where `target` was last seen or heard (FireController).
# Returns whether any weapon fired.
func blind_fire(target) -> bool:
	return fire.blind_fire(target)


# A designator weapon fired through shoot() aims at where this NPC believes
# its current target is (see Mecha.fire_at_point).
func get_default_aim_point(slot: String) -> Vector2:
	if is_instance_valid(current_target):
		return get_target_position(current_target)
	return super.get_default_aim_point(slot)


# Fires every weapon it can at a target in sight (FireController.engage
# with no discipline and no heat bursts: the plain call).
func shoot_weapons(target):
	if holds_fire_at(target):
		fire.cease()
		return
	var eff: Dictionary = logic.behaviour._get_effective_distances(self) if logic.behaviour and logic.behaviour.has_method("_get_effective_distances") else {"max_shoot": INF}
	fire.engage(0.0, target, true, eff, {"heat_ratio": 0.0}, false)


func try_to_shoot(weapon_name, target):
	if fire._try_to_shoot(weapon_name, target):
		AICombatLog.record_shot(self, global_position.distance_to(target.global_position), false)


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
# projectile speed, scaled by this NPC's skill (ai_lead_accuracy), from the
# target's position and velocity as this NPC knows them. Falls back to the
# believed position when it can't or shouldn't lead. Bullet drag is ignored,
# so this slightly over-leads slow rounds.
func compute_lead_point(target) -> Vector2:
	if not is_instance_valid(target):
		return global_position
	var tpos := get_target_position(target)
	# Panic spoils the lead (NPCKnowledge.panic).
	var accuracy: float = ai_lead_accuracy * (1.0 - knowledge.panic * PANIC_LEAD_LOSS)
	if ai_projectile_speed <= 0.0 or accuracy <= 0.0:
		return tpos
	var tvel := Vector2.ZERO
	if scripted:
		tvel = target.velocity if "velocity" in target else Vector2.ZERO
	else:
		tvel = knowledge.velocity_of(target)
	if tvel == Vector2.ZERO:
		return tpos
	# Iterative intercept — converges in a few steps.
	var t := 0.0
	for i in 3:
		t = global_position.distance_to(tpos + tvel * t) / ai_projectile_speed
	var full_lead = tpos + tvel * t
	return tpos + (full_lead - tpos) * accuracy


# Navigation

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
	var profile_start := FrameProfiler.start()
	_navigate(dt, direction, wander, sprint)
	FrameProfiler.add("  navigate (in behaviour)", profile_start)


func _navigate(dt, direction: float, wander: float, sprint: bool) -> void:
	#Forward when direction = 0, Backwards when direction = 1,
	#Clockwise when direction = -0.5, Anticlockwise when direction = 0.5
	if going_to_position:
		var pos := global_position
		var goal: Vector2 = NavAgent.target_position
		# On long trips the NPC follows a planned route (see Routes); on short
		# ones, a fight's kiting included, it heads straight for the goal and
		# the context map takes it round what is in the way. The navigation
		# agent only paths on maps with no route grid.
		var foe = _combat_target()
		var route_start := FrameProfiler.start()
		var target: Vector2 = _route_next(goal, dt)
		FrameProfiler.add("    route (in navigate)", route_start)
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
		var steer_start := FrameProfiler.start()
		if _steer_hard.is_empty() or frame - _steer_built_frame >= interval:
			_steer_built_frame = frame
			_build_context()
			FrameProfiler.add("  steer_build", steer_start)
		_track_progress(dt, foe != null)
		choose_direction(dt)
		FrameProfiler.add("  steer (in behaviour)", steer_start)
		_update_orbit(dt, foe)
		var want_sprint := sprint or _car_burst_time > 0.0 or _cruise_sprint(goal, foe)
		if want_sprint:
			is_sprinting = true
		elif is_sprinting:
			stop_sprinting(chosen_dir)
		# Tanks steer by world direction; other chassis move relative to the
		# body, so they get the direction in the body's frame.
		var move_dir: Vector2 = chosen_dir if movement_type == "tank" else chosen_dir.rotated(-global_rotation)
		var move_start := FrameProfiler.start()
		apply_movement(dt, move_dir)
		FrameProfiler.add("    move (in navigate)", move_start)
		var dash_start := FrameProfiler.start()
		_update_dashes(dt, foe, direction)
		FrameProfiler.add("    dashes (in navigate)", dash_start)
		var rotate_start := FrameProfiler.start()
		if ai_aim_point != null:
			apply_rotation_by_point(dt, ai_aim_point, false)
		elif valid_target and is_instance_valid(valid_target) and is_seeing(valid_target):
			apply_rotation_by_point(dt, get_target_position(valid_target), false)
		else:
			apply_rotation_by_point(dt, target, false)
		FrameProfiler.add("    rotate (in navigate)", rotate_start)


func get_target_navigation_pos():
	if going_to_position:
		return NavAgent.get_final_location()
	return false


# Whether the NPC has reached where it was going (within the agent's
# target_desired_distance), or isn't going anywhere.
func arrived() -> bool:
	if not going_to_position:
		return true
	return global_position.distance_to(NavAgent.target_position) <= NavAgent.target_desired_distance

#Gets an randomly (uniformed) position within a circle
func get_random_point_on_radius(pos : Vector2, radius : float):
	var r = radius * sqrt(randf())
	var angle = 2*PI*randf()
	return Vector2(pos.x + r * cos(angle), pos.y + r * sin(angle))


func _on_NavigationAgent2D_navigation_finished():
	going_to_position = false


func _on_NavigationAgent2D_target_reached():
	going_to_position = false

#-------- Physics and thinking LOD

# By its distance to the player an NPC runs at one of three rates:
#   near (within THINK_FULL_DISTANCE, or anywhere the player can see it: on
#        screen and inside the player's sight circle): steps and thinks
#        every frame
#   far: steps every FAR_STEP_INTERVAL frames, thinks every FAR_THINK_STEPS
#        of those steps (every FAR_THINK_INTERVAL frames)
#   very far (beyond VERY_FAR_DISTANCE): VERY_FAR_STEP_INTERVAL and
#        VERY_FAR_THINK_STEPS the same way
# A step is the whole physics callback, the Mecha base included (heat,
# statuses, collisions, the move); the time of the frames skipped is folded
# into its dt and its moves cover their distance (Mecha._step_scale), so
# motion stays smooth. Between thinks the NPC coasts with its last velocity;
# aiming, decisions and shooting wait for the next think. With no player on
# the map (tests, benches) every NPC is near. Placeholders.
const THINK_FULL_DISTANCE := 4000.0
const VERY_FAR_DISTANCE := 8000.0
const FAR_STEP_INTERVAL := 2
const FAR_THINK_STEPS := 2
const VERY_FAR_STEP_INTERVAL := 3
const VERY_FAR_THINK_STEPS := 2
## Frames between a far NPC's thinks.
const FAR_THINK_INTERVAL := FAR_STEP_INTERVAL * FAR_THINK_STEPS
# Spreads the NPCs' step and think frames so they don't all land together.
var _think_offset := randi() % (FAR_STEP_INTERVAL * VERY_FAR_STEP_INTERVAL * 2)
var _think_dt := 0.0
var _step_dt := 0.0
var _coast_velocity := Vector2.ZERO


func is_near_player() -> bool:
	return lod_tier() == 0


## 0 near, 1 far, 2 very far (see above). An NPC the player can see (on
## screen, which follows the camera's pan, and inside the player's sight
## circle) is always near.
func lod_tier() -> int:
	if arena == null or not ("player" in arena):
		return 0
	var p = arena.player
	if p == null or not is_instance_valid(p):
		return 0
	var d := global_position.distance_squared_to(p.global_position)
	if is_on_screen():
		var sight: float = p.sight_radius()
		if d <= sight * sight:
			return 0
	if d < THINK_FULL_DISTANCE * THINK_FULL_DISTANCE:
		return 0
	return 1 if d < VERY_FAR_DISTANCE * VERY_FAR_DISTANCE else 2


## Frames between this NPC's physics steps, by its tier.
func step_interval() -> int:
	var tier := lod_tier()
	if tier == 1:
		return FAR_STEP_INTERVAL
	if tier == 2:
		return VERY_FAR_STEP_INTERVAL
	return 1


# Asked on step frames only: a far NPC thinks on every Nth of its steps.
func is_thinking_frame() -> bool:
	var tier := lod_tier()
	if tier == 0:
		return true
	var interval := FAR_STEP_INTERVAL if tier == 1 else VERY_FAR_STEP_INTERVAL
	var steps := FAR_THINK_STEPS if tier == 1 else VERY_FAR_THINK_STEPS
	var step_index := floori(float(Engine.get_physics_frames() + _think_offset) / interval)
	return step_index % steps == 0


static func think_interval(near_player: bool) -> int:
	return 1 if near_player else FAR_THINK_INTERVAL


# Whether the NPC is in or near the current camera's view.
func is_on_screen() -> bool:
	if not is_inside_tree():
		return false
	return _screen_rect().has_point(global_position)


# The screen's rectangle in world space, with the margin (MapSenses works
# it out once per physics frame for everything that asks).
func _screen_rect() -> Rect2:
	return MapSenses.screen_rect(self, ON_SCREEN_MARGIN)


## An NPC off screen refreshes its looks every VISUALS_FAR_INTERVAL frames
## (particles, glows, cooldown visuals: Mecha._physics_step), on screen every
## frame.
const VISUALS_FAR_INTERVAL := 10


func wants_visuals() -> bool:
	if is_on_screen():
		return true
	return (Engine.get_physics_frames() + _think_offset) % VISUALS_FAR_INTERVAL == 0


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
## 24 slots, 15° apart. Fewer would change the driving: a soft obstacle
## straight ahead (a vehicle the mecha could push) is worth going round only
## while the next clear direction is a slot or two away; at 22.5° a slot,
## pushing through becomes the better score.
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
const STEER_NEAR_INTERVAL := 10
const STEER_FAR_INTERVAL := 60
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
var _static_probe: PhysicsShapeQueryParameters2D = null
var _static_cast: PhysicsShapeQueryParameters2D = null
var _vehicle_field: VehicleField = null
var _building_field: BuildingField = null
# Buffers reused by every rebuild (no allocation per rebuild).
var _obstacle_buffer := PackedFloat32Array()
var _cost_by_mass := {}
var _skip_buildings := {}


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
	_add_mines()
	if Debug.get_setting("draw_debug_lines"):
		queue_redraw()


# Mines this NPC has seen (NPCKnowledge.known_mines) are hard obstacles,
# each as wide as its trigger reach plus a margin. Mines it missed, or has
# never been near, aren't here: it walks onto them.
func _add_mines() -> void:
	if knowledge.known_mines.is_empty():
		return
	var pos := global_position
	for entry in knowledge.known_mines.values():
		var at: Vector2 = entry.position
		if at.distance_squared_to(pos) > (_steer_range + MINE_AVOID_MARGIN) * (_steer_range + MINE_AVOID_MARGIN):
			continue
		_project_circle(at, float(entry.trigger_radius) + MINE_AVOID_MARGIN, true, 0.0)


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
	var costs := _cost_by_mass
	costs.clear()
	_vehicle_field.steering_obstacles_into(pos, reach + grow, _obstacle_buffer)
	var data := _obstacle_buffer
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
	var skip := _skip_buildings
	skip.clear()
	var own := field.building_at(pos)
	if own >= 0:
		skip[own] = true
	if going_to_position:
		var goal := field.building_at(NavAgent.target_position)
		if goal >= 0:
			skip[goal] = true
	for t in [valid_target, current_target]:
		if t and is_instance_valid(t):
			var b := field.building_at(get_target_position(t))
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
		var prox := 1.0 - clampf(clearance / _steer_range, 0.0, 1.0)
		_project_polygon(field.global_polygon(b), field.polygon_centre(b), dist, grow, MARK_SOFT,
				BUILDING_COST * (0.4 + 0.6 * prox))


# Marks the slots a polygon (global points, with its centre and its distance
# from the mecha) covers, inflated by `grow`, as `kind` at `value`.
func _project_polygon(poly: PackedVector2Array, centre: Vector2, dist: float, grow: float, kind: int, value: float) -> void:
	var pos := global_position
	var ref := (centre - pos).angle()
	var lo := 0.0
	var hi := 0.0
	for p in poly:
		var a := angle_difference(ref, (p - pos).angle())
		lo = minf(lo, a)
		hi = maxf(hi, a)
	var inflate := asin(clampf(grow / maxf(dist, 1.0), 0.0, 1.0))
	_mark(ref + (lo + hi) * 0.5, (hi - lo) * 0.5 + inflate, kind, value)


# Static bodies (walls, barriers, hand-made props). On a map whose building
# field gathered their outlines (BuildingField.solids_ready), they are
# projected from those outlines like buildings, hard, with no physics at all;
# standing inside an outline's clearance, only the directions into its
# nearest edge are blocked. Otherwise (hand-made maps with no field, older
# maps with tile walls): one probe every STATIC_PROBE_INTERVAL frames, and
# when something static is near, the mecha's circle is cast along each slot.
func _add_static_bodies() -> void:
	if _building_field and _building_field.solids_ready():
		_add_static_outlines()
		return
	var space := get_world_2d().direct_space_state
	var frame := Engine.get_physics_frames()
	if _static_shape == null:
		_static_shape = CircleShape2D.new()
		_static_probe = PhysicsShapeQueryParameters2D.new()
		_static_probe.shape = _static_shape
		_static_probe.collision_mask = STATIC_MASK
		_static_cast = PhysicsShapeQueryParameters2D.new()
		_static_cast.shape = _static_shape
		_static_cast.collision_mask = STATIC_MASK
	if frame - _static_probe_frame >= STATIC_PROBE_INTERVAL:
		_static_probe_frame = frame
		_static_near = false
		_static_exclude.clear()
		_static_exclude.append(get_rid())
		_static_shape.radius = _steer_range + _steer_self_radius
		_static_probe.transform = Transform2D(0.0, global_position)
		for hit in space.intersect_shape(_static_probe, 32):
			var col: Object = hit.collider
			if col is StaticBody2D or col is TileMapLayer:
				_static_near = true
			else:
				_static_exclude.append(hit.rid)
	if not _static_near:
		return
	_static_shape.radius = _steer_self_radius * STATIC_CAST_SCALE
	var cast := _static_cast
	cast.transform = Transform2D(0.0, global_position)
	cast.exclude = _static_exclude
	# Already touching something: a cast in any direction stops at once, so
	# only the directions into it are blocked (from the contact normal).
	var touching := space.get_rest_info(cast)
	if not touching.is_empty():
		var normal: Vector2 = touching.normal
		_block_into(normal)
		return
	for i in STEER_SLOTS:
		cast.motion = _slot_dirs[i] * _steer_range
		var safe: float = space.cast_motion(cast)[0]
		if safe < 1.0:
			_steer_hard[i] = maxf(_steer_hard[i], 1.0 - safe)


func _add_static_outlines() -> void:
	var field := _building_field
	var pos := global_position
	var grow := _steer_self_radius + STEER_MARGIN
	for s in field.solids_within(pos, _steer_range + grow):
		var poly := field.solid_polygon(s)
		if Geometry2D.is_point_in_polygon(pos, poly):
			_block_into(field.solid_outward_normal(s, pos))
			continue
		var dist := field.distance_to_solid(s, pos)
		var clearance := dist - grow
		if clearance > _steer_range:
			continue
		var prox := 1.0 - clampf(clearance / _steer_range, 0.0, 1.0)
		_project_polygon(poly, field.solid_centre(s), dist, grow, MARK_HARD, prox)


# Blocks every direction that leads into a surface whose outward normal is
# `normal` (the mecha is touching it or inside its clearance).
func _block_into(normal: Vector2) -> void:
	for i in STEER_SLOTS:
		if _slot_dirs[i].dot(normal) < 0.2:
			_steer_hard[i] = 1.0


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
	# The pace it would keep with nothing in the way (Mecha.free_speed: a
	# heavy legged mecha walks well under its top speed), so a slow mecha
	# making its own pace isn't taken for a blocked one.
	var speed: float = free_speed
	if movement_type == "tank":
		# A tank only drives at speed once its chassis faces the way it wants
		# to go (Mecha.apply_movement: speed scales with that dot product
		# cubed), so it isn't stuck while it turns on the spot.
		var facing: Vector2 = tank_move_target.rotated(deg_to_rad(270.0)).normalized()
		speed = max_speed * throttle * TANK_SPEED_FACTOR * pow(maxf(facing.dot(_steer_desired), 0.0), 3.0)
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
	if AICombatLog.enabled():
		var what := "nothing pushed"
		if car_jam:
			what = "car"
		elif is_instance_valid(_vehicle_field) and _vehicle_field.last_pushed_by(self) >= 0:
			what = "truck"
		AICombatLog.record_stuck(self, "blocked (%s, stage %d)" % [what, _unstick_stage])
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
	var gap := global_position.distance_to(get_target_position(foe))
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


# A round entered the NearbyProjectile area: if it comes within
# SHOT_WEDGE_RADIUS on its way (Mecha.round_comes_close), it is fire taken
# (_took_round).
func _on_nearby_projectile_area_entered(area):
	if area.original_mecha_info and \
	   area.original_mecha_info.name != mecha_name and\
	   is_instance_valid(area.original_mecha_info.body):
		var attacker = area.original_mecha_info.body
		var heading = area.get("dir")
		if not (heading is Vector2):
			heading = area.get("velocity") if area.get("velocity") is Vector2 else Vector2.ZERO
		if not round_comes_close(area.global_position, heading):
			return
		var fired_from: Vector2 = area.original_mecha_info.get("from", attacker.global_position)
		_took_round(attacker, fired_from)
		if attacker.has_method("is_player") and attacker.is_player():
			AICombatLog.record_player_shot(global_position.distance_to(attacker.global_position))
		_try_dodge(fired_from)

		# A squadmate's stray round is forgiven; anyone else's turns the
		# whole squad on the shooter. A companion shot by the player it
		# follows leaves the player's squad, and from here on takes the
		# shot as anyone would.
		var squad = knowledge.squad
		if squad != null:
			if squad.is_member(attacker):
				return
			if squad.is_leader(attacker):
				leave_squad("shot")
			else:
				squad.hostile_to(attacker)

		# Build hostility — 4 shots = max hostility
		add_hostility(attacker, 0.25)

		# Betrayal: if we're Flagged and they shoot us, mark them traitor
		if is_flagged() and not get_relationship(attacker).is_traitor:
			mark_traitor(attacker)
			AICombatLog.record_flag("traitor")


# BARKS AND LOCAL
#
# What happens to an NPC becomes barks (bark, Barks.gd) and a few broadcasts
# to Local. _watch_barks runs on thinking frames, after the behaviour, and
# compares what the NPC is doing now with what it was doing at its last
# think, so the behaviour code needs no hooks of its own:
#   spotted       it starts fighting (the engage intent's fighting stance)
#                 with its target in sight
#   lost_target   its target goes out of sight
#   searching     the target is still out of sight SEARCH_BARK_DELAY s later
#   taking_fire   the first hit of a fight
#   reloading     a weapon starts reloading during a fight
#   overheating   the overheating status comes on
#   retreating    it takes the defend stance or flees
#   target_down   its target dies
#   looting       it reaches a container, and may broadcast a loot shout
#                 (chance: personality.greed x LOOT_SHOUT_GREED)
#   extracting    it heads for an exit
#   idle          now and then while roaming (IDLE_BARK_RATE per second)
# Once per fight it also broadcasts a help call, when it is under fire below
# HELP_CALL_HEALTH structural health (NPCKnowledge._structural_health: its
# armour and components). A fight starts when it enters a combat
# intent or is hit, and ends once it is in a calm intent and no longer under
# fire. Barks and broadcasts are placeholders for the AI work to replace.

## BUDDYING UP (Phase 5): an NPC with a good standing with the player
## (standing_with_player: less than STANDING_HOSTILITY toward it, and the
## player's reputation at or above STANDING_REPUTATION; a pilot the player
## spared always) that sees the player within OFFER_RANGE may offer to buddy
## up, at OFFER_RATE per second by personality (doubled for a pilot that was
## spared, halved for an Anonymous player), once per NPC. An NPC whose help
## call the player answered (shooting the foe it called about within
## HELP_WINDOW s) offers once the fight is over, with HELP_OFFER_CHANCE by
## personality. The offer is a bark and a Local line, and the scene puts the
## prompt up (CombatScene.offer_buddy). A companion leaves when the player
## shoots it, or is further than LEAVE_DISTANCE for LEAVE_TIME s
## (leave_squad); a Rat companion betrays a player it sees at or under
## BETRAY_PLAYER_HEALTH with no other companion about, at BETRAY_PLAYER_RATE
## x treachery per second (betray_player). A Guardian that sees a pilot it
## has nothing against attacked joins it with GUARDIAN_JOIN_CHANCE. All
## placeholders.
const STANDING_HOSTILITY := 0.1
const STANDING_REPUTATION := 0
## THE INFORMATION SYSTEMS (Phase 6). Suspicion: hostility toward a pilot
## with no name on first sight, and toward everyone in sight when a sweep
## finds this NPC. A tagged squad's size (Local's roster) weighs on whether
## to fight one of its members. A car alarm is a lead for Hunters and the
## greedy (greed over ALARM_GREED); a Hunter swept sweeps back this wide. A
## helper that sees the caller it answers hit turns on the attacker by
## HELP_HOSTILITY. Placeholders.
const SUSPICION_ANONYMOUS := 0.2
const SWEPT_SUSPICION := 0.1
const SQUAD_THREAT_PER_MEMBER := 0.3
const ALARM_GREED := 0.5
const SWEEP_BACK_WIDTH := 360.0
const SWEEP_BACK_COOLDOWN := 30.0
const HELP_HOSTILITY := 0.5

var _sweep_back_due := false
var _swept_back_at := -INF
const OFFER_RANGE := 1500.0
const OFFER_RATE := {
	Personality.Type.GUARDIAN: 0.03,
	Personality.Type.PROFESSIONAL: 0.015,
	Personality.Type.SCAVENGER: 0.015,
	Personality.Type.RAT: 0.02,
	Personality.Type.HUNTER: 0.005,
}
const SPARED_OFFER_MULT := 2.0
const ANONYMOUS_OFFER_MULT := 0.5
const HELP_WINDOW := 30.0
const HELP_OFFER_CHANCE := {
	Personality.Type.GUARDIAN: 0.8,
	Personality.Type.HUNTER: 0.3,
}
const HELP_OFFER_CHANCE_DEFAULT := 0.6
const LEAVE_DISTANCE := 6000.0
const LEAVE_TIME := 60.0
const BETRAY_PLAYER_HEALTH := 0.4
const BETRAY_PLAYER_RATE := 0.1
const GUARDIAN_JOIN_CHANCE := 0.6
const LEAVE_LINES := {
	"shot": "You shot me. We're done.",
	"far": "Lost you. Going my own way.",
	"betrayal": "Nothing personal.",
}

var _offered := false
var _joined := false
var _help_called_at := -INF
var _help_foe = null
var _help_answered := false
var _far_time := 0.0


## Whether this NPC thinks well enough of the player to buddy up.
func standing_with_player() -> bool:
	var player = arena.get("player") if arena is Node else null
	if not is_instance_valid(player):
		return false
	if knowledge.spared_by.has(player.get_instance_id()):
		return true
	return get_relationship(player).hostility < STANDING_HOSTILITY \
			and PlayerProgress.get_reputation() >= STANDING_REPUTATION


## The chance this NPC offers after the player answered its help call.
func help_offer_chance() -> float:
	return float(HELP_OFFER_CHANCE.get(personality.type, HELP_OFFER_CHANCE_DEFAULT))


## Each think: a companion watches its distance from the player and, a Rat,
## its chance; anyone else may offer.
func _tick_companion(dt: float) -> void:
	var squad = knowledge.squad
	if squad != null and squad.is_player_led():
		var player = squad.leader
		if global_position.distance_to(player.global_position) > LEAVE_DISTANCE:
			_far_time += dt
			if _far_time >= LEAVE_TIME:
				leave_squad("far")
		else:
			_far_time = 0.0
		if would_betray_player() and randf() < BETRAY_PLAYER_RATE * personality.treachery * dt:
			betray_player()
		return
	if squad == null:
		_consider_offer(dt)


func _consider_offer(dt: float) -> void:
	if _offered or scripted or is_dead or is_flagged():
		return
	var player = arena.get("player") if arena is Node else null
	if not is_instance_valid(player) or player.is_dead or not is_seeing(player):
		return
	if global_position.distance_to(player.global_position) > OFFER_RANGE or not standing_with_player():
		return
	if _help_answered:
		if _in_fight:
			return
		_help_answered = false
		if randf() < help_offer_chance():
			offer_buddy()
		else:
			_offered = true
		return
	var rate: float = float(OFFER_RATE.get(personality.type, 0.01))
	if knowledge.spared_by.has(player.get_instance_id()):
		rate *= SPARED_OFFER_MULT
	if player.get("is_anonymous") == true:
		rate *= ANONYMOUS_OFFER_MULT
	if randf() < rate * dt:
		offer_buddy()


## Offers to buddy up: a bark, a Local line and the scene's prompt.
func offer_buddy() -> void:
	_offered = true
	bark("buddy_offer")
	broadcast("buddy_offer")
	AICombatLog.record_squad("offered")
	if arena is Node and arena.has_method("offer_buddy"):
		arena.offer_buddy(self)


## The player took the offer (CombatScene.accept_offer): it is in the
## player's squad now.
func on_buddy_accepted() -> void:
	_far_time = 0.0
	bark("buddy_accept")
	broadcast("buddy_accept")
	logic.evaluate_now(self)


## The player gave the squad an order (Squad.give_order).
func on_order(_kind: String) -> void:
	bark("order_ack")
	logic.evaluate_now(self)


## Leaves its squad; a companion tells Local why (LEAVE_LINES).
func leave_squad(reason: String) -> void:
	var squad = knowledge.squad
	if squad == null:
		return
	var led: bool = squad.is_player_led()
	squad.remove(self)
	if led:
		broadcast("buddy_left", str(LEAVE_LINES.get(reason, "")))
		AICombatLog.record_squad("left")


## Whether a Rat companion would turn on the player now: the player, as it
## last saw it (NPCKnowledge.health_of), at or under BETRAY_PLAYER_HEALTH,
## and no other companion.
func would_betray_player() -> bool:
	var squad = knowledge.squad
	if personality.type != Personality.Type.RAT or squad == null or not squad.is_player_led():
		return false
	if squad.alive_members().size() > 1:
		return false
	return knowledge.knows(squad.leader) and knowledge.health_of(squad.leader) <= BETRAY_PLAYER_HEALTH


## A Rat companion turns on the player: leaves the squad, hates the player,
## and knows where it is.
func betray_player() -> void:
	var squad = knowledge.squad
	if squad == null or not squad.is_player_led():
		return
	var player = squad.leader
	leave_squad("betrayal")
	bark("betrayal", player)
	add_hostility(player, 1.0)
	_remember(player, player.global_position)
	AICombatLog.record_squad("betrayed_player")
	logic.evaluate_now(self)


## A Hunter is easily provoked (Phase 7): a Flagged mech that stays within
## HUNTER_PROVOKE_RANGE of it, or keeps facing it (within HUNTER_PROVOKE_FACING
## of straight on) within HUNTER_PROVOKE_FACING_RANGE, earns
## HUNTER_PROVOKE_RATE hostility a second, until should_attack lets the
## Hunter finish it. Placeholders.
const HUNTER_PROVOKE_RANGE := 800.0
const HUNTER_PROVOKE_FACING_RANGE := 1500.0
const HUNTER_PROVOKE_FACING := 0.8
const HUNTER_PROVOKE_RATE := 0.08


# Each think: a Hunter's patience with a Flagged mech that crowds it or
# stares it down wears thin.
func _tick_provocation(dt: float) -> void:
	if personality == null or personality.type != Personality.Type.HUNTER or is_flagged():
		return
	for body in knowledge.seen_bodies():
		if body.get("flag_up") != true or body.is_in_group("entity"):
			continue
		if knowledge.squad != null and knowledge.squad.is_in(body):
			continue
		var distance: float = global_position.distance_to(body.global_position)
		var provoked: bool = distance <= HUNTER_PROVOKE_RANGE
		if not provoked and distance <= HUNTER_PROVOKE_FACING_RANGE and body.has_method("get_facing"):
			var facing: Vector2 = body.get_facing()
			provoked = facing.dot(body.global_position.direction_to(global_position)) >= HUNTER_PROVOKE_FACING
		if provoked:
			add_hostility(body, HUNTER_PROVOKE_RATE * dt)


## Chance an NPC is Anonymous: Hunters, and everyone else. Placeholders.
const HUNTER_ANONYMOUS_CHANCE := 0.6
const ANONYMOUS_CHANCE := 0.05
## Placeholders, see above.
const SEARCH_BARK_DELAY := 3.0
const IDLE_BARK_RATE := 0.02
const LOOT_SHOUT_GREED := 0.3
const HELP_CALL_HEALTH := 0.5
const COMBAT_STATES := ["engage", "search", "disengage", "flee"]
const CALM_STATES := ["roam", "investigate", "ambush", "loot", "extract", "follow", "help", "vulture", "scout"]

var _bark_ready_ms := 0
var _bark_state := ""
var _bark_stance := ""
var _bark_target = null
var _bark_target_seen := false
var _bark_unseen_time := 0.0
var _bark_searched := false
var _bark_hit := false
var _bark_reload := false
var _bark_overheating := false
var _bark_looted := 0
var _in_fight := false
var _fight_hit := false
var _fight_help := false


## Says a line for `event` (see Barks): only if the player is within
## earshot (or the scene hears every pilot: _player_in_earshot), the
## cooldowns are over and the event's chance comes up. Returns
## whether it spoke. NPC code can bark new events too; give them lines in
## database/npcs/barks.json.
func bark(event: String, target = null) -> bool:
	if is_dead or not _player_in_earshot():
		return false
	# Panicked, an event's panicked lines (event_panicked) come first.
	var type_name := Barks.type_name(personality)
	if knowledge.panic > PANIC_BARK and Barks.has_lines(event + "_panicked", type_name):
		event = event + "_panicked"
	if Time.get_ticks_msec() < _bark_ready_ms or randf() >= Barks.chance_for(event) or not Barks.global_ready():
		return false
	var line := Barks.line_for(event, type_name, mecha_name, target)
	if line == "":
		return false
	_bark_ready_ms = Time.get_ticks_msec() + int(Barks.NPC_COOLDOWN * 1000.0)
	Barks.use_global()
	say(line)
	return true


## Sends a broadcast to Local (LocalPilots.broadcast). With `text` "", one of
## the kind's lines from barks.json, else its quick chat preset text.
func broadcast(kind: String, text := "") -> void:
	var local = _local_pilots()
	if local == null:
		return
	if text == "":
		text = Barks.broadcast_line(kind)
	local.broadcast(self, kind, text)


## Whether the NPC is in a fight (see BARKS AND LOCAL).
func is_in_fight() -> bool:
	return _in_fight


func _local_pilots():
	if arena is Node:
		var local = arena.get("local_pilots")
		if local is LocalPilots:
			return local
	return null


# A scene with no player can hear every pilot (hears_every_bark: the
# observer arena).
func _player_in_earshot() -> bool:
	if not (arena is Node):
		return false
	if arena.has_method("hears_every_bark") and arena.hears_every_bark():
		return true
	var player = arena.get("player")
	return is_instance_valid(player) and global_position.distance_to(player.global_position) <= Barks.EARSHOT


func _watch_barks(dt: float) -> void:
	var state := str(logic.get_current_state())
	var hit := _bark_hit
	_bark_hit = false
	if state in COMBAT_STATES and state != _bark_state and not _in_fight:
		_start_fight()
	if hit and not _in_fight:
		_start_fight()
	if state in CALM_STATES and under_fire_timer <= 0.0 and not hit:
		_in_fight = false

	if _bark_target != null and (not is_instance_valid(_bark_target) or _bark_target.is_dead):
		if is_instance_valid(_bark_target):
			bark("target_down", _bark_target)
		_bark_target = null

	if hit and not _fight_hit:
		_fight_hit = true
		bark("taking_fire", most_recent_attacker if is_instance_valid(most_recent_attacker) else null)

	@warning_ignore("incompatible_ternary")
	var target = current_target if is_instance_valid(current_target) and not current_target.is_dead else null
	# The engage intent's stance (closing, attack, defend): a fight starts
	# when it leaves closing, and retreating is the defend stance.
	var stance: String = str(logic.behaviour.get("stance")) if state == "engage" and logic.behaviour else ""
	if state != _bark_state:
		if state == "flee":
			bark("retreating")
		elif state == "extract":
			bark("extracting")
		_bark_state = state
		_bark_stance = ""
	if stance != _bark_stance:
		var fighting := stance == "attack" or stance == "defend"
		var was_fighting := _bark_stance == "attack" or _bark_stance == "defend"
		if fighting and not was_fighting and target != null and is_seeing(target):
			bark("spotted", target)
		elif stance == "defend":
			bark("retreating")
		_bark_stance = stance

	if target != _bark_target:
		_bark_target = target
		_bark_target_seen = target != null and is_seeing(target)
		_bark_unseen_time = 0.0
		_bark_searched = false
	elif target != null:
		var seen := is_seeing(target)
		if _bark_target_seen and not seen:
			bark("lost_target", target)
			_bark_unseen_time = 0.0
			_bark_searched = false
		elif not seen and not _bark_searched:
			_bark_unseen_time += dt
			if _bark_unseen_time >= SEARCH_BARK_DELAY:
				_bark_searched = true
				bark("searching", target)
		_bark_target_seen = seen

	var hot: bool = has_status("overheating")
	if hot and not _bark_overheating:
		bark("overheating")
	_bark_overheating = hot

	if _bark_reload:
		_bark_reload = false
		if _in_fight:
			bark("reloading")

	var looted = logic.behaviour.get("times_looted") if logic.behaviour else null
	if looted is int and looted > _bark_looted:
		_bark_looted = looted
		bark("looting")
		if randf() < personality.greed * LOOT_SHOUT_GREED:
			broadcast("found_loot")

	if _in_fight and not _fight_help and (under_fire_timer > 0.0 or hit) \
			and NPCKnowledge._structural_health(self) < HELP_CALL_HEALTH:
		_fight_help = true
		broadcast("need_help")
		# Who it called for help against, for the player answering it.
		_help_called_at = knowledge.now()
		_help_foe = valid_target if is_instance_valid(valid_target) else most_recent_attacker

	if state == "roam" and randf() < IDLE_BARK_RATE * dt:
		bark("idle")


func _start_fight() -> void:
	_in_fight = true
	_fight_hit = false
	_fight_help = false


func _on_took_damage_for_barks(_mecha, is_status) -> void:
	if not is_status:
		_bark_hit = true
		_illuminator_hold = 0.0


func _on_weapon_reloading_for_barks(_reload_time) -> void:
	_bark_reload = true
