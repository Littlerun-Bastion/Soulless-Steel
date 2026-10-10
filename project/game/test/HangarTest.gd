extends Node

# HangarTest loads the real Hangar (HangarScreen.tscn, built on Mech OS) and
# checks it end to end: its three windows, recycling, swapping parts, a
# smaller core pushing cargo into the stash, and cleaning up Mech OS on exit.
# Open HangarTest.tscn and press F6; results print to Output.
#
# The player's real progress is snapshotted and restored, and autosave is off
# while the checks run, so the profile is never touched.

const HANGAR := preload("res://game/ui/HangarScreen.tscn")
const SCRAP := preload("res://database/items/salvage/scrap_plating.tres")   # 3 scrap_metal, 2x1

var _passed := 0
var _failed := 0


func _ready() -> void:
	var saved_state = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.autosave = false
	PlayerProgress.reset()

	await _run_hangar_checks()
	_test_resize_overflow()

	PlayerProgress.set_save_data(saved_state)
	PlayerProgress.autosave = true
	print("[HangarTest] %d passed, %d failed" % [_passed, _failed])


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("[HangarTest] FAIL " + message)


func _pass(test_name: String, failures_before: int) -> void:
	if _failed == failures_before:
		print("  PASS ", test_name)


func _run_hangar_checks() -> void:
	PlayerProgress.get_stash_inventory().add_stack_anywhere(item_stack.from_generic(SCRAP))
	var hangar = HANGAR.instantiate()
	add_child(hangar)
	await get_tree().process_frame

	var before := _failed
	for app_id in ["equipment", "mech_cargo", "stash"]:
		_check(MechOS.open_windows.has(app_id), "%s window open" % app_id)
		if MechOS.open_windows.has(app_id):
			_check(not MechOS.open_windows[app_id].closable, "%s window can't be closed" % app_id)
	var equipment = MechOS.open_windows.get("equipment")
	_check(equipment != null and equipment.can_customize, "equipment editable in the Hangar")
	_check(MechOS.recycling_enabled, "recycling enabled in the Hangar")
	MechOS.toggle_app("equipment")
	_check(MechOS.open_windows.has("equipment"), "taskbar toggle doesn't close the Hangar's equipment")
	_pass("Hangar windows", before)

	before = _failed
	var stash := PlayerProgress.get_stash_inventory()
	var scrap: item_stack = stash.get_stacks()[0]
	var recycle := _action("item", "recycle")
	var ctx := {"type": "item", "stack": scrap, "inventory": stash, "recycle_allowed": MechOS.recycling_enabled}
	_check(recycle["visible_if"].call(ctx), "Recycle offered on stash salvage")
	recycle["run"].call(ctx)
	_check(PlayerProgress.get_material_count("scrap_metal") == 3, "recycled into materials")
	_check("Scrap Metal 3" in hangar.materials_label.text, "materials line updated")
	_pass("recycling in the Hangar", before)

	before = _failed
	_test_swap_returns_to_stash(hangar, equipment)
	_pass("swapped-out part goes to the stash", before)

	before = _failed
	_test_smaller_core(hangar, equipment)
	_pass("smaller core moves cargo to the stash", before)

	before = _failed
	hangar.queue_free()
	await get_tree().process_frame
	_check(MechOS.open_windows.is_empty(), "leaving closes the Hangar's windows")
	_check(not MechOS.recycling_enabled, "recycling off again after leaving")
	_check(MechOS.player_ref == null, "Mech OS forgets the Hangar mecha")
	_pass("leaving the Hangar", before)


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
	_check(equipment.try_equip(_slot(equipment, "head"), stack), "equip a different head")
	_check(mecha.build.head.part_id == new_head, "new head equipped")
	_check(PlayerProgress.count_part("head", old_head) == 1, "old head went to the stash")


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
	_check(equipment.try_equip(_slot(equipment, "core"), equipment.make_part_stack("core", biggest)), "equip the biggest core")
	var current: Array = mecha.build.core.cargo_space
	# Fill the cargo so some of it can't fit the smaller core.
	while cargo.add_stack_anywhere(item_stack.from_generic(SCRAP)):
		pass
	var stash := PlayerProgress.get_stash_inventory()
	var total_before := cargo.get_stacks().size() + stash.get_stacks().size()
	_check(equipment.try_equip(_slot(equipment, "core"), equipment.make_part_stack("core", smaller)), "equip a smaller core")
	var total_after := cargo.get_stacks().size() + stash.get_stacks().size()
	_check(cargo.grid_width * cargo.grid_height < current[0] * current[1], "cargo shrank")
	# +1: the old core went to the stash too.
	_check(total_after == total_before + 1, "nothing lost: overflow is in the stash (%d -> %d)" % [total_before, total_after])


func _area(space: Array) -> int:
	return int(space[0]) * int(space[1])


# Inventory level: resize_and_migrate keeps what fits and returns the rest.
func _test_resize_overflow() -> void:
	var before := _failed
	var inv := Inventory.new()
	inv.initialize_grid(4, 4)
	for _i in 8:
		inv.add_stack_anywhere(item_stack.from_generic(SCRAP))  # 2x1 each, fills 4x4
	var overflow: Array = inv.resize_and_migrate(2, 2)
	_check(inv.get_stacks().size() == 2, "what fits is kept")
	_check(overflow.size() == 6, "the rest is returned, not dropped")
	_pass("cargo resize returns overflow", before)
