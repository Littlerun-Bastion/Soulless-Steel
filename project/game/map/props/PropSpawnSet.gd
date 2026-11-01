class_name PropSpawnSet
extends Resource

# Prop spawn points made by the map generator. Point i has kind
# kinds[kind[i]], a position and size in map px, a rotation in radians, and a
# sprite variant (index into the kind's sprite list; -1 lets the game pick).

@export var kinds := PackedStringArray()
@export var kind := PackedByteArray()
@export var position := PackedVector2Array()
@export var rotation := PackedFloat32Array()
@export var size := PackedVector2Array()
@export var variant := PackedInt32Array()


func count() -> int:
	return position.size()
