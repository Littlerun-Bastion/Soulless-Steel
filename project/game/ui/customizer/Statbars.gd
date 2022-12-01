extends Control

enum STAT {ELECTRONICS, DEFENSES, MOBILITY, ENERGY, RARM, LARM, RSHOULDER, LSHOULDER}

const CAT_PATH = "CategoryContainers/"

onready var StatNodes = [get_node(CAT_PATH + "ElectronicsContainer"),
get_node(CAT_PATH + "DefensesContainer"),
get_node(CAT_PATH + "MobilityContainer"),
get_node(CAT_PATH + "EnergyContainer"),
get_node(CAT_PATH + "RArmContainer"),
get_node(CAT_PATH + "LArmContainer"),
get_node(CAT_PATH + "RShoulderContainer"),
get_node(CAT_PATH + "LShoulderContainer")]

onready var StatNodeTitles = ["Electronics",
"Defenses",
"Mobility",
"Energy",
"Right Arm",
"Left Arm",
"Right Shoulder",
"Left Shoulder"]

onready var CategoryTitle = $CategoryTitle

var current_category = 0

func _ready():
	mode_switch(0)

func mode_switch (mode):
	assert(mode >= 0 and mode <= StatNodes.size() - 1, "Not a valid mode: " + str(mode))
	var target_node = StatNodes[mode]
	for child in $CategoryContainers.get_children():
		child.visible = child == target_node 
	current_category = mode 
	CategoryTitle.text = StatNodeTitles[current_category]

func _on_SwitchRight_pressed():
	current_category = ((current_category + 1) % StatNodes.size())
	mode_switch(current_category)


func _on_SwitchLeft_pressed():
	current_category = posmod(current_category - 1, StatNodes.size())
	mode_switch(current_category)
