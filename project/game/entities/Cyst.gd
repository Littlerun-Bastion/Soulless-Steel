extends Entity
class_name Cyst

# Cyst: an Entity nest grown into the ground (rooted). It can't move or attack. It
# sleeps until a mecha (player or NPC) comes within wake_range; awake, it
# keeps up to max_guards Stalkers and Spitters alive around it, hatching one
# every spawn_interval, up to max_spawns over its life. Its guards are
# leashed (Entity.set_leash): they defend the ground around it rather than
# roam. Hitting it wakes it and sets its guards on the attacker. It regrows
# slowly, and when destroyed bursts open into a rich carcass (entity_cyst
# loot, and a good chance of an NT Engine Heart).
#
# Needs a scene with add_entity(scene, position) to hatch guards (Expedition).

const STALKER := preload("res://game/entities/Stalker.tscn")
const SPITTER := preload("res://game/entities/Spitter.tscn")
const WAKE_CHECK_INTERVAL := 0.5

@export_group("Brood")
@export var wake_range := 2500.0
@export var max_guards := 4
@export var max_spawns := 12
@export var spawn_interval := 3.0
## Seconds from waking to the first guard hatching.
@export var first_spawn_delay := 0.5
@export_range(0.0, 1.0) var spitter_chance := 0.25
## Guards hatch this far out from its edge.
@export var hatch_distance := 220.0
@export var guard_leash := 1800.0

var awake := false
var guards: Array = []
var spawned := 0   # guards hatched over its life

var _guard_pack := EntityPack.new()
var _spawn_timer := 0.0
var _wake_timer := 0.0


func _ready() -> void:
	super._ready()
	_spawn_timer = first_spawn_delay


# It doesn't hunt.
func wants_prey() -> bool:
	return false


func behave(dt: float) -> void:
	heal(regen_rate * dt)
	guards = guards.filter(func(g): return is_instance_valid(g) and not g.is_dead)
	_wake_timer -= dt
	if _wake_timer <= 0.0:
		_wake_timer = WAKE_CHECK_INTERVAL
		if not awake:
			awake = _mecha_near()
	(body_visual as CystBody).awake = awake
	if not awake:
		return
	_spawn_timer -= dt
	if _spawn_timer <= 0.0 and guards.size() < max_guards and spawned < max_spawns:
		_spawn_timer = spawn_interval
		hatch_guard()


func on_hurt(_amount: float) -> void:
	awake = true
	if is_valid_prey(last_attacker):
		for guard in guards:
			guard.join_hunt(last_attacker)


func _mecha_near() -> bool:
	if arena == null or not arena.has_method("get_mechas"):
		return false
	for mecha in arena.get_mechas():
		if is_valid_prey(mecha) and distance_to(mecha) <= wake_range:
			return true
	return false


# A Stalker (joining its brood pack) or a Spitter, leashed to the Cyst.
func hatch_guard() -> Entity:
	if arena == null or not arena.has_method("add_entity"):
		return null
	var scene: PackedScene = SPITTER if randf() < spitter_chance else STALKER
	var offset := Vector2.from_angle(randf() * TAU) * (radius + hatch_distance * randf_range(0.6, 1.0))
	var guard: Entity = arena.add_entity(scene, global_position + offset)
	guard.set_leash(global_position, guard_leash)
	if guard is Stalker:
		_guard_pack.add(guard)
	guards.append(guard)
	spawned += 1
	# Hatched mid-fight: straight into it.
	if is_valid_prey(last_attacker):
		guard.join_hunt(last_attacker)
	AudioManager.play_sfx("medium_impact2", global_position)
	return guard
