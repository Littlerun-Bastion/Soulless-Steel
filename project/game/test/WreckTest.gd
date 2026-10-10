extends Node

# WreckTest runs self-checks on Expedition wrecks: what WreckLoot rolls for a
# destroyed mecha, moving stacks between inventories (Take / Take all), part
# weights in cargo, the Wreck states, and the Mech OS "Take" actions.
# Open WreckTest.tscn and press F6; results print to Output, along with the
# average salvage per wreck.
#
# Rolls use a seeded RandomNumberGenerator so results are the same every run.
# Nothing here touches the player's progress.

const WRECK := preload("res://game/mecha/Wreck.tscn")
const LOW_ITEM := preload("res://database/items/salvage/scrap_plating.tres")   # 2x1
const HIGH_ITEM := preload("res://database/items/salvage/fusion_cell.tres")    # 2x2

const DESIGN_ROLLS := 5000

var _passed := 0
var _failed := 0


# Stands in for a mecha: Wreck/LootContainer only ask is_player().
class FakeMecha extends Node:
	var player := false
	var mech_inventory: Inventory = null
	func is_player() -> bool:
		return player


func _ready() -> void:
	_run("salvage chance per part", _test_salvage_chance)
	_run("average salvage per wreck", _test_salvage_average)
	_run("weapon drops are off by default", _test_weapons_off)
	_run("weapon drops when switched on", _test_weapons_on)
	_run("transfer between inventories", _test_transfer)
	_run("transfer turns items to fit", _test_transfer_rotates)
	_run("part weight in cargo", _test_part_weight)
	_run("wreck states", _test_wreck_states)
	_run("NPC visits don't lock a container", _test_npc_visit)
	_run("Mech OS take actions", _test_take_actions)
	print("[WreckTest] %d passed, %d failed" % [_passed, _failed])


func _run(test_name: String, test: Callable) -> void:
	var failures_before := _failed
	test.call()
	if _failed == failures_before:
		print("  PASS ", test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("[WreckTest] FAIL " + message)


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	return rng


func _equipped_count(design: Dictionary) -> int:
	var n := 0
	for slot in design:
		if typeof(design[slot]) == TYPE_STRING and design[slot] != "":
			n += 1
	return n


func _inventory(w: int, h: int) -> Inventory:
	var inv := Inventory.new()
	inv.initialize_grid(w, h)
	return inv


# ---- WreckLoot ----

func _test_salvage_chance() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	var rng := _seeded_rng()
	var always := WreckLoot.roll(design, rng, 1.0, 0.0)
	_check(always.size() == _equipped_count(design), "chance 1 gives one item per equipped part")
	for stack in always:
		_check(stack.kind == item_stack.ItemKind.GENERIC and stack.item.tech_tier != item_data.TechTier.NONE,
				"salvage is tiered generic loot")
	_check(WreckLoot.roll(design, rng, 0.0, 0.0).is_empty(), "chance 0 gives nothing")
	_check(WreckLoot.roll({"head": false, "core": false}, rng, 1.0, 0.0).is_empty(), "empty slots give nothing")


func _test_salvage_average() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	var rng := _seeded_rng()
	var total := 0
	for _i in DESIGN_ROLLS:
		total += WreckLoot.roll(design, rng).size()
	var average := float(total) / DESIGN_ROLLS
	var expected := WreckLoot.SALVAGE_CHANCE * _equipped_count(design)
	print("    %d wrecks of the default mecha: %.2f salvage each (expected %.2f)" % [DESIGN_ROLLS, average, expected])
	_check(absf(average - expected) < 0.1, "average close to 30% per part")


func _test_weapons_off() -> void:
	_check(WreckLoot.WEAPON_DROP_CHANCE == 0.0, "WEAPON_DROP_CHANCE is 0")
	var rng := _seeded_rng()
	var parts := 0
	for _i in 500:
		for stack in WreckLoot.roll(PlayerProgress.DEFAULT_MECHA.duplicate(), rng):
			if stack.kind == item_stack.ItemKind.PART:
				parts += 1
	_check(parts == 0, "no weapons drop")


func _test_weapons_on() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()  # MA-L127 on both arms
	var stacks := WreckLoot.roll(design, _seeded_rng(), 0.0, 1.0)
	_check(stacks.size() == 2, "one drop per equipped weapon")
	for stack in stacks:
		_check(stack.kind == item_stack.ItemKind.PART and stack.item_type == "arm_weapon"
				and stack.item_id == "MA-L127", "weapon drops as its own part")


# ---- Inventory transfers ----

func _test_transfer() -> void:
	var source := _inventory(4, 4)
	var target := _inventory(2, 2)
	var big := item_stack.from_generic(HIGH_ITEM)   # 2x2, fills target
	var small := item_stack.from_generic(LOW_ITEM)  # 2x1
	source.place_item(big, 0, 0)
	source.place_item(small, 2, 3)

	_check(source.transfer_stack_to(big, target), "stack moved")
	_check(source.get_stacks().size() == 1 and target.get_stacks().size() == 1, "moved, not copied")
	_check(not target.has_room_for(small), "full target has no room")
	_check(not source.transfer_stack_to(small, target), "no room: not moved")
	_check(source._find_origin(small) == Vector2i(2, 3) and not small.rotated, "stays in the same spot")

	var roomy := _inventory(6, 6)
	_check(target.transfer_all_to(roomy) == 1 and source.transfer_all_to(roomy) == 1, "transfer_all_to counts moves")
	_check(source.is_empty() and target.is_empty() and roomy.get_stacks().size() == 2, "everything moved")


func _test_transfer_rotates() -> void:
	var source := _inventory(4, 4)
	var narrow := _inventory(1, 3)  # a 2x1 only fits turned
	var stack := item_stack.from_generic(LOW_ITEM)
	source.place_item(stack, 0, 0)
	_check(narrow.has_room_for(stack) and not stack.rotated, "has_room_for checks both ways without turning")
	_check(source.transfer_stack_to(stack, narrow), "turned to fit")
	_check(stack.rotated and stack.width_cells() == 1, "stored turned")


func _test_part_weight() -> void:
	var weapon := WreckLoot.weapon_stack("arm_weapon_left", "MA-L127")
	var expected := float(PartManager.get_part("arm_weapon", "MA-L127").weight)
	_check(is_equal_approx(weapon.get_unit_weight(), expected), "part weighs what the part does")
	var cargo := _inventory(6, 6)
	cargo.add_stack_anywhere(weapon)
	cargo.add_stack_anywhere(item_stack.from_generic(HIGH_ITEM))
	_check(is_equal_approx(cargo.get_current_weight(), expected + HIGH_ITEM.weight), "cargo weight counts parts and salvage")


# ---- Wreck ----

func _make_wreck(stacks: Array) -> Wreck:
	var wreck: Wreck = WRECK.instantiate()
	wreck.setup("Grob", stacks)
	add_child(wreck)
	return wreck


func _test_wreck_states() -> void:
	var wreck := _make_wreck([item_stack.from_generic(LOW_ITEM), item_stack.from_generic(HIGH_ITEM)])
	_check(wreck.inventory.get_stacks().size() == 2, "rolled stacks placed")
	_check(wreck.display_name == "WRECK - GROB", "titled after the mecha")
	_check(wreck.is_in_group("wreck") and wreck.is_in_group("loot_container"), "in the wreck and loot groups")
	_check(wreck.state == Wreck.State.UNSEARCHED and wreck.get_node("Marker").visible, "starts unsearched with a marker")

	var player := FakeMecha.new()
	player.player = true
	wreck.interact(player)
	_check(wreck.is_open and wreck.state == Wreck.State.SEARCHED, "opening searches it")
	_check(not wreck.get_node("Marker").visible, "marker gone once searched")
	wreck.close()
	_check(wreck.state == Wreck.State.SEARCHED, "still searched while items remain")

	wreck.interact(player)
	wreck.inventory.transfer_all_to(_inventory(6, 6))
	wreck.close()
	_check(wreck.state == Wreck.State.EMPTY, "empty once cleared")
	_check(wreck.get_node("Hull").modulate == Wreck.EMPTY_TINT, "empty wreck goes darker")
	player.free()
	wreck.queue_free()


func _test_npc_visit() -> void:
	var wreck := _make_wreck([item_stack.from_generic(LOW_ITEM)])
	var npc := FakeMecha.new()
	wreck.interact(npc)
	_check(wreck.npc_searched, "NPC visit recorded")
	_check(not wreck.is_open, "NPC visit doesn't open it")
	_check(wreck.state == Wreck.State.UNSEARCHED, "still unsearched for the player")
	npc.free()
	wreck.queue_free()


# ---- Mech OS actions ----

func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


func _test_take_actions() -> void:
	var saved_player = MechOS.player_ref
	var player := FakeMecha.new()
	player.mech_inventory = _inventory(2, 2)
	MechOS.set_player(player)

	var loot := _inventory(6, 6)
	var high := item_stack.from_generic(HIGH_ITEM)  # 2x2: fills the cargo
	var low := item_stack.from_generic(LOW_ITEM)
	loot.place_item(high, 0, 0)
	loot.place_item(low, 3, 0)

	var take := _action("item", "take")
	var take_all := _action("inventory", "take_all")
	_check(not take.is_empty() and not take_all.is_empty(), "take and take_all registered")

	var item_ctx := {"type": "item", "stack": high, "inventory": loot}
	_check(take["visible_if"].call(item_ctx), "take shows on loot")
	_check(take["enabled_if"].call(item_ctx) == "", "take enabled with room")
	take["run"].call(item_ctx)
	_check(player.mech_inventory.get_stacks().has(high), "take moves the item into cargo")

	var low_ctx := {"type": "item", "stack": low, "inventory": loot}
	_check(take["enabled_if"].call(low_ctx) == "NO SPACE", "take disabled when cargo is full")
	_check(not take["visible_if"].call({"type": "item", "stack": high, "inventory": player.mech_inventory}),
			"no take on the cargo itself")

	player.mech_inventory = _inventory(6, 6)
	var all_ctx := {"type": "inventory", "inventory": loot}
	take_all["run"].call(all_ctx)
	_check(loot.is_empty() and player.mech_inventory.get_stacks().size() == 1, "take all empties the loot")
	_check(not take_all["visible_if"].call(all_ctx), "no take all on an empty inventory")

	MechOS.set_player(saved_player)
	player.free()
