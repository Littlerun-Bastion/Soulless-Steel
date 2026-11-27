class_name MapObstacles
extends Resource

# Ground obstacles made by the map generator: closed outlines, in map px,
# that mechas can't walk through but shots and sight pass over (pipe runs and
# racks, open pools). Polygon i is points[starts[i]] up to, but not
# including, points[starts[i + 1]]; kind[i] is PIPE or POOL.

enum { PIPE, POOL }

const KIND_NAMES := ["pipe", "pool"]

@export var points := PackedVector2Array()
@export var starts := PackedInt32Array()
@export var kind := PackedByteArray()


func count() -> int:
	return maxi(0, starts.size() - 1)


func polygon(i: int) -> PackedVector2Array:
	return points.slice(starts[i], starts[i + 1])


func kind_of(i: int) -> int:
	return kind[i] if i < kind.size() else PIPE
