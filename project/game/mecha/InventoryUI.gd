extends Control
class_name InventoryUI

@export var inventory: inventory
@export var cell_scene: PackedScene
#@export var max_grid_width: int = 10
#@export var max_grid_height: int = 20

var is_panning: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

var cell_size: int = 68
var cells_built: bool = false
var sep_x: int = 0
var sep_y: int = 0


@onready var inventory_panel: Panel = $MainFrame/Columns/InventoryColumn/InventoryPanel
@onready var grid_frame: Panel = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame
@onready var scroll: ScrollContainer = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll
@onready var grid_content: Control = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent
@onready var cell_grid: GridContainer = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder/CellGrid
@onready var items_layer: Control = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder/ItemsLayer
@onready var grid_border: Panel = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder
@export var item_scene: PackedScene



var is_dragging_scroll: bool = false
var last_drag_mouse_pos: Vector2 = Vector2.ZERO
var dragging_stack: item_stack = null
var dragging_ui: ItemUI = null
var drag_origin_x: int = -1
var drag_origin_y: int = -1
var grab_offset_x: int = 0
var grab_offset_y: int = 0



func _ready():
	sep_x = cell_grid.get_theme_constant("h_separation")
	sep_y = cell_grid.get_theme_constant("v_separation")
	set_anchors_preset(Control.PRESET_FULL_RECT)


func refresh():
	if inventory == null:
		return
	
	if inventory.grid_width <= 0 or inventory.grid_height <= 0:
		return
		
	_update_grid_content_size()

	if not cells_built:
		_build_cells()

	_draw_items()
	_layout_grid_border()

func _layout_grid_border():
	if inventory == null:
		return

	var cols := inventory.grid_width
	var rows := inventory.grid_height
	if cols <= 0 or rows <= 0:
		return

	var h_sep = 1
	var v_sep = 1

	# Total grid size in pixels (including 1px gaps)
	var grid_w = cols * cell_size + (cols - 1) * h_sep
	var grid_h = rows * cell_size + (rows - 1) * v_sep
	var grid_size := Vector2(grid_w, grid_h)

	# Size of the area you're centering inside
	var area_size := grid_content.get_rect().size

	# Center the border panel within the area
	var origin := (area_size - grid_size) * 0.5

	grid_border.custom_minimum_size = grid_size
	grid_border.size = grid_size
	grid_border.position = origin


func _update_grid_content_size():
	if cell_size <= 0 or inventory == null:
		return

	var content_w = inventory.grid_width * cell_size
	var content_h = inventory.grid_height * cell_size

	# This is the size ScrollContainer will try to show; anything larger than
	# scroll's rect will be scrollable.
	grid_content.custom_minimum_size = Vector2(content_w, content_h)


func _build_cells():
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

	cells_built = true

func _draw_items():
	for c in items_layer.get_children():
		c.queue_free()

	var slot_w := cell_size
	var slot_h := cell_size

	for y in range(inventory.grid_height):
		for x in range(inventory.grid_width):
			var cell_dict = inventory.grid[y][x]
			var stack: item_stack = cell_dict["stack"]

			if stack == null:
				continue

			if dragging_stack != null and stack == dragging_stack:
				continue

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

			ui.position = Vector2(pos_x, pos_y)
			ui.custom_minimum_size = Vector2(size_x, size_y)
			ui.size = ui.custom_minimum_size

			items_layer.add_child(ui)

			# Now that size is final and it's in the tree, configure visuals
			ui.set_stack(stack)





func _notification(what):
	if what == NOTIFICATION_RESIZED:
		cells_built = false
		if inventory != null:
			_update_grid_content_size()
			_build_cells()
			_draw_items()
			
func _input(event: InputEvent) -> void:
	if not visible:
		return
		
	if event is InputEventKey and event.is_action_pressed("inventory_rotate"):
		if dragging_stack != null:
			_rotate_dragged_item()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		# --- Right mouse: panning (already working) ---
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_panning = true
				last_mouse_pos = event.position
			else:
				is_panning = false
			get_viewport().set_input_as_handled()
			return
	
			
		# --- Scroll wheel ---
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			scroll.scroll_vertical -= cell_size
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			scroll.scroll_vertical += cell_size
			get_viewport().set_input_as_handled()
			return

		# --- Left mouse: start / finish drag ---
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_drag()
			get_viewport().set_input_as_handled()
			return


		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if dragging_stack != null:
				_finish_drag()
				get_viewport().set_input_as_handled()
				return

	elif event is InputEventMouseMotion:
		# Panning
		if is_panning:
			var delta: Vector2 = event.relative
			scroll.scroll_vertical -= int(delta.y)
			scroll.scroll_horizontal -= int(delta.x)
			get_viewport().set_input_as_handled()
			return
		elif dragging_stack != null and dragging_ui != null:
			dragging_ui.position += event.relative
			get_viewport().set_input_as_handled()
			return
			
		



	
		
func handle_item_drop(ui: ItemUI) -> void:
	if inventory == null:
		return

	var cols := inventory.grid_width
	var rows := inventory.grid_height

	# Original origin in the grid
	var old_x = ui.grid_x
	var old_y = ui.grid_y
	var stack := ui.stack

	# Position of the item relative to ItemsLayer
	# (ui.position is already local to ItemsLayer)
	var item_pos: Vector2 = ui.position
	var item_size_px: Vector2 = ui.size

	# We'll use the item's center to decide the target cell
	var center: Vector2 = item_pos + item_size_px * 0.5

	var new_x := int(floor(center.x / float(cell_size)))
	var new_y := int(floor(center.y / float(cell_size)))

	# Check bounds
	if new_x < 0 or new_y < 0 or new_x >= cols or new_y >= rows:
		# Outside grid -> revert
		revert_item_position(stack, old_x, old_y)
		return

	# Temporarily remove the stack from the inventory grid
	inventory.remove_item_stack(stack)

	# Try to place it at the new location
	if inventory.place_item(stack, new_x, new_y):
		# Success: redraw with updated positions
		refresh()
	else:
		# Failed to fit: put it back where it was
		inventory.place_item(stack, old_x, old_y)
		refresh()

func revert_item_position(stack: item_stack, old_x: int, old_y: int) -> void:
	# Just reinsert at the original origin
	inventory.place_item(stack, old_x, old_y)
	refresh()
	
func _start_drag() -> void:
	if inventory == null:
		return

	# Mouse position in ItemsLayer's local space
	var local: Vector2 = items_layer.get_local_mouse_position()

	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)

	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))

	if cell_x < 0 or cell_y < 0 or cell_x >= inventory.grid_width or cell_y >= inventory.grid_height:
		return

	var cell_dict = inventory.grid[cell_y][cell_x]
	var stack: item_stack = cell_dict["stack"]

	if stack == null:
		return

	# Resolve origin cell (so clicking any covered cell works)
	var origin_x = cell_dict["origin_x"]
	var origin_y = cell_dict["origin_y"]

	# Fallback: if origin info isn't set, treat this cell as origin
	if origin_x < 0:
		origin_x = cell_x
	if origin_y < 0:
		origin_y = cell_y

	var origin_cell = inventory.grid[origin_y][origin_x]
	stack = origin_cell["stack"]

	if stack == null:
		return
	
		# How far from the origin did we click?
	grab_offset_x = cell_x - origin_x
	grab_offset_y = cell_y - origin_y
	# Remember what we're dragging + where it came from
	dragging_stack = stack
	drag_origin_x = origin_x
	drag_origin_y = origin_y

	# Remove from grid so those slots free up
	inventory.remove_item_stack(stack)

	# Redraw other items (dragged one is skipped in _draw_items)
	_draw_items()

	# Create floating UI
	dragging_ui = item_scene.instantiate() as ItemUI
	dragging_ui.set_stack(stack)
	dragging_ui.cell_size = cell_size

	var w := stack.width_cells()
	var h := stack.height_cells()
	var pos_x = origin_x * (cell_size + sep_x)
	var pos_y = origin_y * (cell_size + sep_y)
	var size_x := w * cell_size + (w - 1) * sep_x
	var size_y := h * cell_size + (h - 1) * sep_y

	dragging_ui.custom_minimum_size = Vector2(size_x, size_y)
	dragging_ui.size = dragging_ui.custom_minimum_size
	dragging_ui.position = Vector2(pos_x, pos_y)

	items_layer.add_child(dragging_ui)
	dragging_ui.set_stack(stack)
	dragging_ui.move_to_front()


func _finish_drag() -> void:
	if dragging_stack == null or dragging_ui == null:
		return

	var cols := inventory.grid_width
	var rows := inventory.grid_height
	
	var local: Vector2 = items_layer.get_local_mouse_position()

	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)

	# Cell the cursor is currently over
	var hover_x := int(floor(local.x / col_width))
	var hover_y := int(floor(local.y / row_height))

	# Compute where the origin *should* be
	var target_origin_x := hover_x - grab_offset_x
	var target_origin_y := hover_y - grab_offset_y

	dragging_ui.queue_free()
	dragging_ui = null

	# If the origin ends up outside the grid, revert
	if target_origin_x < 0 or target_origin_y < 0 or target_origin_x >= cols or target_origin_y >= rows:
		inventory.place_item(dragging_stack, drag_origin_x, drag_origin_y)
		_end_drag_and_refresh()
		return

	# Try to place at the computed origin
	if inventory.place_item(dragging_stack, target_origin_x, target_origin_y):
		_end_drag_and_refresh()
	else:
		# Failed to fit -> revert
		inventory.place_item(dragging_stack, drag_origin_x, drag_origin_y)
		_end_drag_and_refresh()

func _rotate_dragged_item() -> void:
	if dragging_stack == null or dragging_ui == null:
		return

	dragging_stack.rotated = not dragging_stack.rotated

	var w := dragging_stack.width_cells()
	var h := dragging_stack.height_cells()

	var size_x := w * cell_size + (w - 1) * sep_x
	var size_y := h * cell_size + (h - 1) * sep_y

	dragging_ui.custom_minimum_size = Vector2(size_x, size_y)
	dragging_ui.size = dragging_ui.custom_minimum_size

	# Recompute grab offset based on current mouse position
	var local: Vector2 = items_layer.get_local_mouse_position()
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)

	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))

	grab_offset_x = cell_x - drag_origin_x
	grab_offset_y = cell_y - drag_origin_y

	# Force the visual to refresh with new rotation state
	dragging_ui.set_stack(dragging_stack)



func _end_drag_and_refresh() -> void:
	dragging_stack = null
	drag_origin_x = -1
	drag_origin_y = -1
	grab_offset_x = 0
	grab_offset_y = 0
	refresh()
