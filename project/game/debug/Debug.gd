extends CanvasLayer

const ACTIVE = true
const MARKER = preload("res://game/debug/Marker.tscn")

onready var Markers = $Markers

var debug_settings = {
	"window": false,
	"navigation": false,
	"enemy_state": false,
	"player_loadout": true,
	"player_zoom": false,#Vector2(.3,.3),
	"ai_behaviour": "idle",
	"go_to_mode": false,
	"skip_intro": false,
	"disable_projectiles_light": false,
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
	OS.window_size = Vector2(1080, 600)
	OS.window_position = Vector2(400, 100)


func create_marker(pos, color:= Color.white, scale_mod := 1.0):
	print("Creating marker at ", pos, " with color ", str(color))
	var marker = MARKER.instance()
	Markers.add_child(marker)
	marker.global_position = pos
	marker.modulate = color
	marker.scale *= scale_mod
	
	
	return marker
	
	
