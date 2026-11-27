extends TestSuite

# LootTableTest: the loot data. The salvage catalogue (brief section 12:
# every item's weight in tonnes, size, stack, composition in real units,
# price worth exactly its materials, and what it breaks into weighing no more
# than it does), the .50 Cartridge as currency, the wreck and Entity loot
# tables, LootTable rolls and rarity, LootEntry parts (weapon drops),
# LootContainer random contents, and salvage/parts surviving a save in the
# cargo. Prints the tier spread of a large batch of rolls.
#
# Rolls use a seeded RandomNumberGenerator so results are the same every run.
# Each case starts from fresh progress (PlayerProgress.reset).

const WRECK_SALVAGE := preload("res://database/loot-tables/wreck_salvage.tres")
const SALVAGE_DIR := "res://database/items/salvage/"
const LOW_ITEM := preload("res://database/items/salvage/track_links.tres")       # 2x1
const MID_ITEM := preload("res://database/items/salvage/military_radio.tres")
const HIGH_ITEM := preload("res://database/items/salvage/fuel_cassette.tres")
const CARTRIDGE := preload("res://database/items/salvage/cartridge_50.tres")
const LOOT_CONTAINER := preload("res://game/mecha/LootContainer.tscn")

# Matches the weapon in PlayerProgress.DEFAULT_MECHA.
const TEST_WEAPON_TYPE := "arm_weapon"
const TEST_WEAPON_ID := "MA-L127"

const SPREAD_ROLLS := 10000
## The catalogue's rows (items.csv).
const CATALOGUE_SIZE := 45
## Yosqi's engine figures: oil on top of the block's weight.
const HEAVIER_THAN_ITEM := ["bus_engine", "tank_engine"]
## A few rows of the catalogue, as the brief has them:
## id -> [weight t, [w, h], stack, composition in stored units].
const ROWS := {
	"scrap_metal": [0.1, [1, 1], 10, {"steel": 100}],
	"car_battery": [0.02, [1, 1], 10, {"cells": 600}],
	"catalytic_converter": [0.01, [1, 1], 10, {"noble_metals": 5, "steel": 8}],
	"bus_engine": [1.1, [1, 2], 1, {"steel": 1100, "oil": 40000}],
	"cartridge_50": [0.000115, [1, 1], 250, {}],
	"bulk_steel": [10.0, [3, 3], 1, {"steel": 10000}],
	"pilot_capsule": [0.8, [2, 2], 1, {"neural_biomatter": 10, "avidendrites": 1, "steel": 600, "electronics": 20}],
	"entity_residue": [0.01, [1, 1], 20, {"avi_polymer": 8000, "myofibrilium": 500, "nt_fluid": 500}],
	"mote_cluster": [0.002, [1, 1], 50, {"avi_polymer": 1500, "nt_fluid": 100}],
	"fisher_heart": [0.15, [2, 2], 1, {"nt_engines": 1, "myofibrilium": 2000, "nt_fluid": 3000, "avi_polymer": 20000}],
}
const ENTITY_ITEMS := ["entity_residue", "mote_cluster", "fisher_heart", "fisher_shell"]
const ENTITY_TABLES := {
	"entity_coyote": "entity_residue", "entity_coyote_spitter": "entity_residue",
	"entity_spitter": "entity_residue", "entity_stalker": "entity_residue",
	"entity_brute": "entity_residue", "entity_cyst": "entity_residue",
	"entity_fisher": "fisher_shell", "entity_tick_swarm": "mote_cluster",
}


func run_tests() -> void:
	await case("the salvage catalogue", _test_catalogue)
	await case("catalogue rows as the brief has them", _test_rows)
	await case("the .50 Cartridge is currency", _test_currency_item)
	await case("wreck salvage tables", _test_wreck_tables)
	await case("Entity loot tables", _test_entity_tables)
	await case("tier chances", _test_tier_chances)
	await case("roll spread follows weights", _test_roll_spread)
	await case("empty tier falls back", _test_fallback)
	await case("empty table", _test_empty_table)
	await case("entries make fresh stacks", _test_fresh_stacks)
	await case("part entries", _test_part_entry)
	await case("container rolls its contents", _test_container)
	await case("salvage and parts survive a save in cargo", _test_cargo_save)


func before_each() -> void:
	PlayerProgress.reset()


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	return rng


func _salvage_items() -> Array:
	var items := []
	for file in DirAccess.get_files_at(SALVAGE_DIR):
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			items.append(load(SALVAGE_DIR + file))
	return items


func _test_catalogue() -> void:
	var items := _salvage_items()
	check_eq(items.size(), CATALOGUE_SIZE, "one item per catalogue row")
	for item in items:
		if not check(item is item_data, "%s is an item" % str(item)):
			continue
		var id: String = item.id
		check(item.resource_path.get_file() == id + ".tres", "%s id matches its file" % id)
		check(item.display_name != "" and item.description != "" and item.icon != null, "%s is named, described and has an icon" % id)
		check("salvage" in item.tags, "%s is tagged salvage" % id)
		check(item.tech_tier in LootTable.ROLLED_TIERS, "%s has a tech tier, so loot tables roll it" % id)
		check(item.weight > 0.0 and item.width() >= 1 and item.height() >= 1 and item.max_stack >= 1,
				"%s has a weight, a size and a stack" % id)
		check(("bio" in item.tags) == (id in ENTITY_ITEMS), "%s is tagged bio only if an Entity drops it" % id)
		if item_data.CURRENCY_TAG in item.tags:
			continue
		check(not item.composition.is_empty(), "%s can be recycled" % id)
		for material_id in item.composition:
			check(Materials.is_valid(material_id) and int(item.composition[material_id]) > 0,
					"%s recycles into a known material (%s)" % [id, material_id])
		var mass := Materials.mass_of(item.composition)
		if not id in HEAVIER_THAN_ITEM:
			check(mass <= item.weight * 1000.0 + 0.001, "%s breaks into %.1f kg, no more than its %s" % [id, mass, Units.weight(item.weight)])
		check_eq(item.price, maxi(1, roundi(Materials.value_of(item.composition))), "%s is worth exactly its materials" % id)
		check_eq(PlayerProgress.recycle_value(item_stack.from_generic(item, 3)),
				_times(item.composition, 3), "%s recycles 1 to 1" % id)


func _times(amounts: Dictionary, n: int) -> Dictionary:
	var result := {}
	for material_id in amounts:
		result[material_id] = int(amounts[material_id]) * n
	return result


func _test_rows() -> void:
	for id in ROWS:
		var item: item_data = load(SALVAGE_DIR + id + ".tres")
		var row: Array = ROWS[id]
		if not check(item != null, "%s exists" % id):
			continue
		check(is_equal_approx(item.weight, row[0]), "%s weighs %s" % [id, Units.weight(row[0])])
		check_eq(item.item_size, row[1], "%s is %dx%d" % [id, row[1][0], row[1][1]])
		check_eq(item.max_stack, row[2], "%s stacks to %d" % [id, row[2]])
		check_eq(Dictionary(item.composition), row[3], "%s breaks into %s" % [id, Materials.describe(row[3])])
	var engine: item_data = load(SALVAGE_DIR + "bus_engine.tres")
	check_eq(Materials.describe(engine.composition), "1.1 t Steel, 40 L Oil", "compositions read in real units")


func _test_currency_item() -> void:
	check(item_data.CURRENCY_TAG in CARTRIDGE.tags and CARTRIDGE.price == 1 and CARTRIDGE.composition.is_empty(),
			"a currency item worth 1 ct, made of nothing")
	check(is_equal_approx(CARTRIDGE.weight * 1000.0, 0.115), "0.115 kg each")
	check_eq(Units.weight(CARTRIDGE.weight * 250), "28.75 kg", "a full stack weighs 28.75 kg")


func _test_wreck_tables() -> void:
	for table in [WRECK_SALVAGE] + WreckLoot.PART_TABLES.values():
		var file: String = table.resource_path.get_file()
		check(not table.get_entries_of_tier(item_data.TechTier.LOW).is_empty(), "%s has low-tech salvage" % file)
		for entry in table.entries:
			check(entry.is_valid() and entry.item.resource_path.begins_with(SALVAGE_DIR) and "salvage" in entry.item.tags,
					"%s rolls catalogue salvage" % file)
			check(not entry.item.id in ENTITY_ITEMS, "%s rolls no Entity matter" % file)
	check(not WRECK_SALVAGE.get_entries_of_tier(item_data.TechTier.MID).is_empty(), "wreck salvage has mid-tech items")


func _test_entity_tables() -> void:
	for table_name in ENTITY_TABLES:
		var table: LootTable = load("res://database/loot-tables/%s.tres" % table_name)
		if not check(table != null, "%s loads" % table_name):
			continue
		var ids := table.entries.map(func(e): return e.item.id if e.item != null else "")
		check_eq(ids, [ENTITY_TABLES[table_name]], "%s drops %s" % [table_name, ENTITY_TABLES[table_name]])
		var stack := table.roll_stack(_seeded_rng())
		check(stack != null and "bio" in stack.item.tags, "%s rolls bio salvage" % table_name)

	# Carried home in cargo, it survives a save like any salvage.
	var cargo := Inventory.new()
	cargo.initialize_grid(4, 4)
	cargo.add_stack_to_first_available_slot(item_stack.from_generic(load(SALVAGE_DIR + "entity_residue.tres"), 5))
	PlayerProgress.set_mech_inventory(cargo)
	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	check(PlayerProgress.get_mech_inventory().get_stacks().any(func(s): return s.item != null and s.item.id == "entity_residue" and s.quantity == 5),
			"bio salvage survives a save in cargo")


# A table of one item per tier, for the roll tests.
func _tiered_table() -> LootTable:
	var table := LootTable.new()
	for item in [LOW_ITEM, MID_ITEM, HIGH_ITEM]:
		table.entries.append(_entry(item))
	return table


func _test_tier_chances() -> void:
	var chances: Dictionary = WRECK_SALVAGE.get_tier_chances()
	check(is_equal_approx(chances[item_data.TechTier.LOW], 0.70), "low is 70%")
	check(is_equal_approx(chances[item_data.TechTier.MID], 0.25), "mid is 25%")
	check(is_equal_approx(chances[item_data.TechTier.HIGH], 0.05), "high is 5%")


func _test_roll_spread() -> void:
	var rng := _seeded_rng()
	var table := _tiered_table()
	var counts := {item_data.TechTier.LOW: 0, item_data.TechTier.MID: 0, item_data.TechTier.HIGH: 0}
	for _i in SPREAD_ROLLS:
		var entry: LootEntry = table.roll_entry(rng)
		counts[entry.get_tech_tier()] += 1
	var low := float(counts[item_data.TechTier.LOW]) / SPREAD_ROLLS
	var mid := float(counts[item_data.TechTier.MID]) / SPREAD_ROLLS
	var high := float(counts[item_data.TechTier.HIGH]) / SPREAD_ROLLS
	print("    %d rolls: low %.1f%%, mid %.1f%%, high %.1f%%" % [SPREAD_ROLLS, low * 100, mid * 100, high * 100])
	check(absf(low - 0.70) < 0.03, "low close to 70%")
	check(absf(mid - 0.25) < 0.03, "mid close to 25%")
	check(absf(high - 0.05) < 0.015, "high close to 5%")
	check(high < mid and mid < low, "rarer as tech rises")


func _test_fallback() -> void:
	# Only a low item, but every roll wants high tech.
	var table := LootTable.new()
	table.entries.append(_entry(LOW_ITEM))
	table.low_weight = 0.0
	table.mid_weight = 0.0
	table.high_weight = 100.0
	var rng := _seeded_rng()
	var entry := table.roll_entry(rng)
	check(entry != null and entry.item == LOW_ITEM, "high roll steps down to low")

	# Only a high item, every roll wants low tech.
	table = LootTable.new()
	table.entries.append(_entry(HIGH_ITEM))
	table.low_weight = 100.0
	table.mid_weight = 0.0
	table.high_weight = 0.0
	entry = table.roll_entry(rng)
	check(entry != null and entry.item == HIGH_ITEM, "low roll steps up to high")


func _test_empty_table() -> void:
	var table := LootTable.new()
	check(table.roll_entry() == null, "no entry from an empty table")
	check(table.roll_stacks(3).is_empty(), "no stacks from an empty table")


func _test_fresh_stacks() -> void:
	var entry := _entry(LOW_ITEM, 2)
	var a := entry.make_stack()
	var b := entry.make_stack()
	check(a != null and a != b, "each make_stack is a new stack")
	check(a.kind == item_stack.ItemKind.GENERIC and a.item == LOW_ITEM, "generic stack holds the item")
	check(a.quantity == 2, "quantity carried over")
	check(a.width_cells() == 2 and a.height_cells() == 1, "size comes from item_size")
	check(not _entry(null).is_valid(), "entry with nothing set is invalid")


func _test_part_entry() -> void:
	var entry := LootEntry.new()
	entry.part_type = TEST_WEAPON_TYPE
	entry.part_id = TEST_WEAPON_ID
	check(entry.is_part() and entry.is_valid(), "weapon entry is valid")
	check(entry.get_tech_tier() == item_data.TechTier.NONE, "parts have no tier")

	var stack := entry.make_stack()
	check(stack != null and stack.kind == item_stack.ItemKind.PART, "makes a part stack")
	check(stack.item_type == TEST_WEAPON_TYPE and stack.item_id == TEST_WEAPON_ID, "part stack keeps type and id")
	check(stack.width_cells() == 3 and stack.height_cells() == 2, "weapon size resolved through PartManager")

	var bad := LootEntry.new()
	bad.part_type = TEST_WEAPON_TYPE
	bad.part_id = "NOT-A-WEAPON"
	check(not bad.is_valid() and bad.make_stack() == null, "unknown part is invalid")

	# Tier rolls never hand out parts.
	var table := LootTable.new()
	table.entries.append(entry)
	check(table.roll_entry() == null, "table skips part entries")


func _test_container() -> void:
	var container: LootContainer = LOOT_CONTAINER.instantiate()
	container.default_contents = []  # the scene ships with a test item
	container.grid_width = 8
	container.grid_height = 8
	container.loot_table = WRECK_SALVAGE
	container.loot_rolls = 3
	add_child(container)
	check(_count_stacks(container.inventory) == 3, "3 rolled items placed")

	var weapon := LootEntry.new()
	weapon.part_type = TEST_WEAPON_TYPE
	weapon.part_id = TEST_WEAPON_ID
	container.populate([weapon])
	check(_count_stacks(container.inventory) == 4, "part entry placed in a container")
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
	check(found_salvage, "salvage restored with its tier")
	check(found_weapon, "weapon part restored with type and id")


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
