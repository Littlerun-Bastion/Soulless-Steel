extends RefCounted
class_name Materials

# Registry of every crafting material, in display order. Add a new
# MaterialData .tres to database/materials/ and list it here.
#
# The player's material counts live in PlayerProgress (get_materials,
# add_materials, recycle_stack / recycle_all).

const ALL := [
	# Low tech
	preload("res://database/materials/steel.tres"),
	preload("res://database/materials/silicon.tres"),
	preload("res://database/materials/copper.tres"),
	preload("res://database/materials/oil.tres"),
	preload("res://database/materials/avi_polymer.tres"),
	preload("res://database/materials/fissile_materials.tres"),
	# Mid tech
	preload("res://database/materials/nt_fluid.tres"),
	preload("res://database/materials/noble_metals.tres"),
	preload("res://database/materials/neural_biomatter.tres"),
	# High tech
	preload("res://database/materials/nt_engines.tres"),
	preload("res://database/materials/myofibrilium.tres"),
	preload("res://database/materials/avidendrites.tres"),
]

const TIERS := [item_data.TechTier.LOW, item_data.TechTier.MID, item_data.TechTier.HIGH]


static func get_material(material_id: String) -> MaterialData:
	for material in ALL:
		if material.id == material_id:
			return material
	return null


static func is_valid(material_id: String) -> bool:
	return get_material(material_id) != null


static func ids() -> Array:
	return ALL.map(func(m): return m.id)


static func display_name(material_id: String) -> String:
	var material := get_material(material_id)
	return material.display_name if material != null else material_id


# Materials of one tech tier, in registry order.
static func of_tier(tier: int) -> Array:
	return ALL.filter(func(m): return m.tech_tier == tier)


static func tier_name(tier: int) -> String:
	return str(item_data.TechTier.keys()[tier]).capitalize()


# {"steel": 3, "copper": 1} -> "3 Steel, 1 Copper", in registry order.
static func describe(amounts: Dictionary) -> String:
	var parts := []
	for material_id in ids():
		var amount := int(amounts.get(material_id, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, display_name(material_id)])
	return ", ".join(parts)
