extends CanvasLayer

@onready var ReturnButton = $SubViewportContainer/SubViewport/Control/ReturnButton

func _ready():
	disable()


func enable():
	MouseManager.show_cursor()
	$SubViewportContainer.visible = true
	ShaderEffects.reset_shader_effect("gameover")
	ReturnButton.disabled = false
	


func disable():
	$SubViewportContainer.visible = false
	ReturnButton.disabled = true


func killed():
	enable()


func _on_ReturnButton_pressed():
	TransitionManager.transition_to("res://game/start_menu/StartMenuDemo.tscn", "Rebooting System")

