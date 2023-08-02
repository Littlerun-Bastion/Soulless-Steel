extends Node

const MAPS_PATH = "res://database/maps/"

const CIV_GRADE_PAYOUT = 100000.0
const MIL_GRADE_PAYOUT = 1000000.0
const SOA_GRADE_PAYOUT = 10000000.0
const UNDERGROUND_PAYOUT_MODIFIER = 1.5

@onready var MAPS = {}

var map_to_load = false
var current_challengers = ["Lady Volk"]
var exhibitioner_count = 2
var mode = ""
var tier = "Civ-Grade"
var last_match
var last_match_unread = false



func _ready():
	refresh_exhibition()
	setup_maps()


func setup_maps():
	var dir = DirAccess.open(MAPS_PATH)
	if dir:
		dir.list_dir_begin() # TODOGODOT4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				#Found map file, creating data on memory
				MAPS[file_name.replace(".tscn", "").replace(".remap", "")] = load(MAPS_PATH + file_name.replace(".remap", ""))
				
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access maps path: " + str(DirAccess.get_open_error()))


func set_map_to_load(map_name):
	map_to_load = map_name


func get_current_map():
	assert(map_to_load,"There is no map to load")
	var data = get_map(map_to_load)
	map_to_load = false
	return data


func get_map(map_name):
	assert(MAPS.has(map_name),"Not a valid map name: " + str(map_name))
	return MAPS[map_name].instantiate()
	
func refresh_exhibition():
	exhibitioner_count = randi_range(2, 5)
