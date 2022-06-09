extends Node

const DEBUG_ON = true

func window_debug_mode():
	OS.window_fullscreen = false
	OS.window_borderless = false
	OS.window_size = Vector2(1080, 600)
	OS.window_position = Vector2(400, 100)
