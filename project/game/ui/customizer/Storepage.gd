extends Control

const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")
const BASKET_ITEM = preload("res://game/ui/customizer/BasketItem.tscn")
const LERP_WEIGHT = 5
const WEAPON_NAMES = {
	"arm_weapon_right": "Right Arm",
	"arm_weapon_left": "Left Arm",
	"shoulder_weapon_right": "R Shoulder",
	"shoulder_weapon_left": "L Shoulder",
}

enum SIDE {LEFT, RIGHT, SINGLE}
enum STAT {ELECTRONICS, DEFENSES, MOBILITY, ENERGY, RARM, LARM, RSHOULDER, LSHOULDER}

@onready var PartList = $PartListContainer/VBoxContainer
@onready var CategorySelectedUI = $CategorySelectedUI
@onready var CategoryButtons = $CategoryButtons
@onready var PartCategories = $PartCategories
@onready var DisplayMecha = $Mecha
@onready var ComparisonMecha = $ComparisonMecha
@onready var Statcard = $Statcard
@onready var LoadScreen = $LoadScreen
@onready var BasketList = $Basket/ScrollContainer/Basket
@onready var PurchaseComplete = $PurchaseConfirm/complete
@onready var PurchaseConfirm = $PurchaseConfirm/confirm
@onready var TotalCostLabel = $PurchaseConfirm/confirm/TotalCost/Amount
@onready var CommandLine = $CommandLine


var category_visible = false
var current_group = false
var comparing_part = false
var type_name
var basket_total = 0.0
var balance = 100000.0
var region = "United Federation of America" ##United Federation of America, Northern Circle, Continental African Republic, Pacific Association of Nations

func _ready():
	if Profile.stats.current_mecha:
		DisplayMecha.set_parts_from_design(Profile.stats.current_mecha)
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
	else:
		default_loadout()
	DisplayMecha.global_rotation = 0
	ComparisonMecha.global_rotation = 0
	LoadScreen.connect("load_pressed",Callable(self,"_LoadScreen_on_load_pressed"))
	balance = Profile.get_stat("money")
	$BalanceLabel.text = str(balance)
	if BasketList.get_child_count() == 0:
		$Basket/BottomSect/Button.disabled = true
		$Basket2/BottomSect/Button.disabled = true
	$Basket.visible = true	
	$Basket2.visible = false
	ComparisonMecha.visible = false


func _input(event):
	if event.is_action_pressed("toggle_fullscreen"):
		Global.toggle_fullscreen()
	elif event.is_action_pressed("back"):
		if $PurchaseConfirm.visible:
			cancel_purchase()
		elif current_group:
			reset_category()
		else:
			exit()
	elif event.is_action_pressed("confirm"):
		if not $PurchaseConfirm.visible:
			confirm_basket()
		else:
			if PurchaseComplete.visible:
				cancel_purchase()
			else:
				confirm_purchase()
	elif event.is_action_pressed("debug_1"):
		balance += 10000000
		$BalanceLabel.text = str(balance)
		recalculate_total()


func default_loadout():
	DisplayMecha.set_core("MSV-L3J-C")
	DisplayMecha.set_generator("type_1_gen")
	DisplayMecha.set_chipset("type_1_chip")
	DisplayMecha.set_head("MSV-L3J-H")
	DisplayMecha.set_chassis("MSV-L3J-L")
	DisplayMecha.set_arm_weapon("MA-L127", SIDE.LEFT)
	DisplayMecha.set_arm_weapon("MA-L127", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
	DisplayMecha.set_shoulder_weapon(false, SIDE.LEFT)
	DisplayMecha.set_shoulders("MSV-L3J-SG")
	
	ComparisonMecha.set_core("MSV-L3J-C")
	ComparisonMecha.set_generator("type_1")
	ComparisonMecha.set_chipset("type_1")
	ComparisonMecha.set_head("MSV-L3J-H")
	ComparisonMecha.set_chassis("MSV-L3J-L")
	ComparisonMecha.set_arm_weapon("MA-L127", SIDE.LEFT)
	ComparisonMecha.set_arm_weapon("MA-L127", SIDE.RIGHT)
	ComparisonMecha.set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
	ComparisonMecha.set_shoulder_weapon(false, SIDE.LEFT)
	ComparisonMecha.set_shoulders("MSV-M2-SG")
	
	shoulder_weapon_check()


func show_category_button(parts, selected):
	Statcard.visible = false
	category_visible = false
	PartList.visible = false
	for child in PartList.get_children():
		PartList.remove_child(child)
	for category in PartCategories.get_children():
		category.visible = (category == parts)
		for part in category.get_children():
			reset_category_name(part)
			part.visible = true
			part.button_pressed = false
	for child in CategorySelectedUI.get_children():
		child.visible = (child == selected)


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
		if not DisplayMecha.build[part]:
			build_valid = false
			missing_parts = missing_parts + "WARN: " + part + " "
	if not build_valid:
		print(missing_parts)
	return build_valid


func add_to_basket(type, part_name):
	#Transaction code goes here
	CommandLine.display("market_basket_add_item_entry --" + str(part_name))
	var item = PartManager.get_part(type, part_name)
	var basket_item_entry = BASKET_ITEM.instantiate()
	basket_item_entry.setup(item)
	BasketList.add_child(basket_item_entry)
	basket_item_entry.get_button().connect("pressed",Callable(self,"remove_from_basket").bind(basket_item_entry))
	recalculate_total()


func remove_from_basket(item):
	CommandLine.display("market_basket_remove_item_entry --" + str(item.current_item.part_name))
	BasketList.remove_child(item)
	item.queue_free()
	recalculate_total()


func recalculate_total():
	basket_total = 0.0
	var num_items = 0
	for item in BasketList.get_children():
		basket_total += item.get_price()
		num_items += 1
	if BasketList.get_child_count() == 0:
		$Basket/BottomSect/Button.disabled = true
		$Basket2/BottomSect/Button.disabled = true
	else:
		$Basket/BottomSect/Button.disabled = false
		$Basket2/BottomSect/Button.disabled = false
	if balance < basket_total:
		$PurchaseConfirm/confirm/HBoxContainer/Purchase.disabled = true
		$PurchaseConfirm/confirm/Control/Label.text = "Insufficient funds."
	else:
		$PurchaseConfirm/confirm/HBoxContainer/Purchase.disabled = false
		$PurchaseConfirm/confirm/Control/Label.text = "Purchase " + str(num_items) + " items?"
	$Basket/BottomSect/HBoxContainer/Total.text = str(basket_total)
	$Basket2/BottomSect/HBoxContainer/Total.text = str(basket_total)
	$PurchaseConfirm/confirm/TotalCost/Amount.text = str(basket_total)
	$PurchaseConfirm/confirm/CurrentBalance/Amount.text = str(balance)
	$PurchaseConfirm/confirm/RemainingBalance/Amount.text = str(balance - basket_total)


func reset_category():
	CommandLine.display("/market_parser --clear")
	var group_node = PartCategories.get_node(current_group)
	current_group = false
	type_name = false
	Statcard.visible = false
	category_visible = false
	for child in group_node.get_children():
		if not child.visible:
			child.visible = true
		else:
			reset_category_name(child)
	for child in PartList.get_children(): #Clear PartList
		PartList.remove_child(child)
	PartList.visible = false


func reset_category_name(button):
	if WEAPON_NAMES.has(button.name):
		button.text = WEAPON_NAMES[button.name]
	else:
		button.text = button.name
	button.text[0] = button.text[0].capitalize()


func exit():
	AudioManager.play_sfx("back")
	if is_build_valid():
		Profile.set_stat("current_mecha", DisplayMecha.get_design_data())
		TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")
	else:
		print("Build invalid")


func confirm_basket():
	if balance < basket_total:
		AudioManager.play_sfx("keystrike")
		AudioManager.play_sfx("deny_softer")
	else:
		AudioManager.play_sfx("question")
	CommandLine.display("/market_basket_purchase")
	$PurchaseConfirm.visible = true
	PurchaseConfirm.visible = true
	PurchaseComplete.visible = false


func confirm_purchase():
	if balance >= basket_total:
		balance -= basket_total
		CommandLine.display("/market_escrow --ctg_amount(" + str(basket_total) + ")")
		for item in BasketList.get_children():
			Profile.add_to_inventory(item.current_item.part_id)
			BasketList.remove_child(item)
			item.queue_free()
		recalculate_total()
		PurchaseConfirm.visible = false
		PurchaseComplete.visible = true
		$BalanceLabel.text = str(balance)
		Profile.set_stat("money", balance)
		AudioManager.play_sfx("confirm")
	else:
		AudioManager.play_sfx("keystrike")
		AudioManager.play_sfx("deny_softer")


func cancel_purchase():
	AudioManager.play_sfx("back")
	$PurchaseConfirm.visible = false


func _on_Category_pressed(type,group,side = false):
	ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
	if not category_visible:
		CommandLine.display("/market_parser --" + str(type))
		current_group = group
		var group_node = PartCategories.get_node(group)
		type_name = type
		Statcard.visible = false
		if side:
			type_name = type + "_" + side
		category_visible = true
		PartList.visible = true
		for child in group_node.get_children():
			if child.name != type_name:
				child.visible = false
				child.button_pressed = false
			else:
				child.text = "Back"
		var parts = PartManager.get_parts(type)
		for child in PartList.get_children(): #Clear PartList
			PartList.remove_child(child)
		for part_key in parts.keys(): #Parsing through a dictionary using super.values()
			var item = ITEMFRAME.instantiate()
			PartList.add_child(item)
			item.setup(part_key, type, true,false)
			item.get_button().connect("pressed",Callable(self,"_on_ItemFrame_pressed").bind(part_key, type))
			item.get_button().connect("mouse_entered",Callable(self,"_on_ItemFrame_mouse_entered").bind(part_key,type, side))
			item.get_button().connect("mouse_exited",Callable(self,"_on_ItemFrame_mouse_exited"))
	else:
		reset_category()


func _on_HardwareButton_pressed():
	CommandLine.display("/market_category --hardware")
	show_category_button($PartCategories/Hardware, $CategorySelectedUI/Hardware)


func _on_WetwareButton_pressed():
	CommandLine.display("/market_category --wetware")
	show_category_button($PartCategories/Wetware, $CategorySelectedUI/Wetware)


func _on_EquipmentButton_pressed():
	CommandLine.display("/market_category --equipment")
	show_category_button($PartCategories/Equipment, $CategorySelectedUI/Equipment)


func _on_ItemFrame_pressed(part_name,type):
	if not $PurchaseConfirm.visible:
		add_to_basket(type, part_name)


func _on_ItemFrame_mouse_entered(part_name,type,side):
	if side:
		side = DisplayMecha.SIDE.LEFT if side == "left" else DisplayMecha.SIDE.RIGHT
		ComparisonMecha.callv("set_" + str(type), [part_name,side])
	else:
		ComparisonMecha.callv("set_" + str(type), [part_name])
	var current_part = DisplayMecha.build[type_name]
	var new_part = ComparisonMecha.build[type_name]
	Statcard.display_part_stats(current_part, new_part, type_name)
	Statcard.visible = true
	comparing_part = true


func _on_ItemFrame_mouse_exited():
	comparing_part = false


func _on_Save_pressed():
	FileManager.save_mecha_design(DisplayMecha, "test")


func _on_Exit_pressed():
	exit()


func _on_Load_pressed():
	CommandLine.display("/osshell --builddata")
	$LoadScreen.shopping_mode = true
	$LoadScreen.visible = true


func _LoadScreen_on_load_pressed(design):
	DisplayMecha.set_parts_from_design(design)
	ComparisonMecha.set_parts_from_design(design)
	shoulder_weapon_check()


func _on_purchase_pressed():
	confirm_basket()


func _on_cancel_pressed():
	cancel_purchase()


func _on_purchase_items_pressed():
	confirm_purchase()


func _on_storebuttons_mouse_entered():
	AudioManager.play_sfx("keystroke")


func _on_purchase_mouse_entered():
	AudioManager.play_sfx("select")


func _on_expand_pressed():
	$Basket.visible = true
	$Basket2.visible = false
	ComparisonMecha.visible = false


func _on_collapse_pressed():
	$Basket.visible = false
	$Basket2.visible = true
	ComparisonMecha.visible = true
