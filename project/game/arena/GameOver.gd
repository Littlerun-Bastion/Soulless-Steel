extends CanvasLayer

onready var ReturnButton = $ViewportContainer/Viewport/Control/ReturnButton

func _ready():
	disable()


func enable():
	MouseManager.show_cursor()
	$ViewportContainer.visible = true
	ShaderEffects.reset_shader_effect("gameover")
	ReturnButton.disabled = false
	


func disable():
	$ViewportContainer.visible = false
	ReturnButton.disabled = true


func killed():
	enable()


func _on_ReturnButton_pressed():
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/start_menu/StartMenu.tscn")
