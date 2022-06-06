extends Node

const MAPS_PATH = "res://database/maps/"

onready var MAPS = {}

var map_to_load = false


func _ready():
	setup_maps()


func setup_maps():
	var dir = Directory.new()
	if dir.open(MAPS_PATH) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				#Found map file, creating data on memory
				MAPS[file_name.replace(".tscn", "")] = load(MAPS_PATH + file_name)
				
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access maps path.")
		assert(false)


func set_map_to_load(name):
	map_to_load = name


func get_current_map():
	assert(map_to_load, "There is no map to load")
	var data = get_map(map_to_load)
	map_to_load = false
	return data


func get_map(name):
	assert(MAPS.has(name), "Not a valid map name: " + str(name))
	return MAPS[name].instance()
