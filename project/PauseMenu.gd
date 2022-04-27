extends CanvasLayer

func _ready():
	pass 


func _on_Quit_pressed():
	get_tree().quit()


func _on_Resume_pressed():
	$Control.hide()


func _on_PauseMenu_visibility_changed():
	get_tree().paused = not get_tree().paused


func toggle_pause():
	$Control.visible = not $Control.visible
