extends Node

# What one observer-arena dummy does (ObserverArena.spawn_dummy). It is a
# child of the dummy, a scripted Enemy, and drives it every physics step:
#   move      stand, or walk the patrol points in order, round and round
#   light     its illuminator off, on, or flashing (on and off every
#             FLASH_TIME s)
#   fire      every fire_interval s, one shot from its right arm at the fire
#             point or at the arena's selected NPC (aiming for AIM_TIME s
#             first; a gun spools up on the first shoot() after it stopped,
#             so it keeps pulling the trigger for up to TRIGGER_FRAMES
#             physics frames until the round is out); never with the Flag up
#   flag      the Flag up (raise_flag, by choice) or down (lower_flag)
# A dummy is a test tool: it aims at the selected NPC's true position.

enum Move { STAND, PATROL }
enum Light { OFF, ON, FLASH }
enum Fire { OFF, POINT, NPC }

## Placeholders.
const FLASH_TIME := 1.0
const AIM_TIME := 0.4
const TRIGGER_FRAMES := 20
const ARRIVE_DISTANCE := 250.0
const FIRE_SLOT := "arm_weapon_right"
const MIN_INTERVAL := 1.0
const MAX_INTERVAL := 20.0

var arena = null
var dummy = null
var move: Move = Move.STAND
var light: Light = Light.OFF
var fire: Fire = Fire.OFF
var fire_interval := 3.0
var fire_point := Vector2.INF
var patrol_points: Array[Vector2] = []
## Shots fired so far (tests).
var shots := 0

var _patrol_index := 0
var _flash_time := 0.0
var _fire_time := 0.0
var _aiming := 0.0
var _trigger := 0


func setup(arena_ref, dummy_ref) -> void:
	arena = arena_ref
	dummy = dummy_ref


func set_move(value: Move) -> void:
	move = value
	_patrol_index = 0
	if move == Move.STAND:
		dummy.stop_walking()


func set_light(value: Light) -> void:
	light = value
	_flash_time = 0.0
	dummy.set_illuminator(light != Light.OFF)


func set_fire(value: Fire) -> void:
	fire = value
	_fire_time = fire_interval
	_aiming = 0.0
	if fire == Fire.OFF:
		dummy.scripted_aim = null
		dummy.stop_shooting(FIRE_SLOT)


func set_flag(up: bool) -> void:
	if up and not dummy.is_flagged():
		dummy.raise_flag(true)
	elif not up and dummy.is_flagged() and not dummy.is_lowering_flag():
		dummy.lower_flag()


func add_patrol_point(point: Vector2) -> void:
	patrol_points.append(point)


func clear_patrol() -> void:
	patrol_points.clear()
	_patrol_index = 0
	dummy.stop_walking()


## Where it fires at now, or null for nowhere.
func fire_target():
	if fire == Fire.POINT and fire_point != Vector2.INF:
		return fire_point
	if fire == Fire.NPC and arena != null and is_instance_valid(arena.selected_npc) \
			and not is_same(arena.selected_npc, dummy):
		return arena.selected_npc.global_position
	return null


func _physics_process(dt: float) -> void:
	if not is_instance_valid(dummy) or dummy.is_dead or dummy.paused:
		return
	_tick_move()
	_tick_light(dt)
	_tick_fire(dt)


func _tick_move() -> void:
	if move != Move.PATROL or patrol_points.is_empty():
		return
	_patrol_index = posmod(_patrol_index, patrol_points.size())
	var point: Vector2 = patrol_points[_patrol_index]
	if dummy.global_position.distance_to(point) <= ARRIVE_DISTANCE:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		point = patrol_points[_patrol_index]
	dummy.walk_to(point)


func _tick_light(dt: float) -> void:
	if light != Light.FLASH:
		return
	_flash_time += dt
	if _flash_time >= FLASH_TIME:
		_flash_time = 0.0
		dummy.set_illuminator(not dummy.illuminator_on)


func _tick_fire(dt: float) -> void:
	var target = fire_target()
	if target == null:
		return
	dummy.scripted_aim = target
	if dummy.is_flagged():
		_trigger = 0
		return
	if _trigger > 0:
		_pull_trigger()
		return
	if _aiming > 0.0:
		_aiming -= dt
		if _aiming <= 0.0:
			var node = dummy.get_weapon_part(FIRE_SLOT)
			if node and node.can_reload() == "yes" and node.is_clip_empty() and not node.is_reloading():
				node.reload()
			elif node:
				_trigger = TRIGGER_FRAMES
				_pull_trigger()
		return
	_fire_time -= dt
	if _fire_time <= 0.0:
		_fire_time = fire_interval
		_aiming = AIM_TIME


func _pull_trigger() -> void:
	var node = dummy.get_weapon_part(FIRE_SLOT)
	if node == null:
		_trigger = 0
		return
	var before = node.clip_ammo
	dummy.shoot(FIRE_SLOT)
	_trigger -= 1
	if node.clip_ammo != before:
		shots += 1
		_trigger = 0
	if _trigger <= 0:
		dummy.stop_shooting(FIRE_SLOT)
