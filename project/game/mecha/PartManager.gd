extends Node

const DATA_PATH = "res://database/parts/"

onready var ARM_WEAPONS = {}
onready var SHOULDER_WEAPONS = {}
onready var SHOULDERS = {}
onready var CORES = {}
onready var HEADS = {}
onready var PROJECTILES = {}


func _ready():
	setup_parts()


func setup_parts():
	load_parts("arm_weapons", ARM_WEAPONS)
	load_parts("shoulder_weapons", SHOULDER_WEAPONS)
	load_parts("shoulders", SHOULDERS)
	load_parts("cores", CORES)
	load_parts("heads", HEADS)
	load_parts("projectiles", PROJECTILES)


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


func get_part(type, name):
	if type == "arm_weapon":
		assert(ARM_WEAPONS.has(name), "Not a existent arm weapon part: " + str(name))
		return ARM_WEAPONS[name]
	elif type == "shoulder_weapon":
		assert(SHOULDER_WEAPONS.has(name), "Not a existent shoulder weapon part: " + str(name))
		return SHOULDER_WEAPONS[name]
	elif type == "shoulder":
		assert(SHOULDERS.has(name), "Not a existent shoulder part: " + str(name))
		return SHOULDERS[name]
	elif type == "core":
		assert(CORES.has(name), "Not a existent core part: " + str(name))
		return CORES[name]
	elif type == "head":
		assert(HEADS.has(name), "Not a existent head part: " + str(name))
		return HEADS[name]
	elif type == "projectile":
		assert(PROJECTILES.has(name), "Not a existent projectile: " + str(name))
		return PROJECTILES[name]
	else:
		push_error("Not a valid type of part: " + str(type))
