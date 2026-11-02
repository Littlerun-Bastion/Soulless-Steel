class_name Fabricator
extends RefCounted

# The Hangar's Fabricator (the FAB app, FabricatorWindow): builds a part the
# player knows the blueprint for (PlayerProgress.knows_blueprint: learned by
# recycling copies of it) into the stash.
#
# A part costs MATERIAL_FACTOR times what it recycles into (its composition),
# plus CREDIT_RATE of its price in credits. So recycling and rebuilding loses
# half the materials, and building costs half what the Store charges. Half is
# also what selling pays, so building parts to sell them only breaks even
# (before materials) unless they come out Refined or better.
#
# The Fabricator is a Hangar facility (Facilities): it has to be built first
# (Mk I), high-tech parts need Mk II, and at Mk II and III some builds come
# out Refined or Prototype.

const MATERIAL_FACTOR := 2
const CREDIT_RATE := 0.5
# The level a high-tech blueprint needs.
const HIGH_TECH_LEVEL := 2


static func level() -> int:
	return Facilities.fabricator_level()


static func get_part(part_type: String, part_id: String) -> Object:
	if not part_type in PlayerProgress.PART_TYPES or not PartManager.is_valid_part(part_type, part_id):
		return null
	return PartManager.get_part(part_type, part_id)


static func material_cost(part_type: String, part_id: String) -> Dictionary:
	var cost := {}
	var part := get_part(part_type, part_id)
	var composition = part.get("composition") if part != null else null
	if composition is Dictionary:
		for material_id in composition:
			cost[material_id] = int(composition[material_id]) * MATERIAL_FACTOR
	return cost


static func credit_cost(part_type: String, part_id: String) -> int:
	var part := get_part(part_type, part_id)
	var price = part.get("price") if part != null else null
	return int(ceil(price * CREDIT_RATE)) if price is int or price is float else 0


static func needs_upgrade(part_type: String, part_id: String) -> bool:
	var part := get_part(part_type, part_id)
	return part != null and part.get("tech_tier") == item_data.TechTier.HIGH and level() < HIGH_TECH_LEVEL


# Why the part can't be built right now; "" when it can.
static func block_reason(part_type: String, part_id: String) -> String:
	if get_part(part_type, part_id) == null or material_cost(part_type, part_id).is_empty():
		return "CAN'T BE BUILT"
	if level() <= 0:
		return "NO FABRICATOR: BUILD ONE IN FAC"
	if not PlayerProgress.knows_blueprint(part_type, part_id):
		return "NO BLUEPRINT"
	if needs_upgrade(part_type, part_id):
		return "NEEDS FABRICATOR MK II"
	if not PlayerProgress.has_materials(material_cost(part_type, part_id)):
		return "NOT ENOUGH MATERIALS"
	if not PlayerProgress.can_afford(credit_cost(part_type, part_id)):
		return "NOT ENOUGH CREDITS"
	if not PlayerProgress.get_stash_inventory().has_room_for(_new_stack(part_type, part_id)):
		return "STASH FULL"
	return ""


# The grade a build comes out at: rolled by the Fabricator's level
# (Facilities: e.g. Mk II 20% Refined), else Standard.
static func output_grade(rng: RandomNumberGenerator = null) -> String:
	var odds: Dictionary = Facilities.value_at(Facilities.FABRICATOR, level())
	var pick := rng.randf() if rng != null else randf()
	for grade in [Grades.PROTOTYPE, Grades.REFINED]:
		pick -= float(odds.get(grade, 0.0))
		if pick < 0.0:
			return grade
	return Grades.STANDARD


# Builds the part into the stash, paying its materials and credits (saved).
# Returns the new stack, or null (and nothing is paid) if it can't be built.
static func build(part_type: String, part_id: String, rng: RandomNumberGenerator = null) -> item_stack:
	if block_reason(part_type, part_id) != "":
		return null
	var stack := _new_stack(part_type, part_id)
	stack.grade = output_grade(rng)
	if not PlayerProgress.get_stash_inventory().add_stack_to_first_available_slot(stack):
		return null
	PlayerProgress.spend_materials(material_cost(part_type, part_id), false)
	PlayerProgress.spend_money(credit_cost(part_type, part_id))  # saves it all
	return stack


static func _new_stack(part_type: String, part_id: String) -> item_stack:
	var stack := item_stack.new()
	stack.kind = item_stack.ItemKind.PART
	stack.item_category = "part"
	stack.item_type = part_type
	stack.item_id = part_id
	return stack
