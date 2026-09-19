extends Control

const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")
const LERP_WEIGHT = 3
const LERP_EPS = .1
const WEAPON_NAMES = {
	"arm_weapon_right": "Right Arm",
	"arm_weapon_left": "Left Arm",
	"shoulder_weapon_right": "R Shoulder",
	"shoulder_weapon_left": "L Shoulder",
}

# Design dictionary keys, in the order a design is applied (core before the
# shoulder weapons that depend on its mounts).
const DESIGN_SLOTS = ["head", "core", "shoulders", "generator", "chipset",
		"chassis", "thruster", "arm_weapon_left", "arm_weapon_right",
		"shoulder_weapon_left", "shoulder_weapon_right"]

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
@onready var CommandLine = $CommandLine
@onready var Weight = {
	"current_bar": $WeightNodes/CurrentBar,
	"comparison_bar": $WeightNodes/ComparisonBar,
	"current_label": $WeightNodes/WeightAmounts/CurrentWeight/Value,
	"max_label": $WeightNodes/WeightAmounts/MaxWeight/Value,
}

var category_visible = false
var comparing_part = false
var cur_type_selected
var current_group

func _ready():
	$LoadScreen.shopping_mode = false
	DisplayMecha.set_parts_from_design(PlayerProgress.get_current_mecha())
	ComparisonMecha.set_parts_from_design(PlayerProgress.get_current_mecha())
	update_weight()
	ComparisonMecha.global_rotation = 0
	LoadScreen.connect("load_pressed",Callable(self,"_LoadScreen_on_load_pressed"))
	for child in $TopBar.get_children():
		child.reset_comparison(DisplayMecha)
	shoulder_weapon_check()


func _process(dt):
	if not comparing_part:
		lerp_value(Weight.comparison_bar, "value", Weight.current_bar.value, dt)
		lerp_value(Weight.comparison_bar, "max_value", Weight.comparison_bar.max_value, dt)
		
	else:
		lerp_value(Weight.comparison_bar, "value", ComparisonMecha.get_stat("weight"), dt)
		lerp_value(Weight.comparison_bar, "max_value", ComparisonMecha.get_stat("weight_capacity"), dt)


func _input(event):
	if event.is_action_pressed("toggle_fullscreen"):
		Global.toggle_fullscreen()
	elif event.is_action_pressed("back"):
		if category_visible:
			reset_category()
		else:
			exit()
	shoulder_weapon_check()
	update_weight()


func lerp_value(node, stat, target, dt):
	if node[stat] == target:
		return
	var lerp_v = clamp(LERP_WEIGHT*dt, 0.0, 1.0)
	node[stat] = lerp(node[stat], target, lerp_v)
	if abs(node[stat] - target) <= LERP_EPS:
		node[stat] = target

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


# Puts the part on the mecha and shows it in CurrentItemFrame. Does not touch
# the stash — callers take the part out first (see _on_ItemFrame_pressed).
func equip_part(part, type, side):
	if typeof(side) == TYPE_INT:
		DisplayMecha.callv("set_" + str(type), [part,side])
		ComparisonMecha.callv("set_" + str(type), [part,side])
	else:
		DisplayMecha.callv("set_" + str(type), [part])
		ComparisonMecha.callv("set_" + str(type), [part])
	PlayerProgress.set_current_mecha(DisplayMecha.get_design_data())

	if $CurrentItemFrame.get_button().is_connected("pressed",Callable(self,"unequip_part")):
		$CurrentItemFrame.get_button().disconnect("pressed",Callable(self,"unequip_part"))
	if $CurrentItemFrame.get_button().is_connected("pressed",Callable(self,"unequip_core")):
		$CurrentItemFrame.get_button().disconnect("pressed",Callable(self,"unequip_core"))
	$CurrentItemFrame.visible = true
	$CurrentItemFrame.setup(part, type, false, false)
	if type == "core":
		$CurrentItemFrame.get_button().connect("pressed",Callable(self,"unequip_core"))
	else:
		$CurrentItemFrame.get_button().connect("pressed",Callable(self,"unequip_part").bind(type,side))
	update_quantities(type)
	shoulder_weapon_check()
	update_weight()


# Returns the equipped part to the stash. Returns false (and keeps it
# equipped) when the stash is full.
func unequip_part(type, side) -> bool:
	if not $CurrentItemFrame.visible:
		return true
	if not PlayerProgress.add_part(type, $CurrentItemFrame.current_part, false):
		AudioManager.play_sfx("deny")
		CommandLine.display("/throw-error: Stash Full")
		return false
	if typeof(side) == TYPE_INT:
		DisplayMecha.callv("set_" + str(type), [null,side])
		ComparisonMecha.callv("set_" + str(type), [null,side])
	else:
		DisplayMecha.callv("set_" + str(type), [null])
		ComparisonMecha.callv("set_" + str(type), [null])
	PlayerProgress.set_current_mecha(DisplayMecha.get_design_data())

	update_quantities(type)
	$CurrentItemFrame.visible = false
	$CurrentItemFrame.clear()
	shoulder_weapon_check()
	update_weight()
	return true


func update_quantities(type):
	for child in PartList.get_children():
		child.update_quantity(PlayerProgress.count_part(type, child.current_part))


func unequip_core():
	AudioManager.play_sfx("deny")
	CommandLine.display("/throw-error: Trying to Remove Core")


func shoulder_weapon_check():
	if not DisplayMecha.build.core:
		$PartCategories/Equipment/shoulder_weapon_left.disabled = true
		$PartCategories/Equipment/shoulder_weapon_right.disabled = true
	else:
		$PartCategories/Equipment/shoulder_weapon_left.disabled = not DisplayMecha.build.core.has_left_shoulder
		$PartCategories/Equipment/shoulder_weapon_right.disabled = not DisplayMecha.build.core.has_right_shoulder


func is_build_valid():
	var build_valid = true
	var missing_parts : String
	for part in ["head", "core", "shoulders", "generator",\
				"chipset", "chassis", "thruster", "shoulders"]:
		if not DisplayMecha.build[part]:
			build_valid = false
			missing_parts = missing_parts + "WARN: " + part + " "
	$MissingPartsScroll/MissingParts.visible = not build_valid
	if not build_valid:
		$MissingPartsScroll/MissingParts.text = missing_parts
	return build_valid


func reset_category():
	CommandLine.display("/inventory_parser --clear")
	Statcard.visible = false
	var group_node = PartCategories.get_node(current_group)
	cur_type_selected = false
	current_group = false
	category_visible = false
	$CurrentItemFrame.visible = false
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
	if is_build_valid():
		AudioManager.play_sfx("confirm")
		PlayerProgress.set_current_mecha(DisplayMecha.get_design_data())
		TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")
	else:
		AudioManager.play_sfx("deny")
		print("Build invalid")


func _on_Category_pressed(type, group, side = false):
	ComparisonMecha.set_parts_from_design(PlayerProgress.get_current_mecha())
	if not category_visible:
		current_group = group
		var group_node = PartCategories.get_node(group)
		Statcard.visible = false
		cur_type_selected = type
		
		if typeof(side) == TYPE_INT:
			if side == SIDE.LEFT:
				cur_type_selected = type + "_" + "left"
			elif side == SIDE.RIGHT:
				cur_type_selected = type + "_" + "right"
			else:
				push_error("Not a valid side: " + str(side))
			
		CommandLine.display("/inventory_parser --" + str(type))
		category_visible = true
		PartList.visible = true
		for child in group_node.get_children():
			if child.name != cur_type_selected:
				child.visible = false
				child.button_pressed = false
			else:
				child.text = "Back"
		var parts = PartManager.get_parts(type)
		for child in PartList.get_children(): #Clear PartList
			PartList.remove_child(child)
		var inventory = PlayerProgress.get_owned_parts(type)
		for part_key in inventory.keys(): #Parsing through a dictionary using super.values()
			if parts.has(part_key):
				var part = parts[part_key]
				if part.part_id == "Null":
					continue
				var item = ITEMFRAME.instantiate()
				PartList.add_child(item)
				item.setup(part.part_id, type, false, inventory[part_key])
				item.get_button().connect("pressed",Callable(self,"_on_ItemFrame_pressed").bind(part_key,type,side))
				item.get_button().connect("mouse_entered",Callable(self,"_on_ItemFrame_mouse_entered").bind(part_key,type,side))
				item.get_button().connect("mouse_exited",Callable(self,"_on_ItemFrame_mouse_exited"))
		if DisplayMecha.build[cur_type_selected]:
			equip_part(DisplayMecha.build[cur_type_selected].part_id, type, side)
	else:
		reset_category()


func _on_HardwareButton_pressed():
	CommandLine.display("/inventory_category --hardware")
	show_category_button($PartCategories/Hardware, $CategorySelectedUI/Hardware)


func _on_WetwareButton_pressed():
	CommandLine.display("/inventory_category --wetware")
	show_category_button($PartCategories/Wetware, $CategorySelectedUI/Wetware)


func _on_EquipmentButton_pressed():
	CommandLine.display("/inventory_category --equipment")
	show_category_button($PartCategories/Equipment, $CategorySelectedUI/Equipment)


func _on_ItemFrame_pressed(part_name, type, side):
	# Take the new part out of the stash first so its space is free for the
	# part being swapped out.
	if not PlayerProgress.remove_part(type, part_name, false):
		AudioManager.play_sfx("deny_softer")
		return
	if not unequip_part(type, side):
		PlayerProgress.add_part(type, part_name, false)  # fits: its space was just freed
		return
	equip_part(part_name, type, side)


func _on_ItemFrame_mouse_entered(part_name,type,side):
	AudioManager.play_sfx("keystroke")
	if typeof(side) == TYPE_INT:
		ComparisonMecha.callv("set_" + str(type), [part_name,side])
	else:
		ComparisonMecha.callv("set_" + str(type), [part_name])
	for child in $TopBar.get_children():
		child.set_comparing_part(DisplayMecha,ComparisonMecha)
	var current_part = DisplayMecha.build[cur_type_selected]
	var new_part = ComparisonMecha.build[cur_type_selected]
	if ComparisonMecha.is_overweight():
		$Overweight.visible = true
	else:
		$Overweight.visible = false
	Statcard.display_part_stats(current_part, new_part, cur_type_selected)
	Statcard.visible = true
	comparing_part = true
	AudioManager.play_sfx("boop")


func _on_ItemFrame_mouse_exited():
	for child in $TopBar.get_children():
		child.reset_comparison(DisplayMecha)
	comparing_part = false
	if DisplayMecha.is_overweight():
		$Overweight.visible = true
	else:
		$Overweight.visible = false

func update_weight():
	Weight.current_bar.max_value = DisplayMecha.get_stat("weight_capacity")
	Weight.current_bar.value = DisplayMecha.get_stat("weight")
	Weight.current_label.text = str(DisplayMecha.get_stat("weight")) 
	Weight.max_label.text = str(DisplayMecha.get_stat("weight_capacity"))


func _on_Save_pressed():
	FileManager.save_mecha_design(DisplayMecha, "test")


func _on_Exit_pressed():
	exit()


func _on_Load_pressed():
	$LoadScreen.visible = true


# Loads a saved design through the stash: each part that differs is taken
# from the stash and the part it replaces goes back in. Slots whose part isn't
# owned (or whose old part doesn't fit back in the stash) keep what they have.
func _LoadScreen_on_load_pressed(design):
	if category_visible:
		reset_category()
	var not_owned := []
	var stash_full := false
	for slot in DESIGN_SLOTS:
		var new_id = design.get(slot, false)
		var current = DisplayMecha.build[slot]
		var old_id = current.part_id if current else false
		if new_id == old_id:
			continue
		# The core can't be removed here (see unequip_core).
		if slot == "core" and not new_id:
			continue
		var type: String = slot.replace("_left", "").replace("_right", "")
		if new_id and PlayerProgress.count_part(type, new_id) <= 0:
			not_owned.append(str(new_id))
			continue
		if not _swap_slot_from_stash(slot, type, old_id, new_id):
			stash_full = true
	for mecha in [DisplayMecha, ComparisonMecha]:
		mecha.refresh_dynamic_components()
	PlayerProgress.set_current_mecha(DisplayMecha.get_design_data())  # also saves the stash
	if not not_owned.is_empty():
		AudioManager.play_sfx("deny_softer")
		CommandLine.display("/throw-error: Not in stash: " + ", ".join(not_owned))
	if stash_full:
		AudioManager.play_sfx("deny_softer")
		CommandLine.display("/throw-error: Stash Full")
	shoulder_weapon_check()
	update_weight()


# Takes new_id out of the stash and puts old_id back, then sets the slot.
# Returns false (changing nothing) if old_id doesn't fit in the stash.
func _swap_slot_from_stash(slot, type, old_id, new_id) -> bool:
	# Remove the new part first so its space is free for the old one.
	if new_id:
		PlayerProgress.remove_part(type, new_id, false)
	if old_id and not PlayerProgress.add_part(type, old_id, false):
		if new_id:
			PlayerProgress.add_part(type, new_id, false)  # fits: its space was just freed
		return false
	var value = new_id if new_id else null
	var side = false
	if slot.ends_with("_left"):
		side = DisplayMecha.SIDE.LEFT
	elif slot.ends_with("_right"):
		side = DisplayMecha.SIDE.RIGHT
	for mecha in [DisplayMecha, ComparisonMecha]:
		if typeof(side) == TYPE_INT:
			mecha.callv("set_" + type, [value, side])
		else:
			mecha.callv("set_" + type, [value])
	return true


func _on_category_mouse_entered():
	AudioManager.play_sfx("keystroke")
