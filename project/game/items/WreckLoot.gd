extends RefCounted
class_name WreckLoot

# What a destroyed mecha leaves in its wreck (Expedition).
#   Salvage: every equipped part has SALVAGE_CHANCE to give one item rolled
#            from SALVAGE_TABLE (which picks the tech tier, so high tech stays
#            rare).
#   Weapons: every equipped weapon has WEAPON_DROP_CHANCE to drop as itself,
#            as a part stack. 0 for now: weapon drops are ready but switched
#            off. Raise it to turn them on.
#
# roll() takes the mecha's design (Mecha.get_design_data: slot -> part id, or
# false for an empty slot) and an optional seeded RNG for tests.

const SALVAGE_CHANCE := 0.3
const WEAPON_DROP_CHANCE := 0.0
const SALVAGE_TABLE := preload("res://database/loot-tables/wreck_salvage.tres")
const WEAPON_SLOTS := ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]


static func roll(design: Dictionary, rng: RandomNumberGenerator = null,
		salvage_chance := SALVAGE_CHANCE, weapon_chance := WEAPON_DROP_CHANCE,
		table: LootTable = SALVAGE_TABLE) -> Array:
	var stacks := []
	for slot in design:
		var part_id = design[slot]
		if typeof(part_id) != TYPE_STRING or part_id == "":
			continue
		if _randf(rng) < salvage_chance:
			var salvage := table.roll_stack(rng)
			if salvage != null:
				stacks.append(salvage)
		# Skipped entirely while off, so it doesn't change the salvage rolls.
		if weapon_chance > 0.0 and slot in WEAPON_SLOTS and _randf(rng) < weapon_chance:
			var weapon := weapon_stack(slot, part_id)
			if weapon != null:
				stacks.append(weapon)
	return stacks


# A part stack for the weapon in a design slot ("arm_weapon_left" ->
# PartManager type "arm_weapon").
static func weapon_stack(slot: String, part_id: String) -> item_stack:
	var entry := LootEntry.new()
	entry.part_type = "arm_weapon" if slot.begins_with("arm_weapon") else "shoulder_weapon"
	entry.part_id = part_id
	return entry.make_stack()


static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()
