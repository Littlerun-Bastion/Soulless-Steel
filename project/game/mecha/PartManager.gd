extends Node

const DATA_PATH = "res://database/parts/"

enum SIDE {LEFT, RIGHT, SINGLE}

onready var ARM_WEAPONS = {}
onready var SHOULDER_WEAPONS = {}
onready var SHOULDERS = {}
onready var SHOULDERS_LEFT = {}
onready var SHOULDERS_RIGHT = {}
onready var CORES = {}
onready var HEADS = {}
onready var LEGS = {}
onready var LEGS_LEFT = {}
onready var LEGS_RIGHT = {}
onready var LEGS_SINGLE = {}
onready var GENERATORS = {}
onready var CHIPSETS = {}
onready var THRUSTERS = {}
onready var PROJECTILES = {}


func _ready():
	setup_parts()


func setup_parts():
	load_parts("arm_weapons", ARM_WEAPONS)
	load_parts("shoulder_weapons", SHOULDER_WEAPONS)
	load_parts("shoulders", SHOULDERS)
	load_parts("cores", CORES)
	load_parts("heads", HEADS)
	load_parts("legs", LEGS)
	load_parts("generators", GENERATORS)
	load_parts("chipsets", CHIPSETS)
	load_parts("thrusters", THRUSTERS)
	load_parts("projectiles", PROJECTILES)
	
	setup_shoulder_sides()
	setup_leg_sides()


func setup_shoulder_sides():
	for key in SHOULDERS.keys():
		var shoulder = SHOULDERS[key]
		if shoulder.side == SIDE.LEFT:
			SHOULDERS_LEFT[key] = shoulder
		elif shoulder.side == SIDE.RIGHT:
			SHOULDERS_RIGHT[key] = shoulder
		else:
			push_error("Not a valid shoulder side type: " + str(shoulder.side))


func setup_leg_sides():
	for key in LEGS.keys():
		var leg = LEGS[key]
		if leg.side == SIDE.LEFT:
			LEGS_LEFT[key] = leg
		elif leg.side == SIDE.RIGHT:
			LEGS_RIGHT[key] = leg
		elif leg.side == SIDE.SINGLE:
			LEGS_SINGLE[key] = leg
		else:
			push_error("Not a valid leg side type: " + str(leg.side))


func load_parts(name, dict):
	var dir = Directory.new()
	var path = DATA_PATH + name + "/"
	if dir.open(path) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				var key = file_name.replace(".tres", "").replace(".tscn", "")
				dict[key] = load(path + file_name)
				if dict[key] is PackedScene:
					dict[key] = dict[key].instance()
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access part path.")
		assert(false)


func get_parts(type):
	match type:
		"arm_weapon":
			return ARM_WEAPONS
		"shoulder_weapon":
			return SHOULDER_WEAPONS
		"shoulder":
			return SHOULDERS
		"shoulder_left":
			return SHOULDERS_LEFT
		"shoulder_right":
			return SHOULDERS_RIGHT
		"core":
			return CORES
		"head":
			return HEADS
		"leg":
			return LEGS
		"leg_left":
			return LEGS_LEFT
		"leg_right":
			return LEGS_RIGHT
		"leg_single":
			return LEGS_SINGLE
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


func get_part(type, name):
	var table = get_parts(type)
	assert(table.has(name), "Not a existent part: " + str(name))
	return table[name]


func get_random_part_name(type):
	var table = get_parts(type)
	return table.keys()[randi()%table.keys().size()]
	
