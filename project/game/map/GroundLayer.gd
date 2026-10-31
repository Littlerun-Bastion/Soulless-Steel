@tool
class_name GroundLayer
extends Polygon2D

# The ground for a whole map. Owns the map's size: the polygon runs from (0, 0)
# to map_size in local space, so place this node at the map's top-left corner
# (for a map centred on the origin, that is -map_size / 2).
#
# The look comes from the GroundSplat shader on this node's ShaderMaterial. Its
# textures, tile size and tone settings are set on the material itself; only
# map_size is pushed from here, so it lives in one place.

@export var map_size := Vector2(4000, 4000):
	set(value):
		map_size = value
		_apply()


func _ready() -> void:
	_apply()


# Converts a world position into 0..1 coordinates on the ground mask.
func world_to_mask_uv(world_pos: Vector2) -> Vector2:
	return to_local(world_pos) / map_size


func _apply() -> void:
	polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(map_size.x, 0),
		map_size,
		Vector2(0, map_size.y),
	])
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("map_size", map_size)
