extends Control

@onready var player_mecha: Mecha = $Mecha
@onready var inventory_ui: InventoryUI = $MarginContainer/VBoxContainer/MarginContainer/InventoryUI
@onready var materials_label: Label = $MarginContainer/VBoxContainer/MaterialsLabel

var stash_inventory: Inventory = null  # player’s stash / hangar inventory

const TEST_ITEM_DATA := preload("res://database/items/test/TestItem.tres")

func _ready() -> void:
	stash_inventory = PlayerProgress.get_stash_inventory()

	player_mecha.set_parts_from_design(PlayerProgress.get_current_mecha())

	var core_size := _get_core_inventory_size()

	var mech_inv: Inventory = PlayerProgress.get_mech_inventory()

	if mech_inv.grid_width == 0 or mech_inv.grid_height == 0 or mech_inv.grid.is_empty():
		# First-time setup
		mech_inv.initialize_grid(core_size[0], core_size[1])
	elif mech_inv.grid_width != core_size[0] or mech_inv.grid_height != core_size[1]:
		# Core changed → resize and migrate items
		mech_inv.resize_and_migrate(core_size[0], core_size[1])

	# 5) Attach inventory to this Mecha instance
	player_mecha.mech_inventory = mech_inv

	# 6) Hand everything to InventoryUI
	inventory_ui.can_customize = true
	# Right-click salvage in the cargo or stash: Recycle / Recycle all salvage.
	inventory_ui.recycle_allowed = true
	inventory_ui.setup_for_mecha(player_mecha, stash_inventory)

	PlayerProgress.materials_changed.connect(_on_materials_changed)
	_on_materials_changed(PlayerProgress.get_materials())


func _on_materials_changed(materials: Dictionary) -> void:
	var parts := []
	for material_id in Materials.ids():
		parts.append("%s %d" % [Materials.display_name(material_id), int(materials.get(material_id, 0))])
	materials_label.text = "MATERIALS   " + "   ".join(parts)


func _get_core_inventory_size() -> Array:
	# Fallback / safety size
	var default_size := [3,3]

	if not player_mecha or not player_mecha.build:
		return default_size

	var core = player_mecha.build.core
	if core == null:
		print("Using default cargo space.")
		return default_size

	if core.cargo_space:
		return core.cargo_space

	return default_size


func _on_BackButton_pressed() -> void:
	var design = player_mecha.get_design_data()

	PlayerProgress.set_stash_inventory(stash_inventory)
	PlayerProgress.set_mech_inventory(player_mecha.mech_inventory)
	PlayerProgress.set_current_mecha(design)  # also saves the profile
	TransitionManager.transition_to(
		"res://game/start_menu/StartMenu.tscn",
		"Leaving Hangar..."
	)


func _unhandled_input(event):
	if not player_mecha or not player_mecha.mech_inventory:
		return

	if event.is_action_pressed("debug_6"):
		var inv = player_mecha.mech_inventory
		inv.add_item(TEST_ITEM_DATA, 1)
		inventory_ui.refresh()
		get_viewport().set_input_as_handled()
