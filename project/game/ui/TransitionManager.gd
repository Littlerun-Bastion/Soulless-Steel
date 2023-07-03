extends CanvasLayer

signal finished

@onready var BlackScreen = $BlackScreen

var active = false

func _ready():
	BlackScreen.hide()


func transition_to(scene_path: String):
	if active:
		push_warning("Already has an active transition")
		return
	active = true
	
	BlackScreen.show()
	BlackScreen.color.a = 0.0
	var tween = get_tree().create_tween()
	tween.tween_property(BlackScreen, "modulate:a", 1.0, .1)
	
	await tween.finished
	
	
	
# warning-ignore:return_value_discarded
	get_tree().change_scene(scene_path)
	yield(get_tree(), "idle_frame")
	
	tween.interpolate_property(material, "shader_param/value", 1, 0, DURATION_2)
	tween.start()
	
	AudioManager.play_sfx("transition_out")
	yield(tween, "tween_completed")
	yield(get_tree(), "idle_frame")
	active = false
	transition_texture.hide()
	
	emit_signal("finished")
