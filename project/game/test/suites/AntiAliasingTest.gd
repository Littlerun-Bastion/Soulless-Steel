extends TestSuite

const SYSTEM_WINDOW := preload("res://game/ui/mech_os/windows/SystemWindow.tscn")

var _saved_level = null


func run_tests() -> void:
	_saved_level = Profile.get_option("anti_aliasing")
	await case("anti-aliasing is an option, high by default and kept in the save", _test_option)
	await case("each level sets how the game is drawn", _test_levels)
	await case("SYS shows the level and steps through them, applying each at once", _test_system_window)
	Profile.set_option("anti_aliasing", _saved_level)
	Global.apply_anti_aliasing()


func _drawn() -> Array:
	var root := get_tree().root
	return [root.canvas_item_default_texture_filter, root.msaa_2d]


func _test_option() -> void:
	var defaults: Dictionary = Profile.options.duplicate()
	var old_save := {"options": {"screen_shake": defaults.screen_shake}}
	Profile.set_data(old_save, "options", defaults)

	check_eq(defaults.anti_aliasing, Global.ANTI_ALIASING_HIGH, "a save from before it loads with it high")
	check(Profile.get_save_data().options.has("anti_aliasing"), "and it is saved with the other options")


func _test_levels() -> void:
	var expected := {
		Global.ANTI_ALIASING_OFF: [Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST, Viewport.MSAA_DISABLED],
		Global.ANTI_ALIASING_LOW: [Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, Viewport.MSAA_DISABLED],
		Global.ANTI_ALIASING_HIGH: [Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, Viewport.MSAA_4X],
	}
	for level in expected:
		Profile.set_option("anti_aliasing", level)
		Global.apply_anti_aliasing()
		check_eq(_drawn(), expected[level], "%s: texture filter and MSAA" % Global.ANTI_ALIASING_NAMES[level])


func _test_system_window() -> void:
	Profile.set_option("anti_aliasing", Global.ANTI_ALIASING_OFF)
	Global.apply_anti_aliasing()
	var window: Node = SYSTEM_WINDOW.instantiate()
	add_child(window)
	await get_tree().process_frame
	var button: Button = window.anti_aliasing_button
	check_eq(button.text, "OFF", "it shows the level")

	button.pressed.emit()

	check_eq(Profile.get_option("anti_aliasing"), Global.ANTI_ALIASING_LOW, "a press steps to the next level")
	check_eq(button.text, "LOW", "and shows it")
	check_eq(_drawn()[0], Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "applied at once")
	button.pressed.emit()
	button.pressed.emit()
	check_eq(Profile.get_option("anti_aliasing"), Global.ANTI_ALIASING_OFF, "and round from high back to off")
	window.queue_free()
