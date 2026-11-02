class_name Facilities
extends RefCounted

# Hangar facilities (the FAC app, FacilitiesWindow): upgrades bought with
# credits and materials. Their levels live in PlayerProgress (saved).
#   Recycler    recycling yields more (PlayerProgress.recycle_value)
#   Workshop    repair bills shrink (RepairBill.estimate)
#   Fabricator  0 = not built; Mk I builds low and mid tech, Mk II high tech
#               too, and better grades come out (Fabricator)
#   Stash       a bigger stash grid
#
# DATA: per facility its starting level, top level, what each level does
# ("values") and what buying it costs ("costs": credits and materials).

const RECYCLER := "recycler"
const WORKSHOP := "workshop"
const FABRICATOR := "fabricator"
const STASH := "stash"
const ALL := [RECYCLER, WORKSHOP, FABRICATOR, STASH]

const DATA := {
	RECYCLER: {
		"name": "Recycler", "start": 1, "max": 3,
		"values": {1: 1.0, 2: 1.25, 3: 1.5},
		"costs": {2: {"credits": 2500, "materials": {"steel": 20, "copper": 10}},
				3: {"credits": 8000, "materials": {"nt_fluid": 10, "noble_metals": 5}}},
	},
	WORKSHOP: {
		"name": "Workshop", "start": 1, "max": 3,
		"values": {1: 1.0, 2: 0.8, 3: 0.6},
		"costs": {2: {"credits": 2000, "materials": {}}, 3: {"credits": 6000, "materials": {}}},
	},
	FABRICATOR: {
		"name": "Fabricator", "start": 0, "max": 3,
		# Chance of each better grade on a build (the rest are Standard).
		"values": {0: {}, 1: {}, 2: {Grades.REFINED: 0.2}, 3: {Grades.REFINED: 0.35, Grades.PROTOTYPE: 0.05}},
		"costs": {1: {"credits": 1500, "materials": {}}, 2: {"credits": 6000, "materials": {}},
				3: {"credits": 15000, "materials": {"nt_engines": 1}}},
	},
	STASH: {
		"name": "Stash", "start": 1, "max": 3,
		"values": {1: Vector2i(8, 20), 2: Vector2i(8, 26), 3: Vector2i(8, 32)},
		"costs": {2: {"credits": 1500, "materials": {}}, 3: {"credits": 4000, "materials": {}}},
	},
}


static func display_name(id: String) -> String:
	return DATA[id].name


static func start_level(id: String) -> int:
	return DATA[id].start


static func max_level(id: String) -> int:
	return DATA[id].max


static func level(id: String) -> int:
	return PlayerProgress.get_facility_level(id)


static func value_at(id: String, at_level: int):
	return DATA[id]["values"][clampi(at_level, start_level(id), max_level(id))]


static func value(id: String):
	return value_at(id, level(id))


static func recycle_mult() -> float:
	return value(RECYCLER)


static func repair_mult() -> float:
	return value(WORKSHOP)


static func stash_size() -> Vector2i:
	return value(STASH)


static func fabricator_level() -> int:
	return level(FABRICATOR)


# What the next level costs ({"credits", "materials"}); {} at the top.
static func next_cost(id: String) -> Dictionary:
	return DATA[id].costs.get(level(id) + 1, {})


# Why the next level can't be bought now; "" when it can.
static func upgrade_block_reason(id: String) -> String:
	var cost := next_cost(id)
	if cost.is_empty():
		return "MAX LEVEL"
	if not PlayerProgress.has_materials(cost.materials):
		return "NOT ENOUGH MATERIALS"
	if not PlayerProgress.can_afford(cost.credits):
		return "NOT ENOUGH CREDITS"
	return ""


# Buys the next level (saved). False, and nothing paid, if it can't.
static func upgrade(id: String) -> bool:
	if upgrade_block_reason(id) != "":
		return false
	var cost := next_cost(id)
	PlayerProgress.spend_materials(cost.materials, false)
	PlayerProgress.set_facility_level(id, level(id) + 1)
	PlayerProgress.spend_money(cost.credits)  # saves it all
	return true


# What a level does, in a line: "Recycling yields x1.25".
static func describe(id: String, at_level: int) -> String:
	var v = value_at(id, at_level)
	match id:
		RECYCLER:
			return "Recycling yields x%s" % MechUI.fmt(v)
		WORKSHOP:
			return "Repair bills x%s" % MechUI.fmt(v)
		STASH:
			return "Stash %d x %d" % [v.x, v.y]
		FABRICATOR:
			match at_level:
				0:
					return "Not built: no Fabricator"
				1:
					return "Builds low and mid tech, Standard"
				_:
					var odds := []
					for grade in v:
						odds.append("%d%% %s" % [roundi(v[grade] * 100), Grades.display_name(grade)])
					return "Builds high tech too; %s" % ", ".join(odds)
	return ""


# "MK I"; "NOT BUILT" for level 0.
static func level_name(at_level: int) -> String:
	return "NOT BUILT" if at_level <= 0 else "MK " + ["I", "II", "III"][clampi(at_level, 1, 3) - 1]
