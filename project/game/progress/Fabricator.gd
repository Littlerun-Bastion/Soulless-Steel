class_name Fabricator
extends RefCounted

# The Hangar's Fabricator (the FAB app, FabricatorWindow): builds a part the
# player knows the blueprint for (PlayerProgress.knows_blueprint: learned by
# recycling copies of it) into the stash.
#
# A part costs MATERIAL_FACTOR times what it recycles into (its composition),
# plus CREDIT_RATE of its price in credits. Recycling is lossless, so this
# is where the materials are lost: rebuilding loses half of them. Building
# costs half what the Store charges. Half is also what selling pays, so
# building parts to sell them only breaks even (before materials) unless
# they come out Refined or better.
#
# AVI-Polymer filler: a build short of a material can be filled with
# AVI-Polymer at a poor rate, FILLER_KG_PER_KG kg of it for each kg missing
# (by the missing material's MaterialData.kg_per_unit, so a litre of Oil is
# its 0.88 kg, a kWh of Cells its 25 kg). AVI-Polymer a part needs directly
# (Nordomeccanica, Wu-Zhi, the specialist wetware makers) can't be filled.
# The player chooses to fill (build's use_filler).
#
# The Fabricator is a Hangar facility (Facilities): it has to be built first
# (Mk I), high-tech parts need Mk II, and at Mk II and III some builds come
# out Refined or Prototype.

const MATERIAL_FACTOR := 2
const CREDIT_RATE := 0.5
# The level a high-tech blueprint needs.
const HIGH_TECH_LEVEL := 2
## kg of AVI-Polymer per kg of a missing material.
const FILLER_KG_PER_KG := 3.0
## Materials the filler can't stand in for.
const UNFILLABLE := [Materials.AVI_POLYMER]


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


# What the player is short of for the build: material id -> missing amount.
static func shortfall(part_type: String, part_id: String) -> Dictionary:
	var missing := {}
	var cost := material_cost(part_type, part_id)
	for material_id in cost:
		var short := int(cost[material_id]) - PlayerProgress.get_material_count(material_id)
		if short > 0:
			missing[material_id] = short
	return missing


# AVI-Polymer (in its stored unit, g) that fills one material's shortfall.
static func filler_for(material_id: String, missing: int) -> int:
	var material := Materials.get_material(material_id)
	var avi := Materials.get_material(Materials.AVI_POLYMER)
	if material == null or avi == null or missing <= 0:
		return 0
	# The small margin keeps float error from adding a unit (100 kg -> 300 kg).
	return ceili(missing * material.kg_per_unit * FILLER_KG_PER_KG / avi.kg_per_unit - 0.001)


# The AVI-Polymer the whole shortfall takes, on top of any the part needs
# directly; -1 when it can't be filled (an UNFILLABLE material is short).
static func filler_cost(part_type: String, part_id: String) -> int:
	var total := 0
	var missing := shortfall(part_type, part_id)
	for material_id in missing:
		if material_id in UNFILLABLE:
			return -1
		total += filler_for(material_id, int(missing[material_id]))
	return total


# Whether filling with AVI-Polymer would cover the shortfall.
static func can_fill(part_type: String, part_id: String) -> bool:
	var filler := filler_cost(part_type, part_id)
	if filler <= 0:
		return false
	var direct := int(material_cost(part_type, part_id).get(Materials.AVI_POLYMER, 0))
	return PlayerProgress.get_material_count(Materials.AVI_POLYMER) >= direct + filler


# What a build takes out of the materials: the cost, or with use_filler what
# the player has of each short material plus the AVI-Polymer filler.
static func materials_spent(part_type: String, part_id: String, use_filler := false) -> Dictionary:
	var cost := material_cost(part_type, part_id)
	if not use_filler or not can_fill(part_type, part_id):
		return cost
	var spent := {}
	for material_id in cost:
		spent[material_id] = mini(int(cost[material_id]), PlayerProgress.get_material_count(material_id))
	spent[Materials.AVI_POLYMER] = int(cost.get(Materials.AVI_POLYMER, 0)) + filler_cost(part_type, part_id)
	return spent


# Why the part can't be built right now; "" when it can. With use_filler,
# a shortfall the AVI-Polymer covers doesn't stop it.
static func block_reason(part_type: String, part_id: String, use_filler := false) -> String:
	if get_part(part_type, part_id) == null or material_cost(part_type, part_id).is_empty():
		return "CAN'T BE BUILT"
	if level() <= 0:
		return "NO FABRICATOR: BUILD ONE IN FAC"
	if not PlayerProgress.knows_blueprint(part_type, part_id):
		return "NO BLUEPRINT"
	if needs_upgrade(part_type, part_id):
		return "NEEDS FABRICATOR MK II"
	if not PlayerProgress.has_materials(material_cost(part_type, part_id)) \
			and not (use_filler and can_fill(part_type, part_id)):
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


# Builds the part into the stash, paying its materials (filling a shortfall
# with AVI-Polymer when use_filler) and credits (saved). Returns the new
# stack, or null (and nothing is paid) if it can't be built.
static func build(part_type: String, part_id: String, rng: RandomNumberGenerator = null,
		use_filler := false) -> item_stack:
	if block_reason(part_type, part_id, use_filler) != "":
		return null
	var spent := materials_spent(part_type, part_id, use_filler)
	var stack := _new_stack(part_type, part_id)
	stack.grade = output_grade(rng)
	if not PlayerProgress.get_stash_inventory().add_stack_to_first_available_slot(stack):
		return null
	PlayerProgress.spend_materials(spent, false)
	PlayerProgress.spend_money(credit_cost(part_type, part_id))  # saves it all
	return stack


static func _new_stack(part_type: String, part_id: String) -> item_stack:
	var stack := item_stack.new()
	stack.kind = item_stack.ItemKind.PART
	stack.item_category = "part"
	stack.item_type = part_type
	stack.item_id = part_id
	return stack
