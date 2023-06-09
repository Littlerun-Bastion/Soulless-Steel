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


func get_special_npc(npc_name):
	for npc in SPECIAL_NPCS:
		if npc.npc_name == npc_name:
			return npc
	push_error("Couldn't find this special npc: " + str(npc_name))
	return false


func get_random_npc():
	return NPCS.pick_random()


func get_design_data(npc):
	var data = {}
	for part_type in ["head", "core", "shoulders", "generator", "chipset", "chassis",\
					"thruster", "arm_weapon_left", "arm_weapon_right", "shoulders", \
					"shoulder_weapon_left", "shoulder_weapon_right"]:
		var abs_type = part_type.replace("_left", "").replace("_right", "")
		var part = get_part(abs_type, npc[part_type])
		data[part_type] = part.part_id if part else false
	return data

#Given an npc and a part type, gets the correspondent part
#which can be an specific part or a random part based on tags.
func get_part(type, part_data):
	if part_data.size() == 0:
		return false
	
	#Check if it's a specific part
	if PartManager.is_valid_part(type, part_data[0]):
		return PartManager.get_part(type, part_data[0])
	
	#It's a bunch of tags, get an appropriate part
	var valid_parts = PartManager.get_parts_by_tags(type, part_data)
	if valid_parts.size() > 0:
		return valid_parts.pick_random()
	else:
		push_error("Couldn't find a valid part given the tags: " + str(part_data))
		return false
