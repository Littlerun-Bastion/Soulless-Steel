class_name PropSpawnSet
extends Resource

# Prop spawn points made by the map generator. Point i has kind
# kinds[kind[i]], a position and size in map px, a rotation in radians, and a
# sprite variant (index into the kind's sprite list; -1 lets the game pick).
# Everything that reads a set goes by the kind's name, so the generator may
# add kinds (props.KINDS) freely, up to MAX_KINDS (one byte per point).

const MAX_KINDS := 256

@export var kinds := PackedStringArray()
@export var kind := PackedByteArray()
@export var position := PackedVector2Array()
@export var rotation := PackedFloat32Array()
@export var size := PackedVector2Array()
@export var variant := PackedInt32Array()
## 1 for a set piece (a point a site module placed: a car park's cars, an
## ambulance bay), which PropSpawner.kept_share never thins. Empty when the
## set has none.
@export var placed := PackedByteArray()


func count() -> int:
	return position.size()


# A set from props.json's parsed data: {"kinds": [names], "items": [[kind
# index, x, y, rotation, width, length, variant(, 1 for a set piece)], ...]}
# in map px (see props.py). An empty set, with an error, when the data is
# broken.
static func from_json(data) -> PropSpawnSet:
	var out := PropSpawnSet.new()
	if not (data is Dictionary) or not (data.get("kinds") is Array) or not (data.get("items") is Array):
		push_error("PropSpawnSet: props data has no kinds or items")
		return out
	var names := PackedStringArray(data.kinds)
	if names.size() > MAX_KINDS:
		push_error("PropSpawnSet: %d kinds; at most %d fit" % [names.size(), MAX_KINDS])
		return out
	var items: Array = data.items
	var n := items.size()
	out.kind.resize(n)
	out.position.resize(n)
	out.rotation.resize(n)
	out.size.resize(n)
	out.variant.resize(n)
	var placed := PackedByteArray()
	placed.resize(n)
	var any_placed := false
	for i in n:
		var it: Array = items[i]
		var k := int(it[0])
		if k < 0 or k >= names.size():
			push_error("PropSpawnSet: item %d has kind %d of %d" % [i, k, names.size()])
			return PropSpawnSet.new()
		out.kind[i] = k
		out.position[i] = Vector2(it[1], it[2])
		out.rotation[i] = it[3]
		out.size[i] = Vector2(it[4], it[5])
		out.variant[i] = int(it[6]) if it.size() > 6 else -1
		if it.size() > 7 and int(it[7]) == 1:
			placed[i] = 1
			any_placed = true
	if any_placed:
		out.placed = placed
	out.kinds = names
	return out
