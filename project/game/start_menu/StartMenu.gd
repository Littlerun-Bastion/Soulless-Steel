extends Control

@onready var Parallax = $ParallaxBackground
@onready var VersionLabel = $VersionLabel

var parallaxMult = 30.0


func _ready():
	if Profile.SHOW_VERSION:
		VersionLabel.visible = true
		VersionLabel.text = str(Profile.VERSION)
	else:
		VersionLabel.visible = false
	
	if Debug.get_setting("window"):
		Debug.window_debug_mode()
	
	randomize()
	ShaderEffects.reset_shader_effect("main_menu")
	$AnimationPlayer.play("Typewrite")
	AudioManager.play_bgm("main-menu")
	
	if Debug.get_setting("go_to_mode"):
		await get_tree().process_frame
		start_game(Debug.get_setting("go_to_mode"))
		
	_setup_test_contact()
	_show_loss_notice()

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
	
	if event.is_action_pressed("debug_4"):
		MechOS.toggle_app("test")


func start_game(mode):
	AudioManager.stop_bgm()
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
	TransitionManager.transition_to("res://game/ui/HangarScreen.tscn", "Loading Visualizer...")


func _on_Arena_pressed():
	AudioManager.play_sfx("confirm")
	TransitionManager.transition_to("res://game/ui/ladder/Ladder.tscn", "Loading Rankings...")


func _on_Expedition_pressed():
	AudioManager.play_sfx("confirm")
	# Old test mode (tutorial) kept here for reference, currently disconnected:
	#start_game("tutorial")
	AudioManager.stop_bgm()
	TransitionManager.transition_to("res://game/expedition/Expedition.tscn", "Launching Expedition...")


func _on_Store_pressed():
	AudioManager.play_sfx("confirm")
	TransitionManager.transition_to("res://game/ui/customizer/Storepage.tscn", "Loading Store...")

# An expedition lost without a game-over screen (quit from pause, game closed
# or crashed mid-run) is reported here, once.
func _show_loss_notice() -> void:
	if not PlayerProgress.has_loss_report():
		return
	var report := PlayerProgress.take_loss_report()

	var panel := PanelContainer.new()
	panel.name = "LossNotice"
	panel.theme = preload("res://game/ui/HUDFont.tres")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 1)
	style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)

	var title := Label.new()
	title.text = "EXPEDITION ABANDONED" if report.get("reason") == PlayerProgress.LOSS_ABANDONED else "EXPEDITION LOST"
	box.add_child(title)

	var body := Label.new()
	body.text = PlayerProgress.format_loss_report(report)
	body.add_theme_font_size_override("font_size", 28)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 900
	box.add_child(body)

	var ok := Button.new()
	ok.text = "Acknowledge"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func():
		AudioManager.play_sfx("confirm")
		panel.queue_free())
	box.add_child(ok)

	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	AudioManager.play_sfx("back")


func _setup_test_contact() -> void:
	# MessengerUI is an autoload, so the contact survives returning to the menu.
	if MessengerUI.has_contact("Lady Volk"):
		return
	var contact = ContactData.new()
	contact.name = "Lady Volk"
	contact.add_message("Hey. I have a job for you.")
	contact.add_message("Three targets. Extract alive.")
	
	var mission = MissionData.new()
	mission.mission_name = "Lady Volk Contract"
	mission.add_objective("kill", "Eliminate 3 targets", 3)
	mission.add_objective("extract", "Extract from arena", 1)
	# Story hooks for manual testing — press F7 to print story state.
	mission.story_effects = {"flags": {"test_volk_contract_done": true}}

	# Only offered once the contract has been completed. It's both a follow-up
	# to "I'm in." (picking a reply replaces the pending ones) and a top-level
	# reply (for after a restart, when the contact is rebuilt).
	var more_work := {
		"text": "Got any more work?",
		"next_replies": [],
		"requires": {"flags": {"test_volk_contract_done": true}},
	}
	contact.add_reply_option("I'm in.", [more_work], mission,
			{"flags": {"test_volk_contract_accepted": true}})
	contact.add_reply_option("Not interested.")
	contact.pending_replies.append(more_work)
	MessengerUI.add_contact(contact)
