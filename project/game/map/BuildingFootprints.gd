class_name BuildingFootprints
extends Resource

# Outlines of a map's generated buildings, in building-id order, in map px.
# Polygon i is points[starts[i]] up to, but not including, points[starts[i + 1]].
# The roof meshes tag each building's geometry with the same id.
#
# state[i] is building i's ruin state (INTACT, DAMAGED, GUTTED, COLLAPSED) and
# district[i] its district (a MapDistricts code). Either array may be empty
# (a map made before they existed): every building is then intact, in the
# residential district.

enum { INTACT, DAMAGED, GUTTED, COLLAPSED }

const STATE_NAMES := ["intact", "damaged", "gutted", "collapsed"]

@export var points := PackedVector2Array()
@export var starts := PackedInt32Array()
@export var state := PackedByteArray()
@export var district := PackedByteArray()


func count() -> int:
	return maxi(0, starts.size() - 1)


func polygon(i: int) -> PackedVector2Array:
	return points.slice(starts[i], starts[i + 1])


func state_of(i: int) -> int:
	return state[i] if i < state.size() else INTACT


func district_of(i: int) -> int:
	return district[i] if i < district.size() else MapDistricts.RESIDENTIAL
