extends Control

const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")
const LERP_WEIGHT = 5

enum SIDE {LEFT, RIGHT, SINGLE}
enum STAT {ELECTRONICS, DEFENSES, MOBILITY, ENERGY, RARM, LARM, RSHOULDER, LSHOULDER}

onready var PartList = $PartListContainer/VBoxContainer
onready var CategorySelectedUI = $CategorySelectedUI
onready var CategoryButtons = $CategoryButtons
onready var PartCategories = $PartCategories
onready var DisplayMecha = $Mecha
onready var ComparisonMecha = $ComparisonMecha
onready var StatBars = $Statbars
onready var LoadScreen = $LoadScreen

var category_visible = false
var comparing_part = false

func _ready():
	default_loadout()
	$Statbars.update_stats(DisplayMecha)
	update_weight()
	DisplayMecha.global_rotation = 0
	LoadScreen.connect("load_pressed", self, "_LoadScreen_on_load_pressed")

func _process(dt):
	if not comparing_part:
		$WeightComparisonBar.value = lerp($WeightComparisonBar.value, $WeightBar.value, LERP_WEIGHT*dt)
		$WeightComparisonBar.max_value = lerp($WeightComparisonBar.max_value, $WeightBar.max_value, LERP_WEIGHT*dt)
	else:
		$WeightComparisonBar.value = lerp($WeightComparisonBar.value, ComparisonMecha.get_stat("weight"), LERP_WEIGHT*dt)
		$WeightComparisonBar.max_value = lerp($WeightComparisonBar.max_value, ComparisonMecha.get_stat("weight_capacity"), LERP_WEIGHT*dt)

func _input(event):
	if event.is_action_pressed("toggle_fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
		Profile.set_option("fullscreen", OS.window_fullscreen, true)
		if not OS.window_fullscreen:
			yield(get_tree(), "idle_frame")
			OS.window_size = Profile.WINDOW_SIZES[Profile.get_option("window_size")]
			OS.window_position = Vector2(0,0)


func default_loadout():
	DisplayMecha.set_core("MSV-L3J-C")
	DisplayMecha.set_generator("type_1")
	DisplayMecha.set_chipset("type_1")
	DisplayMecha.set_head("MSV-L3J-H")
	DisplayMecha.set_chassis("MSV-L3J-L")
	DisplayMecha.set_arm_weapon("TT1-Shotgun", SIDE.LEFT)
	DisplayMecha.set_arm_weapon("Type2Sh-Gattling", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon(false, SIDE.LEFT)
	DisplayMecha.set_shoulders("MSV-L3J-SG")
	
	
	ComparisonMecha.set_core("MSV-L3J-C")
	ComparisonMecha.set_generator("type_1")
	ComparisonMecha.set_chipset("type_1")
	ComparisonMecha.set_head("MSV-L3J-H")
	ComparisonMecha.set_chassis("MSV-L3J-L")
	ComparisonMecha.set_arm_weapon("TT1-Shotgun", SIDE.LEFT)
	ComparisonMecha.set_arm_weapon("Type2Sh-Gattling", SIDE.RIGHT)
	ComparisonMecha.set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
	ComparisonMecha.set_shoulder_weapon(false, SIDE.LEFT)
	ComparisonMecha.set_shoulders("MSV-M2-SG")
	
	update_weight()


func show_category_button(parts, selected):
	category_visible = false
	PartList.visible = false
	for child in PartList.get_children():
		PartList.remove_child(child)
	for category in PartCategories.get_children():
		category.visible = (category == parts)
		for part in category.get_children():
			part.visible = true
			part.pressed = false
	for child in CategorySelectedUI.get_children():
		child.visible = (child == selected)


func _on_Category_pressed(type,group,side = false):
	var group_node = PartCategories.get_node(group)
	var type_name = type
	if side:
		type_name = type + "_" + side
	if category_visible == false:
		category_visible = true
		PartList.visible = true
		for child in group_node.get_children():
			if child.name != type_name:
				child.visible = false
				child.pressed = false
		var parts = PartManager.get_parts(type)
		for child in PartList.get_children(): #Clear PartList
			PartList.remove_child(child)
		for part_key in parts.keys(): #Parsing through a dictionary using .values()
			var part = parts[part_key]
			var item = ITEMFRAME.instance()
			item.setup(part)
			PartList.add_child(item)
			item.get_button().connect("pressed",self,"_on_ItemFrame_pressed",[part_key,type,side])
			item.get_button().connect("mouse_entered",self,"_on_ItemFrame_mouse_entered",[part_key,type,side])
			item.get_button().connect("mouse_exited",self,"_on_ItemFrame_mouse_exited",[part_key,type,side])
	else:
		category_visible = false
		for child in group_node.get_children():
			child.visible = true
		for child in PartList.get_children(): #Clear PartList
			PartList.remove_child(child)
		PartList.visible = false


func _on_HardwareButton_pressed():
	show_category_button($PartCategories/Hardware, $CategorySelectedUI/Hardware)


func _on_WetwareButton_pressed():
	show_category_button($PartCategories/Wetware, $CategorySelectedUI/Wetware)


func _on_EquipmentButton_pressed():
	show_category_button($PartCategories/Equipment, $CategorySelectedUI/Equipment)


func _on_ItemFrame_pressed(part_name,type,side):
	if side:
		side = DisplayMecha.SIDE.LEFT if side == "left" else DisplayMecha.SIDE.RIGHT
		DisplayMecha.callv("set_" + str(type), [part_name,side])
		ComparisonMecha.callv("set_" + str(type), [part_name,side])
	else:
		DisplayMecha.callv("set_" + str(type), [part_name])
		ComparisonMecha.callv("set_" + str(type), [part_name])
	$Statbars.update_stats(DisplayMecha)
	update_weight()
	comparing_part = false


func _on_ItemFrame_mouse_entered(part_name,type,side):
	if side:
		side = DisplayMecha.SIDE.LEFT if side == "left" else DisplayMecha.SIDE.RIGHT
		ComparisonMecha.callv("set_" + str(type), [part_name,side])
	else:
		ComparisonMecha.callv("set_" + str(type), [part_name])
	StatBars.set_comparing_part(ComparisonMecha)
	comparing_part = true


func _on_ItemFrame_mouse_exited(_part_name,_type,_side):
	StatBars.reset_comparing_part()
	comparing_part = false

func update_weight():
	$WeightBar.max_value = DisplayMecha.get_stat("weight_capacity")
	$WeightBar.value = DisplayMecha.get_stat("weight")
	$CurrentWeightLabel.text = str(DisplayMecha.get_stat("weight")) 
	$MaxWeightLabel.text = str(DisplayMecha.get_stat("weight_capacity"))


func _on_Save_pressed():
	FileManager.save_mecha_design(DisplayMecha, "test")


func _on_Exit_pressed():
	var data = FileManager.load_mecha_design("test")
	if data:
		DisplayMecha.set_parts_from_design(data)

func _on_Load_pressed():
	$LoadScreen.visible = true

func _LoadScreen_on_load_pressed(design):
	DisplayMecha.set_core(design.core)
	DisplayMecha.set_generator(design.generator)
	DisplayMecha.set_chipset(design.chipset)
	DisplayMecha.set_head(design.head)
	DisplayMecha.set_chassis(design.chassis)
	DisplayMecha.set_arm_weapon(design.arm_weapon_left, SIDE.LEFT)
	DisplayMecha.set_arm_weapon(design.arm_weapon_right, SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon(design.shoulder_weapon_right, SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon(design.shoulder_weapon_left, SIDE.LEFT)
	DisplayMecha.set_shoulders(design.shoulders)
	
	ComparisonMecha.set_core(design.core)
	ComparisonMecha.set_generator(design.generator)
	ComparisonMecha.set_chipset(design.chipset)
	ComparisonMecha.set_head(design.head)
	ComparisonMecha.set_chassis(design.chassis)
	ComparisonMecha.set_arm_weapon(design.arm_weapon_left, SIDE.LEFT)
	ComparisonMecha.set_arm_weapon(design.arm_weapon_right, SIDE.RIGHT)
	ComparisonMecha.set_shoulder_weapon(design.shoulder_weapon_right, SIDE.RIGHT)
	ComparisonMecha.set_shoulder_weapon(design.shoulder_weapon_left, SIDE.LEFT)
	ComparisonMecha.set_shoulders(design.shoulders)
	
	update_weight()
