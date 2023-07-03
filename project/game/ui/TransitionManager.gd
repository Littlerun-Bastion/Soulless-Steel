extends CanvasLayer

signal finished

@onready var BlockScreen = $BlockScreen
@onready var CommandLine = $CommandLine

var active = false

func _ready():
	BlockScreen.hide()


func transition_to(scene_path: String, command_line_text: String):
	if active:
		push_warning("Already has an active transition")
		return
	active = true
	
	BlockScreen.show()
	BlockScreen.color = Color.BLACK
	BlockScreen.color.a = 0.0
	var tween = get_tree().create_tween()
	tween.tween_property(BlockScreen, "color:a", 1.0, .1)
	
	await tween.finished
	
	CommandLine.display(command_line_text)
	
	await CommandLine.finished
	
# warning-ignore:return_value_discarded
	get_tree().change_scene_to_file(scene_path)
	
	await get_tree().process_frame
	
	BlockScreen.color = Color.WHITE
	tween = get_tree().create_tween()
	tween.tween_property(BlockScreen, "color:a", 0.0, .8)
	
	await tween.finished
	
	BlockScreen.hide()
	active = false
	emit_signal("finished")
