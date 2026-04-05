extends Resource
class_name item_stack

# You *can* keep a kind enum if you still want meta for serialization/equip,
# but the inventory/grid logic will NOT rely on it anymore.
enum ItemKind { GENERIC, PART }

@export var kind: ItemKind = ItemKind.GENERIC    # optional, for your own logic
@export var item: Resource = null                # can be item_data, Core.gd, whatever
@export var quantity: int = 1
@export var rotated: bool = false

# Optional metadata for saving / equipping – inventory itself won’t care:
@export var item_category: String = ""   # "part", "resource", etc. (for save logic only)
@export var item_type: String = ""       # e.g. "core", "head", "salvage"
@export var item_id: String = ""         # e.g. "MSV-L3J-C" or resource path


# ---- Size helpers (this is where we remove class-specific logic) ----

func width_cells() -> int:
	var size := _get_size_from_item()
	if rotated:
		return size.y
	else:
		return size.x


func height_cells() -> int:
	var size := _get_size_from_item()
	if rotated:
		return size.x
	else:
		return size.y


func _get_size_from_item() -> Vector2i:
	if item == null or not item.has_method("get"):
		return Vector2i(1, 1)

	# Prefer cargo_size if present, fall back to item_size
	var v = item.get("cargo_size")
	if v == null:
		v = item.get("item_size")

	if typeof(v) == TYPE_VECTOR2I:
		return v
	elif typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))

	# Fallbacks: item_width / item_height if you use them
	var w := 1
	var h := 1

	var w_prop = item.get("item_width")
	if typeof(w_prop) == TYPE_FLOAT or typeof(w_prop) == TYPE_INT:
		w = int(w_prop)

	var h_prop = item.get("item_height")
	if typeof(h_prop) == TYPE_FLOAT or typeof(h_prop) == TYPE_INT:
		h = int(h_prop)

	if w <= 0:
		w = 1
	if h <= 0:
		h = 1

	return Vector2i(w, h)



func _get_int_prop(name: String, default_val: int) -> int:
	if item == null or not item.has_method("get"):
		return default_val
	var v = item.get(name)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return default_val

static func from_generic(res: Resource, qty: int = 1) -> item_stack:
	var s := item_stack.new()
	s.kind = ItemKind.GENERIC
	s.item = res
	s.quantity = qty
	s.item_category = "resource"
	if res is Resource and res.resource_path != "":
		s.item_id = res.resource_path
	return s


static func from_part(part: Object, part_type: String, qty: int = 1) -> item_stack:
	var s := item_stack.new()
	s.kind = ItemKind.PART
	s.item = part
	s.quantity = qty
	s.item_category = "part"
	s.item_type = part_type
	if part.has_method("get"):
		var pid = part.get("part_id")
		if pid != null:
			s.item_id = str(pid)
	return s
