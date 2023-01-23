extends Node

const WINDOW_SIZES = [Vector2(1920, 1080), Vector2(1600, 900),
		Vector2(1366, 768), Vector2(1280, 720), Vector2(2560, 1440), 
		Vector2(3840, 2160)]

const LANGUAGES = [
	{"locale":"en", "name": "English"},
	{"locale":"pt_BR", "name": "Português"},
]

const VERSION := "v0.0.1dev"

var options = {
	"master_volume": 0.25,
	"bgm_volume": 1.0,
	"sfx_volume": 1.0,
	"fullscreen": true,
	"window_size": 3,
	"screen_shake": true,
	"locale": 0,
	"invert_x": true,
	"invert_y": false,
	"invert_deadzone_angle": 90,
}

var controls = {
	"toggle_fullscreen": KEY_F11 
}


var stats = {
	"gameover": 0,
}


func get_locale_idx(locale):
	var idx = 0
	for lang in LANGUAGES:
		if lang.locale == locale:
			return idx
		idx += 1
	push_error("Couldn't find given locale: " + str(locale))


func update_translation():
	TranslationServer.set_locale(LANGUAGES[get_option("locale")].locale)


func get_save_data():
	var data = {
		"time": OS.get_datetime(),
		"version": VERSION,
		"options": options,
		"controls": controls,
		"stats": stats,
		"debug": Debug.debug_settings,
	}
	
	return data


func set_save_data(data):
	if data.version != VERSION:
		#Handle version diff here.
		push_warning("Different save version for profile. Its version: " + str(data.version) + " Current version: " + str(Debug.VERSION)) 
		push_warning("Properly updating to new save version")
		push_warning("Profile updated!")
	
	set_data(data, "options", options)
	set_data(data, "controls", controls)
	set_data(data, "stats", stats)
	set_data(data, "debug", Debug.debug_settings)
	
	AudioManager.set_bus_volume(AudioManager.MASTER_BUS, options.master_volume)
	AudioManager.set_bus_volume(AudioManager.BGM_BUS, options.bgm_volume)
	AudioManager.set_bus_volume(AudioManager.SFX_BUS, options.sfx_volume)
	
	if not Debug.get_setting("window"):
		OS.window_fullscreen = options.fullscreen
		if not OS.window_fullscreen:
			yield(get_tree(), "idle_frame")
			OS.window_size = WINDOW_SIZES[options.window_size]
			OS.window_position = Vector2(0,0)
	
	for action in controls.keys():
		edit_control_action(action, controls[action])


func set_data(data, name, default_values):
	if not data.has(name):
		return
	
	#Update received data with missing default values
	for key in default_values.keys():
		if not data[name].has(key):
			data[name][key] = default_values[key]
			push_warning("Adding new profile entry '" + str(key) + str("' for " + str(name)))
		elif typeof(default_values[key]) == TYPE_DICTIONARY:
			set_data(data[name], key, default_values[key])
			
	for key in data[name].keys():
		#Ignore deprecated values
		if default_values.has(key):
			default_values[key] = data[name][key]
		else:
			data[name].erase(key)
			push_warning("Removing deprecated value '" + str(key) + str("' for " + str(name)))


func get_option(name):
	assert(options.has(name), "Not a valid option: " + str(name))
	return options[name]


func set_option(name: String, value, should_save := false):
	assert(options.has(name), "Not a valid option: " + str(name))
	options[name] = value
	if should_save:
		FileManager.save_profile()

func get_control(name):
	assert(controls.has(name), "Not a valid control action: " + str(name))
	return controls[name]


func set_control(name: String, value):
	assert(controls.has(name), "Not a valid control action: " + str(name))
	controls[name] = value
	edit_control_action(name, value)
	FileManager.save_profile()


func edit_control_action(action: String, scancode:int):
	assert(InputMap.has_action(action), "Action not in InputMap: " + str(action))
	var key = InputEventKey.new()
	key.pressed = true
	key.scancode = scancode
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, key)


func get_stat(type):
	assert(stats.has(type), "Not a valid stat: "+str(type))
	return stats[type]


func set_stat(type, value):
	assert(stats.has(type), "Not a valid stat: "+str(type))
	stats[type] = value
	FileManager.save_profile()
