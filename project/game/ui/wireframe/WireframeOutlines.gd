class_name WireframeOutlines
extends Resource

## Outline paths for the HUD frame readout, one per part, made by
## WireframeTracer from the wireframe sprites. Points are in HUD pixels
## (already scaled), centred on where the old Sprite2D's centre was.
## Keys: core, head, shoulder, chassis_leg, chassis_single, weapon.

@export var parts: Dictionary = {}  # name -> PackedVector2Array (closed)


func get_outline(part: String) -> PackedVector2Array:
	return parts.get(part, PackedVector2Array())
