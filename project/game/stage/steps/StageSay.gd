class_name StageSay
extends StageStep

enum Advance { INPUT, TIMED }

const ADVANCE_ACTIONS := [
	"arm_weapon_left_shoot",
	"arm_weapon_right_shoot",
	"shoulder_weapon_left_shoot",
	"shoulder_weapon_right_shoot",
	"thruster_dash",
	"shield",
	"interact",
	"reload_mode",
	"lock_mode",
	"confirm",
]

@export var speaker := ""
@export_multiline var text := ""
@export var advance_on: Advance = Advance.INPUT
@export var seconds := 2.5


func advance() -> void:
	if not is_running():
		return
	var dialogue := director.get_dialogue()
	if dialogue != null and dialogue.is_revealing():
		dialogue.finish_reveal()
		return
	_finish()


func _start() -> void:
	var dialogue := director.get_dialogue()
	if dialogue == null:
		_finish()
		return
	dialogue.say(speaker, text)
	if advance_on == Advance.TIMED:
		get_tree().create_timer(seconds).timeout.connect(_finish)


func _finish() -> void:
	var dialogue := director.get_dialogue() if director != null else null
	if dialogue != null:
		dialogue.clear()
	super()


func _unhandled_input(event: InputEvent) -> void:
	if not is_running() or advance_on != Advance.INPUT:
		return
	for action in ADVANCE_ACTIONS:
		if event.is_action_pressed(action):
			advance()
			get_viewport().set_input_as_handled()
			return
