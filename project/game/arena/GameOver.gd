extends CanvasLayer


func _ready():
	reset()


func reset():
	$Label.visible = false
	$ReturnButton.visible = false


func killed():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ShaderEffects.reset_shader_effect("gameover")
	$Label.visible = true
	$ReturnButton.visible = true


func _on_ReturnButton_pressed():
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/start_menu/StartMenu.tscn")
