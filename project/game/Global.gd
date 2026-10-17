extends Node

var previous_windowed_pos = false

func toggle_fullscreen():
	var window = get_window()
	if window.mode == Window.MODE_WINDOWED:
		previous_windowed_pos = window.position
	Profile.set_option("fullscreen", window.mode == Window.MODE_WINDOWED, true)
	apply_window_mode()


# Puts the window in the mode saved in the profile options (fullscreen, or a
# window of the chosen size). Called when the profile loads and on F11.
func apply_window_mode():
	var window = get_window()
	var cur_screen = window.get_current_screen()
	var fullscreen: bool = Profile.get_option("fullscreen")
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	window.borderless = fullscreen
	if not fullscreen:
		var size = Profile.WINDOW_SIZES[int(Profile.get_option("window_size"))]
		window.size = size
		if previous_windowed_pos:
			window.position = previous_windowed_pos
		else:
			window.move_to_center()
		window.set_current_screen(cur_screen)
