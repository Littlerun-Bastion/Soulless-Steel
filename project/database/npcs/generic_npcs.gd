extends Node

const NPCS = [
	{
		#Main Attributes
		"combat_behaviour": "default",
		"difficulty": 5.0,
		#Mecha build
		"head": ["MSV-L3J-H"],
		"core": ["MSV-L3J-C"],
		"shoulders": ["MSV-L3J-SG"],
		"generator": ["EGV-P1"],
		"chipset": ["type_1_chip"],
		"chassis": ["MSV-L3J-L"],
		"thruster": ["type_1_thruster"],
		"arm_weapon_left": ["MA-L127"],
		"arm_weapon_right": ["MA-L127"],
		"shoulder_weapon_left": [],
		"shoulder_weapon_right": [],
	},
	{
		#Main Attributes
		"combat_behaviour": "idle",
		"difficulty": 0.0,
		#Mecha Build
		"head": ["MSV-M2-H"],
		"core": ["MSV-M2-C"],
		"shoulders": ["MSV-M2-SG"],
		"generator": ["EGV-P1"],
		"chipset": ["type_1_chip"],
		"chassis": ["Crawler_C-type_Chassis"],
		"thruster": ["type_1_thruster"],
		"arm_weapon_left": ["OM1804"],
		"arm_weapon_right": ["OM1810"],
		"shoulder_weapon_left": ["TORI-ML"],
		"shoulder_weapon_right": ["MA-GL44"],
	},
]

static func get_npcs():
	return NPCS
