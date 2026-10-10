extends Node

# LootTableTest runs self-checks on the loot data: tech tiers, LootTable rolls
# and rarity, LootEntry parts (for weapon drops later), LootContainer random
# contents, and salvage/parts surviving a save in the cargo.
# Open LootTableTest.tscn and press F6; results print to Output, along with
# the tier spread of a large batch of rolls.
#
# Rolls use a seeded RandomNumberGenerator so results are the same every run.
# The player's real progress is snapshotted and restored, and autosave is off
# while the checks run, so the profile is never touched.

const WRECK_SALVAGE := preload("res://database/loot-tables/wreck_salvage.tres")
const LOW_ITEM := preload("res://database/items/salvage/scrap_plating.tres")
const HIGH_ITEM := preload("res://database/items/salvage/fusion_cell.tres")
const LOOT_CONTAINER := preload("res://game/mecha/LootContainer.tscn")

# Matches the weapon in PlayerProgress.DEFAULT_MECHA.
const TEST_WEAPON_TYPE := "arm_weapon"
const TEST_WEAPON_ID := "MA-L127"

const SPREAD_ROLLS := 10000

var _passed := 0
var _failed := 0


func _ready() -> void:
	var saved_state = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.autosave = false

	_run("salvage items have tiers", _test_salvage_tiers)
	_run("tier chances", _test_tier_chances)
	_run("roll spread follows weights", _test_roll_spread)
	_run("empty tier falls back", _test_fallback)
	_run("empty table", _test_empty_table)
	_run("entries make fresh stacks", _test_fresh_stacks)
	_run("part entries", _test_part_entry)
	_run("container rolls its contents", _test_container)
	_run("salvage and parts survive a save in cargo", _test_cargo_save)

	PlayerProgress.set_save_data(saved_state)
	PlayerProgress.autosave = true

	print("[LootTableTest] %d passed, %d failed" % [_passed, _failed])


func _run(test_name: String, test: Callable) -> void:
	PlayerProgress.reset()
	var failures_before := _failed
	test.call()
	if _failed == failures_before:
		print("  PASS ", test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("[LootTableTest] FAIL " + message)


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	return rng


func _test_salvage_tiers() -> void:
	for tier in LootTable.ROLLED_TIERS:
		_check(not WRECK_SALVAGE.get_entries_of_tier(tier).is_empty(),
				"wreck_salvage has items of tier %d" % tier)
	for entry in WRECK_SALVAGE.entries:
		_check(entry.get_tech_tier() != item_data.TechTier.NONE,
				"%s has a tech tier" % entry.item.id)
		_check("salvage" in entry.item.tags, "%s is tagged salvage" % entry.item.id)


func _test_tier_chances() -> void:
	var chances: Dictionary = WRECK_SALVAGE.get_tier_chances()
	_check(is_equal_approx(chances[item_data.TechTier.LOW], 0.70), "low is 70%")
	_check(is_equal_approx(chances[item_data.TechTier.MID], 0.25), "mid is 25%")
	_check(is_equal_approx(chances[item_data.TechTier.HIGH], 0.05), "high is 5%")


func _test_roll_spread() -> void:
	var rng := _seeded_rng()
	var counts := {item_data.TechTier.LOW: 0, item_data.TechTier.MID: 0, item_data.TechTier.HIGH: 0}
	for _i in SPREAD_ROLLS:
		var entry: LootEntry = WRECK_SALVAGE.roll_entry(rng)
		counts[entry.get_tech_tier()] += 1
	var low := float(counts[item_data.TechTier.LOW]) / SPREAD_ROLLS
	var mid := float(counts[item_data.TechTier.MID]) / SPREAD_ROLLS
	var high := float(counts[item_data.TechTier.HIGH]) / SPREAD_ROLLS
	print("    %d rolls: low %.1f%%, mid %.1f%%, high %.1f%%" % [SPREAD_ROLLS, low * 100, mid * 100, high * 100])
	_check(absf(low - 0.70) < 0.03, "low close to 70%")
	_check(absf(mid - 0.25) < 0.03, "mid close to 25%")
	_check(absf(high - 0.05) < 0.015, "high close to 5%")
	_check(high < mid and mid < low, "rarer as tech rises")


func _test_fallback() -> void:
	# Only a low item, but every roll wants high tech.
	var table := LootTable.new()
	table.entries.append(_entry(LOW_ITEM))
	table.low_weight = 0.0
	table.mid_weight = 0.0
	table.high_weight = 100.0
	var rng := _seeded_rng()
	var entry := table.roll_entry(rng)
	_check(entry != null and entry.item == LOW_ITEM, "high roll steps down to low")

	# Only a high item, every roll wants low tech.
	table = LootTable.new()
	table.entries.append(_entry(HIGH_ITEM))
	table.low_weight = 100.0
	table.mid_weight = 0.0
	table.high_weight = 0.0
	entry = table.roll_entry(rng)
	_check(entry != null and entry.item == HIGH_ITEM, "low roll steps up to high")


func _test_empty_table() -> void:
	var table := LootTable.new()
	_check(table.roll_entry() == null, "no entry from an empty table")
	_check(table.roll_stacks(3).is_empty(), "no stacks from an empty table")


func _test_fresh_stacks() -> void:
	var entry := _entry(LOW_ITEM, 2)
	var a := entry.make_stack()
	var b := entry.make_stack()
	_check(a != null and a != b, "each make_stack is a new stack")
	_check(a.kind == item_stack.ItemKind.GENERIC and a.item == LOW_ITEM, "generic stack holds the item")
	_check(a.quantity == 2, "quantity carried over")
	_check(a.width_cells() == 2 and a.height_cells() == 1, "size comes from item_size")
	_check(not _entry(null).is_valid(), "entry with nothing set is invalid")


func _test_part_entry() -> void:
	var entry := LootEntry.new()
	entry.part_type = TEST_WEAPON_TYPE
	entry.part_id = TEST_WEAPON_ID
	_check(entry.is_part() and entry.is_valid(), "weapon entry is valid")
	_check(entry.get_tech_tier() == item_data.TechTier.NONE, "parts have no tier")

	var stack := entry.make_stack()
	_check(stack != null and stack.kind == item_stack.ItemKind.PART, "makes a part stack")
	_check(stack.item_type == TEST_WEAPON_TYPE and stack.item_id == TEST_WEAPON_ID, "part stack keeps type and id")
	_check(stack.width_cells() == 3 and stack.height_cells() == 2, "weapon size resolved through PartManager")

	var bad := LootEntry.new()
	bad.part_type = TEST_WEAPON_TYPE
	bad.part_id = "NOT-A-WEAPON"
	_check(not bad.is_valid() and bad.make_stack() == null, "unknown part is invalid")

	# Tier rolls never hand out parts.
	var table := LootTable.new()
	table.entries.append(entry)
	_check(table.roll_entry() == null, "table skips part entries")


func _test_container() -> void:
	var container: LootContainer = LOOT_CONTAINER.instantiate()
	container.default_contents = []  # the scene ships with a test item
	container.grid_width = 8
	container.grid_height = 8
	container.loot_table = WRECK_SALVAGE
	container.loot_rolls = 3
	add_child(container)
	_check(_count_stacks(container.inventory) == 3, "3 rolled items placed")

	var weapon := LootEntry.new()
	weapon.part_type = TEST_WEAPON_TYPE
	weapon.part_id = TEST_WEAPON_ID
	container.populate([weapon])
	_check(_count_stacks(container.inventory) == 4, "part entry placed in a container")
	container.queue_free()


func _test_cargo_save() -> void:
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 6)
	cargo.add_stack_to_first_available_slot(_entry(HIGH_ITEM).make_stack())
	var weapon := LootEntry.new()
	weapon.part_type = TEST_WEAPON_TYPE
	weapon.part_id = TEST_WEAPON_ID
	cargo.add_stack_to_first_available_slot(weapon.make_stack())
	PlayerProgress.set_mech_inventory(cargo)

	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))

	var found_salvage := false
	var found_weapon := false
	var restored := PlayerProgress.get_mech_inventory()
	for stack in _stacks(restored):
		if stack.kind == item_stack.ItemKind.GENERIC and stack.item == HIGH_ITEM:
			found_salvage = stack.item.tech_tier == item_data.TechTier.HIGH
		elif stack.kind == item_stack.ItemKind.PART and stack.item_id == TEST_WEAPON_ID:
			found_weapon = stack.item_type == TEST_WEAPON_TYPE
	_check(found_salvage, "salvage restored with its tier")
	_check(found_weapon, "weapon part restored with type and id")


# ---- Helpers ----

func _entry(item: item_data, quantity := 1) -> LootEntry:
	var entry := LootEntry.new()
	entry.item = item
	entry.quantity = quantity
	return entry


func _stacks(inv: Inventory) -> Array:
	var stacks := []
	if inv == null:
		return stacks
	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell = inv.grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				stacks.append(cell["stack"])
	return stacks


func _count_stacks(inv: Inventory) -> int:
	return _stacks(inv).size()
