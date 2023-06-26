extends Node

const MAPS_PATH = "res://database/maps/"

@onready var MAPS = {}

var map_to_load = false
var current_challengers = ["Lady Volk"]
var exhibitioner_count = 0
var mode = ""



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
				MAPS[file_name.replace(".tscn", "")] = load(MAPS_PATH + file_name)
				
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
