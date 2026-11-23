extends TestSuite

# BootAndMenusTest: starting the game and the main menu, on the real scenes.
#   - the Intro loads the profile from disk and moves on to the main menu
#   - each main-menu button goes where it should (Store: the Hangar, with NET
#     to open at amazing.com; NetStoreTest follows it into the Hangar)
#   - an incomplete mecha can't be taken into a fight
#   - a lost expedition is reported once, on the next visit to the menu
#
# Scene changes are captured (TransitionManager.captured), and the profile
# is a test file (TestSuite.TEST_DIR).

const INTRO := preload("res://game/start_menu/Intro.tscn")
const START_MENU := preload("res://game/start_menu/StartMenu.tscn")


func run_tests() -> void:
	await case("boot loads the profile and opens the main menu", _test_boot)
	await case("a brand new profile boots into the onboarding", _test_new_profile_onboards)
	await case("a profile that never finished the onboarding goes back to it", _test_unfinished_onboarding)
	await case("the menu has a button for the onboarding", _test_onboarding_button)
	await case("main menu buttons go where they should", _test_buttons)
	await case("an incomplete mecha can't deploy", _test_incomplete_mecha)
	await case("a lost expedition is reported once", _test_loss_notice)


func before_each() -> void:
	PlayerProgress.reset()
	StoryDirector.reset(false)
	TransitionManager.captured.clear()


func _boot() -> Array:
	var intro = INTRO.instantiate()
	add_child(intro)
	await wait_until(func(): return not TransitionManager.captured.is_empty(), 10.0)
	intro.queue_free()
	await wait_frames()
	return TransitionManager.captured.duplicate()


func _open_menu() -> Node:
	var menu = START_MENU.instantiate()
	add_child(menu)
	await wait_frames()
	return menu


func _test_boot() -> void:
	PlayerProgress.add_money(777, false)
	FileManager.profile_loaded = true
	FileManager.save_profile()
	FileManager.profile_loaded = false
	PlayerProgress.reset()

	var intro = INTRO.instantiate()
	add_child(intro)
	var moved_on := await wait_until(func(): return not TransitionManager.captured.is_empty(), 10.0)
	check(moved_on, "the intro moves on")
	check_eq(TransitionManager.captured, ["res://game/start_menu/StartMenu.tscn"], "to the main menu")
	check(FileManager.profile_loaded, "the profile was loaded")
	check_eq(PlayerProgress.get_money(), 777.0, "with the saved progress")
	intro.queue_free()
	await wait_frames()


func _test_new_profile_onboards() -> void:
	for path in [FileManager.profile_path, FileManager.backup_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	FileManager.profile_loaded = false

	check_eq(await _boot(), [Onboarding.SCENE_PATH], "a first boot goes to the onboarding")
	check(StoryDirector.get_flag(Onboarding.DONE_FLAG) == false, "the new profile has it still to do")


func _test_unfinished_onboarding() -> void:
	StoryDirector.set_flag(Onboarding.DONE_FLAG, false, false)
	FileManager.profile_loaded = true
	FileManager.save_profile()
	FileManager.profile_loaded = false
	StoryDirector.reset(false)

	check_eq(await _boot(), [Onboarding.SCENE_PATH], "back to the onboarding")


func _test_onboarding_button() -> void:
	var menu = await _open_menu()
	var buttons: Array = menu.find_children("*", "Button", true, false).filter(
			func(b): return b.pressed.is_connected(Callable(menu, "_on_Onboarding_pressed")))
	check_eq(buttons.size(), 1, "one menu button plays the onboarding")
	if buttons.size() == 1:
		buttons[0].pressed.emit()
	check_eq(TransitionManager.captured, [Onboarding.SCENE_PATH], "and it opens the onboarding")
	menu.queue_free()
	await wait_frames()


func _test_buttons() -> void:
	var menu = await _open_menu()
	var routes := {
		"_on_Hangar_pressed": "res://game/ui/HangarScreen.tscn",
		"_on_Expedition_pressed": "res://game/expedition/Expedition.tscn",
		"_on_Arena_pressed": "res://game/arena/TestArena.tscn",
		"_on_Observe_pressed": "res://game/arena/ObserverArena.tscn",
		"_on_Store_pressed": "res://game/ui/HangarScreen.tscn",
	}
	for button in routes:
		TransitionManager.captured.clear()
		menu.call(button)
		check_eq(TransitionManager.captured, [routes[button]], "%s opens %s" % [button, routes[button].get_file()])
	check_eq(HangarScreen.open_net_url, "amazing.com", "Store asks the Hangar to open NET at amazing.com")
	HangarScreen.open_net_url = ""
	for route in routes.values():
		check(ResourceLoader.exists(route), "%s exists" % route)
	TransitionManager.captured.clear()
	menu._on_ExitButton_pressed()
	check_eq(TransitionManager.captured, ["res://game/start_menu/Exiting.tscn"], "Exit closes the game")
	menu.queue_free()
	await wait_frames()


func _test_incomplete_mecha() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["core"] = false
	PlayerProgress.set_current_mecha(design, false)
	var menu = await _open_menu()
	menu._on_Expedition_pressed()
	check(TransitionManager.captured.is_empty(), "Expedition refuses an incomplete mecha")
	check(menu.has_node("MechaNotice"), "and says why")
	if menu.has_node("MechaNotice"):
		check("CORE" in str(menu.get_node("MechaNotice").find_children("*", "Label", true, false).map(func(l): return l.text)),
				"naming the missing part")
	menu._on_Arena_pressed()
	check(TransitionManager.captured.is_empty(), "Arena refuses it too")
	menu._on_Expedition_pressed()
	check(menu.find_children("MechaNotice*", "", false, false).size() == 1, "pressing again doesn't stack notices")
	menu.queue_free()
	await wait_frames()


func _test_loss_notice() -> void:
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 8)
	cargo.add_stack_anywhere(item_stack.from_generic(load("res://database/items/salvage/wiring_loom.tres")))
	PlayerProgress.set_mech_inventory(cargo)
	PlayerProgress.begin_expedition()
	PlayerProgress.lose_expedition(PlayerProgress.LOSS_ABANDONED)

	var menu = await _open_menu()
	check(menu.has_node("LossNotice"), "the menu reports the lost expedition")
	if menu.has_node("LossNotice"):
		var text := str(menu.get_node("LossNotice").find_children("*", "Label", true, false).map(func(l): return l.text))
		check("ABANDONED" in text and "Wiring Loom" in text, "saying it was abandoned and what was lost")
	menu.queue_free()
	await wait_frames()

	menu = await _open_menu()
	check(not menu.has_node("LossNotice"), "only once")
	menu.queue_free()
	await wait_frames()
