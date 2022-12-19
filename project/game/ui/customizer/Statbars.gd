extends Control

enum STAT {ELECTRONICS, DEFENSES, MOBILITY, ENERGY, RARM, LARM, RSHOULDER, LSHOULDER}

const CAT_PATH = "CategoryContainers/"
const LERP_WEIGHT = 5

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
var compared_part = false

func _ready():
	mode_switch(STAT.ELECTRONICS)
	update_max_value()
	
func _process(dt):
	if not compared_part:
		for container in $CategoryContainers.get_children():
			for stat in container.get_node("VBoxContainer").get_children():
				if stat.get_child_count() > 0:
					var comparison_value = stat.get_node("ComparisonValue")
					comparison_value.percent_visible = lerp(comparison_value.percent_visible, 0, LERP_WEIGHT*dt)
					if stat.has_node("ComparisonBar"):
						var comparison_bar = stat.get_node("ComparisonBar")
						var real_bar = stat.get_node("RealBar")
						comparison_bar.value = lerp(comparison_bar.value, real_bar.value, LERP_WEIGHT*dt)
	else:
		for container in $CategoryContainers.get_children():
			for stat in container.get_node("VBoxContainer").get_children():
				if stat.get_child_count() > 0:
					var comparison_value = stat.get_node("ComparisonValue")
					comparison_value.percent_visible = lerp(comparison_value.percent_visible, 100, LERP_WEIGHT*dt)
					

func mode_switch (mode):
	assert(mode >= 0 and mode <= StatNodes.size() - 1, "Not a valid mode: " + str(mode))
	var target_node = StatNodes[mode]
	for child in $CategoryContainers.get_children():
		child.visible = child == target_node 
	current_category = mode 
	CategoryTitle.text = StatNodeTitles[current_category]


func reset_comparing_part():
	compared_part = false


func set_comparing_part(mecha):
	compared_part = true
	for container in $CategoryContainers.get_children():
		for stat in container.get_node("VBoxContainer").get_children():
			if stat.get("stat_name"):
				var stat_value
				var weapon
				if stat.get("weapon_position"):
					weapon = mecha.get(stat.get("weapon_position"))
					stat_value = weapon.get_stat(stat.get("stat_name"))
				else:
					stat_value = mecha.get_stat(stat.get("stat_name"))
				if stat_value is bool:
					if stat_value == true:
						stat.get_node("ComparisonValue").text = "Yes"
					else: 
						stat.get_node("ComparisonValue").text = "No"
				elif stat_value is float or stat_value is int:
					stat.get_node("ComparisonValue").text = str(stat_value)
					if stat.has_node("ComparisonBar"):
						stat.get_node("ComparisonBar").value = stat_value
						stat.get_node("ComparisonBar").value = stat_value
				elif stat_value is String:
					stat.get_node("ComparisonValue").text = stat_value
				else:
					pass


func _on_SwitchRight_pressed():
	current_category = ((current_category + 1) % StatNodes.size())
	mode_switch(current_category)


func _on_SwitchLeft_pressed():
	current_category = posmod(current_category - 1, StatNodes.size())
	mode_switch(current_category)


func update_stats(mecha):
	for container in $CategoryContainers.get_children():
		for stat in container.get_node("VBoxContainer").get_children():
			if stat.get("stat_name"):
				var stat_value
				var weapon
				if stat.get("weapon_position"):
					weapon = mecha.get(stat.get("weapon_position"))
					stat_value = weapon.get_stat(stat.get("stat_name"))
				else:
					stat_value = mecha.get_stat(stat.get("stat_name"))
				if stat_value is bool:
					if stat_value == true:
						stat.get_node("RealValue").text = "Yes"
					else: 
						stat.get_node("RealValue").text = "No"
				elif stat_value is float or stat_value is int:
					stat.get_node("RealValue").text = str(stat_value)
					if stat.has_node("RealBar"):
						stat.get_node("RealBar").value = stat_value
						stat.get_node("ComparisonBar").value = stat_value
				elif stat_value is String:
					stat.get_node("RealValue").text = stat_value
				else:
					pass

func update_max_value():
	for container in $CategoryContainers.get_children():
		for stat in container.get_node("VBoxContainer").get_children():
			if stat.has_node("RealBar") and stat.get("stat_name"):
				stat.get_node("RealBar").max_value = PartManager.get_max_stat_value(stat.stat_name)
				stat.get_node("ComparisonBar").max_value = PartManager.get_max_stat_value(stat.stat_name)
	
