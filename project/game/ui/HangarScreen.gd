extends Control

# The Hangar: refit the mecha between expeditions and recycle salvage.
# Built on Mech OS windows — the same ones used in the field — so the Hangar
# and Expedition share one inventory/equipment system:
#   EQUIPMENT   the mecha's part slots (editable here; view-only mid-run)
#   MECH CARGO  what the mecha carries into the next run (lost if it dies)
#   STASH       everything kept at home (always safe)
# Drag parts between the grids and the slots; right-click salvage in the cargo
# or stash to recycle it into materials (totals in the bar along the bottom;
# MAT on the sidebar opens the full list).
#
# Inventories are the same objects PlayerProgress saves, and materials save as
# they change. The design is handed to PlayerProgress on every equip, so any
# save (recycling, say) writes parts, cargo and stash that agree; leaving or
# closing the game saves it all.

const TEST_ITEM_DATA := preload("res://database/items/test/TestItem.tres")

# Window layout in the 1920x1080 viewport: equipment left, cargo middle,
# stash right, the Hangar bar underneath, 20px apart. Windows can still be
# moved and resized.
const LAYOUT_LEFT := 95.0
const LAYOUT_RIGHT := 1900.0
const LAYOUT_TOP := 46.0
const LAYOUT_GAP := 20.0
const EQUIPMENT_SIZE := Vector2(820, 900)
const CARGO_SIZE := Vector2(440, 420)
const STASH_HEIGHT := 900.0

@onready var player_mecha: Mecha = $Mecha
@onready var materials_label: Label = $HangarBar/Row/Materials/MaterialsLabel
@onready var warning_box: PanelContainer = $HangarBar/Row/WarningBox
@onready var warning_label: Label = $HangarBar/Row/WarningBox/WarningLabel
@onready var leave_button: Button = $HangarBar/Row/LeaveButton

var stash_inventory: Inventory = null


func _ready() -> void:
	stash_inventory = PlayerProgress.get_stash_inventory()

	# Hand over the cargo before equipping: equipping the core sizes it
	# (Mecha.set_core), and anything a smaller core can't hold comes back
	# through cargo_overflow and goes to the stash.
	player_mecha.mech_inventory = PlayerProgress.get_mech_inventory()
	player_mecha.cargo_overflow.connect(_on_cargo_overflow)
	player_mecha.set_parts_from_design(PlayerProgress.get_current_mecha())

	MechOS.set_player(player_mecha)
	MechOS.set_equipment_customizable(true)
	MechOS.recycling_enabled = true
	MechOS.set_app_available("materials", true)
	_open_windows()

	PlayerProgress.materials_changed.connect(_on_materials_changed)
	_on_materials_changed(PlayerProgress.get_materials())
	leave_button.pressed.connect(_on_BackButton_pressed)
	_update_leave_guard()


func _exit_tree() -> void:
	MechOS.set_app_available("materials", false)
	MechOS.close_all()
	MechOS.recycling_enabled = false
	MechOS.set_player(null)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Closing the game: a part still being dragged goes back where it came
		# from first, so it isn't lost. An incomplete design is saved as it is
		# (its parts are in the stash); the main menu won't deploy it.
		MechOS.drag_manager.cancel_drag()
		_save_progress()


func _open_windows() -> void:
	var equipment = MechOS.open_equipment(player_mecha)
	if equipment != null:
		equipment.parts_changed.connect(_sync_design)
	var cargo = MechOS.open_inventory("mech_cargo", player_mecha.mech_inventory, "MECH CARGO")
	var stash = MechOS.open_inventory("stash", stash_inventory, "STASH")
	# The Hangar is these three windows, so they stay open.
	for window in [equipment, cargo, stash]:
		if window != null:
			window.closable = false
	# A window only knows how wide its content needs it to be (the cargo grid
	# sets the cargo window's width) once that content has been laid out.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var windows := [equipment, cargo, stash]
	var wants := [EQUIPMENT_SIZE.x, CARGO_SIZE.x, 0.0]
	var mins := []
	for window in windows:
		mins.append(_min_width(window))
	var columns := lay_out_columns(wants, mins)
	var heights := [EQUIPMENT_SIZE.y, CARGO_SIZE.y, STASH_HEIGHT]
	for i in windows.size():
		var window: MechWindow = windows[i]
		if window == null:
			continue
		window.position = Vector2(columns[i].x, LAYOUT_TOP)
		window.size = Vector2(columns[i].y, heights[i]).max(window.get_combined_minimum_size())


## Columns left to right, LAYOUT_GAP apart: each one its wanted width (or its
## minimum if that's more); the last one fills what's left up to LAYOUT_RIGHT.
## If that's less than the last one's minimum, the first one gives up width
## (down to its own minimum). Returns Vector2(x, width) per column.
static func lay_out_columns(wants: Array, mins: Array) -> Array:
	var widths := []
	for i in wants.size():
		widths.append(maxf(wants[i], mins[i]))
	var last := widths.size() - 1
	var used := LAYOUT_GAP * last
	for i in last:
		used += widths[i]
	var room := LAYOUT_RIGHT - LAYOUT_LEFT - used
	if room < mins[last]:
		var take := minf(mins[last] - room, widths[0] - mins[0])
		widths[0] -= take
		room += take
	widths[last] = maxf(room, mins[last])
	var columns := []
	var x := LAYOUT_LEFT
	for w in widths:
		columns.append(Vector2(x, w))
		x += w + LAYOUT_GAP
	return columns


func _min_width(window) -> float:
	if window == null:
		return 0.0
	return maxf(window.min_size.x, window.get_combined_minimum_size().x)


func _on_cargo_overflow(stacks: Array) -> void:
	for stack in stacks:
		if not stash_inventory.add_stack_anywhere(stack):
			push_warning("Hangar: no room in the stash for an item pushed out of the cargo; it was lost.")
	MechOS.refresh_inventory_windows()


# A short total per tech tier; the MAT window has the full list.
func _on_materials_changed(materials: Dictionary) -> void:
	var parts := []
	for tier in Materials.TIERS:
		var total := 0
		for material in Materials.of_tier(tier):
			total += int(materials.get(material.id, 0))
		parts.append("%s %d" % [Materials.tier_name(tier).to_upper(), total])
	materials_label.text = "   ".join(parts)


# Leaving saves the design, so it's blocked while a required part is missing
# (a mecha without a core etc. spawns broken). The alert shows as soon as a
# slot is empty and clears itself once the slots are filled. Checked every
# frame: it's ten dictionary lookups, and the label only changes on a change.
func _process(_delta: float) -> void:
	_update_leave_guard()


func _update_leave_guard() -> void:
	var missing := get_missing_parts()
	leave_button.disabled = not missing.is_empty()
	if missing.is_empty():
		_hide_warning()
	else:
		_show_warning(missing)


func _show_warning(missing: Array) -> void:
	var text := "! CAN'T LEAVE — NO %s EQUIPPED" % PlayerProgress.describe_missing_parts(missing)
	if warning_label.text != text:
		warning_label.text = text
	if not warning_box.visible:
		warning_label.show()
		warning_box.show()


func _hide_warning() -> void:
	if warning_box.visible:
		warning_label.hide()
		warning_box.hide()


func get_missing_parts() -> Array:
	return PlayerProgress.missing_parts(player_mecha.get_design_data())


func _on_BackButton_pressed() -> void:
	var missing := get_missing_parts()
	if not missing.is_empty():
		_show_warning(missing)
		MechLog.write("HGR", "Can't leave: no %s equipped" % PlayerProgress.describe_missing_parts(missing).to_lower(),
				MechLog.Kind.SYSTEM, true)
		AudioManager.play_sfx("back")
		return
	_save_progress()
	TransitionManager.transition_to(
		"res://game/start_menu/StartMenu.tscn",
		"Leaving Hangar..."
	)


# Without saving: the next save, whatever triggers it, includes the design.
func _sync_design() -> void:
	PlayerProgress.set_current_mecha(player_mecha.get_design_data(), false)


func _save_progress() -> void:
	PlayerProgress.set_stash_inventory(stash_inventory)
	PlayerProgress.set_mech_inventory(player_mecha.mech_inventory)
	PlayerProgress.set_current_mecha(player_mecha.get_design_data())  # also saves the profile


func _unhandled_input(event):
	if not player_mecha or not player_mecha.mech_inventory:
		return

	# ESC leaves, as the button says. Not mid-drag: saving then would save
	# the cargo without the item in hand.
	if event.is_action_pressed("escape"):
		if MechOS.drag_manager.dragging_stack == null:
			_on_BackButton_pressed()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_6"):
		player_mecha.mech_inventory.add_item(TEST_ITEM_DATA, 1)
		MechOS.refresh_inventory_windows()
		get_viewport().set_input_as_handled()
