extends RefCounted
class_name Materials

# Registry of every crafting material, in display order. Add a new
# MaterialData .tres to database/materials/ and list it here.
#
# Materials have no tech tier. They are grouped by origin: Scrap (old-world)
# and Strange (Entity and AVI). Each has a real unit: amounts are whole
# numbers of its stored unit (MaterialData.unit: g, kg, mL, Wh or u), shown
# in its display unit (format_amount).
#
# The player's material counts live in PlayerProgress (get_materials,
# add_materials, recycle_stack / recycle_all). They are a ledger: they take
# no stash space.

const ALL := [
	# Scrap
	preload("res://database/materials/steel.tres"),
	preload("res://database/materials/aluminium.tres"),
	preload("res://database/materials/copper.tres"),
	preload("res://database/materials/electronics.tres"),
	preload("res://database/materials/cells.tres"),
	preload("res://database/materials/oil.tres"),
	preload("res://database/materials/noble_metals.tres"),
	preload("res://database/materials/energetics.tres"),
	# Strange
	preload("res://database/materials/avi_polymer.tres"),
	preload("res://database/materials/nt_fluid.tres"),
	preload("res://database/materials/fissile_materials.tres"),
	preload("res://database/materials/neural_biomatter.tres"),
	preload("res://database/materials/myofibrilium.tres"),
	preload("res://database/materials/avidendrites.tres"),
	preload("res://database/materials/nt_engines.tres"),
]

const ORIGINS := [MaterialData.Origin.SCRAP, MaterialData.Origin.STRANGE]
## The filler the Fabricator can use for a shortfall (Fabricator).
const AVI_POLYMER := "avi_polymer"


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


# Materials of one origin, in registry order.
static func of_origin(origin: int) -> Array:
	return ALL.filter(func(m): return m.origin == origin)


# "Scrap", "Strange".
static func origin_name(origin: int) -> String:
	return str(MaterialData.Origin.keys()[origin]).capitalize()


# 1750 (kg of Steel) -> "1.75 t"; 500 (g of AVI-Polymer) -> "500 g".
static func format_amount(material_id: String, amount: int) -> String:
	var material := get_material(material_id)
	if material == null:
		return str(amount)
	return Units.amount(amount, material.unit, material.display_unit)


# "1.2 / 4 t": had and needed, both in the unit the needed amount shows in.
static func format_pair(material_id: String, have: int, need: int) -> String:
	var need_text := format_amount(material_id, need)
	var material := get_material(material_id)
	if material == null:
		return "%d / %d" % [have, need]
	var shown := need_text.get_slice(" ", 1)
	var have_value := float(have) * float(Units.SCALE[material.unit][1]) / float(Units.SCALE[shown][1])
	return "%s / %s" % [Units.number(have_value), need_text]


# {"steel": 100, "copper": 25} -> "100 kg Steel, 25 kg Copper", in registry
# order.
static func describe(amounts: Dictionary) -> String:
	var parts := []
	for material_id in ids():
		var amount := int(amounts.get(material_id, 0))
		if amount > 0:
			parts.append("%s %s" % [format_amount(material_id, amount), display_name(material_id)])
	return ", ".join(parts)


# What the amounts are worth, in credits (MaterialData.value).
static func value_of(amounts: Dictionary) -> float:
	var total := 0.0
	for material_id in amounts:
		var material := get_material(str(material_id))
		if material != null:
			total += int(amounts[material_id]) * material.value
	return total


# What the amounts weigh, in kg (MaterialData.kg_per_unit).
static func mass_of(amounts: Dictionary) -> float:
	var total := 0.0
	for material_id in amounts:
		var material := get_material(str(material_id))
		if material != null:
			total += int(amounts[material_id]) * material.kg_per_unit
	return total
