extends TestSuite

# PlayerProgressTest: the PlayerProgress autoload. Money, parts in the stash,
# save round-trip and migration of pre-PlayerProgress saves, Expedition stakes
# (begin/extract/lose, abandoned runs), materials and recycling (salvage and
# weapons; lossless, in real units; currency into credits; auto-salvage on
# return), saves from before real units, and the parts a mecha needs to
# deploy.
# Each case starts from fresh progress (PlayerProgress.reset).

const TEST_PART_TYPE := "head"
const TEST_PART_ID := "MSV-L3J-H"
const SALVAGE := preload("res://database/items/salvage/fisher_heart.tres")   # 2x2: 1 u NT Engines, 3 L NT Fluid, ...
const CARTRIDGE := preload("res://database/items/salvage/cartridge_50.tres")


func run_tests() -> void:
	await case("money", _test_money)
	await case("parts in the stash", _test_parts)
	await case("save data survives JSON round-trip", _test_save_round_trip)
	await case("legacy save migration", _test_legacy_migration)
	await case("extracting keeps mecha and cargo", _test_extract)
	await case("losing an expedition", _test_lose)
	await case("no loss outside an expedition", _test_lose_without_expedition)
	await case("abandoned run resolved on load", _test_abandoned)
	await case("materials", _test_materials)
	await case("material registry", _test_material_registry)
	await case("old saves cleaned up on load", _test_old_save_cleanup)
	await case("materials of a save from before real units", _test_legacy_materials)
	await case("removed salvage in an old save is recycled", _test_legacy_items)
	await case("recycling", _test_recycling)
	await case("no recycling mid-run", _test_no_recycling_in_expedition)
	await case("recycle menu actions", _test_recycle_actions)
	await case("recycling weapons", _test_weapon_recycling)
	await case(".50 Cartridges are currency", _test_currency)
	await case("auto-salvage on return", _test_auto_salvage)
	await case("required parts", _test_required_parts)


func before_each() -> void:
	PlayerProgress.reset()


func _test_money() -> void:
	PlayerProgress.add_money(500)
	check(PlayerProgress.get_money() == 500, "add_money")
	check(not PlayerProgress.spend_money(501), "can't overspend")
	check(PlayerProgress.get_money() == 500, "failed spend changes nothing")
	check(PlayerProgress.spend_money(200), "spend_money")
	check(PlayerProgress.get_money() == 300, "balance after spend")


func _test_parts() -> void:
	check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 0, "stash starts empty")
	check(PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID), "add_part")
	check(PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID), "add_part again")
	check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 2, "count_part")
	check(PlayerProgress.get_owned_parts(TEST_PART_TYPE).has(TEST_PART_ID), "get_owned_parts by type")
	check(PlayerProgress.get_owned_parts("core").is_empty(), "get_owned_parts filters type")
	check(PlayerProgress.remove_part(TEST_PART_TYPE, TEST_PART_ID), "remove_part")
	check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "count after remove")
	check(not PlayerProgress.remove_part("core", TEST_PART_ID), "remove_part checks type")


func _test_save_round_trip() -> void:
	PlayerProgress.add_money(1234)
	PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID)
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "TORI-ML"
	PlayerProgress.set_current_mecha(design)

	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))

	check(PlayerProgress.get_money() == 1234, "money restored")
	check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "stash part restored with type and id")
	check(PlayerProgress.get_current_mecha()["shoulder_weapon_left"] == "TORI-ML", "mecha restored")


func _test_legacy_migration() -> void:
	var legacy_design := PlayerProgress.DEFAULT_MECHA.duplicate()
	legacy_design.erase("thruster")  # simulate a slot added after the save
	var legacy_save := {
		"stats": {"gameover": 0, "money": 777, "current_mecha": legacy_design},
		"stash_inventory": {},
		"mech_inventory": {},
	}
	PlayerProgress.set_save_data(PlayerProgress.migrate_legacy_save(legacy_save))
	check(PlayerProgress.get_money() == 777, "legacy money")
	check(PlayerProgress.get_current_mecha().get("thruster") == PlayerProgress.DEFAULT_MECHA["thruster"], "missing slot filled from default")
	check(PlayerProgress.get_stash_inventory().grid_width == PlayerProgress.STASH_SIZE.x, "empty legacy stash gets default size")

# ---- Expedition stakes ----

# A non-default mecha plus one salvage item in a 6x6 cargo.
func _kit_out() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "TORI-ML"
	PlayerProgress.set_current_mecha(design)
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 6)
	cargo.add_stack_to_first_available_slot(item_stack.from_generic(SALVAGE))
	PlayerProgress.set_mech_inventory(cargo)


func _cargo_count() -> int:
	var inv := PlayerProgress.get_mech_inventory()
	var count := 0
	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell = inv.grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				count += 1
	return count


func _test_extract() -> void:
	_kit_out()
	PlayerProgress.begin_expedition()
	check(PlayerProgress.is_in_expedition(), "begin_expedition starts a run")
	PlayerProgress.extract_expedition()
	check(not PlayerProgress.is_in_expedition(), "extract ends the run")
	check(_cargo_count() == 1, "cargo kept")
	check(PlayerProgress.get_current_mecha()["shoulder_weapon_left"] == "TORI-ML", "mecha kept")
	check(not PlayerProgress.has_loss_report(), "no loss report")


func _test_lose() -> void:
	_kit_out()
	PlayerProgress.add_money(300)
	PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID)
	PlayerProgress.begin_expedition()
	var report := PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)

	check(not PlayerProgress.is_in_expedition(), "losing ends the run")
	check(_cargo_count() == 0, "cargo emptied")
	check(PlayerProgress.get_current_mecha() == PlayerProgress.DEFAULT_MECHA, "back in the default mecha")
	check(PlayerProgress.get_money() == 300, "money safe")
	check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "stash safe")

	check(report.get("reason") == PlayerProgress.LOSS_DESTROYED, "report has the reason")
	check(SALVAGE.display_name in report.get("cargo", []), "report lists the cargo")
	check(report.get("mecha", []).size() >= 8, "report lists the equipped parts")
	check(SALVAGE.display_name in PlayerProgress.format_loss_report(report), "formatted text names the cargo")

	check(PlayerProgress.has_loss_report(), "report pending until shown")
	check(PlayerProgress.take_loss_report() == report, "take_loss_report returns it")
	check(not PlayerProgress.has_loss_report(), "only shown once")


func _test_lose_without_expedition() -> void:
	_kit_out()
	check(PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED).is_empty(), "nothing to lose")
	check(_cargo_count() == 1, "cargo untouched")
	check(PlayerProgress.get_current_mecha()["shoulder_weapon_left"] == "TORI-ML", "mecha untouched")
	check(not PlayerProgress.resolve_abandoned_expedition(), "no abandoned run to resolve")


func _test_abandoned() -> void:
	# A save written mid-run, as if the game closed during an expedition.
	_kit_out()
	PlayerProgress.begin_expedition()
	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	check(PlayerProgress.is_in_expedition(), "in-expedition flag saved")
	check(_cargo_count() == 1, "loading alone doesn't lose anything")

	check(PlayerProgress.resolve_abandoned_expedition(), "abandoned run resolved")
	check(_cargo_count() == 0, "abandoned cargo lost")
	check(PlayerProgress.get_current_mecha() == PlayerProgress.DEFAULT_MECHA, "abandoned mecha lost")

	# The pending report survives a save, so a crash can't hide it.
	json = JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	var report := PlayerProgress.take_loss_report()
	check(report.get("reason") == PlayerProgress.LOSS_ABANDONED, "pending report saved with its reason")

# ---- Materials and recycling ----

const SCRAP := preload("res://database/items/salvage/scrap_metal.tres")   # 100 kg Steel


func _test_materials() -> void:
	check(PlayerProgress.get_materials().is_empty(), "no materials at first")
	PlayerProgress.add_materials({"steel": 3, "copper": 1})
	PlayerProgress.add_materials({"steel": 2})
	check(PlayerProgress.get_material_count("steel") == 5, "amounts add up")
	check(PlayerProgress.get_material_count("myofibrilium") == 0, "missing material is 0")

	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	check(PlayerProgress.get_material_count("steel") == 5, "materials survive a save")
	check(typeof(PlayerProgress.get_materials()["steel"]) == TYPE_INT, "loaded as whole numbers")


const SCRAP_SET := ["steel", "aluminium", "copper", "electronics", "cells", "oil", "noble_metals", "energetics"]
const STRANGE_SET := ["avi_polymer", "nt_fluid", "fissile_materials", "neural_biomatter", "myofibrilium", "avidendrites", "nt_engines"]


func _test_material_registry() -> void:
	check(Materials.ALL.size() == 15, "fifteen materials")
	var seen := {}
	for material in Materials.ALL:
		check(material.id != "" and not seen.has(material.id), "unique id: " + material.id)
		seen[material.id] = true
		check(material.display_name != "" and material.description != "", "named and described: " + material.id)
		check(material.unit in ["g", "kg", "mL", "Wh", "u"], "stored in a base unit: " + material.id)
		check(Units.SCALE.has(material.display_unit) and Units.SCALE[material.display_unit][0] == Units.SCALE[material.unit][0],
				"shown in a unit of the same kind: " + material.id)
		check(material.kg_per_unit > 0.0 and material.value > 0.0, "has a mass and a value: " + material.id)
		check(not "tech_tier" in material, "no tech tier: " + material.id)
	check_eq(Materials.of_origin(MaterialData.Origin.SCRAP).map(func(m): return m.id), SCRAP_SET, "Scrap, in order")
	check_eq(Materials.of_origin(MaterialData.Origin.STRANGE).map(func(m): return m.id), STRANGE_SET, "Strange, in order")
	check(not Materials.is_valid("silicon") and Materials.is_valid("electronics"), "Electronics replaces Silicon")
	check(Materials.display_name("avi_polymer") == "AVI-Polymer", "names as written")
	check(Materials.display_name("fissile_materials") == "Fissile", "the old id keeps its save, with the new name")
	check_eq(Materials.origin_name(MaterialData.Origin.STRANGE), "Strange", "origin name")
	check_eq(item_data.tier_name(item_data.TechTier.HIGH), "High", "item tiers keep their names")
	check_eq(Materials.describe({"copper": 25, "steel": 1100}), "1.1 t Steel, 25 kg Copper", "describe in registry order, in real units")

	# Units: stored whole, shown readable.
	var shown := {
		["steel", 175]: "175 kg", ["steel", 1750]: "1.75 t", ["steel", 0]: "0 t",
		["oil", 40000]: "40 L", ["nt_fluid", 500]: "500 mL", ["cells", 600]: "600 Wh",
		["cells", 1500]: "1.5 kWh", ["noble_metals", 5]: "5 g", ["avi_polymer", 1500]: "1.5 kg",
		["avi_polymer", 500]: "500 g", ["nt_engines", 1]: "1 u", ["electronics", 12]: "12 kg",
	}
	for key in shown:
		check_eq(Materials.format_amount(key[0], key[1]), shown[key], "%d of %s" % [key[1], key[0]])
	check_eq(Materials.format_pair("steel", 1200, 4000), "1.2 / 4 t", "had / needed in the needed amount's unit")
	check_eq(Units.weight(15.7), "15.7 t", "part weights in tonnes")
	check_eq(Units.weight(0.4), "400 kg", "kg below 1 t")
	check_eq(Units.weight(0.000115), "115 g", "g below 1 kg")
	check_eq(Units.weight(54.27), "54.27 t", "up to two decimals")
	check_eq(Units.weight(0.0), "0 t", "nothing is 0 t")

	# Every salvage item recycles into real materials only (currency into
	# credits).
	for path in DirAccess.get_files_at("res://database/items/salvage"):
		if not path.ends_with(".tres"):
			continue
		var item = load("res://database/items/salvage/" + path)
		check(not item.composition.is_empty() or item_data.CURRENCY_TAG in item.tags, "%s has a composition" % path)
		for material_id in item.composition:
			check(Materials.is_valid(material_id), "%s uses known material %s" % [path, material_id])


func _test_old_save_cleanup() -> void:
	# A dev save from before the lore materials, with a salvage file that
	# no longer exists next to one that does.
	var old_save := PlayerProgress.get_save_data()
	old_save["materials"] = {"scrap_metal": 4.0, "steel": 2.0, "electronics": 1.0}  # real units: kg
	old_save["stash_inventory"] = {
		"grid_width": 6, "grid_height": 6,
		"items": [
			{"x": 0, "y": 0, "quantity": 1, "rotated": false, "kind": 0, "item_path": "res://database/items/salvage/scrap_plating.tres"},
			{"x": 0, "y": 2, "quantity": 1, "rotated": false, "kind": 0, "item_path": ""},
			{"x": 3, "y": 0, "quantity": 1, "rotated": false, "kind": 0, "item_path": SCRAP.resource_path},
		],
	}
	PlayerProgress.set_save_data(JSON.parse_string(JSON.stringify(old_save)))
	check_eq(PlayerProgress.get_materials(), {"steel": 2, "electronics": 1}, "unknown materials dropped, known kept")
	var stacks := PlayerProgress.get_stash_inventory().get_stacks()
	check(stacks.size() == 1, "missing and blank items dropped")
	check(stacks.size() == 1 and stacks[0].item == SCRAP, "existing item kept")


# A save from before real units has no "materials_units": its old-unit
# counts convert (LegacySave.OLD_UNIT), Silicon into Electronics.
func _test_legacy_materials() -> void:
	var old_save := PlayerProgress.get_save_data()
	old_save.erase("materials_units")
	old_save["materials"] = {"steel": 3.0, "silicon": 2.0, "fissile_materials": 3.0, "avi_polymer": 1.0, "oil": 1.0}
	PlayerProgress.set_save_data(JSON.parse_string(JSON.stringify(old_save)))
	check_eq(PlayerProgress.get_materials(), {"steel": 3000, "electronics": 20, "fissile_materials": 2,
			"avi_polymer": 2000, "oil": 100000}, "3 Steel -> 3 t, 2 Silicon -> 20 kg Electronics, 3 Fissile -> 2 kg, ...")
	var json := JSON.stringify(PlayerProgress.get_save_data())
	check("materials_units" in json, "saved again with its units marked")
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	check_eq(PlayerProgress.get_material_count("steel"), 3000, "and not converted twice")


# Removed salvage in an old save's stash is recycled on load (its old
# composition, converted); out on an expedition the cargo is left alone.
func _test_legacy_items() -> void:
	var old_save := PlayerProgress.get_save_data()
	old_save.erase("materials_units")
	old_save["materials"] = {}
	old_save["stash_inventory"] = {
		"grid_width": 6, "grid_height": 6,
		"items": [
			{"x": 0, "y": 0, "quantity": 2, "rotated": false, "kind": 0, "item_path": "res://database/items/salvage/armor_plate_fragment.tres"},
			{"x": 0, "y": 2, "quantity": 1, "rotated": false, "kind": 0, "item_path": "res://database/items/bio/nt_engine_heart.tres"},
			{"x": 3, "y": 0, "quantity": 1, "rotated": false, "kind": 0, "item_path": SCRAP.resource_path},
		],
	}
	PlayerProgress.set_save_data(JSON.parse_string(JSON.stringify(old_save)))
	check_eq(PlayerProgress.get_materials(), {"steel": 6000, "nt_engines": 1, "nt_fluid": 10000},
			"two armour plates (3 Steel each) and an NT Engine Heart, recycled")
	var stacks := PlayerProgress.get_stash_inventory().get_stacks()
	check(stacks.size() == 1 and stacks[0].item == SCRAP, "items that still exist stay")

	old_save["in_expedition"] = true
	old_save["stash_inventory"] = {}
	old_save["mech_inventory"] = {"grid_width": 4, "grid_height": 4, "items": [
		{"x": 0, "y": 0, "quantity": 1, "rotated": false, "kind": 0, "item_path": "res://database/items/salvage/armor_plate_fragment.tres"}]}
	PlayerProgress.set_save_data(JSON.parse_string(JSON.stringify(old_save)))
	check(PlayerProgress.get_materials().is_empty(), "cargo still at stake isn't recycled")
	PlayerProgress.in_expedition = false


func _test_recycling() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var scrap := item_stack.from_generic(SCRAP, 2)
	var cell := item_stack.from_generic(SALVAGE)  # Fisher Heart: 1 u NT Engines, 3 L NT Fluid, ...
	stash.add_stack_anywhere(scrap)
	stash.add_stack_anywhere(cell)
	PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID)

	check(PlayerProgress.recycle_value(scrap) == {"steel": 200}, "value counts the whole stack, 1 to 1")
	var part_stack: item_stack = null
	for stack in stash.get_stacks():
		if stack.kind == item_stack.ItemKind.PART:
			part_stack = stack
	# Every part has a composition now (the Fabricator builds from it).
	var head_composition: Dictionary = PartManager.get_part(TEST_PART_TYPE, TEST_PART_ID).composition
	var head_value := PlayerProgress.recycle_value(part_stack)
	check(PlayerProgress.can_recycle(part_stack) and head_value.size() == head_composition.size()
			and head_composition.keys().all(func(m): return head_value.get(m) == head_composition[m]),
			"parts recycle into their composition")

	var gained := PlayerProgress.recycle_stack(stash, scrap)
	check(gained == {"steel": 200}, "recycle_stack returns what it gave")
	check(PlayerProgress.get_material_count("steel") == 200, "materials added")
	check(not stash.get_stacks().has(scrap), "recycled stack removed")
	check(PlayerProgress.recycle_stack(stash, scrap).is_empty(), "can't recycle it twice")

	PlayerProgress.recycle_all(stash)
	check(PlayerProgress.get_material_count("nt_engines") == 1 and PlayerProgress.get_material_count("nt_fluid") == 3000,
			"recycle_all gives everything's materials")
	check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "recycle_all leaves parts alone")


func _test_no_recycling_in_expedition() -> void:
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 6)
	var scrap := item_stack.from_generic(SCRAP)
	cargo.add_stack_anywhere(scrap)
	PlayerProgress.begin_expedition()
	check(not PlayerProgress.can_recycle(scrap), "can't recycle during a run")
	check(PlayerProgress.recycle_all(cargo).is_empty() and cargo.get_stacks().has(scrap), "nothing recycled mid-run")
	PlayerProgress.extract_expedition()
	check(PlayerProgress.can_recycle(scrap), "recyclable once home")


func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


func _test_recycle_actions() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var scrap := item_stack.from_generic(SCRAP)
	stash.add_stack_anywhere(scrap)
	var recycle := _action("item", "recycle")
	var recycle_all := _action("inventory", "recycle_all")
	check(not recycle.is_empty() and not recycle_all.is_empty(), "recycle actions registered")

	var ctx := {"type": "item", "stack": scrap, "inventory": stash}
	check(not recycle["visible_if"].call(ctx), "hidden where recycling isn't allowed (Mech OS mid-run)")
	ctx["recycle_allowed"] = true
	check(recycle["visible_if"].call(ctx), "shown in the Hangar")
	check(recycle["enabled_if"].call(ctx) == "", "enabled on salvage")
	var test_item := item_stack.from_generic(load("res://database/items/test/TestItem2.tres"))
	var part_ctx := {"type": "item", "stack": test_item, "inventory": stash, "recycle_allowed": true}
	check(recycle["visible_if"].call(part_ctx) and recycle["enabled_if"].call(part_ctx) == "CAN'T RECYCLE",
			"shown greyed out on things that aren't salvage")
	var take := _action("item", "take")
	var fake_player := _FakePlayer.new()
	MechOS.set_player(fake_player)
	check(not take["visible_if"].call(ctx), "the stash isn't treated as loot")
	var wreck := Inventory.new()
	wreck.initialize_grid(4, 4)
	wreck.add_stack_anywhere(item_stack.from_generic(SCRAP))
	check(take["visible_if"].call({"type": "item", "stack": wreck.get_stacks()[0], "inventory": wreck}),
			"other inventories still are")
	MechOS.set_player(null)
	fake_player.free()
	recycle["run"].call(ctx)
	check(PlayerProgress.get_material_count("steel") == 100 and stash.is_empty(), "Recycle recycles the item")
	check(not recycle_all["visible_if"].call({"type": "inventory", "inventory": stash, "recycle_allowed": true}),
			"no Recycle all on an empty stash")


# Stands in for the player's mecha: just a cargo for MechOS to take into.
class _FakePlayer extends Node:
	var mech_inventory := Inventory.new()

	func _init() -> void:
		mech_inventory.initialize_grid(4, 4)


func _weapon_stack(part_type: String, part_id: String) -> item_stack:
	var entry := LootEntry.new()
	entry.part_type = part_type
	entry.part_id = part_id
	return entry.make_stack()


func _test_weapon_recycling() -> void:
	# Every weapon breaks down into known materials.
	for part_type in ["arm_weapon", "shoulder_weapon"]:
		for part_id in PartManager.get_parts(part_type):
			var weapon := _weapon_stack(part_type, part_id)
			var composition := weapon.get_composition()
			check(not composition.is_empty(), "%s has a composition" % part_id)
			check(weapon.get_tech_tier() in LootTable.ROLLED_TIERS, "%s has a tech tier" % part_id)
			for material_id in composition:
				check(Materials.is_valid(material_id), "%s uses known material %s" % [part_id, material_id])

	var stash := PlayerProgress.get_stash_inventory()
	var gun := _weapon_stack("arm_weapon", "MA-L127")
	var scrap := item_stack.from_generic(SCRAP)
	stash.add_stack_anywhere(gun)
	stash.add_stack_anywhere(scrap)
	check_eq(PlayerProgress.recycle_value(gun), {"steel": 1800, "copper": 150}, "weapon value is its composition (1.8 t Steel, 150 kg Copper)")
	PlayerProgress.recycle_all(stash)
	check(stash.get_stacks().has(gun) and not stash.get_stacks().has(scrap), "recycle_all takes salvage, not weapons")
	var gained := PlayerProgress.recycle_stack(stash, gun)
	check(gained == {"steel": 1800, "copper": 150} and stash.is_empty(), "a weapon recycles on its own")
	check(PlayerProgress.can_recycle(_weapon_stack("head", TEST_PART_ID)), "other parts can too, one at a time")

	# The menu asks before recycling a weapon, and Recycle all ignores them.
	var recycle := _action("item", "recycle")
	var recycle_all := _action("inventory", "recycle_all")
	var gun2 := _weapon_stack("arm_weapon", "MA-L127")
	stash.add_stack_anywhere(gun2)
	var ctx := {"type": "item", "stack": gun2, "inventory": stash, "recycle_allowed": true}
	check(recycle["enabled_if"].call(ctx) == "", "Recycle enabled on a weapon")
	check(recycle["confirm"].call(ctx) == "Confirm: recycle this part?", "weapons ask first")
	check(recycle_all["enabled_if"].call({"type": "inventory", "inventory": stash, "recycle_allowed": true}) == "NO SALVAGE",
			"a stash of only weapons has nothing for Recycle all")


# A .50 Cartridge is money: sold or recycled at home it pays 1 ct each, with
# no sell rate; out on an expedition it is cargo, lost with the mecha.
func _test_currency() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var rounds := item_stack.from_generic(CARTRIDGE, 250)
	stash.add_stack_anywhere(rounds)
	check(PlayerProgress.is_currency(rounds) and not PlayerProgress.is_currency(item_stack.from_generic(SCRAP)), "cartridges are currency")
	check_eq(PlayerProgress.sell_value(rounds), 250, "they sell 1 to 1")
	check(PlayerProgress.can_recycle(rounds) and PlayerProgress.recycle_value(rounds).is_empty(), "and recycle into no materials")
	PlayerProgress.recycle_stack(stash, rounds, false)
	check_eq(PlayerProgress.get_money(), 250.0, "recycling pays them 1 to 1 too")
	check(not stash.get_stacks().has(rounds), "and takes them")
	var more := item_stack.from_generic(CARTRIDGE, 40)
	stash.add_stack_anywhere(more)
	check_eq(PlayerProgress.sell_stack(stash, more, false), 40, "sold: 40 ct for 40")
	var recycle := _action("item", "recycle")
	var ctx := {"type": "item", "stack": item_stack.from_generic(CARTRIDGE, 7), "inventory": stash, "recycle_allowed": true}
	check_eq(recycle["label"].call(ctx), "Recycle (7 ct)", "the menu says what they pay")

	# Carried out, they are loot like anything else.
	var cargo := Inventory.new()
	cargo.initialize_grid(4, 4)
	cargo.add_stack_anywhere(item_stack.from_generic(CARTRIDGE, 100))
	PlayerProgress.set_mech_inventory(cargo)
	PlayerProgress.begin_expedition()
	check(not PlayerProgress.can_recycle(cargo.get_stacks()[0]), "not cashed in mid-run")
	var money := PlayerProgress.get_money()
	var report := PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)
	check(".50 Cartridge x100" in report.get("cargo", []), "lost with the mecha (%s)" % str(report.get("cargo")))
	check_eq(PlayerProgress.get_money(), money, "and never paid")


# With the setting on and Recycler Mk II, extracting recycles the cargo's
# salvage (currency into credits); parts stay. Off, or below Mk II, nothing.
func _test_auto_salvage() -> void:
	var fill := func() -> Inventory:
		var cargo := Inventory.new()
		cargo.initialize_grid(6, 6)
		cargo.add_stack_anywhere(item_stack.from_generic(SCRAP, 3))
		cargo.add_stack_anywhere(item_stack.from_generic(CARTRIDGE, 30))
		var part := LootEntry.new()
		part.part_type = "arm_weapon"
		part.part_id = "MA-L127"
		cargo.add_stack_anywhere(part.make_stack())
		PlayerProgress.set_mech_inventory(cargo)
		return cargo
	var run := func() -> void:
		PlayerProgress.begin_expedition()
		PlayerProgress.extract_expedition()

	Profile.set_option("auto_salvage", true)
	var cargo: Inventory = fill.call()
	run.call()
	check(not PlayerProgress.auto_salvage_on() and cargo.get_stacks().size() == 3, "Recycler Mk I: the setting does nothing")

	PlayerProgress.set_facility_level(Facilities.RECYCLER, 2)
	Profile.set_option("auto_salvage", false)
	cargo = fill.call()
	run.call()
	check(cargo.get_stacks().size() == 3 and PlayerProgress.get_materials().is_empty(), "setting off: the cargo comes home as it is")

	Profile.set_option("auto_salvage", true)
	cargo = fill.call()
	var money := PlayerProgress.get_money()
	run.call()
	check(PlayerProgress.auto_salvage_on(), "on, with Recycler Mk II")
	check_eq(PlayerProgress.get_material_count("steel"), 300, "the salvage turned into materials, 1 to 1")
	check_eq(PlayerProgress.last_auto_salvage, {"steel": 300}, "and what it gave is kept")
	check_eq(PlayerProgress.get_money(), money + 30, "the cartridges into credits")
	var left := cargo.get_stacks()
	check(left.size() == 1 and left[0].is_part(), "parts stay")
	Profile.set_option("auto_salvage", false)


func _test_required_parts() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	check(PlayerProgress.missing_parts(design).is_empty(), "default mecha has every required part")
	design["shoulder_weapon_left"] = false
	design["arm_weapon_right"] = false
	check(PlayerProgress.missing_parts(design).is_empty(), "weapons are optional")
	design["core"] = false
	design.erase("head")
	check(PlayerProgress.missing_parts(design) == ["head", "core"], "empty and absent slots are missing")
	check(PlayerProgress.describe_missing_parts(["head", "core"]) == "HEAD, CORE", "described for messages")
	check(PlayerProgress.missing_parts(null).size() == PlayerProgress.REQUIRED_SLOTS.size(), "no design misses everything")
