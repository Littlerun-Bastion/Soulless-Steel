extends RefCounted
class_name WreckLoot

# What a destroyed mecha leaves in its wreck (Expedition).
#   Salvage: every equipped part has SALVAGE_CHANCE to give one item, rolled
#            from the salvage pool for that kind of part (PART_TABLES: a
#            generator gives generator scrap, a head or chipset electronics).
#            Each pool picks the tech tier, so high tech stays rare; pools
#            with no high-tech item give mid tech on a high roll.
#   Weapons: every equipped weapon has WEAPON_DROP_CHANCE to drop as itself,
#            as a part stack. 0 for now: weapon drops are ready but switched
#            off. Raise it to turn them on.
#
# roll() takes the mecha's design (Mecha.get_design_data: slot -> part id, or
# false for an empty slot) and an optional seeded RNG for tests. Passing a
# table rolls every part from it instead of the per-part pools.

const SALVAGE_CHANCE := 0.3
const WEAPON_DROP_CHANCE := 0.0
# Any part type without a pool of its own rolls from every salvage item.
const SALVAGE_TABLE := preload("res://database/loot-tables/wreck_salvage.tres")
const PART_TABLES := {
	"generator": preload("res://database/loot-tables/salvage_generator.tres"),
	"head": preload("res://database/loot-tables/salvage_electronics.tres"),
	"chipset": preload("res://database/loot-tables/salvage_electronics.tres"),
	"chassis": preload("res://database/loot-tables/salvage_frame.tres"),
	"shoulders": preload("res://database/loot-tables/salvage_frame.tres"),
	"core": preload("res://database/loot-tables/salvage_core.tres"),
	"thruster": preload("res://database/loot-tables/salvage_thruster.tres"),
	"arm_weapon": preload("res://database/loot-tables/salvage_weapon.tres"),
	"shoulder_weapon": preload("res://database/loot-tables/salvage_weapon.tres"),
}
const WEAPON_SLOTS := ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]


static func roll(design: Dictionary, rng: RandomNumberGenerator = null,
		salvage_chance := SALVAGE_CHANCE, weapon_chance := WEAPON_DROP_CHANCE,
		table: LootTable = null) -> Array:
	var stacks := []
	for slot in design:
		var part_id = design[slot]
		if typeof(part_id) != TYPE_STRING or part_id == "":
			continue
		if _randf(rng) < salvage_chance:
			var pool: LootTable = table if table != null else table_for_slot(slot)
			var salvage := pool.roll_stack(rng)
			if salvage != null:
				stacks.append(salvage)
		# Skipped entirely while off, so it doesn't change the salvage rolls.
		if weapon_chance > 0.0 and slot in WEAPON_SLOTS and _randf(rng) < weapon_chance:
			var weapon := weapon_stack(slot, part_id)
			if weapon != null:
				stacks.append(weapon)
	return stacks


# The salvage pool for a design slot ("arm_weapon_left" -> the weapon pool).
static func table_for_slot(slot: String) -> LootTable:
	return PART_TABLES.get(part_type_of(slot), SALVAGE_TABLE)


# Design slot -> PartManager part type: "shoulder_weapon_right" ->
# "shoulder_weapon"; other slots are already a type.
static func part_type_of(slot: String) -> String:
	return slot.trim_suffix("_left").trim_suffix("_right")


# A part stack for the weapon in a design slot.
static func weapon_stack(slot: String, part_id: String) -> item_stack:
	var entry := LootEntry.new()
	entry.part_type = part_type_of(slot)
	entry.part_id = part_id
	return entry.make_stack()


static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()
