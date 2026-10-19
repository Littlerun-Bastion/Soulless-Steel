extends TestSuite

# GameLoopTest follows one player's things through the core loop on the real
# screens, the way the game hands them over between scenes (PlayerProgress):
#   Hangar: equip a weapon from the stash, pack salvage into the cargo, leave
#   Expedition: start with exactly that, loot a wreck, extract
#   Hangar again: the loot is there and recycles into materials
#
# Scene changes are captured, not performed: each screen is opened by the
# test after the previous one asked to leave.

const HANGAR := preload("res://game/ui/HangarScreen.tscn")
const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const SALVAGE := preload("res://database/items/salvage/hydraulic_actuator.tres")   # 2 steel, 2 oil
const LOOT := preload("res://database/items/salvage/circuit_board.tres")           # 2 silicon, 1 copper
const NEW_WEAPON := "Clarent-01"

var _saved_skip_intro = null


func _init() -> void:
	slow = true
	time_scale = 2.0


func run_tests() -> void:
	_saved_skip_intro = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true
	PlayerProgress.reset()
	PlayerProgress.add_part("arm_weapon", NEW_WEAPON, false)
	PlayerProgress.get_stash_inventory().add_stack_anywhere(item_stack.from_generic(SALVAGE))

	await case("Hangar: fit a weapon and pack the cargo", _test_hangar_out)
	await case("Expedition: deploy with it, loot, extract", _test_expedition)
	await case("Hangar: the loot is home and recycles", _test_hangar_back)
	Debug.debug_settings["skip_intro"] = _saved_skip_intro


func _slot(equipment, part_type: String, side: int) -> PartSlot:
	for slot in equipment.part_slots:
		if slot.part_type == part_type and slot.part_side == side:
			return slot
	return null


func _stack_of(inv: Inventory, matches: Callable) -> item_stack:
	for stack in inv.get_stacks():
		if matches.call(stack):
			return stack
	return null


func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


func _test_hangar_out() -> void:
	var hangar = HANGAR.instantiate()
	add_child(hangar)
	await wait_frames()
	var equipment = MechOS.open_windows["equipment"]
	var stash := PlayerProgress.get_stash_inventory()
	var old_weapon: String = PlayerProgress.get_current_mecha()["arm_weapon_left"]

	# What a drag from the stash onto the left arm slot does.
	var weapon := _stack_of(stash, func(s): return s.is_part() and s.item_id == NEW_WEAPON)
	stash.remove_item_stack(weapon)
	check(equipment.try_equip(_slot(equipment, "arm_weapon", PartSlot.SIDE.LEFT), weapon), "weapon dropped on the left arm")
	check(PlayerProgress.count_part("arm_weapon", old_weapon) == 1, "the old weapon went to the stash")

	var salvage := _stack_of(stash, func(s): return s.item == SALVAGE)
	check(stash.transfer_stack_to(salvage, hangar.player_mecha.mech_inventory), "salvage packed into the cargo")

	hangar._on_BackButton_pressed()
	check(TransitionManager.captured.has("res://game/start_menu/StartMenu.tscn"), "ESC leaves for the main menu")
	check_eq(PlayerProgress.get_current_mecha()["arm_weapon_left"], NEW_WEAPON, "the design was saved")
	hangar.queue_free()
	await wait_frames(2)


func _test_expedition() -> void:
	TransitionManager.captured.clear()
	var scene = EXPEDITION.instantiate()
	add_child(scene)
	var ready := await wait_until(func(): return scene.player != null and scene.all_mechas.size() > 1, 20.0)
	if not check(ready, "the expedition started with enemies"):
		scene.queue_free()
		return
	scene.ExpeditionDirector.set_process(false)
	var player: Mecha = scene.player
	check_eq(player.build.arm_weapon_left.part_id, NEW_WEAPON, "deployed with the fitted weapon")
	check(_stack_of(player.mech_inventory, func(s): return s.item == SALVAGE) != null, "deployed with the packed cargo")

	# Loot: a wreck with known contents, taken with Take all.
	# (Contents are set before it enters the map, as Expedition._spawn_wreck does.)
	var wreck = scene.WRECK.instantiate()
	wreck.setup("Test wreck", [item_stack.from_generic(LOOT)])
	scene.Wrecks.add_child(wreck)
	_action("inventory", "take_all")["run"].call({"type": "inventory", "inventory": wreck.inventory})
	check(_stack_of(player.mech_inventory, func(s): return s.item == LOOT) != null, "looted into the cargo")

	player.global_position = scene.get_node("Map/Exits/Exit_Test").global_position
	var extracted := await wait_until(func(): return not PlayerProgress.is_in_expedition(), 20.0)
	check(extracted, "extracted")
	for child in scene.get_children():
		if child is ExtractionSummary:
			child.continue_button.pressed.emit()
	check(TransitionManager.captured.has("res://game/start_menu/StartMenu.tscn"), "back to the main menu")
	scene.queue_free()
	await wait_frames(2)


func _test_hangar_back() -> void:
	var hangar = HANGAR.instantiate()
	add_child(hangar)
	await wait_frames()
	var cargo: Inventory = hangar.player_mecha.mech_inventory
	check(cargo == PlayerProgress.get_mech_inventory(), "the Hangar shows the saved cargo")
	check(_stack_of(cargo, func(s): return s.item == SALVAGE) != null, "the packed salvage came back")
	check(_stack_of(cargo, func(s): return s.item == LOOT) != null, "the loot came back")
	check_eq(hangar.player_mecha.build.arm_weapon_left.part_id, NEW_WEAPON, "the mecha still has the fitted weapon")

	var grid = MechOS.open_windows["mech_cargo"].inventory_grid
	_action("inventory", "recycle_all")["run"].call({"type": "inventory", "inventory": cargo, "recycle_allowed": true, "source": grid})
	check(cargo.is_empty(), "everything recycled")
	check_eq(PlayerProgress.get_materials(), {"steel": 2, "oil": 2, "silicon": 2, "copper": 1}, "into the right materials")
	hangar.queue_free()
	await wait_frames(2)
