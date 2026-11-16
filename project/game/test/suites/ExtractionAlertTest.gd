extends TestSuite

const PLAYER := preload("res://game/mecha/player/Player.tscn")
const THEME := preload("res://game/ui/mech_os/MechTheme.tres")


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
var _alerts: HudAlerts = null


func run_tests() -> void:
	await case("extracting shows a bar that fills and the time left", _test_bar_fills)
	await case("the bar shows under a more urgent alert too", _test_bar_under_critical)
	await case("leaving the exit says the extraction was cancelled", _test_cancelled)
	await case("coming straight back to the exit shows the extraction again", _test_back_at_once)


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
	var canvas := Control.new()
	canvas.theme = THEME
	canvas.size = Vector2(1920, 1080)
	_arena.add_child(canvas)
	_alerts = HudAlerts.new()
	canvas.add_child(_alerts)
	_alerts.setup(_player)
	await get_tree().physics_frame


func _start_extracting() -> void:
	_player.extracting()
	_alerts.extracting = true


func _test_bar_fills() -> void:
	_start_extracting()
	await wait_frames(2)
	var early: float = _alerts.get_extract_ratio()
	check(_alerts.get_current().begins_with("EXTRACTING"), "the alert says so (%s)" % _alerts.get_current())
	check(_alerts.is_extract_bar_shown(), "with a bar")

	await wait_seconds(1.0)
	var later: float = _alerts.get_extract_ratio()
	check(later > early and later < 1.0, "which fills as the seconds go (%.2f, then %.2f)" % [early, later])
	check(_alerts.get_current().contains("s"), "beside the time left (%s)" % _alerts.get_current())


func _test_bar_under_critical() -> void:
	_player.raise_flag()
	_start_extracting()
	await wait_frames(2)

	check(_alerts.get_current().begins_with("!"), "the Flag's alert is on show (%s)" % _alerts.get_current())
	check(_alerts.is_extract_bar_shown(), "and the extraction bar with it")


func _test_cancelled() -> void:
	_start_extracting()
	await wait_frames(2)

	_player.cancel_extract()
	_alerts.extracting = false
	await wait_frames(2)

	check_eq(_alerts.get_current(), "EXTRACTION CANCELLED", "the alert says it was cancelled")
	check(not _alerts.is_extract_bar_shown(), "and the bar is gone")


func _test_back_at_once() -> void:
	_start_extracting()
	await wait_frames(2)
	_player.cancel_extract()
	_alerts.extracting = false
	await wait_frames(2)

	_start_extracting()
	await wait_frames(2)

	check(_alerts.get_current().begins_with("EXTRACTING"), "the alert says it is extracting again (%s)" % _alerts.get_current())
