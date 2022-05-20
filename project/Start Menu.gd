extends Control

const DEBUG = false

var parallaxMult = 30.0


func _ready():
	$AnimationPlayer.play("Typewrite")
	if DEBUG:
		window_debug_mode()


func _input(event):
	if event is InputEventMouseMotion:
		var viewport_size = get_viewport().size
		var mouse_x = event.position.x
		var mouse_y = event.position.y
		var relative_x = (mouse_x - (viewport_size.x/2)) / (viewport_size.x/2)
		var relative_y = (mouse_y - (viewport_size.y/2)) / (viewport_size.y/2)
		$ParallaxBackground/GridLayer.motion_offset.x = parallaxMult * relative_x
		$ParallaxBackground/GridLayer.motion_offset.y = parallaxMult * relative_y
	if event.is_action_pressed("toggle_fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
		OS.window_borderless = OS.window_fullscreen
	if event is InputEventKey:
		#For debugging since deving on fullscreen is horrible
		if event.pressed and event.scancode == KEY_L:
			window_debug_mode()


func _on_launch_system_button_pressed():
	$ShaderEffects/VCREffect.play_transition(5000.0, 0, 3.0)
	PlayerStatManager.NumberofExtracts = 0
	PlayerStatManager.Credits = 0
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/arena/Arena.tscn")


func _on_exit_system_button_pressed():
	get_tree().quit()


#For debugging since deving on fullscreen is horrible
func window_debug_mode():
	OS.window_fullscreen = false
	OS.window_borderless = false
	OS.window_size = Vector2(1080, 600)
	OS.window_position = Vector2(400, 100)


func _on_tutorial_button_pressed():
	$ShaderEffects/VCREffect.play_transition(5000.0, 0, 3.0)
	PlayerStatManager.NumberofExtracts = 0
	PlayerStatManager.Credits = 0
	get_tree().change_scene("res://game/arena/TestArena.tscn")
