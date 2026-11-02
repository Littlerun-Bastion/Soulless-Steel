extends TestSuite

# FabricatorTest: blueprints and the Fabricator (Fabricator, FAB app).
# Recycling copies of a part teaches its blueprint (one Refined copy is
# enough; salvage teaches nothing); a build costs twice the part's
# composition plus a quarter of its price; the Fabricator refuses when it
# isn't built, without a blueprint, for high tech below Mk II, without the
# materials, credits or stash room, and then takes nothing; a build puts a Standard part in the stash and
# pays for it; blueprints save; and the FAB window lists, explains and builds.
# Each case starts from fresh progress (PlayerProgress.reset).

const CHEAP := ["core", "Null"]             # low tech, price 250
const HIGH := ["core", "Lancelot-Core"]     # high tech
const PLATE := preload("res://database/items/salvage/armor_plate_fragment.tres")


func run_tests() -> void:
	await case("recycling parts teaches blueprints", _test_learning)
	await case("what a build costs", _test_costs)
	await case("what stops a build", _test_block_reasons)
	await case("building a part", _test_build)
	await case("blueprints save", _test_save)
	await case("the FAB window", _test_window)


# A Fabricator Mk I is built for every case (the facility starts unbuilt;
# FacilitiesTest covers that).
func before_each() -> void:
	PlayerProgress.reset()
	PlayerProgress.set_facility_level(Facilities.FABRICATOR, 1)


func _part(entry: Array, grade := Grades.STANDARD) -> item_stack:
	var stack := item_stack.new()
	stack.kind = item_stack.ItemKind.PART
	stack.item_category = "part"
	stack.item_type = entry[0]
	stack.item_id = entry[1]
	stack.grade = grade
	return stack


func _recycle(entry: Array, grade := Grades.STANDARD) -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var stack := _part(entry, grade)
	stash.add_stack_anywhere(stack)
	check(not PlayerProgress.recycle_stack(stash, stack, false).is_empty(), "%s %s recycles" % [grade, entry[1]])


# Enough of everything to build the entry.
func _stock_up(entry: Array) -> void:
	PlayerProgress.add_materials(Fabricator.material_cost(entry[0], entry[1]), false)
	PlayerProgress.add_money(Fabricator.credit_cost(entry[0], entry[1]), false)


func _learn(entry: Array) -> void:
	PlayerProgress.blueprints[PlayerProgress.blueprint_key(entry[0], entry[1])] = PlayerProgress.BLUEPRINT_COPIES


func _test_learning() -> void:
	var changed := [0]
	var on_changed := func(): changed[0] += 1
	PlayerProgress.blueprints_changed.connect(on_changed)
	check(not PlayerProgress.knows_blueprint(CHEAP[0], CHEAP[1]), "nothing known at first")
	for copy in range(1, PlayerProgress.BLUEPRINT_COPIES + 1):
		_recycle(CHEAP)
		check_eq(PlayerProgress.blueprint_progress(CHEAP[0], CHEAP[1]), copy, "copy %d recycled" % copy)
	check(PlayerProgress.knows_blueprint(CHEAP[0], CHEAP[1]), "three copies teach it")
	check_eq(changed[0], 3, "each step is announced")
	_recycle(CHEAP)
	check_eq(PlayerProgress.blueprint_progress(CHEAP[0], CHEAP[1]), PlayerProgress.BLUEPRINT_COPIES, "and it stays known")

	_recycle(HIGH, Grades.REFINED)
	check(PlayerProgress.knows_blueprint(HIGH[0], HIGH[1]), "one Refined copy teaches it at once")
	_recycle(["arm_weapon", "MA-L127"], Grades.SCRAP)
	check_eq(PlayerProgress.blueprint_progress("arm_weapon", "MA-L127"), 1, "weapons count too; Scrap is a single step")

	var stash := PlayerProgress.get_stash_inventory()
	var plate := item_stack.from_generic(PLATE)
	stash.add_stack_anywhere(plate)
	PlayerProgress.recycle_stack(stash, plate, false)
	check_eq(PlayerProgress.get_blueprints().size(), 3, "salvage teaches nothing")
	PlayerProgress.blueprints_changed.disconnect(on_changed)


func _test_costs() -> void:
	var part = PartManager.get_part(CHEAP[0], CHEAP[1])
	var cost := Fabricator.material_cost(CHEAP[0], CHEAP[1])
	check(not cost.is_empty(), "a part costs materials")
	for material_id in part.composition:
		check_eq(cost[material_id], part.composition[material_id] * 2, "twice its %s" % material_id)
	check_eq(Fabricator.credit_cost(CHEAP[0], CHEAP[1]), int(ceil(part.price * 0.25)), "plus a quarter of its price in credits")
	check(Fabricator.credit_cost(CHEAP[0], CHEAP[1]) < part.price, "far less than the Store")
	check(Fabricator.material_cost("core", "no_such_core").is_empty(), "nothing for parts that don't exist")


func _test_block_reasons() -> void:
	check_eq(Fabricator.block_reason("core", "no_such_core"), "CAN'T BE BUILT", "a part that doesn't exist")
	PlayerProgress.set_facility_level(Facilities.FABRICATOR, 0)
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "NO FABRICATOR: BUILD ONE IN FAC", "no Fabricator built")
	PlayerProgress.set_facility_level(Facilities.FABRICATOR, 1)
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "NO BLUEPRINT", "no blueprint")
	_learn(CHEAP)
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "NOT ENOUGH MATERIALS", "no materials")
	PlayerProgress.add_materials(Fabricator.material_cost(CHEAP[0], CHEAP[1]), false)
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "NOT ENOUGH CREDITS", "no credits")
	PlayerProgress.add_money(Fabricator.credit_cost(CHEAP[0], CHEAP[1]), false)
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "", "everything in place")

	var stash := PlayerProgress.get_stash_inventory()
	var tiny := Inventory.new()
	tiny.initialize_grid(1, 1)
	PlayerProgress.set_stash_inventory(tiny)
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "STASH FULL", "no room in the stash")
	check(Fabricator.build(CHEAP[0], CHEAP[1]) == null, "build refuses")
	check(PlayerProgress.has_materials(Fabricator.material_cost(CHEAP[0], CHEAP[1]))
			and PlayerProgress.can_afford(Fabricator.credit_cost(CHEAP[0], CHEAP[1])), "and takes nothing")
	PlayerProgress.set_stash_inventory(stash)

	_learn(HIGH)
	_stock_up(HIGH)
	check_eq(Fabricator.level(), 1, "at Mk I")
	check_eq(Fabricator.block_reason(HIGH[0], HIGH[1]), "NEEDS FABRICATOR MK II", "high tech needs Mk II")
	PlayerProgress.set_facility_level(Facilities.FABRICATOR, 2)
	check_eq(Fabricator.block_reason(HIGH[0], HIGH[1]), "", "which builds it")


func _test_build() -> void:
	_learn(CHEAP)
	_stock_up(CHEAP)
	PlayerProgress.add_materials({"steel": 5}, false)
	PlayerProgress.add_money(100, false)
	var steel_before := PlayerProgress.get_material_count("steel")
	var cost := Fabricator.material_cost(CHEAP[0], CHEAP[1])
	var stack := Fabricator.build(CHEAP[0], CHEAP[1])
	check(stack != null, "built")
	if stack == null:
		return
	check(PlayerProgress.get_stash_inventory().get_stacks().has(stack), "into the stash")
	check(stack.item_type == CHEAP[0] and stack.item_id == CHEAP[1], "the right part")
	check_eq(stack.grade, Grades.STANDARD, "Standard at Mk I")
	check_eq(PlayerProgress.get_material_count("steel"), steel_before - int(cost["steel"]), "its materials were used")
	check_eq(PlayerProgress.get_money(), 100.0, "its credits were paid")
	check_eq(Fabricator.block_reason(CHEAP[0], CHEAP[1]), "NOT ENOUGH MATERIALS", "the materials are gone")
	check(PlayerProgress.knows_blueprint(CHEAP[0], CHEAP[1]), "the blueprint stays")


func _test_save() -> void:
	_learn(CHEAP)
	PlayerProgress.blueprints[PlayerProgress.blueprint_key(HIGH[0], HIGH[1])] = 2
	var data: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	data["blueprints"]["core:no_such_core"] = 3
	data["blueprints"]["not_a_type:x"] = 3
	PlayerProgress.reset()
	PlayerProgress.set_save_data(data)
	check(PlayerProgress.knows_blueprint(CHEAP[0], CHEAP[1]), "a known blueprint loads known")
	check_eq(PlayerProgress.blueprint_progress(HIGH[0], HIGH[1]), 2, "one in progress keeps its progress")
	check_eq(PlayerProgress.get_blueprints().size(), 2, "blueprints for parts that don't exist are dropped")
	data.erase("blueprints")
	PlayerProgress.set_save_data(data)
	check(PlayerProgress.get_blueprints().is_empty(), "a save from before blueprints has none")


func _test_window() -> void:
	MechOS.set_app_available("fabricator", true)
	var window: FabricatorWindow = MechOS.open_app("fabricator")
	check(window != null, "FAB opens")
	if window == null:
		return
	check(window.get_rows().is_empty() and window._empty.visible, "with no blueprints it says how to get one")
	check(window.build_button.disabled, "and nothing to build")

	_learn(CHEAP)
	PlayerProgress.blueprints[PlayerProgress.blueprint_key(HIGH[0], HIGH[1])] = 1
	window.refresh()
	var rows := window.get_rows()
	check_eq(rows.size(), 2, "both blueprints listed")
	check(rows[0].contains("KNOWN") and rows[1].contains("BLUEPRINT 1/3"), "known first, then ones being learned (%s)" % str(rows))
	check_eq(window.get_selected(), CHEAP, "the first is selected")
	check(window.build_button.disabled and window.block_label.text == "! NOT ENOUGH MATERIALS", "can't build it yet, and says why")
	var detail := window.get_detail_text()
	check("STEEL" in detail and "0 / 4" in detail and "CREDITS" in detail, "the cost shows had / needed (%s)" % detail)

	_stock_up(CHEAP)
	await wait_frames()  # the window refreshes on the next frame
	check(not window.build_button.disabled, "BUILD once everything's in place")
	window.build_button.pressed.emit()
	check(PlayerProgress.get_stash_inventory().get_stacks().any(func(s): return s.item_id == CHEAP[1]), "BUILD puts the part in the stash")
	check(window.build_button.disabled, "and the materials it used are gone")

	window.select(HIGH[0], HIGH[1])
	check(window.block_label.text == "! NO BLUEPRINT", "a blueprint still being learned can't be built")
	MechOS.close_app("fabricator")
