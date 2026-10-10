extends Node

# PlayerProgressTest runs self-checks against the PlayerProgress autoload:
# money, parts in the stash, save round-trip and migration of pre-PlayerProgress
# saves, Expedition stakes (begin/extract/lose, abandoned runs) and
# recycling salvage into materials.
# Open PlayerProgressTest.tscn and press F6; results print to Output.
#
# The player's real progress is snapshotted first and restored at the end,
# and autosave is off while the checks run, so the profile is never touched.

const TEST_PART_TYPE := "head"
const TEST_PART_ID := "MSV-L3J-H"
const SALVAGE := preload("res://database/items/salvage/fusion_cell.tres")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var saved_state = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.autosave = false

	_run("money", _test_money)
	_run("parts in the stash", _test_parts)
	_run("save data survives JSON round-trip", _test_save_round_trip)
	_run("legacy save migration", _test_legacy_migration)
	_run("extracting keeps mecha and cargo", _test_extract)
	_run("losing an expedition", _test_lose)
	_run("no loss outside an expedition", _test_lose_without_expedition)
	_run("abandoned run resolved on load", _test_abandoned)
	_run("materials", _test_materials)
	_run("recycling", _test_recycling)
	_run("no recycling mid-run", _test_no_recycling_in_expedition)
	_run("recycle menu actions", _test_recycle_actions)

	PlayerProgress.set_save_data(saved_state)
	PlayerProgress.autosave = true

	print("[PlayerProgressTest] %d passed, %d failed" % [_passed, _failed])


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
		push_error("[PlayerProgressTest] FAIL " + message)


func _test_money() -> void:
	PlayerProgress.add_money(500)
	_check(PlayerProgress.get_money() == 500, "add_money")
	_check(not PlayerProgress.spend_money(501), "can't overspend")
	_check(PlayerProgress.get_money() == 500, "failed spend changes nothing")
	_check(PlayerProgress.spend_money(200), "spend_money")
	_check(PlayerProgress.get_money() == 300, "balance after spend")


func _test_parts() -> void:
	_check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 0, "stash starts empty")
	_check(PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID), "add_part")
	_check(PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID), "add_part again")
	_check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 2, "count_part")
	_check(PlayerProgress.get_owned_parts(TEST_PART_TYPE).has(TEST_PART_ID), "get_owned_parts by type")
	_check(PlayerProgress.get_owned_parts("core").is_empty(), "get_owned_parts filters type")
	_check(PlayerProgress.remove_part(TEST_PART_TYPE, TEST_PART_ID), "remove_part")
	_check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "count after remove")
	_check(not PlayerProgress.remove_part("core", TEST_PART_ID), "remove_part checks type")


func _test_save_round_trip() -> void:
	PlayerProgress.add_money(1234)
	PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID)
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "TORI-ML"
	PlayerProgress.set_current_mecha(design)

	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))

	_check(PlayerProgress.get_money() == 1234, "money restored")
	_check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "stash part restored with type and id")
	_check(PlayerProgress.get_current_mecha()["shoulder_weapon_left"] == "TORI-ML", "mecha restored")


func _test_legacy_migration() -> void:
	var legacy_design := PlayerProgress.DEFAULT_MECHA.duplicate()
	legacy_design.erase("thruster")  # simulate a slot added after the save
	var legacy_save := {
		"stats": {"gameover": 0, "money": 777, "current_mecha": legacy_design},
		"stash_inventory": {},
		"mech_inventory": {},
	}
	PlayerProgress.set_save_data(PlayerProgress.migrate_legacy_save(legacy_save))
	_check(PlayerProgress.get_money() == 777, "legacy money")
	_check(PlayerProgress.get_current_mecha().get("thruster") == PlayerProgress.DEFAULT_MECHA["thruster"], "missing slot filled from default")
	_check(PlayerProgress.get_stash_inventory().grid_width == PlayerProgress.STASH_SIZE.x, "empty legacy stash gets default size")

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
	_check(PlayerProgress.is_in_expedition(), "begin_expedition starts a run")
	PlayerProgress.extract_expedition()
	_check(not PlayerProgress.is_in_expedition(), "extract ends the run")
	_check(_cargo_count() == 1, "cargo kept")
	_check(PlayerProgress.get_current_mecha()["shoulder_weapon_left"] == "TORI-ML", "mecha kept")
	_check(not PlayerProgress.has_loss_report(), "no loss report")


func _test_lose() -> void:
	_kit_out()
	PlayerProgress.add_money(300)
	PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID)
	PlayerProgress.begin_expedition()
	var report := PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)

	_check(not PlayerProgress.is_in_expedition(), "losing ends the run")
	_check(_cargo_count() == 0, "cargo emptied")
	_check(PlayerProgress.get_current_mecha() == PlayerProgress.DEFAULT_MECHA, "back in the default mecha")
	_check(PlayerProgress.get_money() == 300, "money safe")
	_check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "stash safe")

	_check(report.get("reason") == PlayerProgress.LOSS_DESTROYED, "report has the reason")
	_check(SALVAGE.display_name in report.get("cargo", []), "report lists the cargo")
	_check(report.get("mecha", []).size() >= 8, "report lists the equipped parts")
	_check(SALVAGE.display_name in PlayerProgress.format_loss_report(report), "formatted text names the cargo")

	_check(PlayerProgress.has_loss_report(), "report pending until shown")
	_check(PlayerProgress.take_loss_report() == report, "take_loss_report returns it")
	_check(not PlayerProgress.has_loss_report(), "only shown once")


func _test_lose_without_expedition() -> void:
	_kit_out()
	_check(PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED).is_empty(), "nothing to lose")
	_check(_cargo_count() == 1, "cargo untouched")
	_check(PlayerProgress.get_current_mecha()["shoulder_weapon_left"] == "TORI-ML", "mecha untouched")
	_check(not PlayerProgress.resolve_abandoned_expedition(), "no abandoned run to resolve")


func _test_abandoned() -> void:
	# A save written mid-run, as if the game closed during an expedition.
	_kit_out()
	PlayerProgress.begin_expedition()
	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	_check(PlayerProgress.is_in_expedition(), "in-expedition flag saved")
	_check(_cargo_count() == 1, "loading alone doesn't lose anything")

	_check(PlayerProgress.resolve_abandoned_expedition(), "abandoned run resolved")
	_check(_cargo_count() == 0, "abandoned cargo lost")
	_check(PlayerProgress.get_current_mecha() == PlayerProgress.DEFAULT_MECHA, "abandoned mecha lost")

	# The pending report survives a save, so a crash can't hide it.
	json = JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	var report := PlayerProgress.take_loss_report()
	_check(report.get("reason") == PlayerProgress.LOSS_ABANDONED, "pending report saved with its reason")

# ---- Materials and recycling ----

const SCRAP := preload("res://database/items/salvage/scrap_plating.tres")   # 3 scrap_metal


func _test_materials() -> void:
	_check(PlayerProgress.get_materials().is_empty(), "no materials at first")
	PlayerProgress.add_materials({"scrap_metal": 3, "electronics": 1})
	PlayerProgress.add_materials({"scrap_metal": 2})
	_check(PlayerProgress.get_material_count("scrap_metal") == 5, "amounts add up")
	_check(PlayerProgress.get_material_count("rare_alloys") == 0, "missing material is 0")

	var json := JSON.stringify(PlayerProgress.get_save_data())
	PlayerProgress.reset()
	PlayerProgress.set_save_data(JSON.parse_string(json))
	_check(PlayerProgress.get_material_count("scrap_metal") == 5, "materials survive a save")
	_check(typeof(PlayerProgress.get_materials()["scrap_metal"]) == TYPE_INT, "loaded as whole numbers")


func _test_recycling() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var scrap := item_stack.from_generic(SCRAP, 2)
	var cell := item_stack.from_generic(SALVAGE)  # fusion cell: 2 power_cells, 1 rare_alloys
	stash.add_stack_anywhere(scrap)
	stash.add_stack_anywhere(cell)
	PlayerProgress.add_part(TEST_PART_TYPE, TEST_PART_ID)

	_check(PlayerProgress.recycle_value(scrap) == {"scrap_metal": 6}, "value counts the whole stack")
	var part_stack: item_stack = null
	for stack in stash.get_stacks():
		if stack.kind == item_stack.ItemKind.PART:
			part_stack = stack
	_check(not PlayerProgress.can_recycle(part_stack), "parts can't be recycled")

	var gained := PlayerProgress.recycle_stack(stash, scrap)
	_check(gained == {"scrap_metal": 6}, "recycle_stack returns what it gave")
	_check(PlayerProgress.get_material_count("scrap_metal") == 6, "materials added")
	_check(not stash.get_stacks().has(scrap), "recycled stack removed")
	_check(PlayerProgress.recycle_stack(stash, scrap).is_empty(), "can't recycle it twice")

	PlayerProgress.recycle_all(stash)
	_check(PlayerProgress.get_material_count("power_cells") == 2 and PlayerProgress.get_material_count("rare_alloys") == 1,
			"recycle_all gives everything's materials")
	_check(PlayerProgress.count_part(TEST_PART_TYPE, TEST_PART_ID) == 1, "recycle_all leaves parts alone")


func _test_no_recycling_in_expedition() -> void:
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 6)
	var scrap := item_stack.from_generic(SCRAP)
	cargo.add_stack_anywhere(scrap)
	PlayerProgress.begin_expedition()
	_check(not PlayerProgress.can_recycle(scrap), "can't recycle during a run")
	_check(PlayerProgress.recycle_all(cargo).is_empty() and cargo.get_stacks().has(scrap), "nothing recycled mid-run")
	PlayerProgress.extract_expedition()
	_check(PlayerProgress.can_recycle(scrap), "recyclable once home")


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
	_check(not recycle.is_empty() and not recycle_all.is_empty(), "recycle actions registered")

	var ctx := {"type": "item", "stack": scrap, "inventory": stash}
	_check(not recycle["visible_if"].call(ctx), "hidden where recycling isn't allowed (Mech OS mid-run)")
	ctx["recycle_allowed"] = true
	_check(recycle["visible_if"].call(ctx), "shown in the Hangar")
	recycle["run"].call(ctx)
	_check(PlayerProgress.get_material_count("scrap_metal") == 3 and stash.is_empty(), "Recycle recycles the item")
	_check(not recycle_all["visible_if"].call({"type": "inventory", "inventory": stash, "recycle_allowed": true}),
			"no Recycle all on an empty stash")
