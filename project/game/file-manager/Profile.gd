extends Node

const WINDOW_SIZES = [Vector2(1920, 1080), Vector2(1600, 900),
		Vector2(1366, 768), Vector2(1280, 720), Vector2(2560, 1440), 
		Vector2(3840, 2160)]

const LANGUAGES = [
	{"locale":"en", "name": "English"},
	{"locale":"pt_BR", "name": "Português"},
]

const VERSION := "v0.0.3"
const SHOW_VERSION = true

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
	"current_mecha" : {
		"head": "MSV-L3J-H", "core": "MSV-L3J-C", "shoulders": "MSV-L3J-SG",
		"generator": "type_1_gen", "chipset": "type_2_chip", "chassis": "MSV-L3J-L",
		"thruster": "type_1_thruster",
		"arm_weapon_left": "MA-L127", "arm_weapon_right": "MA-L127",
		"shoulder_weapon_left": false, "shoulder_weapon_right": false,
	},
	"money": 0,
}

var leaderboards = {
	"civ-grade": [
		"Grob", "Lady Volk", "Avalynn",
		"Damiran Ghad", "Daerry-l", "AlD0H",
		"Rylan Lira", "Siv Maeck", "Tann",
	],
	"mil-grade": [
		"Rusl Senkou", "Akyra", "Allany-X",
		"Paxt", "Saria III", "Ryker",
		"Briyanna J", "Banca Ghyx", "Haelee Volk"
	],
	"state-of-the-art": [
		"LotterReed", "Nix", "Caerson",
		"Bl4yn3", "Jenzen Jen", "Jadirel",
		"Brayln", "Moargan", "Aeden Lyvl"
	],
}

var inventory = {
	"MSV-L3J-H": 1,
	"MSV-L3J-C": 1,
	"MSV-L3J-SG": 1,
	"type_1_gen": 1,
	"type_2_chip": 1,
	"MSV-L3J-L": 1,
	"type_1_thruster": 1,
	"MA-L127": 2,
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
		"time": Time.get_datetime_dict_from_system(),
		"version": VERSION,
		"options": options,
		"controls": controls,
		"stats": stats,
		"leaderboards": leaderboards,
		"debug": Debug.debug_settings,
		"inventory": inventory,
	}
	
	return data


func set_save_data(data):
	if data.version != VERSION:
		#Handle version diff here.
		push_warning("Different save version for profile. Its version: " + str(data.version) + " Current version: " + str(Profile.VERSION)) 
		push_warning("Properly updating to new save version")
		if data.version == "v0.0.2dev":
			data.inventory = inventory 
		push_warning("Profile updated!")
	
	set_data(data, "options", options)
	set_data(data, "controls", controls)
	set_data(data, "stats", stats)
	set_data(data, "leaderboards", leaderboards)
	set_data(data, "debug", Debug.debug_settings)
	
	inventory = data.inventory
	
	AudioManager.set_bus_volume(AudioManager.MASTER_BUS, options.master_volume)
	AudioManager.set_bus_volume(AudioManager.BGM_BUS, options.bgm_volume)
	AudioManager.set_bus_volume(AudioManager.SFX_BUS, options.sfx_volume)
	
	for action in controls.keys():
		edit_control_action(action, controls[action])


func set_data(data, idx, default_values, ignore_deprecated := false):
	if not data.has(idx):
		return
	
	#Update received data with missing default values
	for key in default_values.keys():
		if not data[idx].has(key):
			data[idx][key] = default_values[key]
			push_warning("Adding new profile entry '" + str(key) + str("' for " + str(idx)))
		elif typeof(default_values[key]) == TYPE_DICTIONARY:
			set_data(data[idx], key, default_values[key])
			
	for key in data[idx].keys():
		#Ignore deprecated values
		if default_values.has(key):
			default_values[key] = data[idx][key]
		elif not ignore_deprecated:
			data[idx].erase(key)
			push_warning("Removing deprecated value '" + str(key) + str("' for " + str(idx)))


func get_option(opt_name):
	assert(options.has(opt_name), "Not a valid option: " + str(opt_name))
	return options[opt_name]


func set_option(opt_name: String, value, should_save := false):
	assert(options.has(opt_name),"Not a valid option: " + str(opt_name))
	options[opt_name] = value
	if should_save:
		FileManager.save_profile()


func get_leaderboard(lb_name):
	assert(leaderboards.has(lb_name), "Not a valid leaderboard name: " + str(lb_name))
	return leaderboards[lb_name]


func is_ctrl_pressed(ctrl_name):
	assert(controls.has(ctrl_name),"Not a valid control action: " + str(ctrl_name))
	return controls[ctrl_name]


func set_ctrl_pressed(ctrl_name: String, value):
	assert(controls.has(ctrl_name),"Not a valid control action: " + str(ctrl_name))
	controls[ctrl_name] = value
	edit_control_action(ctrl_name, value)
	FileManager.save_profile()


func edit_control_action(action: String, keycode:int):
	assert(InputMap.has_action(action),"Action not in InputMap: " + str(action))
	var key = InputEventKey.new()
	key.keycode = keycode
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, key)


func get_stat(type):
	assert(stats.has(type),"Not a valid stat: "+str(type))
	return stats[type]


func set_stat(type, value):
	assert(stats.has(type),"Not a valid stat: "+str(type))
	stats[type] = value
	FileManager.save_profile()


func get_inventory():
	return inventory


func get_inventory_amount(part_name):
	assert(inventory.has(part_name), "Inventory doesn't have this item to get amount: " + str(part_name))
	return inventory[part_name]


func add_to_inventory(part_name):
	if inventory.has(part_name):
		inventory[part_name] += 1
	else:
		inventory[part_name] = 1
	FileManager.save_profile()


func remove_from_inventory(part_name):
	assert(inventory.has(part_name), "Inventory doesn't have this item to remove: " + str(part_name))
	if inventory[part_name] > 0:
		inventory[part_name] -= 1
	else:
		push_warning("Inventory doesn't have enough of item to remove: " + str(part_name))
	
	FileManager.save_profile()
