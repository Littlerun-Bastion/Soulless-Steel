extends CharacterBody2D
class_name Entity

# Entities are the AVIS-synthesised creatures of the Expedition map: one body
# with hp and an armour rating, no parts or pilot. A species script (Stalker,
# ...) gives it animal behaviour in behave(). They hunt every mecha, player or
# NPC, and NPC mechas shoot back.
#
# What other code relies on (duck-typed, the way it treats a mecha):
#   group "entity"
#   take_hit(damage, pen, dir, source_info)  projectiles and explosions
#   heard_sound(sound_data)                  loud noises (gunfire) draw them in
#   set_pause(value)                         intro freeze, tests
#   is_dead, mecha_name, velocity, last_damage_source
#   armor, components, internal_temp, overheat_temp, ecm, has_any_status(),
#   get_thermal_signature()                  read by NPC combat AI, lock-on
#                                            and IR seekers when it's a target
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

@export_group("Loot")
## What its carcass holds: loot_rolls (min, max) rolls on loot_table, plus
## rare_drop with rare_chance. See roll_loot().
@export var loot_table: LootTable
@export var loot_rolls := Vector2i(1, 2)
@export var rare_drop: item_data
@export_range(0.0, 1.0) var rare_chance := 0.0
## The carcass's inventory grid.
@export var carcass_grid := Vector2i(4, 4)

var arena = null
var pack: EntityPack = null
var hp := 0.0
var is_dead := false
var paused := false
var mecha_name := ""            # what kill feeds and damage attribution call it
var last_damage_source = null   # {"body", "name"} of whoever hit it last
var last_attacker: Node2D = null
var target: Node2D = null       # the mecha it's hunting
var home := Vector2.ZERO        # where it wanders around
var desired_velocity := Vector2.ZERO
var face_point = null           # a Vector2 to face instead of where it's going

# Read by NPC combat AI, lock-on and IR seekers when an Entity is the target.
# It has no armour plates, and its one "component" is its body.
var armor := {}
var components := {}
var internal_temp := 40.0       # warm-blooded: IR seekers can track it
var overheat_temp := 100.0
var ecm := 0.0
var ecm_frequency := 1.0

var _sense_timer := 0.0
var _flash_timer := 0.0

@onready var body_visual: EntityBody = $Body
@onready var collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("entity")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	hp = max_hp
	if mecha_name == "":
		mecha_name = species
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
	if pack != null and pack.is_leader(self):
		pack.tick(dt)
	_sense_timer -= dt
	if _sense_timer <= 0.0:
		_sense_timer = FAR_SENSE_INTERVAL if _far_from_player() else NEAR_SENSE_INTERVAL
		_sense()
	behave(dt)
	velocity = velocity.move_toward(desired_velocity, acceleration * dt)
	move_and_slide()
	_turn(dt)
	_flash_timer = maxf(_flash_timer - dt, 0.0)
	body_visual.flash = 1.0 if _flash_timer > 0.0 else 0.0
	body_visual.update_motion(velocity.length(), dt)


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


func on_hurt(_amount: float) -> void:
	if target == null and wants_prey() and is_valid_prey(last_attacker):
		acquire_target(last_attacker)


# Another pack member found prey / heard something.
func join_hunt(prey: Node2D) -> void:
	if target == null and wants_prey() and is_valid_prey(prey):
		target = prey
		on_target_acquired(prey)


func join_investigation(_point: Vector2) -> void:
	pass


# ---- Senses ----

func _sense() -> void:
	if target != null:
		if not is_valid_prey(target) or distance_to(target) > lose_range:
			lose_target()
	if target == null and wants_prey():
		var prey := find_prey()
		if prey != null:
			acquire_target(prey)


# Whoever hurt it last, if still around; otherwise the nearest mecha it can see.
func find_prey() -> Node2D:
	if is_valid_prey(last_attacker) and distance_to(last_attacker) < lose_range:
		return last_attacker
	if arena == null or not arena.has_method("get_mechas"):
		return null
	var best: Node2D = null
	var best_distance := sight_range
	for mecha in arena.get_mechas():
		if not is_valid_prey(mecha):
			continue
		var d := distance_to(mecha)
		if d < best_distance and can_see(mecha):
			best = mecha
			best_distance = d
	return best


func acquire_target(prey: Node2D) -> void:
	target = prey
	on_target_acquired(prey)


func lose_target() -> void:
	target = null
	face_point = null
	on_target_lost()


func is_valid_prey(node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree() \
			and node.is_in_group("mecha") and not node.is_dead


# Line of sight; other Entities don't block it (they're low to the ground).
func can_see(node: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, node.global_position)
	query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.collider == node or result.collider is Entity


func heard_sound(sound_data: Dictionary) -> void:
	if is_dead or paused or target != null:
		return
	if sound_data.get("volume_type") != "loud":
		return
	on_heard(sound_data.position)


# ---- Damage ----

# knockback is in weapon impact_force units (OM1810: 20).
func take_hit(damage: float, pen: int, dir := Vector2.ZERO, source_info = null, knockback := 0.0) -> void:
	if is_dead:
		return
	var dealt := damage if pen >= armor_rating else damage * 0.5
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


func _update_components() -> void:
	components = {"body": {"tissue": {"hp": ceili(hp), "max_hp": ceili(max_hp)}}}


# ---- Movement ----

func move_to(point: Vector2, speed: float, arrive_distance := 40.0) -> void:
	var to := point - global_position
	if to.length() <= arrive_distance:
		desired_velocity = Vector2.ZERO
	else:
		desired_velocity = to.normalized() * speed


func move_in(dir: Vector2, speed: float) -> void:
	desired_velocity = dir.normalized() * speed


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


func _far_from_player() -> bool:
	if arena == null or not ("player" in arena):
		return false
	var player = arena.player
	return player != null and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) > FAR_FROM_PLAYER
