extends TestSuite

const PLAYER := preload("res://game/mecha/player/Player.tscn")


class FakeArena extends Node2D:
	var mechas: Array = []
	var local_pilots := LocalPilots.new()

	func get_mechas() -> Array:
		return mechas

	func get_entities() -> Array:
		return []

	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null
var _player = null


func run_tests() -> void:
	await case("taking control lowers a shield the player was holding up", _test_shield_dropped)
	await case("taking control lets go of a dash the player was holding", _test_dash_dropped)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	_player = PLAYER.instantiate()
	_player.mech_inventory = Inventory.new()
	_arena.add_child(_player)
	_player.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	_player.arena = _arena
	_player.mecha_name = "Player"
	_arena.mechas.append(_player)
	await get_tree().physics_frame


func _press(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	_player._input(event)


func _test_shield_dropped() -> void:
	_press("shield", true)
	var raised := await wait_until(func(): return _player.is_shielding, 2.0)
	check(raised, "the shield is up")

	_player.lock_controls()
	_press("shield", false)
	_player.unlock_controls()

	var lowered := await wait_until(func(): return not _player.is_shielding, _player.SHIELD_TOGGLE_LOCK + 1.0)
	check(lowered, "it came down, though the release came while control was taken")


func _test_dash_dropped() -> void:
	_press("thruster_dash", true)
	_player.lock_controls()
	_press("thruster_dash", false)
	_player.unlock_controls()

	await wait_seconds(_player.SPRINTING_TIMEOUT * 3.0)
	check(not _player.is_sprinting, "the held dash did not turn into a sprint")
