extends TestSuite

# WreckTest: Expedition wrecks. What WreckLoot rolls for a destroyed mecha
# (per-part salvage pools, weapon drops), moving stacks between inventories
# (Take / Take all), part weights in cargo, the Wreck states, and the Mech OS
# "Take" actions. Prints the average salvage and weapons per wreck.
#
# Rolls use a seeded RandomNumberGenerator so results are the same every run.

const WRECK := preload("res://game/mecha/Wreck.tscn")
const LOW_ITEM := preload("res://database/items/salvage/armor_plate_fragment.tres")   # 2x1
const HIGH_ITEM := preload("res://database/items/salvage/damaged_nt_engine.tres")    # 2x2

const DESIGN_ROLLS := 5000


# Stands in for a mecha: Wreck/LootContainer only ask is_player().
class FakeMecha extends Node:
	var player := false
	var mech_inventory: Inventory = null
	func is_player() -> bool:
		return player


func run_tests() -> void:
	await case("salvage chance per part", _test_salvage_chance)
	await case("average salvage per wreck", _test_salvage_average)
	await case("salvage pools per part type", _test_part_pools)
	await case("salvage comes from the part's pool", _test_salvage_by_part)
	await case("pool tier spread", _test_pool_tiers)
	await case("weapon drops", _test_weapon_drops)
	await case("weapon drops when switched on", _test_weapons_on)
	await case("transfer between inventories", _test_transfer)
	await case("transfer turns items to fit", _test_transfer_rotates)
	await case("part weight in cargo", _test_part_weight)
	await case("wreck states", _test_wreck_states)
	await case("NPC visits don't lock a container", _test_npc_visit)
	await case("Mech OS take actions", _test_take_actions)


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
	check(always.size() == _equipped_count(design), "chance 1 gives one item per equipped part")
	for stack in always:
		check(stack.kind == item_stack.ItemKind.GENERIC and stack.item.tech_tier != item_data.TechTier.NONE,
				"salvage is tiered generic loot")
	check(WreckLoot.roll(design, rng, 0.0, 0.0).is_empty(), "chance 0 gives nothing")
	check(WreckLoot.roll({"head": false, "core": false}, rng, 1.0, 0.0).is_empty(), "empty slots give nothing")


func _test_salvage_average() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	var rng := _seeded_rng()
	var total := 0
	for _i in DESIGN_ROLLS:
		total += WreckLoot.roll(design, rng, WreckLoot.SALVAGE_CHANCE, 0.0).size()
	var average := float(total) / DESIGN_ROLLS
	var expected := WreckLoot.SALVAGE_CHANCE * _equipped_count(design)
	print("    %d wrecks of the default mecha: %.2f salvage each (expected %.2f)" % [DESIGN_ROLLS, average, expected])
	check(absf(average - expected) < 0.1, "average close to 30% per part")


func _items_of(table: LootTable) -> Array:
	return table.entries.map(func(e): return e.item)


func _test_part_pools() -> void:
	var covered := {}
	for slot in PlayerProgress.DEFAULT_MECHA:
		var table := WreckLoot.table_for_slot(slot)
		check(table != WreckLoot.SALVAGE_TABLE, "%s has its own salvage pool" % slot)
		check(not table.get_entries_of_tier(item_data.TechTier.LOW).is_empty(), "%s pool has low-tech salvage" % slot)
		for item in _items_of(table):
			check(item in _items_of(WreckLoot.SALVAGE_TABLE), "%s pool item %s is wreck salvage" % [slot, item.id])
			covered[item] = true
	for item in _items_of(WreckLoot.SALVAGE_TABLE):
		check(covered.has(item), "%s drops from some part" % item.id)
	check(WreckLoot.table_for_slot("arm_weapon_left") == WreckLoot.table_for_slot("shoulder_weapon_right"),
			"arm and shoulder weapons share a pool")
	check(WreckLoot.table_for_slot("not_a_part") == WreckLoot.SALVAGE_TABLE, "unknown part types roll from everything")


# A design with only the given slots filled.
func _only(slots: Dictionary) -> Dictionary:
	var design := {}
	for slot in PlayerProgress.DEFAULT_MECHA:
		design[slot] = slots.get(slot, false)
	return design


func _test_salvage_by_part() -> void:
	var rng := _seeded_rng()
	for slot in ["generator", "head", "chassis", "core", "thruster", "arm_weapon_left"]:
		var pool := _items_of(WreckLoot.table_for_slot(slot))
		var design := _only({slot: PlayerProgress.DEFAULT_MECHA.get(slot, "X")})
		var stray := 0
		for _i in 300:
			for stack in WreckLoot.roll(design, rng, 1.0, 0.0):
				if not stack.item in pool:
					stray += 1
		check(stray == 0, "a wreck with only a %s drops from its pool" % slot)
	# A table passed in still overrides the pools (tests and special wrecks).
	var only_low := LootTable.new()
	var entry := LootEntry.new()
	entry.item = LOW_ITEM
	only_low.entries.append(entry)
	var stacks := WreckLoot.roll(PlayerProgress.DEFAULT_MECHA.duplicate(), rng, 1.0, 0.0, only_low)
	check(not stacks.is_empty() and stacks.all(func(s): return s.item == LOW_ITEM), "a given table overrides the pools")


func _test_pool_tiers() -> void:
	var rng := _seeded_rng()
	var rolls := 4000
	# Full pool: about 70 / 25 / 5.
	var counts := {item_data.TechTier.LOW: 0, item_data.TechTier.MID: 0, item_data.TechTier.HIGH: 0}
	var frame := WreckLoot.table_for_slot("chassis")
	for _i in rolls:
		counts[frame.roll_stack(rng).item.tech_tier] += 1
	print("    chassis pool over %d rolls: low %d, mid %d, high %d" % [rolls, counts[1], counts[2], counts[3]])
	check(absf(counts[item_data.TechTier.LOW] / float(rolls) - 0.70) < 0.03, "about 70% low tech")
	check(absf(counts[item_data.TechTier.HIGH] / float(rolls) - 0.05) < 0.015, "about 5% high tech")
	# No high-tech item in the pool: high rolls give mid instead.
	var core := WreckLoot.table_for_slot("core")
	var high := 0
	for _i in 1000:
		if core.roll_stack(rng).item.tech_tier == item_data.TechTier.HIGH:
			high += 1
	check(high == 0, "core pool never gives high tech")


func _test_weapon_drops() -> void:
	check(WreckLoot.WEAPON_DROP_CHANCE == 0.2, "WEAPON_DROP_CHANCE is 20%")
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()  # MA-L127 on both arms
	var rng := _seeded_rng()
	var weapons := 0
	var with_weapon := 0
	for _i in DESIGN_ROLLS:
		var parts := WreckLoot.roll(design, rng).filter(func(s): return s.is_part()).size()
		weapons += parts
		if parts > 0:
			with_weapon += 1
	var per_wreck := float(weapons) / DESIGN_ROLLS
	print("    %d wrecks of the default mecha: %.2f weapons each, %.0f%% have one" % [DESIGN_ROLLS, per_wreck, 100.0 * with_weapon / DESIGN_ROLLS])
	check(absf(per_wreck - 0.4) < 0.04, "about 20% per equipped weapon")
	# A weapon that drops isn't also scrapped: with every roll succeeding,
	# the two arms give weapons and every other part gives salvage.
	var stacks := WreckLoot.roll(design, rng, 1.0, 1.0)
	var dropped := stacks.filter(func(s): return s.is_part()).size()
	check(dropped == 2 and stacks.size() == _equipped_count(design), "a dropped weapon replaces its salvage")


func _test_weapons_on() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()  # MA-L127 on both arms
	var stacks := WreckLoot.roll(design, _seeded_rng(), 0.0, 1.0)
	check(stacks.size() == 2, "one drop per equipped weapon")
	for stack in stacks:
		check(stack.kind == item_stack.ItemKind.PART and stack.item_type == "arm_weapon"
				and stack.item_id == "MA-L127", "weapon drops as its own part")


# ---- Inventory transfers ----

func _test_transfer() -> void:
	var source := _inventory(4, 4)
	var target := _inventory(2, 2)
	var big := item_stack.from_generic(HIGH_ITEM)   # 2x2, fills target
	var small := item_stack.from_generic(LOW_ITEM)  # 2x1
	source.place_item(big, 0, 0)
	source.place_item(small, 2, 3)

	check(source.transfer_stack_to(big, target), "stack moved")
	check(source.get_stacks().size() == 1 and target.get_stacks().size() == 1, "moved, not copied")
	check(not target.has_room_for(small), "full target has no room")
	check(not source.transfer_stack_to(small, target), "no room: not moved")
	check(source._find_origin(small) == Vector2i(2, 3) and not small.rotated, "stays in the same spot")

	var roomy := _inventory(6, 6)
	check(target.transfer_all_to(roomy) == 1 and source.transfer_all_to(roomy) == 1, "transfer_all_to counts moves")
	check(source.is_empty() and target.is_empty() and roomy.get_stacks().size() == 2, "everything moved")


func _test_transfer_rotates() -> void:
	var source := _inventory(4, 4)
	var narrow := _inventory(1, 3)  # a 2x1 only fits turned
	var stack := item_stack.from_generic(LOW_ITEM)
	source.place_item(stack, 0, 0)
	check(narrow.has_room_for(stack) and not stack.rotated, "has_room_for checks both ways without turning")
	check(source.transfer_stack_to(stack, narrow), "turned to fit")
	check(stack.rotated and stack.width_cells() == 1, "stored turned")


func _test_part_weight() -> void:
	var weapon := WreckLoot.weapon_stack("arm_weapon_left", "MA-L127")
	var expected := float(PartManager.get_part("arm_weapon", "MA-L127").weight)
	check(is_equal_approx(weapon.get_unit_weight(), expected), "part weighs what the part does")
	var cargo := _inventory(6, 6)
	cargo.add_stack_anywhere(weapon)
	cargo.add_stack_anywhere(item_stack.from_generic(HIGH_ITEM))
	check(is_equal_approx(cargo.get_current_weight(), expected + HIGH_ITEM.weight), "cargo weight counts parts and salvage")


# ---- Wreck ----

func _make_wreck(stacks: Array) -> Wreck:
	var wreck: Wreck = WRECK.instantiate()
	wreck.setup("Grob", stacks)
	add_child(wreck)
	return wreck


func _test_wreck_states() -> void:
	var wreck := _make_wreck([item_stack.from_generic(LOW_ITEM), item_stack.from_generic(HIGH_ITEM)])
	check(wreck.inventory.get_stacks().size() == 2, "rolled stacks placed")
	check(wreck.display_name == "WRECK - GROB", "titled after the mecha")
	check(wreck.is_in_group("wreck") and wreck.is_in_group("loot_container"), "in the wreck and loot groups")
	check(wreck.state == Wreck.State.UNSEARCHED and wreck.get_node("Marker").visible, "starts unsearched with a marker")

	var player := FakeMecha.new()
	player.player = true
	wreck.interact(player)
	check(wreck.is_open and wreck.state == Wreck.State.SEARCHED, "opening searches it")
	check(not wreck.get_node("Marker").visible, "marker gone once searched")
	wreck.close()
	check(wreck.state == Wreck.State.SEARCHED, "still searched while items remain")

	wreck.interact(player)
	wreck.inventory.transfer_all_to(_inventory(6, 6))
	wreck.close()
	check(wreck.state == Wreck.State.EMPTY, "empty once cleared")
	check(wreck.get_node("Hull").modulate == Wreck.EMPTY_TINT, "empty wreck goes darker")
	player.free()
	wreck.queue_free()


func _test_npc_visit() -> void:
	var wreck := _make_wreck([item_stack.from_generic(LOW_ITEM)])
	var npc := FakeMecha.new()
	wreck.interact(npc)
	check(wreck.npc_searched, "NPC visit recorded")
	check(not wreck.is_open, "NPC visit doesn't open it")
	check(wreck.state == Wreck.State.UNSEARCHED, "still unsearched for the player")
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
	check(not take.is_empty() and not take_all.is_empty(), "take and take_all registered")

	var item_ctx := {"type": "item", "stack": high, "inventory": loot}
	check(take["visible_if"].call(item_ctx), "take shows on loot")
	check(take["enabled_if"].call(item_ctx) == "", "take enabled with room")
	take["run"].call(item_ctx)
	check(player.mech_inventory.get_stacks().has(high), "take moves the item into cargo")

	var low_ctx := {"type": "item", "stack": low, "inventory": loot}
	check(take["enabled_if"].call(low_ctx) == "NO SPACE", "take disabled when cargo is full")
	check(not take["visible_if"].call({"type": "item", "stack": high, "inventory": player.mech_inventory}),
			"no take on the cargo itself")

	player.mech_inventory = _inventory(6, 6)
	var all_ctx := {"type": "inventory", "inventory": loot}
	take_all["run"].call(all_ctx)
	check(loot.is_empty() and player.mech_inventory.get_stacks().size() == 1, "take all empties the loot")
	check(not take_all["visible_if"].call(all_ctx), "no take all on an empty inventory")

	MechOS.set_player(saved_player)
	player.free()
