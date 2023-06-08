extends Node

const GENERIC_NPCS_PATH = "res://database/npcs/generic_npcs.gd"
const SPECIAL_NPCS_PATH = "res://database/npcs/special_npcs/"

enum SIDE {LEFT, RIGHT, SINGLE}

@onready var NPCS = []
@onready var SPECIAL_NPCS = []


func _ready():
	setup()


func setup():
	#Get generic NPCs
	NPCS = load(GENERIC_NPCS_PATH).get_npcs()
	
	#Get special NPCS
	var dir = DirAccess.open(SPECIAL_NPCS_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				SPECIAL_NPCS.append(load(SPECIAL_NPCS_PATH + file_name))
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access special npcs path: " + str(DirAccess.get_open_error()))
