class_name Grades
extends RefCounted

# Part grades. Every copy of a part has one: item_stack.grade in an inventory,
# Mecha.part_grades (design slot -> grade) once fitted, and
# PlayerProgress.current_grades for the player's saved design. Missing or
# unknown means Standard, so old saves and NPC mechas need nothing.
#
# A better grade is worth more (selling, repairs), recycles into more, and
# scales the stats that add up across a mecha's parts (GRADED_STATS, through
# Mecha.get_stat and StatsPanel.sum_stat). Other stats are read straight off
# the shared part data, so grades don't touch them.
#
# Store parts and NPC mechas are Standard; weapons dropped by wrecks roll one
# (WreckLoot.weapon_stack).

const SCRAP := "scrap"
const STANDARD := "standard"
const REFINED := "refined"
const PROTOTYPE := "prototype"
const ALL := [SCRAP, STANDARD, REFINED, PROTOTYPE]

const DATA := {
	SCRAP: {"name": "Scrap", "short": "SCR", "stats": 0.9, "value": 0.5, "recycle": 0.5, "drop": 45.0,
			"color": Color(0.62, 0.52, 0.45)},
	STANDARD: {"name": "Standard", "short": "", "stats": 1.0, "value": 1.0, "recycle": 1.0, "drop": 45.0,
			"color": Color(0.85, 0.85, 0.85)},
	REFINED: {"name": "Refined", "short": "REF", "stats": 1.05, "value": 1.6, "recycle": 1.25, "drop": 9.0,
			"color": Color(0.45, 0.78, 1.0)},
	PROTOTYPE: {"name": "Prototype", "short": "PRT", "stats": 1.1, "value": 2.5, "recycle": 1.5, "drop": 1.0,
			"color": Color(1.0, 0.72, 0.3)},
}

# Stats that add up across a mecha's parts, where more is better.
const GRADED_STATS := ["weight_capacity", "stability", "arms_accuracy_modifier",
		"max_speed", "thrust_max_speed"]


# grade, or Standard if it isn't one.
static func of(grade) -> String:
	return grade if grade is String and DATA.has(grade) else STANDARD


static func is_valid(grade) -> bool:
	return grade is String and DATA.has(grade)


static func display_name(grade) -> String:
	return DATA[of(grade)].name


# "REF" etc. for tiles; "" for Standard, which shows nothing.
static func short_name(grade) -> String:
	return DATA[of(grade)].short


static func color(grade) -> Color:
	return DATA[of(grade)].color


# "Refined MA-L127"; Standard parts keep their plain name.
static func label(grade, part_name: String) -> String:
	return part_name if of(grade) == STANDARD else "%s %s" % [display_name(grade), part_name]


static func stat_mult(grade, stat: String) -> float:
	return DATA[of(grade)].stats if stat in GRADED_STATS else 1.0


static func value_mult(grade) -> float:
	return DATA[of(grade)].value


static func recycle_mult(grade) -> float:
	return DATA[of(grade)].recycle


# A grade for a dropped part, by the "drop" weights.
static func roll(rng: RandomNumberGenerator = null) -> String:
	var total := 0.0
	for grade in ALL:
		total += DATA[grade].drop
	var pick := (rng.randf() if rng != null else randf()) * total
	for grade in ALL:
		pick -= DATA[grade].drop
		if pick < 0.0:
			return grade
	return STANDARD
