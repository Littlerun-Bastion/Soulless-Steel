extends Control
##Storepage
const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")
const BASKET_ITEM = preload("res://game/ui/customizer/BasketItem.tscn")
const LERP_WEIGHT = 5

enum SIDE {LEFT, RIGHT, SINGLE}
enum STAT {ELECTRONICS, DEFENSES, MOBILITY, ENERGY, RARM, LARM, RSHOULDER, LSHOULDER}

@onready var PartList = $PartListContainer/VBoxContainer
@onready var CategorySelectedUI = $CategorySelectedUI
@onready var CategoryButtons = $CategoryButtons
@onready var PartCategories = $PartCategories
@onready var DisplayMecha = $Mecha
@onready var ComparisonMecha = $ComparisonMecha
#onready var StatBars = $Statbars
@onready var Statcard = $Statcard
@onready var LoadScreen = $LoadScreen
@onready var BasketList = $Basket/ScrollContainer/Basket
@onready var PurchaseComplete = $PurchaseConfirm/complete
@onready var PurchaseConfirm = $PurchaseConfirm/confirm
@onready var TotalCostLabel = $PurchaseConfirm/confirm/TotalCost/Amount


var category_visible = false
var comparing_part = false
var type_name
var basket_total = 0.0
var balance = 100000.0

func _ready():
	if Profile.stats.current_mecha:
		DisplayMecha.set_parts_from_design(Profile.stats.current_mecha)
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
	else:
		default_loadout()
	#$Statbars.update_stats(DisplayMecha)
	DisplayMecha.global_rotation = 0
	LoadScreen.connect("load_pressed",Callable(self,"_LoadScreen_on_load_pressed"))

func _input(event):
	if event.is_action_pressed("toggle_fullscreen"):
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (not ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN))) else Window.MODE_WINDOWED
		Profile.set_option("fullscreen", ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN)), true)
		if not ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN)):
			await get_tree().idle_frame
			get_window().size = Profile.WINDOW_SIZES[Profile.get_option("window_size")]
			get_window().position = Vector2(0,0)


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
	
	shoulder_weapon_check()


func show_category_button(parts, selected):
	category_visible = false
	PartList.visible = false
	for child in PartList.get_children():
		PartList.remove_child(child)
	for category in PartCategories.get_children():
		category.visible = (category == parts)
		for part in category.get_children():
			part.visible = true
			part.button_pressed = false
	for child in CategorySelectedUI.get_children():
		child.visible = (child == selected)


func _on_Category_pressed(type,group,side = false):
	var group_node = PartCategories.get_node(group)
	type_name = type
	if side:
		type_name = type + "_" + side
	if category_visible == false:
		category_visible = true
		PartList.visible = true
		for child in group_node.get_children():
			if child.name != type_name:
				child.visible = false
				child.button_pressed = false
		var parts = PartManager.get_parts(type)
		for child in PartList.get_children(): #Clear PartList
			PartList.remove_child(child)
		for part_key in parts.keys(): #Parsing through a dictionary using super.values()
			var part = parts[part_key]
			var item = ITEMFRAME.instantiate()
			item.setup(part,true)
			PartList.add_child(item)
			item.get_button().connect("pressed",Callable(self,"_on_ItemFrame_pressed").bind(part_key,type,side,item))
			item.get_button().connect("mouse_entered",Callable(self,"_on_ItemFrame_mouse_entered").bind(part_key,type,side,item))
			item.get_button().connect("mouse_exited",Callable(self,"_on_ItemFrame_mouse_exited").bind(part_key,type,side,item))
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


func _on_ItemFrame_pressed(part_name,type,side,item):
	add_to_basket(type, part_name)


func _on_ItemFrame_mouse_entered(part_name,type,side,item):
	if item.is_disabled == true:
		item.get_button().disabled = false
	if side:
		side = DisplayMecha.SIDE.LEFT if side == "left" else DisplayMecha.SIDE.RIGHT
		ComparisonMecha.callv("set_" + str(type), [part_name,side])
	else:
		ComparisonMecha.callv("set_" + str(type), [part_name])
	#StatBars.set_comparing_part(ComparisonMecha)
	var current_part = DisplayMecha.get(type_name)
	var new_part = ComparisonMecha.get(type_name)
	Statcard.display_part_stats(current_part, new_part, type_name)
	Statcard.visible = true
	comparing_part = true

func shoulder_weapon_check():
	var core
	if DisplayMecha.core:
		core = DisplayMecha.core
	else:
		$PartCategories/Equipment/shoulder_weapon_left.disabled = true
		$PartCategories/Equipment/shoulder_weapon_right.disabled = true
		return
	if not core.has_left_shoulder:
		$PartCategories/Equipment/shoulder_weapon_left.disabled = true
	else:
		$PartCategories/Equipment/shoulder_weapon_left.disabled = false
	if not core.has_right_shoulder:
		$PartCategories/Equipment/shoulder_weapon_right.disabled = true
	else:
		$PartCategories/Equipment/shoulder_weapon_right.disabled = false

func is_build_valid():
	var build_valid = true
	var missing_parts : String
	for part in ["head", "core", "shoulders", "generator",\
				"chipset", "chassis", "thruster", "shoulders"]:
		if not DisplayMecha.get(part):
			build_valid = false
			missing_parts = missing_parts + "WARN: " + part + " "
	if not build_valid:
		$MissingPartsScroll/MissingParts.text = missing_parts
		$MissingPartsScroll/MissingParts.visible = true
	else:
		$MissingPartsScroll/MissingParts.visible = false
	return build_valid

func _on_ItemFrame_mouse_exited(_part_name,_type,_side, item):
	if item.is_disabled == true:
		item.get_button().disabled = true
	#StatBars.reset_comparing_part()
	comparing_part = false
	Statcard.visible = false

func _on_Save_pressed():
	FileManager.save_mecha_design(DisplayMecha, "test")


func _on_Exit_pressed():
	if is_build_valid():
		Profile.set_stat("current_mecha", DisplayMecha.get_design_data())
		get_tree().change_scene_to_file("res://game/start_menu/StartMenuDemo.tscn")
	else:
		print("Build invalid")

func _on_Load_pressed():
	$LoadScreen.shopping_mode = true
	$LoadScreen.visible = true

func _LoadScreen_on_load_pressed(design):
	DisplayMecha.set_parts_from_design(design)
	ComparisonMecha.set_parts_from_design(design)
	shoulder_weapon_check()

func add_to_basket(type, part_name):
	#Transaction code goes here
	var item = PartManager.get_part(type, part_name)
	var basket_item_entry = BASKET_ITEM.instantiate()
	basket_item_entry.setup(item)
	BasketList.add_child(basket_item_entry)
	basket_item_entry.get_button().connect("pressed",Callable(self,"remove_from_basket").bind(basket_item_entry))
	recalculate_total()

func remove_from_basket(item):
	BasketList.remove_child(item)
	item.queue_free()
	recalculate_total()

func recalculate_total():
	basket_total = 0.0
	var num_items = 0
	for item in BasketList.get_children():
		basket_total += item.get_price()
		num_items += 1
	$Basket/BottomSect/HBoxContainer/Total.text = str(basket_total)
	
	$PurchaseConfirm/confirm/Control/Label.text = "Purchase " + str(num_items) + " items?"
	$PurchaseConfirm/confirm/TotalCost/Amount.text = str(basket_total)
	$PurchaseConfirm/confirm/CurrentBalance/Amount.text = str(balance)
	$PurchaseConfirm/confirm/RemainingBalance/Amount.text = str(balance - basket_total)


func _on_purchase_pressed():
	$PurchaseConfirm.visible = true
	PurchaseConfirm.visible = true
	PurchaseComplete.visible = false
