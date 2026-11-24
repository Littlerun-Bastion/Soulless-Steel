extends RefCounted
class_name WreckLoot

# What a destroyed mecha leaves in its wreck (Expedition).
#   Salvage: every equipped part has SALVAGE_CHANCE to give one item, rolled
#            from the salvage pool for that kind of part (PART_TABLES: a
#            frame gives scrap metal, a head or chipset electronics). Each
#            pool picks the tech tier, so higher tech stays rarer.
#   Weapons: every equipped weapon has WEAPON_DROP_CHANCE to drop intact, as
#            a part stack with a rolled grade (Grades.roll: mostly Scrap or
#            Standard, rarely better). A weapon that drops gives no salvage on
#            top (it wasn't scrapped), so loot per wreck stays about the same.
#   SAV items (sav_items), on top of those: every dead SAV leaves its Pilot
#            Capsule; legs (chassis) and arms (shoulders) of SAV_ITEM_TIER or
#            higher leave an Actuator Bundle each; a generator of that tier
#            leaves a Fissile Fuel Cassette; a core cooled with NT Fluid
#            (AVF coolant, or NT Fluid in its composition) leaves an NT Fluid
#            Canister; each .50 weapon (CAL50_WEAPONS) leaves a stack of .50
#            Cartridges.
#
# roll() is all of it; roll_parts() only the salvage and weapons, and
# sav_items() only the SAV items. They take the mecha's design
# (Mecha.get_design_data: slot -> part id, or false for an empty slot) and
# an optional seeded RNG for tests. Passing a table rolls every part from it
# instead of the per-part pools.

const SALVAGE_CHANCE := 0.3
const WEAPON_DROP_CHANCE := 0.2
# Any part type without a pool of its own rolls from every salvage item.
const SALVAGE_TABLE := preload("res://database/loot-tables/wreck_salvage.tres")
const PART_TABLES := {
	"generator": preload("res://database/loot-tables/salvage_generator.tres"),
	"head": preload("res://database/loot-tables/salvage_electronics.tres"),
	"chipset": preload("res://database/loot-tables/salvage_electronics.tres"),
	"internal": preload("res://database/loot-tables/salvage_electronics.tres"),
	"chassis": preload("res://database/loot-tables/salvage_frame.tres"),
	"shoulders": preload("res://database/loot-tables/salvage_frame.tres"),
	"core": preload("res://database/loot-tables/salvage_core.tres"),
	"thruster": preload("res://database/loot-tables/salvage_thruster.tres"),
	"arm_weapon": preload("res://database/loot-tables/salvage_weapon.tres"),
	"shoulder_weapon": preload("res://database/loot-tables/salvage_weapon.tres"),
}
const WEAPON_SLOTS := ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]

const PILOT_CAPSULE := preload("res://database/items/salvage/pilot_capsule.tres")
const ACTUATOR_BUNDLE := preload("res://database/items/salvage/actuator_bundle.tres")
const FUEL_CASSETTE := preload("res://database/items/salvage/fuel_cassette.tres")
const NT_CANISTER := preload("res://database/items/salvage/nt_canister.tres")
const CARTRIDGE := preload("res://database/items/salvage/cartridge_50.tres")
## The tech tier from which legs, arms and generators count as higher-tech.
const SAV_ITEM_TIER := item_data.TechTier.MID
## Chance of each SAV item (1.0: always).
const PILOT_CAPSULE_CHANCE := 1.0
const ACTUATOR_CHANCE := 1.0
const FUEL_CASSETTE_CHANCE := 1.0
const NT_CANISTER_CHANCE := 1.0
## Weapons that fire 12.7 mm (.50) rounds, and the cartridges each leaves
## (min, max).
const CAL50_WEAPONS := ["MA-L127"]
const CARTRIDGES := Vector2i(20, 60)
const ACTUATOR_SLOTS := ["chassis", "shoulders"]
const AVF_COOLANT := "res://database/parts/coolants/avf_coolant.tres"


static func roll(design: Dictionary, rng: RandomNumberGenerator = null,
		salvage_chance := SALVAGE_CHANCE, weapon_chance := WEAPON_DROP_CHANCE,
		table: LootTable = null) -> Array:
	var stacks := roll_parts(design, rng, salvage_chance, weapon_chance, table)
	stacks.append_array(sav_items(design, rng))
	return stacks


# Each part's salvage roll, or its weapon intact (see the header).
static func roll_parts(design: Dictionary, rng: RandomNumberGenerator = null,
		salvage_chance := SALVAGE_CHANCE, weapon_chance := WEAPON_DROP_CHANCE,
		table: LootTable = null) -> Array:
	var stacks := []
	for slot in design:
		var part_id = design[slot]
		if typeof(part_id) != TYPE_STRING or part_id == "":
			continue
		# Skipped entirely when off, so it doesn't change the salvage rolls.
		if weapon_chance > 0.0 and slot in WEAPON_SLOTS and _randf(rng) < weapon_chance:
			var weapon := weapon_stack(slot, part_id, rng)
			if weapon != null:
				stacks.append(weapon)
				continue
		if _randf(rng) < salvage_chance:
			var pool: LootTable = table if table != null else table_for_slot(slot)
			var salvage := pool.roll_stack(rng)
			if salvage != null:
				stacks.append(salvage)
	return stacks


# What every dead SAV leaves besides its parts' salvage (see the header).
static func sav_items(design: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var stacks := []
	if _has_part(design, "core") and _chance(rng, PILOT_CAPSULE_CHANCE):
		stacks.append(item_stack.from_generic(PILOT_CAPSULE))
	for slot in ACTUATOR_SLOTS:
		if _tier_of(design, slot) >= SAV_ITEM_TIER and _chance(rng, ACTUATOR_CHANCE):
			stacks.append(item_stack.from_generic(ACTUATOR_BUNDLE))
	if _tier_of(design, "generator") >= SAV_ITEM_TIER and _chance(rng, FUEL_CASSETTE_CHANCE):
		stacks.append(item_stack.from_generic(FUEL_CASSETTE))
	if uses_nt_coolant(design) and _chance(rng, NT_CANISTER_CHANCE):
		stacks.append(item_stack.from_generic(NT_CANISTER))
	for slot in WEAPON_SLOTS:
		if design.get(slot) is String and design[slot] in CAL50_WEAPONS:
			var count := rng.randi_range(CARTRIDGES.x, CARTRIDGES.y) if rng != null else randi_range(CARTRIDGES.x, CARTRIDGES.y)
			stacks.append(item_stack.from_generic(CARTRIDGE, count))
	return stacks


# Whether the design's core is cooled with NT Fluid: AVF coolant (made from
# it), or NT Fluid in the core's composition.
static func uses_nt_coolant(design: Dictionary) -> bool:
	var core := _part(design, "core")
	if core == null:
		return false
	var coolant = core.get("coolant_type")
	if coolant is Resource and coolant.resource_path == AVF_COOLANT:
		return true
	var composition = core.get("composition")
	return composition is Dictionary and int(composition.get("nt_fluid", 0)) > 0


# The salvage pool for a design slot ("arm_weapon_left" -> the weapon pool).
static func table_for_slot(slot: String) -> LootTable:
	return PART_TABLES.get(part_type_of(slot), SALVAGE_TABLE)


# Design slot -> PartManager part type: "shoulder_weapon_right" ->
# "shoulder_weapon"; other slots are already a type.
static func part_type_of(slot: String) -> String:
	return slot.trim_suffix("_left").trim_suffix("_right")


# A part stack for the weapon in a design slot, with a rolled grade.
static func weapon_stack(slot: String, part_id: String, rng: RandomNumberGenerator = null) -> item_stack:
	var entry := LootEntry.new()
	entry.part_type = part_type_of(slot)
	entry.part_id = part_id
	var stack := entry.make_stack()
	if stack != null:
		stack.grade = Grades.roll(rng)
	return stack


static func _has_part(design: Dictionary, slot: String) -> bool:
	return design.get(slot) is String and design[slot] != ""


# The part in a design slot, or null.
static func _part(design: Dictionary, slot: String) -> Object:
	if not _has_part(design, slot):
		return null
	var part_type := part_type_of(slot)
	var part_id: String = design[slot]
	if not PartManager.get_parts(part_type) is Dictionary or not PartManager.is_valid_part(part_type, part_id):
		return null
	return PartManager.get_part(part_type, part_id)


# The tech tier of the part in a design slot; NONE without one.
static func _tier_of(design: Dictionary, slot: String) -> int:
	var part := _part(design, slot)
	var tier = part.get("tech_tier") if part != null else null
	return int(tier) if tier is int else item_data.TechTier.NONE


static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()


# A certain chance (1.0) takes no draw, so it doesn't shift seeded rolls.
static func _chance(rng: RandomNumberGenerator, chance: float) -> bool:
	return chance >= 1.0 or _randf(rng) < chance
