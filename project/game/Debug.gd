extends Node

const ACTIVE = true


var debug_settings = {
	"window": true,
	"navigation": false,
	"enemy_state": true,
	"player_loadout": true,
	"player_zoom": false,
	"ai_behaviour": false,
}


func _ready():
	if get_setting("window"):
		window_debug_mode()


func get_setting(mode):
	assert(debug_settings.has(mode), "Not a valid debug mode:" + str(mode))
	if ACTIVE:
		return debug_settings[mode]
	return false


func window_debug_mode():
	OS.window_fullscreen = false
	OS.window_borderless = false
	OS.window_size = Vector2(1080, 600)
	OS.window_position = Vector2(400, 100)
