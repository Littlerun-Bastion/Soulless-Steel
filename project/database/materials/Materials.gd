extends RefCounted
class_name Materials

# Registry of every crafting material, in display order. Add a new
# MaterialData .tres to database/materials/ and list it here.
#
# The player's material counts live in PlayerProgress (get_materials,
# add_materials, recycle_stack / recycle_all).

const ALL := [
	preload("res://database/materials/scrap_metal.tres"),
	preload("res://database/materials/electronics.tres"),
	preload("res://database/materials/power_cells.tres"),
	preload("res://database/materials/rare_alloys.tres"),
]


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


# {"scrap_metal": 3, "electronics": 1} -> "3 Scrap Metal, 1 Electronics",
# in registry order.
static func describe(amounts: Dictionary) -> String:
	var parts := []
	for material_id in ids():
		var amount := int(amounts.get(material_id, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, display_name(material_id)])
	return ", ".join(parts)
