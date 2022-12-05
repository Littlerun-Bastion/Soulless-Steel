extends Control

const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")

enum SIDE {LEFT, RIGHT, SINGLE}
enum STAT {ELECTRONICS, DEFENSES, MOBILITY, ENERGY, RARM, LARM, RSHOULDER, LSHOULDER}

onready var PartList = $PartListContainer/VBoxContainer
onready var DisplayMecha = $Mecha
onready var categoryVisible = false

func _ready():
	default_loadout()
	$Statbars.update_stats(DisplayMecha)

func default_loadout():
	DisplayMecha.set_core("MSV-L3J")
	DisplayMecha.set_generator("type_1")
	DisplayMecha.set_chipset("type_1")
	DisplayMecha.set_head("head_test")
	DisplayMecha.set_chassis("MSV-L3J-L", SIDE.LEFT)
	DisplayMecha.set_chassis("MSV-L3J-R", SIDE.RIGHT)
	DisplayMecha.set_arm_weapon("TT1-Shotgun", SIDE.LEFT)
	DisplayMecha.set_arm_weapon("Type2Sh-Gattling", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon(false, SIDE.LEFT)
	DisplayMecha.set_shoulders("shoulder_test")

func _on_Category_pressed(type,group,side = false):
	var groupNode = get_node(group)
	var typeName = type
	if side:
		typeName = type + "_" + side
	if categoryVisible == false:
		categoryVisible = true
		PartList.visible = true
		for child in groupNode.get_children():
			if child == get_node(group + "/" + typeName):
				pass
			else:
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
			item.get_button().connect("pressed",self,"_on_itemFrame_pressed",[part_key,type,side])
			item.get_button().connect("mouse_entered",self,"_on_itemFrame_mouse_entered",[part_key,type,side])
			item.get_button().connect("mouse_exited",self,"_on_itemFrame_mouse_exited",[part_key,type,side])
	else:
		categoryVisible = false
		for child in groupNode.get_children():
			child.visible = true
		for child in PartList.get_children(): #Clear PartList
			PartList.remove_child(child)
		PartList.visible = false
	

func hide_all_buttons():
	categoryVisible = false
	PartList.visible = false
	for child in PartList.get_children(): #Clear PartList
		PartList.remove_child(child)
	$Hardware.visible = false
	$Wetware.visible = false
	$Equipment.visible = false
	$HardwareSelected.visible = false
	$WetwareSelected.visible = false
	$EquipmentSelected.visible = false
	
	

func _on_HardwareButton_pressed():
	hide_all_buttons()
	$HardwareSelected.visible = true
	$Hardware.visible = true


func _on_WetwareButton_pressed():
	hide_all_buttons()
	$WetwareSelected.visible = true
	$Wetware.visible = true


func _on_EquipmentButton_pressed():
	hide_all_buttons()
	$EquipmentSelected.visible = true
	$Equipment.visible = true

func _on_itemFrame_pressed(part_name,type,side):
	var part = PartManager.get_part(type,part_name)
	if type == "chassis":
		DisplayMecha.callv("set_" + str(type), [part_name,part.side])
	elif side:
		side = DisplayMecha.SIDE.LEFT if side == "left" else DisplayMecha.SIDE.RIGHT
		DisplayMecha.callv("set_" + str(type), [part_name,side])
	else:
		DisplayMecha.callv("set_" + str(type), [part_name])
		

func _on_itemFrame_mouse_entered(part_name,type,side):
	pass
	

func _on_itemFrame_mouse_exited(part_name,type,side):
	pass


