extends Node

const DATA_PATH = "res://database/parts/"

onready var ARM_WEAPONS = {}
onready var SHOULDER_WEAPONS = {}
onready var SHOULDERS = {}
onready var CORES = {}
onready var HEADS = {}


func _ready():
	setup_parts()


func setup_parts():
	load_parts("arm_weapons", ARM_WEAPONS)
	load_parts("shoulder_weapons", SHOULDER_WEAPONS)
	load_parts("shoulders", SHOULDERS)
	load_parts("cores", CORES)
	load_parts("heads", HEADS)


func load_parts(name, dict):
	var dir = Directory.new()
	var path = DATA_PATH + name + "/"
	if dir.open(path) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				dict[file_name.replace(".tres", "")] = load(path + file_name)
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access sfxs path.")
		assert(false)
