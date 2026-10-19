extends TestSuite

# HangarTest loads the real Hangar (HangarScreen.tscn, built on Mech OS) and
# checks it end to end: its three windows, recycling (with the Materials
# window and the high-tech confirm), the leave guard, swapping parts, a
# smaller core pushing cargo into the stash, and cleaning up Mech OS on exit.
# The cases share one Hangar, opened at the start, in order.

const HANGAR := preload("res://game/ui/HangarScreen.tscn")
const SCRAP := preload("res://database/items/salvage/armor_plate_fragment.tres")   # 3 steel, 2x1

var _hangar = null
var _equipment = null


func run_tests() -> void:
	PlayerProgress.reset()
	PlayerProgress.get_stash_inventory().add_stack_anywhere(item_stack.from_generic(SCRAP))
	_hangar = HANGAR.instantiate()
	add_child(_hangar)
	await wait_frames()
	_equipment = MechOS.open_windows.get("equipment")

	await case("Hangar windows", _test_windows)
	await case("recycling in the Hangar", _test_recycling)
	await case("high tech asks before recycling", func(): await _test_high_tech_confirm(PlayerProgress.get_stash_inventory()))
	await case("can't leave with a required part missing", func(): await _test_leave_guard(_hangar, _equipment))
	await case("swapped-out part goes to the stash", func(): _test_swap_returns_to_stash(_hangar, _equipment))
	await case("closing the game in the Hangar keeps the design", _test_close_game)
	await case("smaller core moves cargo to the stash", func(): _test_smaller_core(_hangar, _equipment))
	await case("leaving the Hangar", _test_leaving)
	await case("cargo resize returns overflow", _test_resize_overflow)


func _test_windows() -> void:
	for app_id in ["equipment", "mech_cargo", "stash"]:
		check(MechOS.open_windows.has(app_id), "%s window open" % app_id)
		if MechOS.open_windows.has(app_id):
			check(not MechOS.open_windows[app_id].closable, "%s window can't be closed" % app_id)
	check(_equipment != null and _equipment.can_customize, "equipment editable in the Hangar")
	check(MechOS.recycling_enabled, "recycling enabled in the Hangar")
	MechOS.toggle_app("equipment")
	check(MechOS.open_windows.has("equipment"), "taskbar toggle doesn't close the Hangar's equipment")


func _test_recycling() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var scrap: item_stack = stash.get_stacks()[0]
	var recycle := _action("item", "recycle")
	var ctx := {"type": "item", "stack": scrap, "inventory": stash, "recycle_allowed": MechOS.recycling_enabled}
	check(recycle["visible_if"].call(ctx) and recycle["enabled_if"].call(ctx) == "", "Recycle offered on stash salvage")
	check(recycle["label"].call(ctx) == "Recycle (3 Steel)", "label previews what it gives")
	check(recycle["confirm"].call(ctx) == "", "low tech recycles without asking")
	var menu_ids := MechOS._get_context_actions(ctx).map(func(a): return a["id"])
	check(not "take" in menu_ids and not "take_all" in menu_ids, "no looting actions on the stash")
	check(MechOS.is_app_available("materials"), "MAT on the taskbar in the Hangar")
	var materials_window = MechOS.open_app("materials")
	check(materials_window != null and materials_window.get_count_text("steel") == "0", "Materials window lists steel at 0")
	recycle["run"].call(ctx)
	check(PlayerProgress.get_material_count("steel") == 3, "recycled into materials")
	check("LOW 3" in _hangar.materials_label.text, "materials line shows the tier totals")
	check(materials_window.get_count_text("steel") == "3", "Materials window updates live")
	materials_window._show_detail(Materials.get_material("steel"))
	check(Materials.get_material("steel").description in materials_window.detail_label.text, "hovering shows the description")


func _test_leaving() -> void:
	_hangar.queue_free()
	await wait_frames()
	check(MechOS.open_windows.is_empty(), "leaving closes the Hangar's windows")
	check(not MechOS.recycling_enabled, "recycling off again after leaving")
	check(MechOS.player_ref == null, "Mech OS forgets the Hangar mecha")
	check(not MechOS.is_app_available("materials"), "MAT gone from the taskbar after leaving")


# Through the real menu: the first click only asks, the second recycles.
func _test_high_tech_confirm(stash: Inventory) -> void:
	var engine := item_stack.from_generic(load("res://database/items/salvage/damaged_nt_engine.tres"))
	stash.add_stack_anywhere(engine)
	var grid = MechOS.open_windows["stash"].inventory_grid
	var ctx := {"type": "item", "stack": engine, "inventory": stash, "recycle_allowed": true, "source": grid}
	var menu: ContextMenu = MechOS.context_menu
	menu.open([_action("item", "recycle")], ctx, Vector2(400, 400))
	var button: Button = menu._list.get_child(0)
	check(button.text == "Recycle (2 NT Fluid, 1 NT Engines)", "high-tech label previews too")
	button.pressed.emit()
	check(stash.get_stacks().has(engine) and menu.is_open(), "first click only asks")
	check(button.text.begins_with("Confirm"), "button asks to confirm")
	button.pressed.emit()
	check(not stash.get_stacks().has(engine), "second click recycles")
	check(PlayerProgress.get_material_count("nt_engines") == 1, "high-tech materials added")
	check(not menu.is_open(), "menu closes after recycling")
	await wait_frames()


func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


func _slot(equipment, part_type: String) -> PartSlot:
	for slot in equipment.part_slots:
		if slot.part_type == part_type:
			return slot
	return null


# Only the blocked path is pressed: a complete mecha would really leave.
func _test_leave_guard(hangar, equipment) -> void:
	var mecha: Mecha = hangar.player_mecha
	var core_id: String = mecha.build.core.part_id
	var saved_design := PlayerProgress.get_current_mecha().duplicate()
	check(hangar.get_missing_parts().is_empty(), "default mecha is complete")
	equipment._set_mecha_part_for_slot(_slot(equipment, "core"), null)
	equipment.refresh_slots()
	check(hangar.get_missing_parts() == ["core"], "core reported missing")
	hangar._on_BackButton_pressed()
	check(hangar.warning_label.visible and "NO CORE EQUIPPED" in hangar.warning_label.text, "warning names the empty slot")
	check(PlayerProgress.get_current_mecha() == saved_design, "incomplete design not saved")
	check(is_instance_valid(hangar) and hangar.is_inside_tree(), "still in the Hangar")
	equipment._set_mecha_part_for_slot(_slot(equipment, "core"), core_id)
	equipment.refresh_slots()
	await wait_frames()
	check(not hangar.warning_label.visible, "warning clears once the core is back")


func _test_swap_returns_to_stash(hangar, equipment) -> void:
	var mecha: Mecha = hangar.player_mecha
	var old_head: String = mecha.build.head.part_id
	var new_head := ""
	for head_id in PartManager.HEADS:
		if head_id != old_head:
			new_head = head_id
			break
	if new_head == "":
		print("    (only one head exists; swap check skipped)")
		return
	var stack: item_stack = equipment.make_part_stack("head", new_head)
	check(equipment.try_equip(_slot(equipment, "head"), stack), "equip a different head")
	check(mecha.build.head.part_id == new_head, "new head equipped")
	check(PlayerProgress.count_part("head", old_head) == 1, "old head went to the stash")
	# So a save before leaving (recycling, say) can't keep the old head in
	# both the design and the stash.
	check(PlayerProgress.get_current_mecha()["head"] == new_head, "the design PlayerProgress saves has the new head")


# Closing the window (or Alt+F4) instead of leaving with ESC used to lose the
# design. Here a part is mid-drag off the mecha when the game closes.
func _test_close_game() -> void:
	var mecha: Mecha = _hangar.player_mecha
	var head_id: String = mecha.build.head.part_id
	var stash_before := PlayerProgress.get_stash_inventory().get_stacks().size()
	_equipment._on_slot_pressed(_slot(_equipment, "head"))
	check(MechOS.drag_manager.is_dragging() and mecha.build.head == null, "head picked up off the mecha")
	check(not PlayerProgress.get_current_mecha()["head"], "the design follows the unequip")
	_hangar.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	check(not MechOS.drag_manager.is_dragging(), "closing drops the drag")
	check(mecha.build.head != null and mecha.build.head.part_id == head_id, "the head went back on the mecha")
	check(PlayerProgress.get_current_mecha() == mecha.get_design_data(), "the design is handed over to be saved")
	check(PlayerProgress.get_stash_inventory().get_stacks().size() == stash_before, "nothing duplicated or lost in the stash")
	check(PlayerProgress.get_mech_inventory() == mecha.mech_inventory, "the cargo is handed over too")


func _test_smaller_core(hangar, equipment) -> void:
	var mecha: Mecha = hangar.player_mecha
	var cargo: Inventory = mecha.mech_inventory
	# Biggest and smallest cargo among all cores.
	var biggest := ""
	var smaller := ""
	for core_id in PartManager.CORES:
		var space: Array = PartManager.get_part("core", core_id).cargo_space
		if biggest == "" or _area(space) > _area(PartManager.get_part("core", biggest).cargo_space):
			biggest = core_id
		if smaller == "" or _area(space) < _area(PartManager.get_part("core", smaller).cargo_space):
			smaller = core_id
	if _area(PartManager.get_part("core", biggest).cargo_space) == _area(PartManager.get_part("core", smaller).cargo_space):
		print("    (all cores have the same cargo space; overflow check skipped)")
		return
	check(equipment.try_equip(_slot(equipment, "core"), equipment.make_part_stack("core", biggest)), "equip the biggest core")
	var current: Array = mecha.build.core.cargo_space
	# Fill the cargo so some of it can't fit the smaller core.
	while cargo.add_stack_anywhere(item_stack.from_generic(SCRAP)):
		pass
	var stash := PlayerProgress.get_stash_inventory()
	var total_before := cargo.get_stacks().size() + stash.get_stacks().size()
	check(equipment.try_equip(_slot(equipment, "core"), equipment.make_part_stack("core", smaller)), "equip a smaller core")
	var total_after := cargo.get_stacks().size() + stash.get_stacks().size()
	check(cargo.grid_width * cargo.grid_height < current[0] * current[1], "cargo shrank")
	# +1: the old core went to the stash too.
	check(total_after == total_before + 1, "nothing lost: overflow is in the stash (%d -> %d)" % [total_before, total_after])


func _area(space: Array) -> int:
	return int(space[0]) * int(space[1])


# Inventory level: resize_and_migrate keeps what fits and returns the rest.
func _test_resize_overflow() -> void:
	var inv := Inventory.new()
	inv.initialize_grid(4, 4)
	for _i in 8:
		inv.add_stack_anywhere(item_stack.from_generic(SCRAP))  # 2x1 each, fills 4x4
	var overflow: Array = inv.resize_and_migrate(2, 2)
	check(inv.get_stacks().size() == 2, "what fits is kept")
	check(overflow.size() == 6, "the rest is returned, not dropped")
