extends Node

const NPCS = [
	{
		#Main Attributes
		"combat_behaviour": "default",
		"difficulty": 5.0,
		"personality": "professional",
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
		"internal": ["ECM-20"],
	},
	{
		#Main Attributes
		"combat_behaviour": "default",
		"difficulty": 0.0,
		"personality": "scavenger",
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
		"internal": [],
	},
	# Placeholder builds from existing parts, so every personality and every
	# squad role has a design to spawn with. The "personality" here is the
	# default; spawns usually draw one from NPCManager.PERSONALITY_WEIGHTS.
	{
		# A guard: direct fire, smoke to cover a withdrawal, a ward out.
		"combat_behaviour": "default",
		"difficulty": 4.0,
		"personality": "guardian",
		"head": ["MSV-L3J-H"],
		"core": ["MSV-L3J-C"],
		"shoulders": ["MSV-L3J-SG"],
		"generator": ["EGV-P1"],
		"chipset": ["type_1_chip"],
		"chassis": ["MSV-L3J-L"],
		"thruster": ["type_1_thruster"],
		"arm_weapon_left": ["MA-L178"],
		"arm_weapon_right": ["MA-L127"],
		"shoulder_weapon_left": ["MA-SL6"],
		"shoulder_weapon_right": [],
		"internal": ["WD-2"],
	},
	{
		# A hunter: long guns, a lock-on launcher, a drone.
		"combat_behaviour": "aggressive",
		"difficulty": 6.0,
		"personality": "hunter",
		"head": ["MSV-L3J-H"],
		"core": ["MSV-L3J-C"],
		"shoulders": ["MSV-L3J-SG"],
		"generator": ["EGV-P1"],
		"chipset": ["type_1_chip"],
		"chassis": ["MSV-L3J-L"],
		"thruster": ["type_1_thruster"],
		"arm_weapon_left": ["Kruis_CL157.0"],
		"arm_weapon_right": ["Kruis_CL157.0"],
		"shoulder_weapon_left": ["TORI-ML"],
		"shoulder_weapon_right": [],
		"internal": ["DR-4"],
	},
	{
		# A rat: a crawler with close guns, a mine layer and a decoy.
		"combat_behaviour": "cautious",
		"difficulty": 3.0,
		"personality": "rat",
		"head": ["MSV-M2-H"],
		"core": ["MSV-M2-C"],
		"shoulders": ["MSV-M2-SG"],
		"generator": ["EGV-P1"],
		"chipset": ["type_1_chip"],
		"chassis": ["Crawler_C-type_Chassis"],
		"thruster": ["type_1_thruster"],
		"arm_weapon_left": ["OM1804"],
		"arm_weapon_right": ["OM1810"],
		"shoulder_weapon_left": ["MA-ML1"],
		"shoulder_weapon_right": [],
		"internal": ["DC-2"],
	},
	{
		# A support build for a squad's third member: a mortar and a ward.
		"combat_behaviour": "cautious",
		"difficulty": 4.0,
		"personality": "professional",
		"head": ["MSV-M2-H"],
		"core": ["MSV-M2-C"],
		"shoulders": ["MSV-M2-SG"],
		"generator": ["EGV-P1"],
		"chipset": ["type_1_chip"],
		"chassis": ["Crawler_C-type_Chassis"],
		"thruster": ["type_1_thruster"],
		"arm_weapon_left": ["OM1804"],
		"arm_weapon_right": [],
		"shoulder_weapon_left": ["MA-M120"],
		"shoulder_weapon_right": [],
		"internal": ["WD-2"],
	},
]

static func get_npcs():
	return NPCS
