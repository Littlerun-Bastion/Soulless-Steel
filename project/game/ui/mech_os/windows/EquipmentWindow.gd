extends MechWindow

var mecha_ref: Mecha = null
var can_customize: bool = false

var part_slots: Array = []

@onready var slot_container: VBoxContainer = $Content/VBox/SlotContainer
@onready var hardware_btn: Button = $Content/VBox/TabBar/HardwareButton
@onready var wetware_btn: Button = $Content/VBox/TabBar/WetwareButton
@onready var weapons_btn: Button = $Content/VBox/TabBar/WeaponsButton


func _ready() -> void:
	super()
	print("slot_container: ", slot_container)
	print("hardware_btn: ", hardware_btn)
	print("wetware_btn: ", wetware_btn)
	print("weapons_btn: ", weapons_btn)
	_collect_part_slots()
	print("part_slots found: ", part_slots.size())
	super()
	_collect_part_slots()
	hardware_btn.pressed.connect(_on_hardware_pressed)
	wetware_btn.pressed.connect(_on_wetware_pressed)
	weapons_btn.pressed.connect(_on_weapons_pressed)
	
	# Override PartSlot's default pressed behavior
	for slot in part_slots:
		# Disconnect old signal if connected
		if slot.is_connected("pressed", slot._on_slot_pressed):
			slot.disconnect("pressed", slot._on_slot_pressed)
		slot.pressed.connect(_on_slot_pressed.bind(slot))


func setup(mecha: Mecha) -> void:
	print("EquipmentWindow.setup called, mecha: ", mecha)
	print("can_customize: ", can_customize)
	mecha_ref = mecha
	refresh_slots()
	MechOS.drag_manager.equipment_window = self
	mecha_ref = mecha
	refresh_slots()
	
	# Register with DragManager
	MechOS.drag_manager.equipment_window = self


func set_customize(enabled: bool) -> void:
	can_customize = enabled


func refresh_slots() -> void:
	if mecha_ref == null:
		return
	for slot in part_slots:
		if slot == null:
			continue
		var part_res = _get_mecha_part_for_slot(slot)
		slot.set_current_part(part_res)


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
	return true


func revert_equip(slot: PartSlot, stack: item_stack) -> void:
	# Re-equip a part that was unequipped for a drag that got cancelled
	_set_mecha_part_for_slot(slot, stack.item_id)
	refresh_slots()

func _return_stack_to_inventory(stack: item_stack) -> bool:
	# Try to place the stack in any open inventory window
	for app_id in MechOS.open_windows:
		var window = MechOS.open_windows[app_id]
		if window is InventoryWindow and window.inventory_grid != null:
			var inv: Inventory = window.inventory_grid.get_inventory()
			if inv != null and inv.add_stack_to_first_available_slot(stack):
				window.refresh()
				return true
	return false


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
