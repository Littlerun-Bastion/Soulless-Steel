class_name StageWaitForPlayer
extends StageStep

@export var action := ""
@export var travel := 0.0
@export var player_signal := ""
@export var flag_down := false
@export var speaker := ""
@export_multiline var hint := ""
## What the player may do from this turn on, if the scene withheld it.
@export var grants: Array[String] = []

var _player = null
var _from := Vector2.ZERO
var _done := false


func _start() -> void:
	_done = false
	_player = director.get_player()
	if _player == null:
		_finish()
		return
	_from = _player.global_position
	if player_signal != "" and _player.has_signal(player_signal):
		_player.connect(player_signal, _on_player_signal)
	if hint != "":
		director.get_dialogue().say(speaker, StageKeys.expand(hint), false)
	for ability in grants:
		director.grant(ability)
	director.hand_over()


func _process(_dt: float) -> void:
	if not is_running():
		return
	if _done:
		if not director.is_hud_booting():
			_finish()
		return
	if not is_instance_valid(_player):
		return
	if travel > 0.0 and _player.global_position.distance_to(_from) >= travel:
		_complete()
	elif flag_down and not _player.is_flagged():
		_complete()


func _input(event: InputEvent) -> void:
	if is_running() and action != "" and event.is_action_pressed(action):
		_complete()


func _on_player_signal(_a = null, _b = null, _c = null) -> void:
	_complete()


## Done, but the screen stays the player's until the HUD has booted.
func _complete() -> void:
	if not is_running() or _done:
		return
	_done = true
	if hint != "":
		director.get_dialogue().clear()


func _finish() -> void:
	if not is_running():
		return
	if is_instance_valid(_player) and player_signal != "" and _player.is_connected(player_signal, _on_player_signal):
		_player.disconnect(player_signal, _on_player_signal)
	if hint != "":
		director.get_dialogue().clear()
	director.take_back()
	super()
