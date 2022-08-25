extends Node

const ACTIVE = false


var debug_settings = {
	"window": true,
	"navigation": false,
	"enemy_state": false,
}


func window_debug_mode():
	OS.window_fullscreen = false
	OS.window_borderless = false
	OS.window_size = Vector2(1080, 600)
	OS.window_position = Vector2(400, 100)
