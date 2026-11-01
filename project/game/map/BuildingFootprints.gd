class_name BuildingFootprints
extends Resource

# Outlines of a map's generated buildings, in building-id order, in map px.
# Polygon i is points[starts[i]] up to, but not including, points[starts[i + 1]].
# The roof meshes tag each building's geometry with the same id.

@export var points := PackedVector2Array()
@export var starts := PackedInt32Array()


func count() -> int:
	return maxi(0, starts.size() - 1)


func polygon(i: int) -> PackedVector2Array:
	return points.slice(starts[i], starts[i + 1])
