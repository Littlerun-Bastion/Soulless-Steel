extends Node

const DATA_PATH = "res://database/parts/"

enum SIDE {LEFT, RIGHT, SINGLE}

@onready var ARM_WEAPONS = {}
@onready var SHOULDER_WEAPONS = {}
@onready var SHOULDERS = {}
@onready var CORES = {}
@onready var HEADS = {}
@onready var CHASSIS = {}
@onready var GENERATORS = {}
@onready var CHIPSETS = {}
@onready var THRUSTERS = {}
@onready var PROJECTILES = {}

var current_player_mech


func _ready():
	setup_parts()


func setup_parts():
	load_parts("arm_weapons", ARM_WEAPONS)
	load_parts("shoulder_weapons", SHOULDER_WEAPONS)
	load_parts("shoulders", SHOULDERS)
	load_parts("cores", CORES)
	load_parts("heads", HEADS)
	load_parts("chassis", CHASSIS)
	load_parts("generators", GENERATORS)
	load_parts("chipsets", CHIPSETS)
	load_parts("thrusters", THRUSTERS)
	load_parts("projectiles", PROJECTILES)
	

func load_parts(part_name, dict):
	var path = DATA_PATH + part_name + "/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				var key = file_name.replace(".tres", "").replace(".tscn", "").replace(".remap", "")
				dict[key] = load(path + file_name.replace(".remap", ""))
				if dict[key] is PackedScene:
					dict[key] = dict[key].instantiate()
				dict[key].part_id = key
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access part path: " + str(DirAccess.get_open_error()))


func get_parts(type):
	match type:
		"arm_weapon":
			return ARM_WEAPONS
		"shoulder_weapon":
			return SHOULDER_WEAPONS
		"shoulders":
			return SHOULDERS
		"core":
			return CORES
		"head":
			return HEADS
		"chassis":
			return CHASSIS
		"generator":
			return GENERATORS
		"chipset":
			return CHIPSETS
		"thruster":
			return THRUSTERS
		"projectile":
			return PROJECTILES
		_:
			push_error("Not a valid type of part: " + str(type))
			return false


func is_valid_part(type, part_name):
	return get_parts(type).has(part_name)


func get_part(type, part_name):
	var table = get_parts(type)
	assert(table.has(part_name),"Not a existent part: " + str(part_name) + " for part type: " + str(type))
	return table[part_name]


func get_random_part_name(type):
	var table = get_parts(type)
	return table.keys()[randi()%table.keys().size()]


func get_max_stat_value(stat_name):
	var max_value = 0.0
	var categories = [ARM_WEAPONS, SHOULDER_WEAPONS, SHOULDERS, CORES, HEADS, CHASSIS, GENERATORS, CHIPSETS, THRUSTERS]
	for parts in categories:
		var current_max = 0
		for part in parts.values():
			if part.get(stat_name) and part.get(stat_name) > current_max:
				current_max = part.get(stat_name)
		max_value += current_max
	return float(max_value)


func get_parts_by_tags(type, search_tags):
	var table = get_parts(type)
	var final_list = []
	for part in table:
		var valid = true
		var part_tags = get_part(type,part).tags
		for tag in search_tags:
			if not tag in part_tags:
				valid = false
				break
		if valid:
			final_list.append(part)
	return final_list

