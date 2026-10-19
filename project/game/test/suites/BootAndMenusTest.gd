extends TestSuite

# BootAndMenusTest: starting the game and the main menu, on the real scenes.
#   - the Intro loads the profile from disk and moves on to the main menu
#   - each main-menu button goes where it should
#   - an incomplete mecha can't be taken into a fight
#   - a lost expedition is reported once, on the next visit to the menu
#
# Scene changes are captured (TransitionManager.captured), and the profile
# is a test file (TestSuite.TEST_DIR).

const INTRO := preload("res://game/start_menu/Intro.tscn")
const START_MENU := preload("res://game/start_menu/StartMenu.tscn")


func run_tests() -> void:
	await case("boot loads the profile and opens the main menu", _test_boot)
	await case("main menu buttons go where they should", _test_buttons)
	await case("an incomplete mecha can't deploy", _test_incomplete_mecha)
	await case("a lost expedition is reported once", _test_loss_notice)


func before_each() -> void:
	PlayerProgress.reset()
	TransitionManager.captured.clear()


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


func _test_buttons() -> void:
	var menu = await _open_menu()
	var routes := {
		"_on_Hangar_pressed": "res://game/ui/HangarScreen.tscn",
		"_on_Expedition_pressed": "res://game/expedition/Expedition.tscn",
		"_on_Arena_pressed": "res://game/ui/ladder/Ladder.tscn",
		"_on_Store_pressed": "res://game/ui/customizer/Storepage.tscn",
	}
	for button in routes:
		TransitionManager.captured.clear()
		menu.call(button)
		check_eq(TransitionManager.captured, [routes[button]], "%s opens %s" % [button, routes[button].get_file()])
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
