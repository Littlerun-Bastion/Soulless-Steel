extends Control

@onready var item_base = preload("res://game/ui/inventory/ItemBase.tscn")
@onready var inventory_slot = preload("res://game/ui/inventory/InventorySlot.tscn")
@onready var scroll_container = $Storage/MarginContainer/VBoxContainer/ScrollContainer
@onready var grid_container = $Storage/MarginContainer/VBoxContainer/ScrollContainer/GridContainer

var x_size = 50
var y_size = 50
var x_count = 1
var y_count = 1
var num_slots = 1
var grid_array := []
var item_held = null
var hovered_slot = null
var hovered_mecha_slot = null
var can_place := false
var item_anchor : Vector2
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func setup(inventory_data):
	if inventory_data:
		x_size = inventory_data.inventory_size[0] * 50
		y_size = inventory_data.inventory_size[1] * 50
		x_count = inventory_data.inventory_size[0]
		y_count = inventory_data.inventory_size[1]
		if x_size > 350:
			x_size = 350
		if y_size > 750:
			y_size = 750
		scroll_container.custom_minimum_size.x = x_size
		scroll_container.custom_minimum_size.y = y_size
		num_slots = inventory_data.inventory_size[0] * inventory_data.inventory_size[1]
	for i in range(num_slots):
		create_slot()

func create_slot():
	var new_slot = inventory_slot.instantiate()
	new_slot.slot_id = grid_array.size()
	grid_container.add_child(new_slot)
	grid_array.append(new_slot)
	new_slot.inventory_slot_entered.connect(_on_slot_mouse_entered)
	new_slot.inventory_slot_exited.connect(_on_slot_mouse_exited)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if item_held:
		if Input.is_action_just_released("left_click"):
			if scroll_container.get_global_rect().has_point(get_global_mouse_position()):
				if hovered_slot:
					place_item(hovered_slot)
	else:
		if Input.is_action_just_pressed("left_click"):
			if scroll_container.get_global_rect().has_point(get_global_mouse_position()):
				pick_up_item()


func _on_slot_mouse_entered(slot):
	item_anchor = Vector2(100,100)
	hovered_slot = slot
	if item_held:
		check_space(hovered_slot)
		set_grids.call_deferred(hovered_slot)
	
func _on_slot_mouse_exited(slot):
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

func clear_grid():
	for slot in grid_array:
		if not slot.item_stored:
			slot.set_color(slot.States.DEFAULT)
		else:
			slot.set_color(slot.States.EMPTY)

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
				
func place_item(_slot):
	var adjusted_position = _slot.global_position
	adjusted_position.x += 25
	adjusted_position.y += 25
	item_held.snap_to(adjusted_position)
	item_held.get_parent().remove_child(item_held)
	if hovered_slot:
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
