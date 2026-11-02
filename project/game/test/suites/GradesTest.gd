extends TestSuite

# GradesTest: part grades (Grades). The grade table; wreck weapon drops
# rolling grades at their odds; a grade scaling what a part sells for,
# recycles into and costs to repair; grades scaling the summed stats of a
# real mecha (Mecha.get_stat, its walk speed, StatsPanel.sum_stat) and
# nothing else; grades surviving a save round trip, old saves loading as
# Standard; names showing the grade; and a lost expedition resetting them.
# Each case starts from fresh progress (PlayerProgress.reset).

const MECHA := preload("res://game/mecha/Mecha.tscn")
const GUN := "MA-L127"


func run_tests() -> void:
	await case("the grade table", _test_table)
	await case("wreck weapons roll grades at their odds", _test_drop_odds)
	await case("grade scales value, recycling and repairs", _test_value_and_recycling)
	await case("grade scales a mecha's summed stats", _test_mecha_stats)
	await case("grades survive saving and loading", _test_save_round_trip)
	await case("old saves load as Standard", _test_old_saves)
	await case("names show the grade", _test_names)
	await case("losing an expedition resets the grades", _test_lose_resets)


func before_each() -> void:
	PlayerProgress.reset()


func _gun(grade: String) -> item_stack:
	var entry := LootEntry.new()
	entry.part_type = "arm_weapon"
	entry.part_id = GUN
	var stack := entry.make_stack()
	stack.grade = grade
	return stack


func _make_mecha(grades: Dictionary) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.part_grades = grades
	add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	return mecha


func _test_table() -> void:
	check_eq(Grades.ALL, [Grades.SCRAP, Grades.STANDARD, Grades.REFINED, Grades.PROTOTYPE], "four grades, worst to best")
	var expected := {  # stats, value, recycle
		Grades.SCRAP: [0.9, 0.5, 0.5], Grades.STANDARD: [1.0, 1.0, 1.0],
		Grades.REFINED: [1.05, 1.6, 1.25], Grades.PROTOTYPE: [1.1, 2.5, 1.5],
	}
	for grade in expected:
		var want: Array = expected[grade]
		check(is_equal_approx(Grades.stat_mult(grade, "weight_capacity"), want[0]), "%s stats x%s" % [grade, want[0]])
		check(is_equal_approx(Grades.value_mult(grade), want[1]), "%s value x%s" % [grade, want[1]])
		check(is_equal_approx(Grades.recycle_mult(grade), want[2]), "%s recycling x%s" % [grade, want[2]])
	check_eq(Grades.stat_mult(Grades.PROTOTYPE, "weight"), 1.0, "weight isn't a graded stat")
	check_eq(Grades.stat_mult(Grades.PROTOTYPE, "battery_capacity"), 1.0, "nor are stats read off the part directly")
	check_eq(Grades.of("legendary"), Grades.STANDARD, "anything unknown counts as Standard")
	check_eq(Grades.of(null), Grades.STANDARD, "so does nothing")
	check_eq(Grades.label(Grades.REFINED, "Gun"), "Refined Gun", "graded names say their grade")
	check_eq(Grades.label(Grades.STANDARD, "Gun"), "Gun", "Standard ones don't")
	check_eq(Grades.short_name(Grades.STANDARD), "", "Standard tiles show no tag")
	check_eq(_gun(Grades.STANDARD).grade, Grades.STANDARD, "a new stack is Standard")
	check_eq(item_stack.new().grade, Grades.STANDARD, "every stack starts Standard")


func _test_drop_odds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var counts := {}
	var rolls := 20000
	for i in rolls:
		var grade := Grades.roll(rng)
		counts[grade] = counts.get(grade, 0) + 1
	var odds := {Grades.SCRAP: 0.45, Grades.STANDARD: 0.45, Grades.REFINED: 0.09, Grades.PROTOTYPE: 0.01}
	for grade in odds:
		var share := float(counts.get(grade, 0)) / rolls
		check(absf(share - odds[grade]) < 0.015, "%s about %d%% of drops (%.1f%%)" % [grade, roundi(odds[grade] * 100), share * 100])
	var weapon := WreckLoot.weapon_stack("arm_weapon_left", GUN, rng)
	check(weapon != null and Grades.is_valid(weapon.grade), "a wreck's weapon drop has a grade")
	var seen := {}
	for i in 400:
		seen[WreckLoot.weapon_stack("arm_weapon_right", GUN, rng).grade] = true
	check(seen.size() >= 3, "and drops vary (%s)" % str(seen.keys()))


func _test_value_and_recycling() -> void:
	var price: float = PartManager.get_part("arm_weapon", GUN).price
	for grade in Grades.ALL:
		check_eq(PlayerProgress.sell_value(_gun(grade)), int(floor(price * Grades.value_mult(grade) * PlayerProgress.SELL_RATE)),
				"a %s gun sells for %s of its price, halved" % [grade, Grades.value_mult(grade)])
	check(PlayerProgress.sell_value(_gun(Grades.PROTOTYPE)) > PlayerProgress.sell_value(_gun(Grades.SCRAP)) * 4,
			"a Prototype is worth five Scraps")

	var composition: Dictionary = _gun(Grades.STANDARD).get_composition()
	check_eq(PlayerProgress.recycle_value(_gun(Grades.STANDARD)), composition, "a Standard gun recycles into its composition")
	for grade in [Grades.SCRAP, Grades.REFINED, Grades.PROTOTYPE]:
		var got := PlayerProgress.recycle_value(_gun(grade))
		for material_id in composition:
			var want := int(floor(composition[material_id] * Grades.recycle_mult(grade)))
			check_eq(int(got.get(material_id, 0)), want, "%s: %s %s -> %d" % [grade, composition[material_id], material_id, want])

	var plain := _make_mecha({})
	var proto := _make_mecha({"core": Grades.PROTOTYPE})
	await wait_frames()
	check(is_equal_approx(RepairBill.section_value(proto, "core") - RepairBill.section_value(plain, "core"),
			plain.build.core.price * 1.5), "a Prototype core costs 2.5x to repair")
	check_eq(RepairBill.section_value(proto, "head"), RepairBill.section_value(plain, "head"), "other sections unchanged")
	plain.queue_free()
	proto.queue_free()


func _test_mecha_stats() -> void:
	var plain := _make_mecha({})
	var graded := _make_mecha({"core": Grades.PROTOTYPE, "chassis": Grades.SCRAP})
	await wait_frames()
	var core = plain.build.core
	var chassis = plain.build.chassis
	for stat in ["weight_capacity", "stability"]:
		var want: float = plain.get_stat(stat) + (core.get(stat) if core.get(stat) else 0.0) * 0.1 \
				- (chassis.get(stat) if chassis.get(stat) else 0.0) * 0.1
		check(is_equal_approx(graded.get_stat(stat), want),
				"%s: Prototype core +10%%, Scrap chassis -10%% (%.1f -> %.1f)" % [stat, plain.get_stat(stat), graded.get_stat(stat)])
	check_eq(graded.get_stat("weight"), plain.get_stat("weight"), "weight is the same whatever the grade")
	check(is_equal_approx(graded.max_speed, chassis.max_speed * 0.9), "a Scrap chassis walks 10% slower")
	check(is_equal_approx(plain.max_speed, chassis.max_speed), "a Standard one at its own speed")
	check(is_equal_approx(StatsPanel.sum_stat(graded.build, "weight_capacity", graded.part_grades),
			graded.get_stat("weight_capacity")), "the stats panel adds up the same as the mecha")
	check(is_equal_approx(StatsPanel.sum_stat(graded.build, "weight_capacity"), plain.get_stat("weight_capacity")),
			"and without grades counts everything as Standard")
	plain.queue_free()
	graded.queue_free()


func _test_save_round_trip() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	stash.add_stack_anywhere(_gun(Grades.REFINED))
	stash.add_stack_anywhere(_gun(Grades.STANDARD))
	check(PlayerProgress.add_part("head", "MSV-L3J-H", false, Grades.SCRAP), "add_part takes a grade")
	PlayerProgress.set_current_grades({"core": Grades.PROTOTYPE, "head": Grades.STANDARD,
			"not_a_slot": Grades.REFINED, "chassis": "legendary"})
	check_eq(PlayerProgress.get_current_grades(), {"core": Grades.PROTOTYPE},
			"only real slots with a grade other than Standard are kept")

	var data = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	var saved_items: Array = data["stash_inventory"]["items"]
	check(saved_items.any(func(e): return e.get("grade") == Grades.REFINED), "the Refined gun saves its grade")
	check(saved_items.filter(func(e): return e.has("grade")).size() == 2, "Standard parts save no grade")
	PlayerProgress.reset()
	PlayerProgress.set_save_data(data)

	var grades := {}
	for stack in PlayerProgress.get_stash_inventory().get_stacks():
		grades[stack.item_id + ":" + stack.grade] = true
	check(grades.has(GUN + ":" + Grades.REFINED) and grades.has(GUN + ":" + Grades.STANDARD), "both guns load with their grades")
	check(grades.has("MSV-L3J-H:" + Grades.SCRAP), "and the Scrap head")
	check_eq(PlayerProgress.get_current_grades(), {"core": Grades.PROTOTYPE}, "the fitted parts' grades load")


func _test_old_saves() -> void:
	PlayerProgress.get_stash_inventory().add_stack_anywhere(_gun(Grades.STANDARD))
	var data: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	data.erase("current_grades")
	PlayerProgress.reset()
	PlayerProgress.set_save_data(data)
	check_eq(PlayerProgress.get_current_grades(), {}, "a save from before grades fits Standard parts")
	check_eq(PlayerProgress.get_stash_inventory().get_stacks()[0].grade, Grades.STANDARD, "and its parts are Standard")


func _test_names() -> void:
	var cargo := PlayerProgress.get_mech_inventory()
	cargo.initialize_grid(8, 8)
	cargo.add_stack_anywhere(_gun(Grades.PROTOTYPE))
	var gun_name := str(PartManager.get_part("arm_weapon", GUN).part_name)
	check(PlayerProgress.describe_cargo().has("Prototype " + gun_name), "the cargo list names the grade")


func _test_lose_resets() -> void:
	PlayerProgress.set_current_grades({"core": Grades.REFINED})
	PlayerProgress.begin_expedition()
	var report := PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)
	var core_name := str(PartManager.get_part("core", PlayerProgress.DEFAULT_MECHA.core).part_name)
	check(report.mecha.has("Refined " + core_name), "the loss report names what was lost, grade and all")
	check_eq(PlayerProgress.get_current_grades(), {}, "the replacement mecha is all Standard")
