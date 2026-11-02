extends TestSuite

# FacilitiesTest: the Hangar facilities (Facilities, FAC app). Where they
# start; what an upgrade costs and what stops it (credits, materials, the top
# level), paying nothing when refused; the Recycler raising yields (and the
# tooltip saying so), the
# Workshop cutting a real mecha's repair bill, the Stash growing with every
# item left in place, the Fabricator's grade odds; levels saving; and the
# FAC window showing and buying upgrades.
# Each case starts from fresh progress (PlayerProgress.reset).

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLATE := preload("res://database/items/salvage/armor_plate_fragment.tres")  # 3 steel


func run_tests() -> void:
	await case("where the facilities start", _test_start)
	await case("upgrading and what stops it", _test_upgrading)
	await case("the Recycler raises yields", _test_recycler)
	await case("the Workshop cuts repair bills", _test_workshop)
	await case("the Stash grows and keeps its items", _test_stash)
	await case("the Fabricator's grades", _test_fabricator_grades)
	await case("facility levels save", _test_save)
	await case("the FAC window", _test_window)


func before_each() -> void:
	PlayerProgress.reset()


func _test_start() -> void:
	check_eq(Facilities.level(Facilities.RECYCLER), 1, "Recycler Mk I")
	check_eq(Facilities.level(Facilities.WORKSHOP), 1, "Workshop Mk I")
	check_eq(Facilities.level(Facilities.FABRICATOR), 0, "no Fabricator yet")
	check_eq(Facilities.level(Facilities.STASH), 1, "Stash Mk I")
	check_eq(Facilities.recycle_mult(), 1.0, "recycling as is")
	check_eq(Facilities.repair_mult(), 1.0, "repairs at full price")
	check_eq(Facilities.stash_size(), PlayerProgress.STASH_SIZE, "the stash at its starting size")
	check_eq(Facilities.next_cost(Facilities.FABRICATOR).credits, 1500, "building a Fabricator costs 1,500 ct")


func _test_upgrading() -> void:
	check_eq(Facilities.upgrade_block_reason(Facilities.WORKSHOP), "NOT ENOUGH CREDITS", "no credits")
	check(not Facilities.upgrade(Facilities.WORKSHOP), "upgrade refuses")
	PlayerProgress.add_money(2500, false)
	check(Facilities.upgrade(Facilities.WORKSHOP), "with 2,000 ct it goes through")
	check_eq(Facilities.level(Facilities.WORKSHOP), 2, "Workshop Mk II")
	check_eq(PlayerProgress.get_money(), 500.0, "and was paid for")
	check(is_equal_approx(Facilities.repair_mult(), 0.8), "repairs x0.8")

	PlayerProgress.add_money(10000, false)
	check_eq(Facilities.upgrade_block_reason(Facilities.RECYCLER), "NOT ENOUGH MATERIALS", "the Recycler needs materials too")
	check(not Facilities.upgrade(Facilities.RECYCLER) and PlayerProgress.get_money() == 10500.0, "refused, nothing paid")
	PlayerProgress.add_materials(Facilities.next_cost(Facilities.RECYCLER).materials, false)
	check(Facilities.upgrade(Facilities.RECYCLER), "with them it goes through")
	check(PlayerProgress.get_material_count("steel") == 0 and PlayerProgress.get_money() == 8000.0, "materials and credits paid")

	PlayerProgress.set_facility_level(Facilities.WORKSHOP, 3)
	check_eq(Facilities.upgrade_block_reason(Facilities.WORKSHOP), "MAX LEVEL", "nothing past Mk III")
	check(Facilities.next_cost(Facilities.WORKSHOP).is_empty() and not Facilities.upgrade(Facilities.WORKSHOP), "so nothing to buy")

	PlayerProgress.charge_repairs(20000, false)
	check_eq(Facilities.upgrade_block_reason(Facilities.STASH), "NOT ENOUGH CREDITS", "nothing in debt")


func _test_recycler() -> void:
	var plates := item_stack.from_generic(PLATE, 4)
	var want := {1: 12, 2: 15, 3: 18}
	for at in want:
		PlayerProgress.set_facility_level(Facilities.RECYCLER, at)
		check_eq(PlayerProgress.recycle_value(plates).get("steel", 0), want[at],
				"Recycler Mk %d: 4 plates give %d steel" % [at, want[at]])
	PlayerProgress.set_facility_level(Facilities.RECYCLER, 2)
	check_eq(PlayerProgress.recycle_value(item_stack.from_generic(PLATE)).get("steel", 0), 4,
			"Mk II rounds 3.75 up, so one plate gains too")

	# The tooltip says what one really gives, Recycler included.
	var tooltip: ItemTooltip = load("res://game/mecha/ItemTooltip.tscn").instantiate()
	add_child(tooltip)
	tooltip.show_item(plates)
	check("Recycles into: 4 Steel" in tooltip.stats_label.text, "the tooltip shows the Recycler's yield, per item (%s)" % tooltip.stats_label.text)
	tooltip.queue_free()


func _test_workshop() -> void:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	await wait_frames()
	for comp in mecha.components.core.values():
		comp.hp = 0
	var full := RepairBill.estimate(mecha)
	check(full > 0, "a wrecked core costs something (%d)" % full)
	PlayerProgress.set_facility_level(Facilities.WORKSHOP, 3)
	var cut := RepairBill.estimate(mecha)
	check(absi(cut - roundi(full * 0.6)) <= 1, "Workshop Mk III: 60%% of the bill (%d -> %d)" % [full, cut])
	mecha.queue_free()


func _test_stash() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var low := item_stack.from_generic(PLATE)
	check(stash.place_item(low, 0, 18), "an item near the bottom of the stash")
	PlayerProgress.add_money(1500, false)
	check(Facilities.upgrade(Facilities.STASH), "Stash Mk II bought")
	check_eq(Vector2i(stash.grid_width, stash.grid_height), Vector2i(8, 26), "the stash grew to 8 x 26")
	check(stash.grid[18][0].stack == low, "the item stayed where it was")
	check(stash.place_item(item_stack.from_generic(PLATE), 0, 25), "the new rows hold items")

	var data: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.reset()
	check_eq(PlayerProgress.get_stash_inventory().grid_height, 20, "a fresh profile's stash is 20 high")
	PlayerProgress.set_save_data(data)
	check_eq(PlayerProgress.get_stash_inventory().grid_height, 26, "the bigger stash loads")

	data["stash_inventory"]["grid_height"] = 20  # saved before the stash grew
	data["stash_inventory"]["items"] = []
	PlayerProgress.set_save_data(data)
	check_eq(PlayerProgress.get_stash_inventory().grid_height, 26, "a stash smaller than its level grows on load")
	PlayerProgress.reset()
	PlayerProgress.set_facility_level(Facilities.STASH, 3)
	check_eq(PlayerProgress.get_stash_inventory().grid_height, 32, "a new stash is made at the Stash's size")


func _test_fabricator_grades() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var expected := {1: {}, 2: {Grades.REFINED: 0.2}, 3: {Grades.REFINED: 0.35, Grades.PROTOTYPE: 0.05}}
	for at in expected:
		PlayerProgress.set_facility_level(Facilities.FABRICATOR, at)
		var counts := {}
		var rolls := 6000
		for i in rolls:
			var grade := Fabricator.output_grade(rng)
			counts[grade] = counts.get(grade, 0) + 1
		for grade in [Grades.REFINED, Grades.PROTOTYPE]:
			var share := float(counts.get(grade, 0)) / rolls
			var want: float = expected[at].get(grade, 0.0)
			check(absf(share - want) < 0.02, "Mk %d: %s about %d%% (%.1f%%)" % [at, grade, roundi(want * 100), share * 100])
		check(not counts.has(Grades.SCRAP), "Mk %d never builds Scrap" % at)


func _test_save() -> void:
	PlayerProgress.set_facility_level(Facilities.RECYCLER, 3)
	PlayerProgress.set_facility_level(Facilities.FABRICATOR, 2)
	var data: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	data["facilities"]["workshop"] = 9
	data["facilities"]["teleporter"] = 2
	PlayerProgress.reset()
	PlayerProgress.set_save_data(data)
	check_eq(Facilities.level(Facilities.RECYCLER), 3, "the Recycler loads at Mk III")
	check_eq(Facilities.level(Facilities.FABRICATOR), 2, "the Fabricator at Mk II")
	check_eq(Facilities.level(Facilities.WORKSHOP), 3, "a level past the top is clamped")
	check(not PlayerProgress.facilities.has("teleporter"), "unknown facilities are dropped")
	data.erase("facilities")
	PlayerProgress.set_save_data(data)
	check_eq(Facilities.level(Facilities.FABRICATOR), 0, "a save from before facilities starts them fresh")


func _test_window() -> void:
	MechOS.set_app_available("facilities", true)
	var window: FacilitiesWindow = MechOS.open_app("facilities")
	check(window != null, "FAC opens")
	if window == null:
		return
	for id in Facilities.ALL:
		check(window.get_text(id).begins_with(Facilities.display_name(id).to_upper()), "a section for the %s" % id)
	check("NOT BUILT" in window.get_text(Facilities.FABRICATOR), "the Fabricator shows as not built")
	check_eq(window.upgrade_buttons[Facilities.FABRICATOR].text, "BUILD", "with a BUILD button")
	var workshop: Button = window.upgrade_buttons[Facilities.WORKSHOP]
	check(workshop.disabled and window.reason_labels[Facilities.WORKSHOP].text == "NOT ENOUGH CREDITS",
			"can't upgrade without credits, and says why")
	check("0 / 2000 CT" in window.get_text(Facilities.WORKSHOP), "the cost shows had / needed")

	PlayerProgress.add_money(2000, false)
	await wait_frames()  # the window refreshes on the next frame
	workshop = window.upgrade_buttons[Facilities.WORKSHOP]
	check(not workshop.disabled, "enabled once affordable")
	workshop.pressed.emit()
	check_eq(Facilities.level(Facilities.WORKSHOP), 2, "UPGRADE buys the next level")
	check("WORKSHOP · MK II" in window.get_text(Facilities.WORKSHOP), "and the window shows it")
	MechOS.close_app("facilities")
