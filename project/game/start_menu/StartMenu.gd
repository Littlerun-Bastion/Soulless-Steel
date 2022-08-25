extends Control

onready var Parallax = $ParallaxBackground
onready var VCREffect = $ShaderEffects/VCREffect

var parallaxMult = 30.0


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$AnimationPlayer.play("Typewrite")
	AudioManager.play_bgm("main-menu")
	if Debug.ACTIVE:
		Debug.window_debug_mode()


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
			Debug.window_debug_mode()


func start_game(mode):
	VCREffect.play_transition(5000.0, 0, 3.0)
	AudioManager.stop_bgm()
	PlayerStatManager.NumberofExtracts = 0
	PlayerStatManager.Credits = 0
	match mode:
		"main":
			ArenaManager.set_map_to_load("map1")
		"tutorial":
			ArenaManager.set_map_to_load("tutorial")
		_:
			push_error("Not a valid mode: " + str(mode))
	# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/arena/Arena.tscn")

func _on_Button_mouse_entered():
	AudioManager.play_sfx("select")
	Parallax.mouse_hovered = true


func _on_Button_mouse_exited():
	Parallax.mouse_hovered = false


func _on_TutorialButton_pressed():
	AudioManager.play_sfx("confirm")
	start_game("tutorial")



func _on_LaunchSystemButton_pressed():
	AudioManager.play_sfx("confirm")
	start_game("main")



func _on_SettingsButton_pressed():
	AudioManager.play_sfx("back")


func _on_ExitButton_pressed():
	AudioManager.play_sfx("back")
	get_tree().quit()


