extends CanvasLayer

const ACTIVE = true
const MARKER = preload("res://game/debug/Marker.tscn")

@onready var Markers = $Markers

var debug_settings = {
	"window": false,
	"navigation": false,
	"enemy_state": false,
	"debug_loadout": false,
	"player_zoom": false,
	"ai_behaviour": false,
	"go_to_mode": false,
	"skip_intro": false,
	"disable_projectiles_light": false,
	"use_debug_cam": false,
}


func get_setting(mode):
	assert(debug_settings.has(mode),"Not a valid debug mode:" + str(mode))
	if ACTIVE:
		return debug_settings[mode]
	return false


func window_debug_mode():
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2(1080, 600)


func create_marker(pos, color:= Color.WHITE, scale_mod := 1.0):
	print("Creating marker at ", pos, " with color ", str(color))
	var marker = MARKER.instantiate()
	Markers.add_child(marker)
	marker.global_position = pos
	marker.modulate = color
	marker.scale *= scale_mod
	
	
	return marker
	
	
