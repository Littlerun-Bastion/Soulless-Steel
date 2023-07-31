extends Control

@onready var Parallax = $ParallaxBackground
@onready var VersionLabel = $VersionLabel

var parallaxMult = 30.0


func _ready():
	FileManager.load_game()
	if Profile.SHOW_VERSION:
		VersionLabel.visible = true
		VersionLabel.text = str(Profile.VERSION)
	else:
		VersionLabel.visible = false
	
	if Debug.get_setting("window"):
		Debug.window_debug_mode()
	
	randomize()
	MouseManager.show_cursor()
	ShaderEffects.reset_shader_effect("main_menu")
	$AnimationPlayer.play("Typewrite")
	AudioManager.play_bgm("main-menu")
	
	if Debug.get_setting("go_to_mode"):
		await get_tree().process_frame
		start_game(Debug.get_setting("go_to_mode"))


func _input(event):
	if event is InputEventMouseMotion:
		var viewport_size = get_viewport().size
		var mouse_x = event.position.x
		var mouse_y = event.position.y
		var relative_x = (mouse_x - (viewport_size.x/2)) / (viewport_size.x/2)
		var relative_y = (mouse_y - (viewport_size.y/2)) / (viewport_size.y/2)
		$ParallaxBackground/GridLayer.motion_offset.x  = parallaxMult * relative_x
		$ParallaxBackground/GridLayer.motion_offset.y = parallaxMult * relative_y
	if event.is_action_pressed("toggle_fullscreen"):
		Global.toggle_fullscreen()


func start_game(mode):
	AudioManager.stop_bgm()
	PlayerStatManager.NumberofExtracts = 0
	PlayerStatManager.Credits = 0
	match mode:
		"main":
			ArenaManager.set_map_to_load("arena_oldgate")
		"tutorial":
			ArenaManager.mode = "Tutorial"
			ArenaManager.set_map_to_load("tutorial")
		"test":
			ArenaManager.set_map_to_load("test_buildings")
		_:
			push_error("Not a valid mode: " + str(mode))
		
	TransitionManager.transition_to("res://game/arena/Arena.tscn", "Initializing Combat Sequence...")


func _on_Button_mouse_entered():
	AudioManager.play_sfx("select")
	Parallax.mouse_hovered = true


func _on_Button_mouse_exited():
	Parallax.mouse_hovered = false


func _on_SettingsButton_pressed():
	AudioManager.play_sfx("back")


func _on_ExitButton_pressed():
	AudioManager.play_sfx("back")
	FileManager.save_and_quit()


func _on_Hangar_pressed():
	AudioManager.play_sfx("confirm")
	TransitionManager.transition_to("res://game/ui/customizer/Customizer.tscn", "Loading Visualizer...")


func _on_Arena_pressed():
	AudioManager.play_sfx("confirm")
	TransitionManager.transition_to("res://game/ui/ladder/Ladder.tscn", "Loading Rankings...")


func _on_TestMode_pressed():
	AudioManager.play_sfx("confirm")
	start_game("tutorial")


func _on_Store_pressed():
	AudioManager.play_sfx("confirm")
	TransitionManager.transition_to("res://game/ui/customizer/Storepage.tscn", "Loading Store...")
