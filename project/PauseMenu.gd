extends CanvasLayer

func _ready():
	$Control.hide()


func _on_Quit_pressed():
	get_tree().change_scene("res://Start Menu.tscn")


func _on_Resume_pressed():
	$Control.hide()


func _on_PauseMenu_visibility_changed():
	get_tree().paused = not get_tree().paused


func toggle_pause():
	$Control.visible = not $Control.visible
	$ParallaxBackground/GridLayer.visible = not $ParallaxBackground/GridLayer.visible
	$ParallaxBackground/GridLayer2.visible = not $ParallaxBackground/GridLayer2.visible
	if $Control.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		$ShaderEffects/VCREffect.play_transition(0, 3000, 2.0)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

