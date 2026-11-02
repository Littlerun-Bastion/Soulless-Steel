class_name RepairBill
extends RefCounted

# What fixing a mecha's damage costs when it comes home from an Expedition.
# Expedition charges it on extraction (PlayerProgress.charge_repairs); the
# debrief shows it. A mecha that goes down is written off instead: no bill.
#
# The frame has five sections (Mecha.components / Mecha.armor). Each is worth
# the parts it carries (SECTIONS), and is charged RATE of that worth for the
# share of it that's damaged: component HP lost plus armour pips worn, out of
# the section's total of both.

const RATE := 0.25
# Pips a fresh armour facing has (Mecha sets every fitted facing to this).
const ARMOR_PIPS := 3
# Section -> {build slot: share of that part's price}. A shoulder carries half
# the shoulders part and the weapons on its side.
const SECTIONS := {
	"core": {"core": 1.0, "generator": 1.0, "chipset": 1.0, "thruster": 1.0},
	"head": {"head": 1.0},
	"chassis": {"chassis": 1.0},
	"left_shoulder": {"shoulders": 0.5, "arm_weapon_left": 1.0, "shoulder_weapon_left": 1.0},
	"right_shoulder": {"shoulders": 0.5, "arm_weapon_right": 1.0, "shoulder_weapon_right": 1.0},
}


# The whole bill, in credits.
static func estimate(mecha) -> int:
	var total := 0.0
	for section in SECTIONS:
		total += section_value(mecha, section) * section_damage(mecha, section) * RATE
	return int(round(total))


# What the parts a section carries are worth (price scaled by grade).
static func section_value(mecha, section: String) -> float:
	var value := 0.0
	var build: Dictionary = mecha.build
	var grades = mecha.get("part_grades")
	if not grades is Dictionary:
		grades = {}
	for slot in SECTIONS[section]:
		var part = build.get(slot)
		if not part:
			continue
		var price = part.get("price")
		if price is int or price is float:
			value += price * Grades.value_mult(grades.get(slot)) * SECTIONS[section][slot]
	return value


# How damaged a section is, 0 (as new) to 1 (every component and plate gone).
static func section_damage(mecha, section: String) -> float:
	var lost := 0.0
	var total := 0.0
	for comp in mecha.components.get(section, {}).values():
		total += comp.max_hp
		lost += comp.max_hp - maxf(comp.hp, 0)
	for facing in mecha.armor.get(section, {}).values():
		if facing.level <= 0:
			continue  # no part fitted there
		total += ARMOR_PIPS
		lost += ARMOR_PIPS - clampi(facing.pips, 0, ARMOR_PIPS)
	return lost / total if total > 0.0 else 0.0
