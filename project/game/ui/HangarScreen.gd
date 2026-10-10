extends Control

# The Hangar: refit the mecha between expeditions and recycle salvage.
# Built on Mech OS windows — the same ones used in the field — so the Hangar
# and Expedition share one inventory/equipment system:
#   EQUIPMENT   the mecha's part slots (editable here; view-only mid-run)
#   MECH CARGO  what the mecha carries into the next run (lost if it dies)
#   STASH       everything kept at home (always safe)
# Drag parts between the grids and the slots; right-click salvage in the cargo
# or stash to recycle it into materials (shown along the bottom).
#
# The mecha design is saved when leaving (ESC). Inventories are the same
# objects PlayerProgress saves, and materials save as they change.

const TEST_ITEM_DATA := preload("res://database/items/test/TestItem.tres")

# Window layout in the 1920x1080 viewport: equipment left, cargo middle,
# stash right. Windows can still be moved and resized.
const EQUIPMENT_RECT := Rect2(90, 40, 460, 820)
const CARGO_RECT := Rect2(580, 40, 560, 620)
const STASH_RECT := Rect2(1170, 40, 700, 900)

@onready var player_mecha: Mecha = $Mecha
@onready var materials_label: Label = $MarginContainer/VBoxContainer/MaterialsLabel

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
	_open_windows()

	PlayerProgress.materials_changed.connect(_on_materials_changed)
	_on_materials_changed(PlayerProgress.get_materials())


func _exit_tree() -> void:
	MechOS.close_all()
	MechOS.recycling_enabled = false
	MechOS.set_player(null)


func _open_windows() -> void:
	_place(MechOS.open_equipment(player_mecha), EQUIPMENT_RECT)
	_place(MechOS.open_inventory("mech_cargo", player_mecha.mech_inventory, "MECH CARGO"), CARGO_RECT)
	_place(MechOS.open_inventory("stash", stash_inventory, "STASH"), STASH_RECT)


# The Hangar is these three windows, so they stay open.
func _place(window: MechWindow, rect: Rect2) -> void:
	if window == null:
		return
	window.closable = false
	window.position = rect.position
	window.size = rect.size.max(window.min_size)


func _on_cargo_overflow(stacks: Array) -> void:
	for stack in stacks:
		if not stash_inventory.add_stack_anywhere(stack):
			push_warning("Hangar: no room in the stash for an item pushed out of the cargo; it was lost.")
	MechOS.refresh_inventory_windows()


func _on_materials_changed(materials: Dictionary) -> void:
	var parts := []
	for material_id in Materials.ids():
		parts.append("%s %d" % [Materials.display_name(material_id), int(materials.get(material_id, 0))])
	materials_label.text = "MATERIALS   " + "   ".join(parts)


func _on_BackButton_pressed() -> void:
	PlayerProgress.set_stash_inventory(stash_inventory)
	PlayerProgress.set_mech_inventory(player_mecha.mech_inventory)
	PlayerProgress.set_current_mecha(player_mecha.get_design_data())  # also saves the profile
	TransitionManager.transition_to(
		"res://game/start_menu/StartMenu.tscn",
		"Leaving Hangar..."
	)


func _unhandled_input(event):
	if not player_mecha or not player_mecha.mech_inventory:
		return

	if event.is_action_pressed("debug_6"):
		player_mecha.mech_inventory.add_item(TEST_ITEM_DATA, 1)
		MechOS.refresh_inventory_windows()
		get_viewport().set_input_as_handled()
