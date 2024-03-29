extends Node

var previous_windowed_pos = false

func toggle_fullscreen():
	var window = get_window()
	var cur_screen = window.get_current_screen()
	if window.mode == Window.MODE_WINDOWED:
		previous_windowed_pos = window.position
	window.mode = Window.MODE_FULLSCREEN if window.mode == Window.MODE_WINDOWED else Window.MODE_WINDOWED
	Profile.set_option("fullscreen", window.mode != Window.MODE_WINDOWED, true)
	window.borderless =  window.mode != Window.MODE_WINDOWED
	if window.mode == Window.MODE_WINDOWED:
		var size = Profile.WINDOW_SIZES[Profile.get_option("window_size")]
		window.size = size
		if previous_windowed_pos:
			window.position = previous_windowed_pos
		else:
			window.position = Vector2(100, 400)
		window.set_current_screen(cur_screen)
