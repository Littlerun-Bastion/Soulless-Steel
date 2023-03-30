extends Control

@onready var Parallax = $ParallaxBackground

var parallaxMult = 30.0


func _ready():
	FileManager.load_game()
	
	if Debug.get_setting("window"):
		Debug.window_debug_mode()
	
	randomize()
	MouseManager.show_cursor()
	ShaderEffects.reset_shader_effect("main_menu")
	$AnimationPlayer.play("Typewrite")
	AudioManager.play_bgm("main-menu")
	
	if Debug.get_setting("go_to_mode"):
		await get_tree().idle_frame
		start_game(Debug.get_setting("go_to_mode"))


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
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if get_window().mode != Window.MODE_EXCLUSIVE_FULLSCREEN else Window.MODE_WINDOWED
		Profile.set_option("fullscreen", get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN, true)
		if get_window().mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
			await get_tree().process_frame
			get_window().size = Profile.WINDOW_SIZES[Profile.get_option("window_size")]
			get_window().position = Vector2(0,0)


func start_game(mode):
	AudioManager.stop_bgm()
	PlayerStatManager.NumberofExtracts = 0
	PlayerStatManager.Credits = 0
	match mode:
		"main":
			ArenaManager.set_map_to_load("map1")
		"tutorial":
			ArenaManager.set_map_to_load("tutorial")
		"test":
			ArenaManager.set_map_to_load("test_buildings")
		_:
			push_error("Not a valid mode: " + str(mode))
	ShaderEffects.play_transition(5000.0, 0, 0.5)
	# warning-ignore:return_value_discarded
	get_tree().change_scene_to_file("res://game/arena/Arena.tscn")


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
	FileManager.save_and_quit()


