extends Control

@onready var item_base = preload("res://game/ui/inventory/ItemBase.tscn")
@onready var inventory_slot = preload("res://game/ui/inventory/InventorySlot.tscn")
@onready var grid_container = $MarginContainer/HBoxContainer/Storage/MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var scroll_container = $MarginContainer/HBoxContainer/Storage/MarginContainer/VBoxContainer/ScrollContainer
@onready var y_count = grid_container.columns
@onready var DisplayMecha = $Mecha
@onready var ComparisonMecha = $ComparisonMecha
@onready var MechaSlots = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer/MechaSlotsContainer
@onready var BasicStats = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/BasicStats/MarginContainer/VBoxContainer2/MarginContainer/GridContainer
@onready var Tabs = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer

var num_slots = 480
var grid_array := []
var item_held = null
var hovered_slot = null
var hovered_mecha_slot = null
var can_place := false
var item_anchor : Vector2

# Called when the node enters the scene tree for the first time.
func _ready():
	if Profile.stats.current_mecha:
		DisplayMecha.set_parts_from_design(Profile.stats.current_mecha)
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
		for slot in MechaSlots.get_children():
			#slot.mecha_slot_pressed.connect(_on_mecha_slot_pressed)
			slot.mecha_slot_mouse_entered.connect(_on_mecha_slot_mouse_entered)
			slot.mecha_slot_mouse_exited.connect(_on_mecha_slot_mouse_exited)
			if DisplayMecha.build[slot.type]:
				slot.change_part(DisplayMecha.build[slot.type].part_id)
			else:
				slot.change_part(null)
	else:
		push_error("Couldn't find a current mecha")
	for i in range(num_slots):
		create_slot()
	
	ComparisonMecha.global_rotation = 0
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if item_held:
		if Input.is_action_just_released("left_click"):
			if scroll_container.get_global_rect().has_point(get_global_mouse_position()):
				if hovered_slot:
					place_item(hovered_slot)
			
			if hovered_mecha_slot:
				place_item(hovered_mecha_slot)
	else:
		if Input.is_action_just_pressed("left_click"):
			if scroll_container.get_global_rect().has_point(get_global_mouse_position()) or hovered_mecha_slot:
				pick_up_item()
			

func create_slot():
	var new_slot = inventory_slot.instantiate()
	new_slot.slot_id = grid_array.size()
	grid_container.add_child(new_slot)
	grid_array.append(new_slot)
	new_slot.inventory_slot_entered.connect(_on_slot_mouse_entered)
	new_slot.inventory_slot_exited.connect(_on_slot_mouse_exited)

func _on_slot_mouse_entered(slot):
	item_anchor = Vector2(100,100)
	hovered_slot = slot
	if hovered_slot.item_stored and hovered_slot.item_stored.part_type and not hovered_slot.item_stored.part_type.contains("weapon"):
		ComparisonMecha.callv("set_" + str(hovered_slot.item_stored.part_type), [hovered_slot.item_stored.item_id])
		for child in BasicStats.get_children():
			child.set_comparing_part(DisplayMecha,ComparisonMecha)
	if item_held:
		check_space(hovered_slot)
		set_grids.call_deferred(hovered_slot)
	
func _on_slot_mouse_exited(slot):
	if slot.item_stored and slot.item_stored.part_type and not slot.item_stored.part_type.contains("weapon"):
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
		for child in BasicStats.get_children():
			child.reset_comparison(DisplayMecha)
	if not item_held and not scroll_container.get_global_rect().has_point(get_global_mouse_position()):
		hovered_slot = null
	clear_grid()	

func check_space(slot):
	for row in item_held.item_size[1]:
		for space in item_held.item_size[0]:
			var slot_id_to_check = slot.slot_id + space + (row * y_count)
			var wrap_check = slot.slot_id % y_count + space
			if wrap_check < 0 or wrap_check >= y_count:
				can_place = false
				return
			if slot_id_to_check < 0 or slot_id_to_check >= grid_array.size():
				can_place = false
				return
			if grid_array[slot_id_to_check].state == grid_array[slot_id_to_check].States.FILLED:
				can_place = false
				return
	can_place = true

func set_grids(slot):
	for row in item_held.item_size[1]:
		for space in item_held.item_size[0]:
			var slot_id_to_check = slot.slot_id + space + (row * y_count)
			var wrap_check = slot.slot_id % y_count + space
			if slot_id_to_check < 0 or slot_id_to_check >= grid_array.size():
				continue
			if wrap_check < 0 or wrap_check >= y_count:
				continue
			if can_place:
				grid_array[slot_id_to_check].set_color(grid_array[slot_id_to_check].States.EMPTY)
			else:
				grid_array[slot_id_to_check].set_color(grid_array[slot_id_to_check].States.FILLED)

func clear_grid():
	for slot in grid_array:
		if not slot.item_stored:
			slot.set_color(slot.States.DEFAULT)
		else:
			slot.set_color(slot.States.EMPTY)


func place_item(_slot):
	var adjusted_position = _slot.global_position
	adjusted_position.x += 25
	adjusted_position.y += 25
	item_held.snap_to(adjusted_position)
	item_held.get_parent().remove_child(item_held)
	if hovered_mecha_slot:
		var _type = _slot.type
		if _slot.type.contains("arm_weapon"):
			_type = "arm_weapon"
		elif _slot.type.contains("shoulder_weapon"):
			_type = "arm_weapon"
		if PartManager.get_part(_type, item_held.item_id):
			equip_part(_slot.type, item_held.item_id)
			print("Equipped " + item_held.item_id + " in slot " + _slot.type)
		else:
			print("No part: " + item_held.item_id)
		hovered_mecha_slot.change_part(DisplayMecha.build[hovered_mecha_slot.type].part_id)
		item_held.queue_free()
		hovered_slot = null
	elif hovered_slot:
		grid_container.add_child(item_held)
		item_held.global_position = get_global_mouse_position()
		item_held.grid_anchor = hovered_slot.slot_id
		for row in item_held.item_size[1]:
			for space in item_held.item_size[0]:
				var slot_id_to_check = hovered_slot.slot_id + space + (row * y_count)
				grid_array[slot_id_to_check].state = grid_array[slot_id_to_check].States.FILLED
				grid_array[slot_id_to_check].item_stored = item_held
		ItemManager.player_inventory_add_item(item_held.item_name, hovered_slot.slot_id, item_held.quantity, item_held.part_type)
	item_held = null
	clear_grid()
	
func pick_up_item():
	if hovered_slot and hovered_slot.item_stored:
		item_held = hovered_slot.item_stored
		item_held.selected = true
		item_held.get_parent().remove_child(item_held)
		add_child(item_held)
		item_held.global_position = get_global_mouse_position()
		ItemManager.player_inventory_remove_item(item_held.grid_anchor)
		for row in item_held.item_size[1]:
			for space in item_held.item_size[0]:
				var slot_id_to_check = item_held.grid_anchor + space + (row * y_count)
				grid_array[slot_id_to_check].state = grid_array[slot_id_to_check].States.EMPTY
				grid_array[slot_id_to_check].item_stored = null
			
		check_space(hovered_slot)
		set_grids.call_deferred(hovered_slot)
	elif hovered_mecha_slot:
		if not DisplayMecha.build[hovered_mecha_slot.type] and not item_held:
			return
		if DisplayMecha.build[hovered_mecha_slot.type].part_id == "Null" and not item_held:
			return
		var unequipped_item = item_base.instantiate()
		unequipped_item.setup_item(DisplayMecha.build[hovered_mecha_slot.type].part_id, hovered_mecha_slot.type)
		add_child(unequipped_item)

		if not item_held:
			hovered_mecha_slot.change_part(null)
			unequip_part(hovered_mecha_slot.type)
		item_held = unequipped_item	
		item_held.selected = true
		item_held.global_position = get_global_mouse_position()

func unequip_part(_type):
	if _type.contains("right"):
		DisplayMecha.callv("set_" + str(_type), [null,1])
		ComparisonMecha.callv("set_" + str(_type), [null,1])
	elif _type.contains("left"):
		DisplayMecha.callv("set_" + str(_type), [null,0])
		ComparisonMecha.callv("set_" + str(_type), [null,0])
	else:
		DisplayMecha.callv("set_" + str(_type), [null])
		ComparisonMecha.callv("set_" + str(_type), [null])
	Profile.set_stat("current_mecha", DisplayMecha.get_design_data())
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)
	shoulder_weapon_check()
	update_weight()

func equip_part(_type,_part):
	if not item_held:
		return
	if _type.contains("right"):
		DisplayMecha.callv("set_" + str(_type), [_part,1])
		ComparisonMecha.callv("set_" + str(_type), [_part,1])
	elif _type.contains("left"):
		DisplayMecha.callv("set_" + str(_type), [_part,0])
		ComparisonMecha.callv("set_" + str(_type), [_part,0])
	else:
		DisplayMecha.callv("set_" + str(_type), [_part])
		ComparisonMecha.callv("set_" + str(_type), [_part])
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)

func shoulder_weapon_check():
	if not DisplayMecha.build.core:
		pass
	

func update_weight():
	pass

func _on_mecha_slot_mouse_entered(_slot):
	hovered_mecha_slot = _slot
	print(_slot)
	
func _on_mecha_slot_mouse_exited(_slot):
	hovered_mecha_slot = null


func _on_tab_pressed(subtype):
	for child in MechaSlots.get_children():
		if child.subtype == subtype:
			child.visible = true
		else:
			child.visible = false
	for child in Tabs.get_children():
		if child.name != subtype:
			child.button_pressed = false
	$MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer/TabLabel.text = subtype
