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
#
# A section that came off in the field (Mecha.lose_part) is written off
# instead, with no bill: written_off_slots() names the parts that go with it
# (WRITE_OFF), and those are left out of what the other sections are worth.

const RATE := 0.25
# Pips a fresh armour facing has (Mecha sets every fitted facing to this).
const ARMOR_PIPS := 3
# Section -> {build slot: share of that part's price}. A shoulder carries half
# the shoulders part and the weapons on its side; the core carries the
# internal bay.
const SECTIONS := {
	"core": {"core": 1.0, "generator": 1.0, "chipset": 1.0, "thruster": 1.0, "internal": 1.0},
	"head": {"head": 1.0},
	"chassis": {"chassis": 1.0},
	"left_shoulder": {"shoulders": 0.5, "arm_weapon_left": 1.0, "shoulder_weapon_left": 1.0},
	"right_shoulder": {"shoulders": 0.5, "arm_weapon_right": 1.0, "shoulder_weapon_right": 1.0},
}


# Lost part (Mecha.lost_parts) -> the build slots written off with it: a
# shoulder takes the whole shoulders item and the weapons on its side.
const WRITE_OFF := {
	"left_shoulder": ["shoulders", "arm_weapon_left", "shoulder_weapon_left"],
	"right_shoulder": ["shoulders", "arm_weapon_right", "shoulder_weapon_right"],
	"head": ["head"],
	"arm_weapon_left": ["arm_weapon_left"],
	"arm_weapon_right": ["arm_weapon_right"],
}


# The whole bill, in credits, after the Workshop's discount (Facilities).
# Lost sections aren't charged.
static func estimate(mecha) -> int:
	var total := 0.0
	var written_off := written_off_slots(mecha)
	for section in SECTIONS:
		if _is_lost(mecha, section):
			continue
		total += section_value(mecha, section, written_off) * section_damage(mecha, section) * RATE
	return int(round(total * Facilities.repair_mult()))


# The fitted build slots written off with what came off the mecha.
static func written_off_slots(mecha) -> Array:
	var slots := []
	var lost = mecha.get("lost_parts")
	if not lost is Dictionary:
		return slots
	for part in lost:
		for slot in WRITE_OFF.get(part, []):
			if not slot in slots and mecha.build.get(slot):
				slots.append(slot)
	return slots


static func _is_lost(mecha, section: String) -> bool:
	return mecha.has_method("is_part_lost") and mecha.is_part_lost(section)


# What the parts a section carries are worth (price scaled by grade),
# leaving out the slots in `skip`.
static func section_value(mecha, section: String, skip: Array = []) -> float:
	var value := 0.0
	var build: Dictionary = mecha.build
	var grades = mecha.get("part_grades")
	if not grades is Dictionary:
		grades = {}
	for slot in SECTIONS[section]:
		var part = build.get(slot)
		if not part or slot in skip:
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
