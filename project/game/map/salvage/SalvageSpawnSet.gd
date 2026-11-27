class_name SalvageSpawnSet
extends Resource

# Salvage sources placed by the map generator. Source i is of kind
# kinds[kind[i]] (a SalvageField source kind, such as "solar_panels"), sits
# at position[i] in map px, turned by rotation[i] radians, with an outline box
# of size[i] px centred on its position (the HUD bracket fits that box).
#
# building[i] is the id of the generated building whose roof holds the source
# (BuildingFootprints id), or -1 for a source on the ground. amount[i] scales
# the yield for kinds that use it (intact solar modules, AC boxes); 0 when the
# kind doesn't. vehicle[i] is 1 when the source is a VehicleField vehicle
# parked at position[i] (a bus, a tank): the source then follows the vehicle
# when it is pushed.
# Everything that reads a set goes by the kind's name, so the generator may
# add kinds (salvage.KINDS) freely, up to MAX_KINDS (one byte per source).

const MAX_KINDS := 256

@export var kinds := PackedStringArray()
@export var kind := PackedByteArray()
@export var position := PackedVector2Array()
@export var rotation := PackedFloat32Array()
@export var size := PackedVector2Array()
@export var building := PackedInt32Array()
@export var amount := PackedInt32Array()
@export var vehicle := PackedByteArray()


func count() -> int:
	return position.size()


func kind_name(i: int) -> String:
	return kinds[kind[i]]


# A set from salvage.json's parsed data: {"kinds": [names], "items": [[kind
# index, x, y, rotation, width, height, building, amount, vehicle], ...]} in
# map px (see salvage.py). An empty set, with an error, when the data is
# broken.
static func from_json(data) -> SalvageSpawnSet:
	var out := SalvageSpawnSet.new()
	if not (data is Dictionary) or not (data.get("kinds") is Array) or not (data.get("items") is Array):
		push_error("SalvageSpawnSet: salvage data has no kinds or items")
		return out
	var names := PackedStringArray(data.kinds)
	if names.size() > MAX_KINDS:
		push_error("SalvageSpawnSet: %d kinds; at most %d fit" % [names.size(), MAX_KINDS])
		return out
	var items: Array = data.items
	var n := items.size()
	out.kind.resize(n)
	out.position.resize(n)
	out.rotation.resize(n)
	out.size.resize(n)
	out.building.resize(n)
	out.amount.resize(n)
	out.vehicle.resize(n)
	for i in n:
		var it: Array = items[i]
		var k := int(it[0])
		if k < 0 or k >= names.size():
			push_error("SalvageSpawnSet: item %d has kind %d of %d" % [i, k, names.size()])
			return SalvageSpawnSet.new()
		out.kind[i] = k
		out.position[i] = Vector2(it[1], it[2])
		out.rotation[i] = it[3]
		out.size[i] = Vector2(it[4], it[5])
		out.building[i] = int(it[6])
		out.amount[i] = int(it[7])
		out.vehicle[i] = int(it[8])
	out.kinds = names
	return out
