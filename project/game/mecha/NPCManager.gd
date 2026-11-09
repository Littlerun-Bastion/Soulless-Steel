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
				SPECIAL_NPCS.append(load(SPECIAL_NPCS_PATH + file_name.replace(".remap", "")))
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access special npcs path: " + str(DirAccess.get_open_error()))


func get_special_npc(npc_name):
	for npc in SPECIAL_NPCS:
		if npc.mecha_name == npc_name:
			return npc
	push_error("Couldn't find this special npc: " + str(npc_name))
	return false


## How often each personality is picked for a generic NPC (pick_personality_name).
## Placeholders.
const PERSONALITY_WEIGHTS := {"professional": 0.3, "scavenger": 0.3, "guardian": 0.15, "hunter": 0.15, "rat": 0.1}


func get_random_npc():
	return NPCS.pick_random()


## A personality type name drawn by PERSONALITY_WEIGHTS.
func pick_personality_name() -> String:
	var total := 0.0
	for weight in PERSONALITY_WEIGHTS.values():
		total += float(weight)
	var roll := randf() * total
	for personality in PERSONALITY_WEIGHTS:
		roll -= float(PERSONALITY_WEIGHTS[personality])
		if roll <= 0.0:
			return personality
	return "professional"


## A generic NPC's design data with a personality drawn by the weights, not
## the design's own.
func random_design_data() -> Dictionary:
	return get_design_data(get_random_npc(), pick_personality_name())


## Whether a design (its data) fights with direct-fire arm weapons.
func is_direct_fire(data: Dictionary) -> bool:
	for slot in ["arm_weapon_left", "arm_weapon_right"]:
		var id = data.get(slot)
		if id is String and PartManager.is_valid_part("arm_weapon", id):
			var weapon = PartManager.get_part("arm_weapon", id)
			if not weapon.is_indirect_fire and not weapon.requires_lock:
				return true
	return false


## Whether a design (its data) is a support build: an indirect shoulder
## weapon, or a sensing part in the bay.
func is_support(data: Dictionary) -> bool:
	for slot in ["shoulder_weapon_left", "shoulder_weapon_right"]:
		var id = data.get(slot)
		if id is String and PartManager.is_valid_part("shoulder_weapon", id) \
				and PartManager.get_part("shoulder_weapon", id).is_indirect_fire:
			return true
	var internal = data.get("internal")
	if internal is String and PartManager.is_valid_part("internal", internal):
		return PartManager.get_part("internal", internal).function in ["ward", "drone", "seeker", "flare"]
	return false


## Design data for a squad of `size`: at least one direct-fire build first,
## then any, a third that prefers support. Personalities drawn by the
## weights.
func pick_squad_designs(size: int) -> Array:
	var all: Array = []
	for npc in NPCS:
		all.append(get_design_data(npc, pick_personality_name()))
	var direct: Array = all.filter(func(d): return is_direct_fire(d))
	var support: Array = all.filter(func(d): return is_support(d))
	var picked: Array = []
	picked.append((direct if not direct.is_empty() else all).pick_random())
	if size >= 2:
		picked.append(all.pick_random())
	if size >= 3:
		picked.append((support if not support.is_empty() else all).pick_random())
	return picked


## `personality_name` ("rat", ...) replaces the design's own personality.
func get_design_data(npc, personality_name := ""):
	var data = {}
	# The internal bay is optional: a design without it (older special NPCs)
	# leaves it empty.
	for part_type in ["head", "core", "shoulders", "generator", "chipset", "chassis",\
					"thruster", "arm_weapon_left", "arm_weapon_right", \
					"shoulder_weapon_left", "shoulder_weapon_right", "internal"]:
		var abs_type = part_type.replace("_left", "").replace("_right", "")
		var spec = npc.get(part_type)
		var part = get_part(abs_type, spec if spec != null else [])
		data[part_type] = part.part_id if part else false

	# Pass personality through to Enemy.setup()
	if personality_name != "":
		data["personality"] = _personality_from_string(personality_name)
	elif npc is Resource and npc.get("personality") is Personality:
		data["personality"] = npc.personality
	elif npc is Dictionary and npc.has("personality"):
		data["personality"] = _personality_from_string(npc.personality)

	# A named NPC keeps its own name as its callsign (Local, name tags).
	if npc is Resource and npc.get("mecha_name") is String:
		data["callsign"] = npc.mecha_name

	# Pass combat_behaviour through to Enemy.setup() (used for AI state machine)
	if npc is Resource and npc.get("combat_behaviour"):
		data["combat_behaviour"] = npc.combat_behaviour
	elif npc is Dictionary and npc.has("combat_behaviour"):
		data["combat_behaviour"] = npc["combat_behaviour"]

	return data


func _personality_from_string(type_name: String) -> Personality:
	var p = Personality.new()
	match type_name:
		"scavenger":
			p.type = Personality.Type.SCAVENGER
			p.aggression = 0.2
			p.courage = 0.2
			p.greed = 0.9
			p.loyalty = 0.0
			p.treachery = 0.0
		"guardian":
			p.type = Personality.Type.GUARDIAN
			p.aggression = 0.4
			p.courage = 0.8
			p.greed = 0.1
			p.loyalty = 0.9
			p.treachery = 0.0
		"hunter":
			p.type = Personality.Type.HUNTER
			p.aggression = 0.9
			p.courage = 0.8
			p.greed = 0.2
			p.loyalty = 0.0
			p.treachery = 0.0
		"rat":
			p.type = Personality.Type.RAT
			p.aggression = 0.6
			p.courage = 0.3
			p.greed = 0.5
			p.loyalty = 0.0
			p.treachery = 0.9
		_: # "professional" or unknown
			p.type = Personality.Type.PROFESSIONAL
			p.aggression = 0.5
			p.courage = 0.5
			p.greed = 0.3
			p.loyalty = 0.1
			p.treachery = 0.0
	p.skill = Personality.roll_skill(p.type)
	return p

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
