extends TestSuite

# LootTableTest: the loot data. Tech tiers, LootTable rolls and rarity,
# LootEntry parts (weapon drops), LootContainer random contents, and
# salvage/parts surviving a save in the cargo. Prints the tier spread of a
# large batch of rolls.
#
# Rolls use a seeded RandomNumberGenerator so results are the same every run.
# Each case starts from fresh progress (PlayerProgress.reset).

const WRECK_SALVAGE := preload("res://database/loot-tables/wreck_salvage.tres")
const LOW_ITEM := preload("res://database/items/salvage/armor_plate_fragment.tres")
const HIGH_ITEM := preload("res://database/items/salvage/damaged_nt_engine.tres")
const LOOT_CONTAINER := preload("res://game/mecha/LootContainer.tscn")

# Matches the weapon in PlayerProgress.DEFAULT_MECHA.
const TEST_WEAPON_TYPE := "arm_weapon"
const TEST_WEAPON_ID := "MA-L127"

const SPREAD_ROLLS := 10000


func run_tests() -> void:
	await case("salvage items have tiers", _test_salvage_tiers)
	await case("bio salvage and Entity loot tables", _test_bio_salvage)
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


func _test_salvage_tiers() -> void:
	for tier in LootTable.ROLLED_TIERS:
		check(not WRECK_SALVAGE.get_entries_of_tier(tier).is_empty(),
				"wreck_salvage has items of tier %d" % tier)
	for entry in WRECK_SALVAGE.entries:
		check(entry.get_tech_tier() != item_data.TechTier.NONE,
				"%s has a tech tier" % entry.item.id)
		check("salvage" in entry.item.tags, "%s is tagged salvage" % entry.item.id)
		check(not entry.item.composition.is_empty(), "%s can be recycled" % entry.item.id)
		for material_id in entry.item.composition:
			check(Materials.is_valid(material_id), "%s recycles into a known material (%s)" % [entry.item.id, material_id])
		var item: item_data = entry.item
		check(item.weight >= 0.25 and item.weight <= 2.0, "%s is light salvage (0.25-2)" % item.id)
		check(item.width() <= 2 and item.height() <= 2, "%s is at most 2x2" % item.id)
		check(item.display_name != "" and item.description != "", "%s is named and described" % item.id)
		check(item.resource_path.get_file() == item.id + ".tres", "%s id matches its file" % item.id)

	# Every salvage item is in the table, once: 4 low, 4 mid, 3 high.
	var table_items := WRECK_SALVAGE.entries.map(func(e): return e.item)
	var files := Array(DirAccess.get_files_at("res://database/items/salvage")).filter(func(f): return f.ends_with(".tres"))
	check(files.size() == 11 and table_items.size() == 11, "eleven salvage items, all in the table")
	for file in files:
		check(load("res://database/items/salvage/" + file) in table_items, "%s is in wreck_salvage" % file)
	check(WRECK_SALVAGE.get_entries_of_tier(item_data.TechTier.LOW).size() == 4, "four low-tech")
	check(WRECK_SALVAGE.get_entries_of_tier(item_data.TechTier.MID).size() == 4, "four mid-tech")
	check(WRECK_SALVAGE.get_entries_of_tier(item_data.TechTier.HIGH).size() == 3, "three high-tech")


# Bio salvage (database/items/bio/) comes from Entity carcasses. Every item is
# proper salvage, and drops from at least one Entity's table, except the NT
# Engine Heart, which is a rare extra (Brutes, Cysts), never a table roll.
const BIO_DIR := "res://database/items/bio/"
const ENTITY_TABLES := ["entity_stalker", "entity_spitter", "entity_brute", "entity_cyst"]
const RARE_ONLY := ["nt_engine_heart"]

func _test_bio_salvage() -> void:
	var files := Array(DirAccess.get_files_at(BIO_DIR)).filter(func(f): return f.ends_with(".tres"))
	check_eq(files.size(), 8, "bio items")
	var dropped := {}
	for table_name in ENTITY_TABLES:
		var table: LootTable = load("res://database/loot-tables/%s.tres" % table_name)
		if not check(table != null, "%s loads" % table_name):
			continue
		for tier in LootTable.ROLLED_TIERS:
			check(not table.get_entries_of_tier(tier).is_empty(), "%s has items of tier %d" % [table_name, tier])
		for entry in table.entries:
			check(entry.is_valid() and entry.item.resource_path.begins_with(BIO_DIR), "%s only drops bio salvage" % table_name)
			dropped[entry.item.id] = true
	for file in files:
		var item: item_data = load(BIO_DIR + file)
		check(item.tech_tier != item_data.TechTier.NONE, "%s has a tech tier" % item.id)
		check("salvage" in item.tags and "bio" in item.tags, "%s is tagged salvage, bio" % item.id)
		check(not item.composition.is_empty(), "%s can be recycled" % item.id)
		for material_id in item.composition:
			check(Materials.is_valid(material_id), "%s recycles into a known material (%s)" % [item.id, material_id])
		check_eq(PlayerProgress.recycle_value(item_stack.from_generic(item)), Dictionary(item.composition), "%s recycles into its composition" % item.id)
		check(item.weight >= 0.25 and item.weight <= 2.0, "%s is light salvage (0.25-2)" % item.id)
		check(item.width() <= 2 and item.height() <= 2, "%s is at most 2x2" % item.id)
		check(item.display_name != "" and item.description != "" and item.price > 0, "%s is named, described and priced" % item.id)
		check(item.resource_path.get_file() == item.id + ".tres", "%s id matches its file" % item.id)
		if item.id in RARE_ONLY:
			check(not dropped.has(item.id), "%s is a rare extra, not a table roll" % item.id)
		else:
			check(dropped.has(item.id), "%s drops from an Entity table" % item.id)

	# Carried home in cargo, it survives a save like any salvage.
	var cargo := Inventory.new()
	cargo.initialize_grid(4, 4)
	cargo.add_stack_to_first_available_slot(item_stack.from_generic(load(BIO_DIR + "nt_fluid_sac.tres")))
	PlayerProgress.set_mech_inventory(cargo)
	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	check(PlayerProgress.get_mech_inventory().get_stacks().any(func(s): return s.item != null and s.item.id == "nt_fluid_sac"),
			"bio salvage survives a save in cargo")


func _test_tier_chances() -> void:
	var chances: Dictionary = WRECK_SALVAGE.get_tier_chances()
	check(is_equal_approx(chances[item_data.TechTier.LOW], 0.70), "low is 70%")
	check(is_equal_approx(chances[item_data.TechTier.MID], 0.25), "mid is 25%")
	check(is_equal_approx(chances[item_data.TechTier.HIGH], 0.05), "high is 5%")


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
