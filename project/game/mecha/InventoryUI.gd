extends Control
class_name InventoryUI

enum SIDE {LEFT, RIGHT, SINGLE}

# --- Data references ---

@export var main_inventory: inventory            # primary inventory (mech)
var other_inventory: inventory = null       # secondary inventory (stash/container/target)

@export var cell_scene: PackedScene         # scene for individual grid cells
@export var item_scene: PackedScene         # scene for item UI panel

@export var can_customize: bool = true     # if true, equipment slots are interactive
var mecha_ref: Mecha = null                 # use this inside equip_part/unequip_part


# --- Equipment / Part slots ---

var part_slots: Array = []                  # all PartSlot buttons (Head, Core, etc)


# --- Layout / UI node refs ---

var cell_size: int = 68                     # size of a single cell in pixels
var sep_x: int = 0                          # horizontal separation between cells
var sep_y: int = 0                          # vertical separation between cells

@onready var drag_layer: Control = $DragLayer
@onready var tooltip: ItemTooltip = $ItemTooltip
var hover_stack: item_stack = null

# Mech inventory (middle column)
@onready var inventory_panel: Panel      = $MainFrame/Columns/InventoryColumn/InventoryPanel
@onready var grid_frame: Panel           = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame
@onready var scroll: ScrollContainer     = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll
@onready var grid_content: Control       = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent
@onready var cell_grid: GridContainer    = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder/CellGrid
@onready var items_layer: Control        = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder/ItemsLayer
@onready var grid_border: Panel          = $MainFrame/Columns/InventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder

# Target inventory (right column)
@onready var other_inventory_panel: Panel      = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel
@onready var other_grid_frame: Panel           = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel/GridFrame
@onready var other_scroll: ScrollContainer     = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel/GridFrame/Scroll
@onready var other_grid_content: Control       = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent
@onready var other_cell_grid: GridContainer    = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder/CellGrid
@onready var other_items_layer: Control        = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder/ItemsLayer
@onready var other_grid_border: Panel          = $MainFrame/Columns/OtherInventoryColumn/InventoryPanel/GridFrame/Scroll/GridContent/GridBorder

@onready var tab_buttons_container: Control = $MainFrame/Columns/EquipmentColumn/MarginContainer/HBoxContainer
# --- State: panning / drag & drop ---

var is_panning: bool = false                # right-mouse panning flag

var dragging_stack: item_stack = null       # stack currently being dragged (data)
var dragging_ui: ItemUI = null              # floating UI for dragged stack (art ghost)
var drag_origin_x: int = -1                 # original origin cell (x) in source inventory
var drag_origin_y: int = -1                 # original origin cell (y)
var drag_source_inventory: inventory = null # which inventory the drag started from
var drag_source_slot: Node = null           # which part slot the drag started from (if any)

var drag_hover_x: int = -1                  # predicted origin cell X while dragging
var drag_hover_y: int = -1                  # predicted origin cell Y while dragging

var drag_preview: Panel = null              # transparent footprint outline

var pan_scroll: ScrollContainer = null  # which scroll we're currently panning


func setup_for_mecha(mecha: Mecha, target_inv: inventory = null) -> void:
	mecha_ref = mecha

	# Hook the inventories
	main_inventory = mecha.mech_inventory          # main cargo
	other_inventory = target_inv              # stash / container / null

	# Discover all PartSlots under the EquipmentColumn
	part_slots.clear()
	var equip_column = $MainFrame/Columns/EquipmentColumn/EquipmentPanel/EquipmentMargin/HBoxContainer/VBoxContainer
	_collect_part_slots_recursive(equip_column)
	for slot in part_slots:
		slot.inventory_ui = self

	# Build grids + items
	refresh()

	# Sync the slots with currently equipped parts
	refresh_part_slots_from_mecha()

func _ready() -> void:
	# Separation is defined via theme on GridContainer
	drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep_x = cell_grid.get_theme_constant("h_separation")
	sep_y = cell_grid.get_theme_constant("v_separation")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)

	# Gather all part slots via group "part_slots"
	for node in get_tree().get_nodes_in_group("part_slots"):
		if node is Button:
			part_slots.append(node)
			(node as Button).pressed.connect(_on_part_slot_pressed.bind(node))


func _process(_delta: float) -> void:
	_update_hover_tooltip()


func refresh() -> void:
	# Rebuilds both inventory grids + their item UIs from the current
	# state of `main_inventory` and `other_inventory`.
	if main_inventory == null:
		return

	sep_x = cell_grid.get_theme_constant("h_separation")
	sep_y = cell_grid.get_theme_constant("v_separation")

	# Primary inventory (mech)
	_update_grid_content_size_for(main_inventory, grid_content)
	_build_cells_for(main_inventory, cell_grid)
	_draw_items_for(main_inventory, items_layer)
	_layout_grid_border_for(main_inventory, grid_content, grid_border)

	# Secondary inventory (target/stash) if present
	if other_inventory != null:
		_update_grid_content_size_for(other_inventory, other_grid_content)
		_build_cells_for(other_inventory, other_cell_grid)
		_draw_items_for(other_inventory, other_items_layer)
		_layout_grid_border_for(other_inventory, other_grid_content, other_grid_border)
		other_inventory_panel.visible = true
	else:
		other_inventory_panel.visible = false
	
		

# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _update_grid_content_size_for(inv: inventory, content: Control) -> void:
	if cell_size <= 0 or inv == null:
		return
	content.custom_minimum_size = Vector2(
		inv.grid_width * cell_size,
		inv.grid_height * cell_size
	)


func _build_cells_for(inv: inventory, grid: GridContainer) -> void:
	if inv == null:
		return

	for c in grid.get_children():
		c.queue_free()

	grid.columns = inv.grid_width

	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell = cell_scene.instantiate()
			cell.x = x
			cell.y = y
			cell.custom_minimum_size = Vector2(cell_size, cell_size)
			grid.add_child(cell)


func _layout_grid_border_for(inv: inventory, content: Control, border: Panel) -> void:
	"""
	Size & center the border panel so it tightly wraps the active grid,
	with a 1px gap between cells to visually form a grid.
	"""
	if inv == null:
		return

	var cols := inv.grid_width
	var rows := inv.grid_height
	if cols <= 0 or rows <= 0:
		return

	var h_sep := 1
	var v_sep := 1

	var grid_w = cols * cell_size + (cols - 1) * h_sep
	var grid_h = rows * cell_size + (rows - 1) * v_sep
	var grid_size := Vector2(grid_w, grid_h)

	var area_size := content.get_rect().size
	var origin := (area_size - grid_size) * 0.5

	border.custom_minimum_size = grid_size
	border.size = grid_size
	border.position = origin


func _draw_items_for(inv: inventory, layer: Control) -> void:
	"""
	Instantiate an ItemUI for each *origin* cell in `inv`, skipping
	secondary cells and the stack currently being dragged.
	"""
	for c in layer.get_children():
		c.queue_free()

	if inv == null:
		return

	var slot_w := cell_size
	var slot_h := cell_size

	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell_dict = inv.grid[y][x]
			var stack: item_stack = cell_dict["stack"]

			if stack == null:
				continue

			# Skip currently dragged stack (no matter which inventory)
			if dragging_stack != null and stack == dragging_stack:
				continue

			# Only draw once per item, at its origin cell
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

			layer.add_child(ui)
			ui.set_stack(stack)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if main_inventory != null:
			refresh()


# ---------------------------------------------------------------------------
# Input handling (rotate, pan, drag & drop)
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Rotate currently dragged item
	if event is InputEventKey and event.is_action_pressed("inventory_rotate"):
		if dragging_stack != null:
			_rotate_dragged_item()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var target_scroll := _get_scroll_under_mouse()
		var over_inv := target_scroll != null

		# --- Right mouse: panning in whichever inventory is under the mouse ---
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and over_inv:
				is_panning = true
				pan_scroll = target_scroll
				get_viewport().set_input_as_handled()
			elif not event.pressed and is_panning:
				is_panning = false
				pan_scroll = null
				get_viewport().set_input_as_handled()
			return

		# --- Scroll wheel: scroll the inventory under the mouse ---
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and target_scroll != null:
			target_scroll.scroll_vertical -= cell_size
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and target_scroll != null:
			target_scroll.scroll_vertical += cell_size
			get_viewport().set_input_as_handled()
			return

		# --- Left mouse: start / finish drag (only if over inventory) ---
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _is_mouse_over_inventory() and _start_drag():
				get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if dragging_stack != null:
				_finish_drag()
				get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseMotion:
		# --- Panning with right mouse ---
		if is_panning and pan_scroll != null:
			var delta: Vector2 = event.relative
			pan_scroll.scroll_vertical -= int(delta.y)
			pan_scroll.scroll_horizontal -= int(delta.x)
			get_viewport().set_input_as_handled()
			return

		# --- Move floating drag UI + update footprint preview ---
		elif dragging_stack != null and dragging_ui != null:
			_update_drag_visual_position()
			get_viewport().set_input_as_handled()
			return


func _is_tab_button(node: Node) -> bool:
	var current := node
	while current:
		if current == tab_buttons_container:
			return true
		current = current.get_parent()
	return false

# ---------------------------------------------------------------------------
# Drag & Drop – from inventory grids
# ---------------------------------------------------------------------------

func _start_drag() -> bool:
	# Begin dragging an item from whichever inventory is under the mouse.
	# Returns true if we actually started a drag, false otherwise.

	var info := _get_inventory_under_mouse()
	if info.is_empty():
		return false

	var inv: inventory = info["inventory"]
	var layer: Control = info["layer"]
	if inv == null:
		return false

	# Mouse in that inventory layer's local space
	var local: Vector2 = layer.get_local_mouse_position()
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)

	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))

	if cell_x < 0 or cell_y < 0 or cell_x >= inv.grid_width or cell_y >= inv.grid_height:
		return false

	var cell_dict = inv.grid[cell_y][cell_x]
	var stack: item_stack = cell_dict["stack"]
	if stack == null:
		return false

	# Resolve origin cell so that clicking any covered cell works
	var origin_x = cell_dict["origin_x"]
	var origin_y = cell_dict["origin_y"]
	if origin_x < 0:
		origin_x = cell_x
	if origin_y < 0:
		origin_y = cell_y

	var origin_cell = inv.grid[origin_y][origin_x]
	stack = origin_cell["stack"]
	if stack == null:
		return false

	# --- Drag state ---
	dragging_stack = stack
	drag_origin_x = origin_x
	drag_origin_y = origin_y
	drag_source_inventory = inv

	if tooltip != null:
		tooltip.hide()

	# Remove from source inventory and redraw grids
	inv.remove_item_stack(stack)
	refresh()

	# Floating UI in drag_layer (art ghost, snapped to grid when over an inventory)
	dragging_ui = item_scene.instantiate() as ItemUI
	dragging_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE  # make sure it doesn't eat clicks
	dragging_ui.cell_size = cell_size

	var w := stack.width_cells()
	var h := stack.height_cells()
	var size_x := w * cell_size + (w - 1) * sep_x
	var size_y := h * cell_size + (h - 1) * sep_y
	dragging_ui.custom_minimum_size = Vector2(size_x, size_y)
	dragging_ui.size = dragging_ui.custom_minimum_size

	drag_layer.add_child(dragging_ui)
	dragging_ui.set_stack(stack)
	dragging_ui.z_index = 1
	dragging_ui.move_to_front()

	# Footprint preview (transparent box with border, follows cursor)
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

	_update_drag_visual_position()
	return true



# Drag that starts from a part slot (unequip → drag)
func _start_drag_from_stack(stack: item_stack, slot: Node) -> void:
	dragging_stack = stack
	drag_source_inventory = null
	drag_source_slot = slot
	drag_origin_x = -1
	drag_origin_y = -1

	if tooltip != null:
		tooltip.hide()

	# No grid removal needed; the stack came from equipment, not from an inventory grid.
	# Just spawn the drag ghost + preview as usual.
	dragging_ui = item_scene.instantiate() as ItemUI
	dragging_ui.cell_size = cell_size

	var w := stack.width_cells()
	var h := stack.height_cells()
	var size_x := w * cell_size + (w - 1) * sep_x
	var size_y := h * cell_size + (h - 1) * sep_y
	dragging_ui.custom_minimum_size = Vector2(size_x, size_y)
	dragging_ui.size = dragging_ui.custom_minimum_size

	drag_layer.add_child(dragging_ui)
	dragging_ui.set_stack(stack)
	dragging_ui.z_index = 1
	dragging_ui.move_to_front()

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

	_update_drag_visual_position()


func _finish_drag() -> void:
	# End a drag operation. Decide where we dropped:
	# 1) On an equipment slot  -> equip_part()
	# 2) On an inventory grid  -> place_item()
	# 3) Nowhere               -> revert
	if dragging_stack == null or dragging_ui == null:
		return

	# Make sure hover info is up to date
	_update_drag_visual_position()

	# --- 1) Check equipment slots (left column) first ---
	var slot := _get_part_slot_under_mouse()
	if slot != null and can_customize:
		dragging_ui.queue_free()
		dragging_ui = null

		if drag_preview != null:
			drag_preview.queue_free()
			drag_preview = null

		# Let  game logic handle compatibility, mech wiring, old-part return, etc.
		var ok := equip_part(slot, dragging_stack, drag_source_inventory, drag_origin_x, drag_origin_y)

		if not ok:
			# Equip failed -> revert
			if drag_source_inventory != null and drag_origin_x >= 0 and drag_origin_y >= 0:
				drag_source_inventory.place_item(dragging_stack, drag_origin_x, drag_origin_y)
			elif drag_source_slot != null:
				# Drag started from a slot: re-equip to the original slot
				equip_part(drag_source_slot, dragging_stack, null, -1, -1)

		_end_drag_and_refresh()
		return

	# --- 2) Otherwise, treat it as a grid drop  ---
	var info := _get_inventory_under_mouse()

	dragging_ui.queue_free()
	dragging_ui = null

	if drag_preview != null:
		drag_preview.queue_free()
		drag_preview = null

	if info.is_empty() or drag_hover_x < 0 or drag_hover_y < 0:
		# Not over any inventory – revert
		if drag_source_inventory != null and drag_origin_x >= 0 and drag_origin_y >= 0:
			drag_source_inventory.place_item(dragging_stack, drag_origin_x, drag_origin_y)
		elif drag_source_slot != null:
			# Came from slot: re-equip
			equip_part(drag_source_slot, dragging_stack, null, -1, -1)
		_end_drag_and_refresh()
		return

	var target_inv: inventory = info["inventory"]
	var target_origin_x := drag_hover_x
	var target_origin_y := drag_hover_y

	if target_inv.place_item(dragging_stack, target_origin_x, target_origin_y):
		_end_drag_and_refresh()
	else:
		# Failed -> revert to original source
		if drag_source_inventory != null and drag_origin_x >= 0 and drag_origin_y >= 0:
			drag_source_inventory.place_item(dragging_stack, drag_origin_x, drag_origin_y)
		elif drag_source_slot != null:
			equip_part(drag_source_slot, dragging_stack, null, -1, -1)
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

	# Refresh icon & rotation visuals
	dragging_ui.set_stack(dragging_stack)

	# Re-snap to grid under the cursor with the new shape
	_update_drag_visual_position()


func _end_drag_and_refresh() -> void:
	dragging_stack = null
	dragging_ui = null
	drag_origin_x = -1
	drag_origin_y = -1
	drag_hover_x = -1
	drag_hover_y = -1
	drag_source_inventory = null
	drag_source_slot = null

	if drag_preview != null:
		drag_preview.queue_free()
		drag_preview = null

	refresh()


# ---------------------------------------------------------------------------
# Equipment slot helpers
# ---------------------------------------------------------------------------

# Called when a PartSlot button is pressed (wired in _ready via group "part_slots")
func _on_part_slot_pressed(slot: Node) -> void:
	# If we're already dragging something, ignore the click.
	if dragging_stack != null:
		return
	if not can_customize:
		return

	# Ask game logic to unequip this slot and return an item_stack for it.
	var stack: item_stack = unequip_part(slot)
	if stack == null:
		return

	# Start a drag originating from this equipment slot
	_start_drag_from_stack(stack, slot)


# Find which slot (if any) is under mouse
func _get_part_slot_under_mouse() -> Node:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for slot in part_slots:
		if slot is Control:
			var c := slot as Control
			if c.get_global_rect().has_point(mouse_pos):
				return slot
	return null

func _collect_part_slots_recursive(node: Node) -> void:
	if node is PartSlot:
		part_slots.append(node)
	for c in node.get_children():
		_collect_part_slots_recursive(c)

func refresh_part_slots_from_mecha() -> void:
	if mecha_ref == null:
		return

	for slot in part_slots:
		if slot == null:
			continue
		var part_res = _get_mecha_part_for_slot(slot)
		slot.set_current_part(part_res)

func _get_mecha_part_for_slot(slot: PartSlot):
	# We assume mecha_ref is a Mecha / Player that has a `build` struct.
	if mecha_ref == null:
		return null

	var b = mecha_ref.build  # Player extends Mecha, so `build` should exist.

	var p_type: String = slot.part_type
	var side: int = slot.part_side

	match p_type:
		"head":
			return b.head
		"core":
			return b.core
		"chassis":
			return b.chassis
		"shoulders":
			return b.shoulders
		"chipset":
			return b.chipset
		"generator":
			return b.generator
		"thruster":
			return b.thruster

		"arm_weapon":
			if side == PartSlot.SIDE.LEFT:
				return b.arm_weapon_left
			elif side == PartSlot.SIDE.RIGHT:
				return b.arm_weapon_right

		"shoulder_weapon":
			if side == PartSlot.SIDE.LEFT:
				return b.shoulder_weapon_left
			elif side == PartSlot.SIDE.RIGHT:
				return b.shoulder_weapon_right

		_:
			return null

func _set_mecha_part_for_slot(slot: PartSlot, value) -> void:
	if mecha_ref == null:
		return

	match slot.part_type:
		"head":
			mecha_ref.set_head(value)
		"core":
			mecha_ref.set_core(value)
		"chassis":
			mecha_ref.set_chassis(value)
		"chipset":
			mecha_ref.set_chipset(value)
		"generator":
			mecha_ref.set_generator(value)
		"thruster":
			mecha_ref.set_thruster(value)
		"shoulders":
			mecha_ref.set_shoulders(value)
		"arm_weapon":
			match slot.part_side:
				PartSlot.SIDE.LEFT:
					mecha_ref.set_arm_weapon(value, SIDE.LEFT)
				PartSlot.SIDE.RIGHT:
					mecha_ref.set_arm_weapon(value, SIDE.RIGHT)
		"shoulder_weapon":
			match slot.part_side:
				PartSlot.SIDE.LEFT:
					mecha_ref.set_shoulder_weapon(value, SIDE.LEFT)
				PartSlot.SIDE.RIGHT:
					mecha_ref.set_shoulder_weapon(value, SIDE.RIGHT)


func _on_hardware_button_pressed() -> void:
	var equip_column = $MainFrame/Columns/EquipmentColumn/EquipmentPanel/EquipmentMargin/HBoxContainer/VBoxContainer
	for child in equip_column.get_children():
		if child.part_type == "head" or child.part_type == "core" or child.part_type == "shoulders" or child.part_type == "chassis":
			child.visible = true
		else:
			child.visible = false
	

func _on_wetware_button_pressed() -> void:
	var equip_column = $MainFrame/Columns/EquipmentColumn/EquipmentPanel/EquipmentMargin/HBoxContainer/VBoxContainer
	for child in equip_column.get_children():
		if child.part_type == "chipset" or child.part_type == "thruster" or child.part_type == "generator":
			child.visible = true
		else:
			child.visible = false


func _on_weapons_button_pressed() -> void:
	var equip_column = $MainFrame/Columns/EquipmentColumn/EquipmentPanel/EquipmentMargin/HBoxContainer/VBoxContainer
	for child in equip_column.get_children():
		if child.part_type == "arm_weapon" or child.part_type == "shoulder_weapon":
			child.visible = true
		else:
			child.visible = false

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

func _get_inventory_under_mouse() -> Dictionary:
	# Return a small dict describing which inventory (if any) is under the mouse 

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	# Check mech column
	if grid_frame.get_global_rect().has_point(mouse_pos) and main_inventory != null:
		return {
			"inventory": main_inventory,
			"layer": items_layer,
			"type": "mech"
		}

	# Check other/target column
	if other_inventory != null and other_grid_frame.get_global_rect().has_point(mouse_pos):
		return {
			"inventory": other_inventory,
			"layer": other_items_layer,
			"type": "other"
		}

	return {}  # nothing under mouse

func _get_scroll_under_mouse() -> ScrollContainer:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	# Mech inventory scroll
	if grid_frame.get_global_rect().has_point(mouse_pos):
		return scroll

	# Other / target inventory scroll
	if other_inventory != null and other_grid_frame.get_global_rect().has_point(mouse_pos):
		return other_scroll

	return null


func _get_mouse_pos_in(control: Control) -> Vector2:
	# Convert the global mouse position into the local space of `control`.
	# Used primarily for drag_layer so the drag ghost stays under the cursor.
	var global_mouse := get_viewport().get_mouse_position()
	var rect := control.get_global_rect()
	return global_mouse - rect.position


func _update_drag_visual_position() -> void:
	if dragging_stack == null or dragging_ui == null:
		return

	var mouse_local_drag: Vector2 = _get_mouse_pos_in(drag_layer)
	var info := _get_inventory_under_mouse()

	if info.is_empty():
		# Not over any inventory – art ghost + preview both follow cursor
		dragging_ui.position = mouse_local_drag - dragging_ui.size * 0.5
		drag_hover_x = -1
		drag_hover_y = -1

		if drag_preview != null:
			drag_preview.visible = true
			drag_preview.size = dragging_ui.size
			drag_preview.position = mouse_local_drag - drag_preview.size * 0.5

		return

	var inv: inventory = info["inventory"]
	var layer: Control = info["layer"]

	var local: Vector2 = layer.get_local_mouse_position()
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)

	# How many cells wide/high is this item right now?
	var w := dragging_stack.width_cells()
	var h := dragging_stack.height_cells()

	# Cell the mouse is currently over
	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))

	# Offset so the center of the item lines up with the hovered cell
	# For odd sizes (e.g. 1x3), this makes the middle cell sit under the cursor.
	# For even sizes (e.g. 2x2), we approximate to the closest top-left.
	var center_offset_x := int(floor(w / 2.0))
	var center_offset_y := int(floor(h / 2.0))

	var max_x := inv.grid_width  - w
	var max_y := inv.grid_height - h

	var origin_x := cell_x - center_offset_x
	var origin_y := cell_y - center_offset_y

	origin_x = clamp(origin_x, 0, max_x)
	origin_y = clamp(origin_y, 0, max_y)

	drag_hover_x = origin_x
	drag_hover_y = origin_y

	# Position of the top-left cell in the inventory layer
	var pos_x := origin_x * col_width
	var pos_y := origin_y * row_height

	# Convert that to drag_layer local coordinates (for the snapped ghost)
	var layer_rect := layer.get_global_rect()
	var drag_rect := drag_layer.get_global_rect()
	var global_pos := layer_rect.position + Vector2(pos_x, pos_y)
	var local_in_drag := global_pos - drag_rect.position

	# Art ghost: snapped to grid using the adjusted origin
	dragging_ui.position = local_in_drag

	# Preview: follows cursor, not snapped, but sized to footprint
	if drag_preview != null:
		drag_preview.visible = true
		drag_preview.size = dragging_ui.size
		drag_preview.position = mouse_local_drag - drag_preview.size * 0.5


func _update_hover_tooltip() -> void:
	if tooltip == null:
		return

	# Don’t show tooltip while dragging, or when UI is hidden
	if not visible or dragging_stack != null:
		if hover_stack != null:
			hover_stack = null
			tooltip.hide()
		return

	var info := _get_inventory_under_mouse()
	if info.is_empty():
		if hover_stack != null:
			hover_stack = null
			tooltip.hide()
		return

	var inv: inventory = info["inventory"]
	var layer: Control = info["layer"]
	if inv == null:
		if hover_stack != null:
			hover_stack = null
			tooltip.hide()
		return

	var local: Vector2 = layer.get_local_mouse_position()
	var col_width := float(cell_size + sep_x)
	var row_height := float(cell_size + sep_y)

	var cell_x := int(floor(local.x / col_width))
	var cell_y := int(floor(local.y / row_height))

	if cell_x < 0 or cell_y < 0 or cell_x >= inv.grid_width or cell_y >= inv.grid_height:
		if hover_stack != null:
			hover_stack = null
			tooltip.hide()
		return

	var cell_dict = inv.grid[cell_y][cell_x]
	var stack: item_stack = cell_dict["stack"]
	if stack == null:
		if hover_stack != null:
			hover_stack = null
			tooltip.hide()
		return

	# Resolve to origin cell for consistent tooltip per footprint
	var origin_x = cell_dict["origin_x"]
	var origin_y = cell_dict["origin_y"]
	if origin_x >= 0 and origin_y >= 0:
		var origin_cell = inv.grid[origin_y][origin_x]
		var origin_stack: item_stack = origin_cell["stack"]
		if origin_stack != null:
			stack = origin_stack

	# If we're still on the same stack, do nothing
	if stack == hover_stack:
		return

	hover_stack = stack
	tooltip.show_item(stack)

func _is_mouse_over_inventory() -> bool:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	if grid_frame.get_global_rect().has_point(mouse_pos) and main_inventory != null:
		return true
	if other_inventory != null and other_grid_frame.get_global_rect().has_point(mouse_pos):
		return true
	return false


# ---------------------------------------------------------------------------
# Mech Equip/Unequip
# ---------------------------------------------------------------------------

# Called when an item is dropped on a part slot.
# slot: the PartSlot Button you dropped on
# stack: the item_stack being dropped
# source_inventory: which inventory it came from (or null if from a slot)
# origin_x/origin_y: where in that inventory it came from (or -1 if from a slot)
# Return true if equip succeeded, false to revert the drag.
func equip_part(slot: Node, stack: item_stack, source_inventory: inventory, origin_x: int, origin_y: int) -> bool:
	print(slot, " -> ", stack.part_scene)
	return false


# Called when a part slot is clicked with no item being dragged.
# Should:
#   - unequip that slot from the mech
#   - return a new item_stack representing the unequipped part
# Return null if nothing is equipped or unequip failed.
func unequip_part(slot: PartSlot):
	print("Here!")
	# Only allowed in hangar / customization context
	if not can_customize:
		return
	if mecha_ref == null:
		return
	if main_inventory == null:
		return

	# 1) Find which part is currently equipped in this slot
	var part = _get_mecha_part_for_slot(slot)
	if part == null:
		return
	# 2) Build an item_stack for that part
	var stack := make_part_stack(slot.part_type, slot.current_part_id)
	if stack == null:
		push_error("InventoryUI: _stack_from_part() returned null for part: %s" % [str(part)])
		return

	# 3) Try to add it to the mech inventory
	if not main_inventory.add_stack_to_first_available_slot(stack):
		# No space: optionally re-equip the part or just bail
		push_warning("InventoryUI: No space in inventory to unequip part.")
		return

	# 4) Actually unequip from the mecha
	_set_mecha_part_for_slot(slot, null)

	# 5) Refresh UI so the new item appears
	refresh()

func make_part_stack(part_type: String, part_id: String, qty: int = 1) -> item_stack:
	var s := item_stack.new()
	s.kind = item_stack.ItemKind.PART
	s.part_type = part_type      # must be one of the PartManager keys: "head", "core", "arm_weapon", etc.
	s.part_name = part_id        # e.g. "Lancelot-Core"
	s.quantity = qty
	return s
