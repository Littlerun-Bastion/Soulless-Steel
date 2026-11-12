class_name StageWaitForPlayer
extends StageStep

@export var action := ""
@export var travel := 0.0
@export var player_signal := ""
@export var flag_down := false
@export var speaker := ""
@export_multiline var hint := ""

var _player = null
var _from := Vector2.ZERO


func _start() -> void:
	_player = director.get_player()
	if _player == null:
		_finish()
		return
	_from = _player.global_position
	if player_signal != "" and _player.has_signal(player_signal):
		_player.connect(player_signal, _on_player_signal)
	if hint != "":
		director.get_dialogue().say(speaker, StageKeys.expand(hint), false)
	director.hand_over()


func _process(_dt: float) -> void:
	if not is_running() or not is_instance_valid(_player):
		return
	if travel > 0.0 and _player.global_position.distance_to(_from) >= travel:
		_finish()
	elif flag_down and not _player.is_flagged():
		_finish()


func _input(event: InputEvent) -> void:
	if is_running() and action != "" and event.is_action_pressed(action):
		_finish()


func _on_player_signal(_a = null, _b = null, _c = null) -> void:
	_finish()


func _finish() -> void:
	if not is_running():
		return
	if is_instance_valid(_player) and player_signal != "" and _player.is_connected(player_signal, _on_player_signal):
		_player.disconnect(player_signal, _on_player_signal)
	if hint != "":
		director.get_dialogue().clear()
	director.take_back()
	super()
