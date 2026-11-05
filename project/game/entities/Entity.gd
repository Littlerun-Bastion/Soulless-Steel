extends CharacterBody2D
class_name Entity

# Entities are the AVIS-synthesised creatures of the Expedition map: one body
# with hp and an armour rating, no parts or pilot. A species script (Stalker,
# ...) gives it animal behaviour in behave(). They hunt every mecha, player or
# NPC, and NPC mechas shoot back.
#
# What other code relies on (duck-typed, the way it treats a mecha):
#   group "entity"
#   take_hit(damage, pen, dir, source_info, knockback, is_aoe, impact)
#                                            projectiles and explosions; a
#                                            blast's hit is marked is_aoe
#   heard_sound(sound_data)                  loud noises (gunfire) draw them in
#   set_pause(value)                         intro freeze, tests
#   is_dead, mecha_name, velocity, last_damage_source
#   armor, components, internal_temp, overheat_temp, ecm, has_any_status(),
#   get_thermal_signature()                  read by NPC combat AI, lock-on
#                                            and IR seekers when it's a target
#
# Prey is found by heat (see the Heat exports): hotter mechas are sensed from
# further away, and prey that cools down enough is let go. Being hurt, a pack
# mate's alarm or a loud noise bring them in regardless.
#
# Memory (memory_time > 0): it perceives its prey (perceives) by its heat in
# range and in sight, by its light (Illumination.in_light_range), by having
# it within close_sense (heard and felt, cold, dark or behind a wall), or by
# being hurt by it. Each time it does, it notes where (last_known). Prey it
# no longer perceives isn't let go: it hunts where it last had it
# (target_point; the species decides how) until memory_time s have gone by
# without perceiving it, cold or not. Without memory the old rule holds:
# prey it can't sense by heat is let go at once.
#
# Use: instantiate, add to the tree, then setup(arena) (the combat scene,
# for get_mechas()). Forward is +X.
#
# Dying, it lies there as a corpse and fades, unless the scene replaces it:
# Expedition leaves a Carcass holding its bio salvage (roll_loot) instead.

signal died(entity)

const HIT_FLASH_TIME := 0.1
const CORPSE_TIME := 3.0        # lies there this long, then fades
const CORPSE_FADE_TIME := 1.5
const FAR_FROM_PLAYER := 5000.0
const NEAR_SENSE_INTERVAL := 0.25
const FAR_SENSE_INTERVAL := 1.0
const KNOCKBACK_SCALE := 20.0   # impact_force -> speed (px/s) added
## Frenzy: an Entity whose target has ticks on it (Mecha.get_tick_count)
## moves this much faster, waits this fraction of its usual time between
## attacks, and doesn't flee. Its body (SandBody.frenzy) flows faster and
## thrashes.
const FRENZY_SPEED := 1.25
const FRENZY_ATTACK_GAP := 0.5

@export var species := "Entity"
@export var max_hp := 10.0
## Weapons with less armour pen than this do half damage.
@export var armor_rating := 1
## Body radius: how close it has to get to bite.
@export var radius := 40.0
@export var walk_speed := 300.0
@export var run_speed := 600.0
@export var acceleration := 2200.0
@export var turn_rate := 8.0
@export var sight_range := 1800.0
## Gives up on prey this far away.
@export var lose_range := 3200.0
## Hit points regained per second while not hunting.
@export var regen_rate := 0.3
## Never moves (a Cyst): no movement, no knockback, not nudged by others.
@export var rooted := false
## Comes to investigate a mecha's sensor sweep (a loud sound only creatures
## hear, Mecha.sweep).
@export var hears_sweeps := true

@export_group("Heat")
## Entities find prey by its heat (Mecha.get_thermal_signature, 0 = at
## ambient, 1 = very hot). Below heat_sense_min a mecha can't be sensed at
## all. The defaults leave heat out of it.
@export_range(0.0, 1.0) var heat_sense_min := 0.0
## How far it senses prey, as a fraction of sight_range: x for a mecha at
## heat_sense_min, y for one at full heat.
@export var heat_sense_scale := Vector2(1.0, 1.0)
## A target whose heat drops below this is let go. Keep it under
## heat_sense_min, or the prey is picked straight back up. Below 0 it never
## lets go for this.
@export var release_below := -1.0
## How hot its body is (°C) to a mecha's IR sensor (IRSensing). Just above
## ambient by default, under the stock heads' sensitivity. Placeholder.
@export var body_temp := 0.0

@export_group("Memory")
## How long (s) it keeps prey it no longer perceives, hunting where it last
## had it (see Memory above). 0: let go as soon as it can't sense it.
@export var memory_time := 0.0
## Any mecha this close (px) is perceived, cold, dark or behind a wall. 0 for
## none.
@export var close_sense := 0.0

@export_group("Loot")
## What its carcass holds: loot_rolls (min, max) rolls on loot_table, plus
## rare_drop with rare_chance. See roll_loot().
@export var loot_table: LootTable
@export var loot_rolls := Vector2i(1, 2)
@export var rare_drop: item_data
@export_range(0.0, 1.0) var rare_chance := 0.0
## The carcass's inventory grid.
@export var carcass_grid := Vector2i(4, 4)
## Whether it leaves a Carcass (Expedition); without one its corpse fades.
@export var leaves_carcass := true

var arena = null
var pack: EntityPack = null
var hp := 0.0
var is_dead := false
var paused := false
var mecha_name := ""            # what kill feeds and damage attribution call it
var last_damage_source = null   # {"body", "name"} of whoever hit it last
var last_attacker: Node2D = null
var target: Node2D = null       # the mecha it's hunting
## Where it last perceived its prey (INF for nowhere), and when (its own
## clock, seconds); and whether it perceived it at the last senses check.
var last_known := Vector2.INF
var last_known_at := -INF
var target_perceived := false
var home := Vector2.ZERO        # where it wanders around
# A Cyst's guards are leashed to it (set_leash): they only fight and follow
# noises inside leash_radius of leash_center, and always settle back there.
var leash_center := Vector2.ZERO
var leash_radius := 0.0         # 0 = free to roam
var desired_velocity := Vector2.ZERO
var scripted := false
var scripted_destination = null
var scripted_aim = null
var face_point = null           # a Vector2 to face instead of where it's going

# Read by NPC combat AI, lock-on and IR seekers when an Entity is the target.
# It has no armour plates, and its one "component" is its body.
var armor := {}
var components := {}
var internal_temp := 40.0       # warm-blooded: IR seekers can track it
var overheat_temp := 100.0
var ecm := 0.0
var ecm_frequency := 1.0

## Whether the last hit was a blast's (take_hit's is_aoe).
var last_hit_aoe := false
## In frenzy this frame (see FRENZY_SPEED).
var frenzied := false

var _sense_timer := 0.0
var _clock := 0.0               # game seconds it has run (not paused)
var _flash_timer := 0.0
var _body_frenzy := false  # the body shows frenzy (has a frenzy flag)

## The Entity's look. Any Node2D works if it has a `flash` (0..1) and a `dead`
## flag, plus update_motion(velocity, dt) and die(): EntityBody for the old
## placeholder species, SandBody for the sand ones.
@onready var body_visual: Node2D = $Body
@onready var collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("entity")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	hp = max_hp
	if mecha_name == "":
		mecha_name = species
	_body_frenzy = "frenzy" in body_visual
	_update_components()


func setup(arena_ref) -> void:
	arena = arena_ref
	home = global_position
	_sense_timer = randf() * NEAR_SENSE_INTERVAL


func set_pause(value: bool) -> void:
	paused = value
	if paused:
		velocity = Vector2.ZERO
		desired_velocity = Vector2.ZERO


func _physics_process(dt: float) -> void:
	if is_dead or paused:
		return
	var profile_start := FrameProfiler.start()
	_physics_step(dt)
	FrameProfiler.add("entities", profile_start)


func _physics_step(dt: float) -> void:
	_clock += dt
	frenzied = target != null and is_valid_prey(target) and target is Mecha and target.get_tick_count() > 0
	if _body_frenzy:
		body_visual.frenzy = frenzied
	if scripted:
		_drive_scripted()
	else:
		if pack != null and pack.is_leader(self):
			pack.tick(dt)
		_sense_timer -= dt
		if _sense_timer <= 0.0:
			_sense_timer = FAR_SENSE_INTERVAL if _far_from_player() else NEAR_SENSE_INTERVAL
			_sense()
		behave(dt)
	if rooted:
		velocity = Vector2.ZERO
	else:
		velocity = velocity.move_toward(desired_velocity, acceleration * dt)
		move_and_slide()
		_turn(dt)
	_flash_timer = maxf(_flash_timer - dt, 0.0)
	body_visual.flash = 1.0 if _flash_timer > 0.0 else 0.0
	body_visual.update_motion(velocity, dt)


# ---- Species hooks ----

# Every physics frame: decide where to go (desired_velocity) and attack.
func behave(_dt: float) -> void:
	pass


func on_target_acquired(_prey: Node2D) -> void:
	pass


# False while it wants no fight (fleeing, licking its wounds).
func wants_prey() -> bool:
	return true


func on_target_lost() -> void:
	pass


func on_heard(_point: Vector2) -> void:
	pass


# Hurt by a mecha: it takes the shooter on (or keeps it) and knows where it
# fired from, cold or not (see Memory), and tells others (on_shot_from).
func on_hurt(_amount: float) -> void:
	var attacker := last_attacker
	if not is_valid_prey(attacker) or not in_territory(attacker):
		return
	if target == null and wants_prey():
		acquire_target(attacker)
	if target == attacker:
		remember(attacker.global_position)
		target_perceived = true
	on_shot_from(attacker, attacker.global_position)


## Shot by `shooter`, from about `point`: a species may pass it on.
func on_shot_from(_shooter: Node2D, _point: Vector2) -> void:
	pass


# Another pack member (or its Cyst) found prey / heard something; `point` is
# where it was told the prey is (the prey's position if not given).
func join_hunt(prey: Node2D, point := Vector2.INF) -> void:
	if target == null and wants_prey() and is_valid_prey(prey) and in_territory(prey):
		target = prey
		remember(prey.global_position if point == Vector2.INF else point)
		target_perceived = false
		on_target_acquired(prey)


## Notes that its prey is at `point` now (see Memory).
func remember(point: Vector2) -> void:
	last_known = point
	last_known_at = _clock


## Where it goes after its prey: where it is while perceived, else where it
## last had it.
func target_point() -> Vector2:
	if target == null:
		return global_position
	if target_perceived or last_known == Vector2.INF:
		return target.global_position
	return last_known


## Seconds since it last perceived its prey (INF with none).
func memory_age() -> float:
	return _clock - last_known_at if last_known != Vector2.INF else INF


func join_investigation(_point: Vector2) -> void:
	pass


# ---- Senses ----

# Its prey is let go when it's gone, or it has strayed past its leash.
# Without memory, also when too far (lose_range) or too cold (release_below),
# but never while the prey's illuminator gives it away
# (Illumination.in_light_range: a mecha with its light on within a screen
# of it).
#
# With memory (memory_time > 0), prey it perceives is noted where it is;
# prey it doesn't is kept until memory_time s after it last perceived it
# (see Memory).
func _sense() -> void:
	if target != null:
		if not is_valid_prey(target) or beyond_leash():
			lose_target()
		elif memory_time > 0.0:
			target_perceived = perceives(target)
			if target_perceived:
				remember(target.global_position)
			elif memory_age() > memory_time:
				lose_target()
		elif not Illumination.in_light_range(self, target) \
				and (distance_to(target) > lose_range or prey_heat(target) < release_below):
			lose_target()
		else:
			target_perceived = true
	if target == null and wants_prey():
		var prey := find_prey()
		if prey != null:
			acquire_target(prey)


# Whoever hurt it last, if still around; otherwise the nearest mecha it
# perceives (perceives).
func find_prey() -> Node2D:
	if is_valid_prey(last_attacker) and distance_to(last_attacker) < lose_range and in_territory(last_attacker):
		return last_attacker
	if arena == null or not arena.has_method("get_mechas"):
		return null
	var best: Node2D = null
	var best_distance := INF
	for mecha in arena.get_mechas():
		if not is_valid_prey(mecha) or not in_territory(mecha):
			continue
		var d := distance_to(mecha)
		if d >= best_distance:
			continue
		if perceives(mecha):
			best = mecha
			best_distance = d
	return best


## Whether it perceives `mecha` now: its light within a screen
## (Illumination.in_light_range); within close_sense, whatever else; or its
## heat in range (sense_range: a tree over the mecha, or over us, shortens
## it) and in sight (walls and smoke block can_see).
func perceives(mecha: Node2D) -> bool:
	if not is_valid_prey(mecha):
		return false
	if Illumination.in_light_range(self, mecha):
		return true
	var d := distance_to(mecha)
	if d <= close_sense:
		return true
	var reach := sense_range(mecha) * MapSenses.sight_mult(self)
	return d < reach and d < reach * MapSenses.detection_mult(mecha) and can_see(mecha)


# How hot a mecha runs, 0..1. Anything without a signature counts as hot.
func prey_heat(node: Node2D) -> float:
	return node.get_thermal_signature() if node.has_method("get_thermal_signature") else 1.0


# How far away it can sense this mecha (0 = not at all): further the hotter
# it runs.
func sense_range(node: Node2D) -> float:
	var heat := prey_heat(node)
	if heat < heat_sense_min:
		return 0.0
	var k := inverse_lerp(heat_sense_min, 1.0, heat) if heat_sense_min < 1.0 else 1.0
	return sight_range * lerpf(heat_sense_scale.x, heat_sense_scale.y, k)


func acquire_target(prey: Node2D) -> void:
	target = prey
	remember(prey.global_position)
	target_perceived = true
	on_target_acquired(prey)


func lose_target() -> void:
	target = null
	face_point = null
	last_known = Vector2.INF
	last_known_at = -INF
	target_perceived = false
	on_target_lost()


# ---- Leash ----

func set_leash(center: Vector2, radius_: float) -> void:
	leash_center = center
	leash_radius = radius_
	home = center


# Where to wander from after a hunt, a noise or a scare: the leash centre if
# it has one, else wherever it ended up.
func settle_home() -> void:
	home = leash_center if leash_radius > 0.0 else global_position


# Chasing prey at the edge of its territory takes it a little past the leash
# (circling, lunging); only well past it does it give up and go back.
const LEASH_SLACK := 1.4

# How far from home it wanders: its own range, but well inside a leash.
func wander_reach(wander_radius: float) -> float:
	return minf(wander_radius, leash_radius * 0.6) if leash_radius > 0.0 else wander_radius


func beyond_leash() -> bool:
	return leash_radius > 0.0 and global_position.distance_to(leash_center) > leash_radius * LEASH_SLACK


# Leashed Entities only take on what comes into their territory.
func in_territory(node: Node2D) -> bool:
	return leash_radius <= 0.0 or node.global_position.distance_to(leash_center) <= leash_radius


func is_valid_prey(node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree() \
			and node.is_in_group("mecha") and not node.is_dead


# Line of sight; other Entities and vehicles don't block it (they're low to
# the ground). Building walls and smoke do.
func can_see(node: Node2D) -> bool:
	if MapSenses.smoke_between(global_position, node.global_position):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, node.global_position, MapSenses.SIGHT_MASK)
	query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.collider == node or result.collider is Entity


func heard_sound(sound_data: Dictionary) -> void:
	if is_dead or paused or target != null:
		return
	if sound_data.get("volume_type") != "loud":
		return
	if sound_data.get("type") == "sweep" and not hears_sweeps:
		return
	if leash_radius > 0.0 and sound_data.position.distance_to(leash_center) > leash_radius:
		return
	on_heard(sound_data.position)


# ---- Damage ----

# knockback is in weapon impact_force units (OM1810: 20). is_aoe marks a
# blast's hit (complex_projectile's explosion); impact is where it landed
# (INF when the caller doesn't say).
func take_hit(damage: float, pen: int, dir := Vector2.ZERO, source_info = null, knockback := 0.0,
		is_aoe := false, _impact := Vector2.INF) -> void:
	if is_dead:
		return
	last_hit_aoe = is_aoe
	var dealt := damage if pen >= hit_armor(dir) else damage * 0.5
	hp = maxf(hp - dealt, 0.0)
	_update_components()
	if typeof(source_info) == TYPE_DICTIONARY:
		last_damage_source = source_info
		var body = source_info.get("body")
		if body != self and is_valid_prey(body):
			last_attacker = body
	if knockback > 0.0 and dir != Vector2.ZERO:
		velocity += dir.normalized() * knockback * KNOCKBACK_SCALE
	_flash_timer = HIT_FLASH_TIME
	if hp <= 0.0:
		die()
	else:
		on_hurt(dealt)


# The armour a hit travelling along dir meets (a species may cover a side).
func hit_armor(_dir: Vector2) -> int:
	return armor_rating


func die() -> void:
	if is_dead:
		return
	is_dead = true
	desired_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	collision.set_deferred("disabled", true)
	remove_from_group("entity")
	if pack != null:
		pack.remove(self)
	AudioManager.play_sfx("medium_impact1", global_position)
	body_visual.die()
	died.emit(self)
	# The scene may have replaced the corpse with a Carcass and freed it.
	if is_queued_for_deletion():
		return
	var fade := create_tween()
	fade.tween_interval(CORPSE_TIME)
	fade.tween_property(self, "modulate:a", 0.0, CORPSE_FADE_TIME)
	fade.tween_callback(queue_free)


# The bio salvage its carcass holds. Takes an optional seeded rng (tests).
func roll_loot(rng: RandomNumberGenerator = null) -> Array:
	var stacks := []
	if loot_table != null:
		var count := rng.randi_range(loot_rolls.x, loot_rolls.y) if rng else randi_range(loot_rolls.x, loot_rolls.y)
		stacks.append_array(loot_table.roll_stacks(count, rng))
	if rare_drop != null and (rng.randf() if rng else randf()) < rare_chance:
		stacks.append(item_stack.from_generic(rare_drop))
	return stacks


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	_update_components()


func get_hp_fraction() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func has_any_status() -> bool:
	return false


func get_thermal_signature() -> float:
	return 0.5


## Its body temperature in °C, for IR sensors (IRSensing).
func get_body_temp() -> float:
	return body_temp


func _update_components() -> void:
	components = {"body": {"tissue": {"hp": ceili(hp), "max_hp": ceili(max_hp)}}}


# ---- Movement ----

func set_scripted(value: bool) -> void:
	scripted = value
	scripted_destination = null
	scripted_aim = null
	if value:
		paused = false
		target = null
		face_point = null
		stop()


func walk_to(point) -> void:
	scripted_destination = point


func stop_walking() -> void:
	scripted_destination = null
	stop()


func _drive_scripted() -> void:
	face_point = scripted_aim
	if scripted_destination == null:
		stop()
	else:
		move_to(scripted_destination, walk_speed)


func move_to(point: Vector2, speed: float, arrive_distance := 40.0) -> void:
	var to := point - global_position
	if to.length() <= arrive_distance:
		desired_velocity = Vector2.ZERO
	else:
		desired_velocity = to.normalized() * speed * speed_mult()


func move_in(dir: Vector2, speed: float) -> void:
	desired_velocity = dir.normalized() * speed * speed_mult()


# Movement speed multiplier: faster in frenzy.
func speed_mult() -> float:
	return FRENZY_SPEED if frenzied else 1.0


# Multiplier on the time between attacks: shorter in frenzy.
func attack_gap_mult() -> float:
	return FRENZY_ATTACK_GAP if frenzied else 1.0


func stop() -> void:
	desired_velocity = Vector2.ZERO


func forward() -> Vector2:
	return Vector2.RIGHT.rotated(rotation)


func distance_to(node: Node2D) -> float:
	return global_position.distance_to(node.global_position)


# A random point within radius of center, on the map's navmesh when it has one.
func random_point_near(center: Vector2, radius_: float) -> Vector2:
	var point := center + Vector2.from_angle(randf() * TAU) * radius_ * sqrt(randf())
	if arena != null and arena.has_method("_ensure_position_on_nav"):
		point = arena._ensure_position_on_nav(point)
	return point


func _turn(dt: float) -> void:
	var dir: Vector2 = (face_point - global_position) if face_point is Vector2 else velocity
	if dir.length() < 5.0:
		return
	rotation = lerp_angle(rotation, dir.angle(), clampf(turn_rate * dt, 0.0, 1.0))


# Shots and globs fly above everything: in the scene's projectile layer when
# it has one.
func _projectile_parent() -> Node:
	var projectiles = arena.get("Projectiles") if is_instance_valid(arena) else null
	return projectiles if projectiles is Node else get_parent()


func _far_from_player() -> bool:
	if arena == null or not ("player" in arena):
		return false
	var player = arena.player
	return player != null and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) > FAR_FROM_PLAYER
