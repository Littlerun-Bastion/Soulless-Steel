extends Resource
class_name item_stack

enum ItemKind { GENERIC, PART }

@export var kind: int = ItemKind.GENERIC

# Normal loot items
@export var item: item_data

# Mech parts
@export var part_type: StringName = ""   # "head", "core", "arm_weapon", etc.
@export var part_name: StringName = ""   # e.g. "Lancelot-Core"

@export var quantity: int = 1
var rotated: bool = false


func get_resource() -> Object:
	# 1) Generic items use item_data directly
	if kind == ItemKind.GENERIC and item != null:
		return item

	# 2) Parts are looked up in PartManager
	if kind == ItemKind.PART and part_type != "" and part_name != "":
		if PartManager.is_valid_part(part_type, part_name):
			return PartManager.get_part(part_type, part_name)

	return null


func _get_base_size_cells() -> Vector2i:
	var res := get_resource()
	if res == null:
		return Vector2i(1, 1)

	var raw = null
	if res.has_method("get"):
		raw = res.get("item_size")

	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))

	return Vector2i(1, 1)


func width_cells() -> int:
	var base := _get_base_size_cells()
	return base.y if rotated else base.x


func height_cells() -> int:
	var base := _get_base_size_cells()
	return base.x if rotated else base.y
