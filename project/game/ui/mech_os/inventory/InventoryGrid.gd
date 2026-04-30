extends Control
class_name InventoryGrid

@export var cell_scene: PackedScene
@export var item_scene: PackedScene
@export var cell_size: int = 68

var inventory: Inventory = null

var sep_x: int = 0
var sep_y: int = 0

# Stack to exclude from drawing (the one currently being dragged)
var excluded_stack: item_stack = null

@onready var grid_frame: Panel = $GridFrame
@onready var scroll: ScrollContainer = $GridFrame/Scroll
@onready var grid_content: Control = $GridFrame/Scroll/GridContent
@onready var grid_border: Panel = $GridFrame/Scroll/GridContent/GridBorder
@onready var cell_grid: GridContainer = $GridFrame/Scroll/GridContent/GridBorder/CellGrid
@onready var items_layer: Control = $GridFrame/Scroll/GridContent/GridBorder/ItemsLayer


func _ready() -> void:
	sep_x = cell_grid.get_theme_constant("h_separation")
	sep_y = cell_grid.get_theme_constant("v_separation")


func set_inventory(inv: Inventory) -> void:
	inventory = inv
	refresh()


func get_inventory() -> Inventory:
	return inventory


func refresh() -> void:
	if inventory == null:
		return
	
	sep_x = cell_grid.get_theme_constant("h_separation")
	sep_y = cell_grid.get_theme_constant("v_separation")
	
	_update_grid_content_size()
	_build_cells()
	_draw_items()
	call_deferred("_layout_grid_border")


func is_mouse_over() -> bool:
	var mouse_pos := get_viewport().get_mouse_position()
	return grid_frame.get_global_rect().has_point(mouse_pos)


func get_cell_at_mouse() -> Dictionary:
	# Returns {"x": int, "y": int} or {} if not over the grid
	if inventory == null or not is_mouse_over():
		return {}
	
	var local: Vector2 = items_layer.get_local_mouse_position()
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)
	
	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))
	
	if cell_x < 0 or cell_y < 0 or cell_x >= inventory.grid_width or cell_y >= inventory.grid_height:
		return {}
	
	return {"x": cell_x, "y": cell_y}


func get_stack_at_mouse() -> Dictionary:
	# Returns {"stack": item_stack, "origin_x": int, "origin_y": int} or {}
	var cell := get_cell_at_mouse()
	if cell.is_empty():
		return {}
	
	var cell_dict = inventory.grid[cell.y][cell.x]
	var stack: item_stack = cell_dict["stack"]
	if stack == null:
		return {}
	
	# Resolve to origin cell
	var origin_x: int = cell_dict["origin_x"]
	var origin_y: int = cell_dict["origin_y"]
	if origin_x < 0:
		origin_x = cell.x
	if origin_y < 0:
		origin_y = cell.y
	
	var origin_cell = inventory.grid[origin_y][origin_x]
	stack = origin_cell["stack"]
	if stack == null:
		return {}
	
	return {"stack": stack, "origin_x": origin_x, "origin_y": origin_y}


func get_drop_position(stack: item_stack, mouse_pos: Vector2) -> Dictionary:
	# Given a stack being dragged and the global mouse position,
	# returns {"x": int, "y": int, "valid": bool} for where it would land.
	if inventory == null:
		return {}
	
	if not grid_frame.get_global_rect().has_point(mouse_pos):
		return {}
	
	var local: Vector2 = items_layer.get_local_mouse_position()
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)
	
	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))
	
	var w := stack.width_cells()
	var h := stack.height_cells()
	
	var center_offset_x := int(floor(w / 2.0))
	var center_offset_y := int(floor(h / 2.0))
	
	var origin_x: int = clampi(cell_x - center_offset_x, 0, inventory.grid_width - w)
	var origin_y: int = clampi(cell_y - center_offset_y, 0, inventory.grid_height - h)
	
	var valid := inventory.item_fits_at(stack, origin_x, origin_y)
	
	return {"x": origin_x, "y": origin_y, "valid": valid}


func get_global_cell_position(cell_x: int, cell_y: int) -> Vector2:
	# Returns the global position of a specific cell — used by DragManager
	# for snapping the drag ghost.
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)
	var local_pos := Vector2(cell_x * col_width, cell_y * row_height)
	return items_layer.get_global_rect().position + local_pos


func get_item_count() -> int:
	if inventory == null:
		return 0
	var count := 0
	for y in range(inventory.grid_height):
		for x in range(inventory.grid_width):
			var cell = inventory.grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				count += 1
	return count


func get_total_weight() -> float:
	if inventory == null:
		return 0.0
	return inventory.get_current_weight()


func _update_grid_content_size() -> void:
	if cell_size <= 0 or inventory == null:
		return
	grid_content.custom_minimum_size = Vector2(
		inventory.grid_width * cell_size,
		inventory.grid_height * cell_size
	)


func _build_cells() -> void:
	if inventory == null:
		return
	
	for c in cell_grid.get_children():
		c.queue_free()
	
	cell_grid.columns = inventory.grid_width
	
	for y in range(inventory.grid_height):
		for x in range(inventory.grid_width):
			var cell = cell_scene.instantiate()
			cell.x = x
			cell.y = y
			cell.custom_minimum_size = Vector2(cell_size, cell_size)
			cell_grid.add_child(cell)


func _draw_items() -> void:
	for c in items_layer.get_children():
		c.queue_free()
	
	if inventory == null:
		return
	
	var slot_w := cell_size
	var slot_h := cell_size
	
	for y in range(inventory.grid_height):
		for x in range(inventory.grid_width):
			var cell_dict = inventory.grid[y][x]
			var stack: item_stack = cell_dict["stack"]
			
			if stack == null:
				continue
			
			# Skip the stack currently being dragged
			if excluded_stack != null and stack == excluded_stack:
				continue
			
			# Only draw at origin cell
			if cell_dict["origin_x"] != x or cell_dict["origin_y"] != y:
				continue
			
			var ui: ItemUI = item_scene.instantiate()
			ui.cell_size = cell_size
			
			var w := stack.width_cells()
			var h := stack.height_cells()
			
			var pos_x := x * (slot_w + sep_x)
			var pos_y := y * (slot_h + sep_y)
			var size_x := w * slot_w + (w - 1) * sep_x
			var size_y := h * slot_h + (h - 1) * sep_y
			
			items_layer.add_child(ui)
			ui.position = Vector2(pos_x, pos_y)
			ui.custom_minimum_size = Vector2(size_x, size_y)
			ui.size = Vector2(size_x, size_y)
			ui.set_stack(stack)


func _layout_grid_border() -> void:
	if inventory == null:
		return
	
	var cols := inventory.grid_width
	var rows := inventory.grid_height
	if cols <= 0 or rows <= 0:
		return
	
	var h_sep := 1
	var v_sep := 1
	
	var grid_w = cols * cell_size + (cols - 1) * h_sep
	var grid_h = rows * cell_size + (rows - 1) * v_sep
	var grid_size := Vector2(grid_w, grid_h)
	
	var area_size := grid_content.get_rect().size
	if area_size.x <= 0 or area_size.y <= 0:
		# Fallback: just use grid size directly
		area_size = grid_size
		
	var origin := (area_size - grid_size) * 0.5
	origin.x = max(origin.x, 0)
	origin.y = max(origin.y, 0)
	
	
	grid_border.custom_minimum_size = grid_size
	grid_border.size = grid_size
	grid_border.position = origin
