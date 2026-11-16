extends TestSuite


func run_tests() -> void:
	await case("in menus the mouse is free to leave the window", _test_menus_free)
	await case("aiming in combat keeps the mouse in the window", _test_aiming_confined)
	await case("pause and the free cursor let the mouse go again", _test_pointer_frees)
	await case("the drawn cursor hides while the mouse is outside the window", _test_cursor_outside)
	await case("the mouse leaving before the manager is ready is noted, not a crash", _test_early_notification)


func before_each() -> void:
	MouseManager.reset()
	MouseManager._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)


func _test_menus_free() -> void:
	check(not MouseManager.is_aiming(), "a menu is pointer mode")
	check_eq(MouseManager.window_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "the mouse isn't held in the window")


func _test_aiming_confined() -> void:
	MouseManager.set_aim_available(true)
	check(MouseManager.is_aiming(), "combat is aim mode")
	check_eq(MouseManager.window_mouse_mode(), Input.MOUSE_MODE_CONFINED, "the mouse is held in the window")


func _test_pointer_frees() -> void:
	MouseManager.set_aim_available(true)
	MouseManager.force_pointer(true)
	check_eq(MouseManager.window_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "the pause menu lets it go")
	MouseManager.force_pointer(false)
	check_eq(MouseManager.window_mouse_mode(), Input.MOUSE_MODE_CONFINED, "back to aiming holds it again")

	var held := InputEventAction.new()
	held.action = "free_cursor"
	held.pressed = true
	MouseManager._input(held)
	check_eq(MouseManager.window_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "holding the free cursor key lets it go")
	var released := InputEventAction.new()
	released.action = "free_cursor"
	MouseManager._input(released)
	check_eq(MouseManager.window_mouse_mode(), Input.MOUSE_MODE_CONFINED, "letting go holds it again")


func _test_cursor_outside() -> void:
	check(MouseManager.cursor_sprite.visible, "the drawn cursor shows in a menu")
	MouseManager._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	check(not MouseManager.cursor_sprite.visible, "it hides once the mouse leaves, so it isn't left stuck at the edge")
	MouseManager._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	check(MouseManager.cursor_sprite.visible, "and shows again when it comes back")

	MouseManager.set_aim_available(true)
	MouseManager._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	MouseManager._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	check(not MouseManager.cursor_sprite.visible, "coming back while aiming doesn't bring the pointer up")


func _test_early_notification() -> void:
	var manager: Node = load("res://game/ui/MouseManager.gd").new()
	manager._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	check(not manager.mouse_in_window, "it notes the mouse is outside")
	add_child(manager)
	check(not manager.cursor_sprite.visible, "and its drawn cursor starts hidden")
	manager.queue_free()
	await wait_frames()
	MouseManager._update_mode()
