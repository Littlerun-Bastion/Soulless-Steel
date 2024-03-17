extends GridContainer

var grid_array := []
var item_anchor : Vector2
var x_count = 1
var y_count = 1

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func setup(inv_size):
	x_count = inv_size[0]
	y_count = inv_size[1]
	columns = y_count
	for i in (x_count * y_count):
		create_slot()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if ItemManager.item_held:
		if Input.is_action_just_released("left_click") and get_global_rect().has_point(get_global_mouse_position()):
			if ItemManager.can_place:
				place_item(ItemManager.hovered_slot)
			#else:
				#ItemManager.bounce_back()
	else:
		if Input.is_action_just_pressed("left_click") and get_global_rect().has_point(get_global_mouse_position()):
			pick_up_item()

func create_slot():
	var new_slot = ItemManager.inventory_slot.instantiate()
	new_slot.slot_id = grid_array.size()
	add_child(new_slot)
	grid_array.append(new_slot)
	new_slot.inventory_slot_entered.connect(_on_slot_mouse_entered)
	new_slot.inventory_slot_exited.connect(_on_slot_mouse_exited)
	
func _on_slot_mouse_entered(slot):
	slot.set_color(slot.States.FILLED)
	item_anchor = Vector2(100,100)
	if ItemManager.item_held:
		check_space(slot)
		set_grids.call_deferred(slot)
	ItemManager.hovered_slot = slot
	
	
func _on_slot_mouse_exited(slot):
	slot.set_color(slot.States.EMPTY)
	if not ItemManager.item_held and not get_global_rect().has_point(get_global_mouse_position()):
		ItemManager.hovered_slot = null
	clear_grid()	


func check_space(slot):
	for row in ItemManager.item_held.item_size[1]:
		for space in ItemManager.item_held.item_size[0]:
			var slot_id_to_check = slot.slot_id + space + (row * y_count)
			var wrap_check = slot.slot_id % y_count + space
			if wrap_check < 0 or wrap_check >= y_count:
				ItemManager.can_place = false
				return
			if slot_id_to_check < 0 or slot_id_to_check >= grid_array.size():
				ItemManager.can_place = false
				return
			if grid_array[slot_id_to_check].state == grid_array[slot_id_to_check].States.FILLED:
				ItemManager.can_place= false
				return
	ItemManager.can_place = true

func set_grids(slot):
	for row in ItemManager.item_held.item_size[1]:
		for space in ItemManager.item_held.item_size[0]:
			var slot_id_to_check = slot.slot_id + space + (row * y_count)
			var wrap_check = slot.slot_id % y_count + space
			if slot_id_to_check < 0 or slot_id_to_check >= grid_array.size():
				continue
			if wrap_check < 0 or wrap_check >= y_count:
				continue
			if ItemManager.can_place:
				grid_array[slot_id_to_check].set_color(grid_array[slot_id_to_check].States.EMPTY)
			else:
				grid_array[slot_id_to_check].set_color(grid_array[slot_id_to_check].States.FILLED)

func clear_grid():
	for slot in grid_array:
		if not slot.item_stored:
			slot.set_color(slot.States.DEFAULT)
		else:
			slot.set_color(slot.States.EMPTY)

func pick_up_item():
	if ItemManager.hovered_slot and ItemManager.hovered_slot.item_stored:
		ItemManager.item_held = ItemManager.hovered_slot.item_stored
		ItemManager.item_held.selected = true
		ItemManager.item_held.get_parent().remove_child(ItemManager.item_held)
		get_tree().get_current_scene().add_child(ItemManager.item_held)
		ItemManager.item_held.global_position = get_global_mouse_position()
		ItemManager.player_inventory_remove_item(ItemManager.item_held.grid_anchor)
		for row in ItemManager.item_held.item_size[1]:
			for space in ItemManager.item_held.item_size[0]:
				var slot_id_to_check = ItemManager.item_held.grid_anchor + space + (row * y_count)
				grid_array[slot_id_to_check].state = grid_array[slot_id_to_check].States.EMPTY
				grid_array[slot_id_to_check].item_stored = null
			
		check_space(ItemManager.hovered_slot)
		set_grids.call_deferred(ItemManager.hovered_slot)
		ItemManager.original_slot = ItemManager.hovered_slot

func place_item(_slot):
	var adjusted_position = _slot.global_position
	adjusted_position.x += 25
	adjusted_position.y += 25
	if _slot.slot_type == "inventory_slot":
		ItemManager.item_held.snap_to(adjusted_position)
		ItemManager.item_held.get_parent().remove_child(ItemManager.item_held)
		add_child(ItemManager.item_held)
		ItemManager.item_held.global_position = get_global_mouse_position()
		ItemManager.item_held.grid_anchor = _slot.slot_id
		for row in ItemManager.item_held.item_size[1]:
			for space in ItemManager.item_held.item_size[0]:
				var slot_id_to_check = _slot.slot_id + space + (row * y_count)
				grid_array[slot_id_to_check].state = grid_array[slot_id_to_check].States.FILLED
				grid_array[slot_id_to_check].item_stored = ItemManager.item_held
		ItemManager.player_inventory_add_item(ItemManager.item_held.item_name, _slot.slot_id, ItemManager.item_held.quantity, ItemManager.item_held.part_type)
		ItemManager.original_slot = null
	ItemManager.item_held = null
	clear_grid()
