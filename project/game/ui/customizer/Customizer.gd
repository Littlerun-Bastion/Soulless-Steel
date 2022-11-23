extends Control

const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")

enum SIDE {LEFT, RIGHT, SINGLE}

onready var PartList = $PartListContainer/VBoxContainer
onready var DisplayMecha = $Mecha

func _ready():
	default_loadout()

func default_loadout():
	DisplayMecha.set_core("MSV-L3J")
	DisplayMecha.set_generator("type_1")
	DisplayMecha.set_chipset("type_1")
	DisplayMecha.set_head("head_test")
	DisplayMecha.set_leg("MSV-L3J-L", SIDE.LEFT)
	DisplayMecha.set_leg("MSV-L3J-R", SIDE.RIGHT)
	DisplayMecha.set_arm_weapon("TT1-Shotgun", SIDE.LEFT)
	DisplayMecha.set_arm_weapon("Type2Sh-Gattling", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon(false, SIDE.LEFT)
	DisplayMecha.set_shoulder("shoulder_test")

func _on_Category_pressed(type,side = false):
	var parts = PartManager.get_parts(type)
	for child in PartList.get_children(): #Clear PartList
		PartList.remove_child(child)
	for part_key in parts.keys(): #Parsing through a dictionary using .values()
		var part = parts[part_key]
		var item = ITEMFRAME.instance()
		item.setup(part)
		PartList.add_child(item)
		item.get_button().connect("pressed",self,"_on_itemFrame_pressed",[part_key,type,side])

func hide_all_buttons():
	for child in PartList.get_children(): #Clear PartList
		PartList.remove_child(child)
	$HardwareContainer.visible = false
	$WetwareContainer.visible = false
	$EquipmentContainer.visible = false
	$HardwareSelected.visible = false
	$WetwareSelected.visible = false
	$EquipmentSelected.visible = false
	
	

func _on_HardwareButton_pressed():
	hide_all_buttons()
	$HardwareSelected.visible = true
	$HardwareContainer.visible = true


func _on_WetwareButton_pressed():
	hide_all_buttons()
	$WetwareSelected.visible = true
	$WetwareContainer.visible = true


func _on_EquipmentButton_pressed():
	hide_all_buttons()
	$EquipmentSelected.visible = true
	$EquipmentContainer.visible = true

func _on_itemFrame_pressed(part_name,type,side):
	var part = PartManager.get_part(type,part_name)
	if type == "legs":
		DisplayMecha.callv("set_" + str(type), [part_name,part.side])
	elif side:
		side = DisplayMecha.SIDE.LEFT if side == "left" else DisplayMecha.SIDE.RIGHT
		DisplayMecha.callv("set_" + str(type), [part_name,side])
	else:
		DisplayMecha.callv("set_" + str(type), [part_name])
	
