extends MechWindow
class_name EquipmentWindow

# Part slots on the left, the stats panel on the right.
# While a part is dragged, the stats show what swapping it in would change,
# and in the Hangar the slot it would drop into lights up.

# A part was equipped or taken off through this window.
signal parts_changed

const MIN_SIZE := Vector2(820, 640)
const STATS_REFRESH := 0.25  # seconds; picks up cargo weight changes too

var mecha_ref: Mecha = null
var can_customize: bool = false

var part_slots: Array = []
var stats_panel: StatsPanel = null

var _notice: PanelContainer = null
var _notice_label: Label = null
var _tab_group := ButtonGroup.new()
var _preview_key := ""
var _refresh_timer := 0.0

@onready var slot_container: VBoxContainer = $Content/VBox/SlotContainer
@onready var hardware_btn: Button = $Content/VBox/TabBar/HardwareButton
@onready var wetware_btn: Button = $Content/VBox/TabBar/WetwareButton
@onready var weapons_btn: Button = $Content/VBox/TabBar/WeaponsButton


func _ready() -> void:
	super()
	min_size = MIN_SIZE
	custom_minimum_size = MIN_SIZE
	_collect_part_slots()
	_build_layout()

	for btn in [hardware_btn, wetware_btn, weapons_btn]:
		btn.theme_type_variation = &"Tab"
		btn.toggle_mode = true
		btn.button_group = _tab_group
		btn.focus_mode = Control.FOCUS_NONE
	hardware_btn.pressed.connect(_on_hardware_pressed)
	wetware_btn.pressed.connect(_on_wetware_pressed)
	weapons_btn.pressed.connect(_on_weapons_pressed)

	for slot in part_slots:
		slot.pressed.connect(_on_slot_pressed.bind(slot))

	hardware_btn.button_pressed = true
	_on_hardware_pressed()
	_update_notice()


func setup(mecha: Mecha) -> void:
	mecha_ref = mecha
	refresh_slots()
	# Register with DragManager
	MechOS.drag_manager.equipment_window = self


func set_customize(enabled: bool) -> void:
	can_customize = enabled
	_update_notice()


func refresh_slots() -> void:
	if mecha_ref == null:
		return
	for slot in part_slots:
		if slot == null:
			continue
		var part_res = _get_mecha_part_for_slot(slot)
		slot.set_current_part(part_res)
		_style_slot(slot, part_res != null, false)
	# Force the stats (and any drag comparison) to redraw next frame.
	_preview_key = "-"
	_refresh_timer = 0.0


func refresh_stats(preview: Dictionary = {}, header: String = "") -> void:
	if mecha_ref == null or stats_panel == null:
		return
	stats_panel.show_stats(mecha_ref.build, mecha_ref.get_inventory_weight(), preview, header)


# Slot interaction
func _on_slot_pressed(slot: PartSlot) -> void:
	if not can_customize:
		return
	if MechOS.drag_manager.is_dragging():
		return

	# Unequip the part and start a drag
	var part = _get_mecha_part_for_slot(slot)
	if part == null:
		return

	var stack := make_part_stack(slot.part_type, part.part_id)
	if stack == null:
		return

	# Remove from mech
	_set_mecha_part_for_slot(slot, null)
	refresh_slots()
	parts_changed.emit()

	# Tell DragManager to start dragging this stack
	MechOS.drag_manager.start_drag_from_equipment(stack, slot, self)


func get_slot_under_mouse() -> PartSlot:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for slot in part_slots:
		if slot is Control and slot.visible:
			if (slot as Control).get_global_rect().has_point(mouse_pos):
				return slot
	return null


func try_equip(slot: PartSlot, stack: item_stack) -> bool:
	if not can_customize or mecha_ref == null:
		return false
	if stack == null or stack.item_type != slot.part_type:
		return false

	# If something is already equipped, return it to the closest open inventory
	var existing_part = _get_mecha_part_for_slot(slot)
	if existing_part:
		var existing_stack := make_part_stack(slot.part_type, existing_part.part_id)
		if existing_stack == null:
			return false
		# Find an open inventory window to put the old part
		if not _return_stack_to_inventory(existing_stack):
			push_warning("EquipmentWindow: No space to return existing part.")
			return false

	# Equip the new part
	_set_mecha_part_for_slot(slot, stack.item_id)
	refresh_slots()
	parts_changed.emit()
	return true


func revert_equip(slot: PartSlot, stack: item_stack) -> void:
	# Re-equip a part that was unequipped for a drag that got cancelled
	_set_mecha_part_for_slot(slot, stack.item_id)
	refresh_slots()
	parts_changed.emit()

# Where a part swapped out of a slot goes, in order; then any other open
# inventory window.
const RETURN_ORDER := ["stash", "mech_cargo"]

func _return_stack_to_inventory(stack: item_stack) -> bool:
	var app_ids: Array = RETURN_ORDER.duplicate()
	for win_app_id in MechOS.open_windows:
		if not win_app_id in app_ids:
			app_ids.append(win_app_id)
	for win_app_id in app_ids:
		var window = MechOS.open_windows.get(win_app_id)
		if window is InventoryWindow and window.inventory_grid != null:
			var inv: Inventory = window.inventory_grid.get_inventory()
			if inv != null and inv.add_stack_anywhere(stack):
				window.refresh()
				return true
	return false


# ---- stats comparison while dragging -------------------------------------

func _process(delta: float) -> void:
	if mecha_ref == null or stats_panel == null:
		return

	var stack: item_stack = null
	var dm = MechOS.drag_manager
	if dm != null and dm.is_dragging() and dm.dragging_stack != null \
			and dm.dragging_stack.kind == item_stack.ItemKind.PART:
		stack = dm.dragging_stack
	var target: PartSlot = _preview_slot(stack) if stack != null else null
	var key := ""
	if target != null:
		key = "%s|%s|%d" % [stack.item_id, target.part_type, target.part_side]

	_refresh_timer -= delta
	if key == _preview_key and _refresh_timer > 0.0:
		return
	_preview_key = key
	_refresh_timer = STATS_REFRESH

	# Light the drop slot only where a drop would work.
	for slot in part_slots:
		_style_slot(slot, _get_mecha_part_for_slot(slot) != null, can_customize and slot == target)

	if target == null:
		refresh_stats()
		return
	var new_part = PartManager.get_part(stack.item_type, stack.item_id)
	var preview: Dictionary = mecha_ref.build.duplicate()
	preview[_build_key(target)] = new_part
	var header := "COMPARING %s   %s > %s" % [
			target.display_name, _part_name(_get_mecha_part_for_slot(target)), _part_name(new_part)]
	refresh_stats(preview, header)


# The slot a dragged part would go into: the one under the mouse if it
# takes that part, else the first slot of that type.
func _preview_slot(stack: item_stack) -> PartSlot:
	var hovered := get_slot_under_mouse()
	if hovered != null and hovered.part_type == stack.item_type:
		return hovered
	for slot in part_slots:
		if slot.part_type == stack.item_type:
			return slot
	return null


func _build_key(slot: PartSlot) -> String:
	if slot.part_type == "arm_weapon" or slot.part_type == "shoulder_weapon":
		return slot.part_type + ("_left" if slot.part_side == PartSlot.SIDE.LEFT else "_right")
	return slot.part_type


static func _part_name(part) -> String:
	if not part:
		return "EMPTY"
	var part_name = part.get("part_name")
	return str(part_name) if part_name else str(part.get("part_id"))


# ---- layout and styling ---------------------------------------------------

# The scene has one column (tabs + slots). Wrap it in a row and add the
# stats panel beside it, so the .tscn stays as it is.
func _build_layout() -> void:
	var column: VBoxContainer = $Content/VBox
	var row := HBoxContainer.new()
	row.theme_type_variation = &"WindowColumns"
	content.remove_child(column)
	content.add_child(row)
	row.add_child(column)
	column.custom_minimum_size.x = 300

	_notice = PanelContainer.new()
	_notice_label = Label.new()
	_notice_label.theme_type_variation = &"LabelMeta"
	_notice.add_child(_notice_label)
	column.add_child(_notice)
	column.move_child(_notice, 1)  # under the tabs

	# The stats are taller than the window: they scroll, the slots don't.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	stats_panel = StatsPanel.new()
	scroll.add_child(stats_panel)


func _update_notice() -> void:
	if _notice == null:
		return
	if can_customize:
		_notice.theme_type_variation = &"AlertNotice"
		_notice_label.text = "REFIT ON · DRAG PARTS TO SWAP"
	else:
		_notice.theme_type_variation = &"NoticeDashed"
		_notice_label.text = "VIEW ONLY — REFIT IN THE HANGAR"


func _style_slot(slot: PartSlot, filled: bool, target: bool) -> void:
	if target:
		slot.theme_type_variation = &"PartSlotTarget"
	else:
		slot.theme_type_variation = &"PartSlot" if filled else &"PartSlotEmpty"
	var margin := slot.get_node_or_null("MarginContainer")
	if margin:
		margin.theme_type_variation = &"SlotMargin"
	if slot.PartCategory:
		slot.PartCategory.theme_type_variation = &"LabelMeta"
	if slot.PartName:
		slot.PartName.theme_type_variation = &"LabelBody" if filled else &"LabelDim"


# ---- unchanged helpers -----------------------------------------------------

func _collect_part_slots() -> void:
	part_slots.clear()
	for child in slot_container.get_children():
		if child is PartSlot:
			part_slots.append(child)


func _get_mecha_part_for_slot(slot: PartSlot):
	if mecha_ref == null:
		return null
	var b = mecha_ref.build
	var p_type: String = slot.part_type
	var side: int = slot.part_side

	if p_type == "head":
		return b.head
	elif p_type == "core":
		return b.core
	elif p_type == "chassis":
		return b.chassis
	elif p_type == "shoulders":
		return b.shoulders
	elif p_type == "chipset":
		return b.chipset
	elif p_type == "generator":
		return b.generator
	elif p_type == "thruster":
		return b.thruster
	elif p_type == "arm_weapon":
		if side == PartSlot.SIDE.LEFT:
			return b.arm_weapon_left
		elif side == PartSlot.SIDE.RIGHT:
			return b.arm_weapon_right
	elif p_type == "shoulder_weapon":
		if side == PartSlot.SIDE.LEFT:
			return b.shoulder_weapon_left
		elif side == PartSlot.SIDE.RIGHT:
			return b.shoulder_weapon_right
	return null


func _set_mecha_part_for_slot(slot: PartSlot, value) -> void:
	if mecha_ref == null:
		return
	if slot.part_type == "head":
		mecha_ref.set_head(value)
	elif slot.part_type == "core":
		mecha_ref.set_core(value)
	elif slot.part_type == "chassis":
		mecha_ref.set_chassis(value)
	elif slot.part_type == "chipset":
		mecha_ref.set_chipset(value)
	elif slot.part_type == "generator":
		mecha_ref.set_generator(value)
	elif slot.part_type == "thruster":
		mecha_ref.set_thruster(value)
	elif slot.part_type == "shoulders":
		mecha_ref.set_shoulders(value)
	elif slot.part_type == "arm_weapon":
		if slot.part_side == PartSlot.SIDE.LEFT:
			mecha_ref.set_arm_weapon(value, Mecha.SIDE.LEFT)
		elif slot.part_side == PartSlot.SIDE.RIGHT:
			mecha_ref.set_arm_weapon(value, Mecha.SIDE.RIGHT)
	elif slot.part_type == "shoulder_weapon":
		if slot.part_side == PartSlot.SIDE.LEFT:
			mecha_ref.set_shoulder_weapon(value, Mecha.SIDE.LEFT)
		elif slot.part_side == PartSlot.SIDE.RIGHT:
			mecha_ref.set_shoulder_weapon(value, Mecha.SIDE.RIGHT)


func make_part_stack(part_type: String, part_id: String, qty: int = 1) -> item_stack:
	var s := item_stack.new()
	s.kind = item_stack.ItemKind.PART
	s.item_category = "part"
	s.item_type = part_type
	s.item_id = part_id
	s.quantity = qty
	return s

func _filter_slots(visible_types: Array) -> void:
	for slot in part_slots:
		slot.visible = slot.part_type in visible_types

func _on_hardware_pressed() -> void:
	_filter_slots(["head", "core", "shoulders", "chassis"])

func _on_wetware_pressed() -> void:
	_filter_slots(["chipset", "thruster", "generator"])

func _on_weapons_pressed() -> void:
	_filter_slots(["arm_weapon", "shoulder_weapon"])
