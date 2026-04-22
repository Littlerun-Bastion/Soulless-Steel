extends Node
class_name DragManager

var drag_layer: Control = null
var tooltip: ItemTooltip = null

# Each entry: {"grid": InventoryGrid, "window": MechWindow}
var grid_participants: Array = []

# Equipment window reference (set later in Step 4)
var equipment_window = null

var dragging_stack: item_stack = null
var dragging_ui: ItemUI = null
var drag_preview: Panel = null
var drag_source_grid: InventoryGrid = null
var drag_source_slot = null  # for equipment drags (Step 4)
var drag_origin_x: int = -1
var drag_origin_y: int = -1

var cell_size: int = 68
var sep_x: int = 1
var sep_y: int = 1
var item_scene: PackedScene = preload("res://game/mecha/ItemUI.tscn")


func setup(layer: Control) -> void:
	drag_layer = layer


func register_grid(grid: InventoryGrid, window: MechWindow) -> void:
	# Avoid duplicates
	for entry in grid_participants:
		if entry["grid"] == grid:
			return
	grid_participants.append({"grid": grid, "window": window})


func unregister_grid(grid: InventoryGrid) -> void:
	for i in range(grid_participants.size() - 1, -1, -1):
		if grid_participants[i]["grid"] == grid:
			grid_participants.remove_at(i)


func unregister_window(window: MechWindow) -> void:
	for i in range(grid_participants.size() - 1, -1, -1):
		if grid_participants[i]["window"] == window:
			grid_participants.remove_at(i)


# Input — called from MechOS._input
func handle_input(event: InputEvent) -> bool:
	# Returns true if the event was consumed
	
	if event is InputEventKey and event.is_action_pressed("inventory_rotate"):
		if dragging_stack != null:
			_rotate_dragged_item()
			return true
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if dragging_stack == null:
				return _try_start_drag()
		else:
			if dragging_stack != null:
				_finish_drag()
				return true
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and dragging_stack != null:
			_cancel_drag()
			return true
	
	if event is InputEventMouseMotion and dragging_stack != null:
		_update_drag_visual()
		return true
	
	return false


func is_dragging() -> bool:
	return dragging_stack != null


# Start drag
func _try_start_drag() -> bool:
	# Check each registered grid to see if the mouse is over a stack
	for entry in grid_participants:
		var grid: InventoryGrid = entry["grid"]
		var window: MechWindow = entry["window"]
		
		# Only allow drags from visible windows
		if not window.visible:
			continue
		
		var info := grid.get_stack_at_mouse()
		if info.is_empty():
			continue
		
		var stack: item_stack = info["stack"]
		var origin_x: int = info["origin_x"]
		var origin_y: int = info["origin_y"]
		
		# Store drag source
		drag_source_grid = grid
		drag_source_slot = null
		drag_origin_x = origin_x
		drag_origin_y = origin_y
		dragging_stack = stack
		
		# Remove from source grid
		grid.inventory.remove_item_stack(stack)
		grid.excluded_stack = stack
		grid.refresh()
		
		# Create drag ghost
		_create_drag_visuals(stack)
		_update_drag_visual()
		
		return true
	
	return false


# Drag visuals
func _create_drag_visuals(stack: item_stack) -> void:
	if drag_layer == null:
		return
	
	var w := stack.width_cells()
	var h := stack.height_cells()
	var size_x: float = w * cell_size + (w - 1) * sep_x
	var size_y: float = h * cell_size + (h - 1) * sep_y
	
	# Ghost item
	dragging_ui = item_scene.instantiate() as ItemUI
	dragging_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dragging_ui.cell_size = cell_size
	dragging_ui.custom_minimum_size = Vector2(size_x, size_y)
	dragging_ui.size = Vector2(size_x, size_y)
	drag_layer.add_child(dragging_ui)
	dragging_ui.set_stack(stack)
	dragging_ui.z_index = 1
	dragging_ui.move_to_front()
	
	# Footprint preview
	drag_preview = Panel.new()
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.0)
	style.border_color = Color(1, 1, 1, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	drag_preview.add_theme_stylebox_override("panel", style)
	drag_layer.add_child(drag_preview)
	drag_preview.z_index = dragging_ui.z_index + 1


func _update_drag_visual() -> void:
	if dragging_stack == null or dragging_ui == null or drag_layer == null:
		return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var drag_rect := drag_layer.get_global_rect()
	var mouse_local := mouse_pos - drag_rect.position
	
	# Check if we're over any registered grid
	var target_grid: InventoryGrid = null
	var drop_info: Dictionary = {}
	
	for entry in grid_participants:
		var grid: InventoryGrid = entry["grid"]
		var window: MechWindow = entry["window"]
		if not window.visible:
			continue
		
		var info := grid.get_drop_position(dragging_stack, mouse_pos)
		if not info.is_empty():
			target_grid = grid
			drop_info = info
			break
	
	if target_grid != null and not drop_info.is_empty():
		# Snap ghost to grid cell
		var snap_pos: Vector2 = target_grid.get_global_cell_position(drop_info.x, drop_info.y)
		dragging_ui.position = snap_pos - drag_rect.position
		
		# Preview follows cursor
		if drag_preview != null:
			drag_preview.visible = true
			drag_preview.size = dragging_ui.size
			drag_preview.position = mouse_local - drag_preview.size * 0.5
		
		# Tint based on validity
		if drop_info.valid:
			dragging_ui.modulate = Color(1, 1, 1, 0.8)
		else:
			dragging_ui.modulate = Color(1, 0.3, 0.3, 0.8)
	else:
		# Not over any grid — follow cursor freely
		dragging_ui.position = mouse_local - dragging_ui.size * 0.5
		dragging_ui.modulate = Color(1, 1, 1, 0.6)
		
		if drag_preview != null:
			drag_preview.visible = true
			drag_preview.size = dragging_ui.size
			drag_preview.position = mouse_local - drag_preview.size * 0.5


# Finish drag
func _finish_drag() -> void:
	if dragging_stack == null:
		return
	
	var mouse_pos := get_viewport().get_mouse_position()
	
	# Check each grid for a valid drop
	for entry in grid_participants:
		var grid: InventoryGrid = entry["grid"]
		var window: MechWindow = entry["window"]
		if not window.visible:
			continue
		
		var info := grid.get_drop_position(dragging_stack, mouse_pos)
		if info.is_empty():
			continue
		
		if info.valid:
			# Place the item
			grid.inventory.place_item(dragging_stack, info.x, info.y)
			_clear_drag()
			_refresh_all_grids()
			return
	
	# TODO: Check equipment window (Step 4)
	
	# No valid drop — revert
	_revert_drag()


func _cancel_drag() -> void:
	if dragging_stack == null:
		return
	_revert_drag()


func _revert_drag() -> void:
	if dragging_stack == null:
		return
	
	# Return to source
	if drag_source_grid != null and drag_origin_x >= 0 and drag_origin_y >= 0:
		drag_source_grid.inventory.place_item(dragging_stack, drag_origin_x, drag_origin_y)
	elif drag_source_slot != null:
		# Equipment revert — will be handled in Step 4
		pass
	
	_clear_drag()
	_refresh_all_grids()


func _clear_drag() -> void:
	# Clean up visuals
	if dragging_ui != null:
		dragging_ui.queue_free()
		dragging_ui = null
	if drag_preview != null:
		drag_preview.queue_free()
		drag_preview = null
	
	# Clear excluded stack on source grid
	if drag_source_grid != null:
		drag_source_grid.excluded_stack = null
	
	# Reset state
	dragging_stack = null
	drag_source_grid = null
	drag_source_slot = null
	drag_origin_x = -1
	drag_origin_y = -1


func _refresh_all_grids() -> void:
	for entry in grid_participants:
		entry["grid"].refresh()


# Rotate
func _rotate_dragged_item() -> void:
	if dragging_stack == null:
		return
	dragging_stack.rotated = not dragging_stack.rotated
	
	# Rebuild ghost with new dimensions
	if dragging_ui != null:
		var w := dragging_stack.width_cells()
		var h := dragging_stack.height_cells()
		var size_x: float = w * cell_size + (w - 1) * sep_x
		var size_y: float = h * cell_size + (h - 1) * sep_y
		dragging_ui.custom_minimum_size = Vector2(size_x, size_y)
		dragging_ui.size = Vector2(size_x, size_y)
		dragging_ui.set_stack(dragging_stack)
	
	_update_drag_visual()
