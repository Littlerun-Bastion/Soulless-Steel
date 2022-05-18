extends CanvasLayer

func _ready():
	$Control.hide()


func _on_Quit_pressed():
	get_tree().quit()


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
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
