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
