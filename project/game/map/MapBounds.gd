class_name MapBounds
extends Node2D

# The edges of a map. map_rect is the whole map in this node's space (what
# the camera may show); the outer `border` px of it on every side is a band
# that mechas, NPCs and Entities can't enter, so the play area is map_rect
# shrunk by `border` (play_rect). The generator fills the band with the same
# content as the rest of the map, so the world doesn't seem to end, but puts
# no salvage, loot, spawns or exits in it.
#
# The band is blocked by one static body of four segments along the edge of
# the play area, made directly in the physics server on
# MapSenses.BARRIER_LAYER: mechas and Entities collide with it, rays don't
# see it, and as one body it costs rays almost nothing.

@export var map_rect := Rect2(-54000, -54000, 108000, 108000)
@export var border := 4000.0

var _body := RID()
var _shape := RID()


func _ready() -> void:
	add_to_group("map_bounds")
	if not Engine.is_editor_hint():
		_build_border()


func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer2D.free_rid(_body)
		_body = RID()
	if _shape.is_valid():
		PhysicsServer2D.free_rid(_shape)
		_shape = RID()


static func find(node: Node) -> MapBounds:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("map_bounds") as MapBounds


# The play area in this node's space.
func play_rect() -> Rect2:
	return map_rect.grow(-border)


# The whole map in global space.
func global_map_rect() -> Rect2:
	return global_transform * map_rect


# The play area in global space.
func global_play_rect() -> Rect2:
	return global_transform * play_rect()


func is_in_play_area(global_pos: Vector2) -> bool:
	return global_play_rect().has_point(global_pos)


# The nearest point to `global_pos` that is at least `margin` px inside the
# play area.
func clamp_to_play_area(global_pos: Vector2, margin := 0.0) -> Vector2:
	var r := global_play_rect().grow(-margin)
	return global_pos.clamp(r.position, r.end)


func border_body() -> RID:
	return _body


func _build_border() -> void:
	var r := play_rect()
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	_shape = PhysicsServer2D.concave_polygon_shape_create()
	PhysicsServer2D.shape_set_data(_shape, PackedVector2Array([a, b, b, c, c, d, d, a]))
	_body = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(_body, _shape)
	PhysicsServer2D.body_set_collision_layer(_body, MapSenses.BARRIER_MASK)
	PhysicsServer2D.body_set_collision_mask(_body, 0)
	PhysicsServer2D.body_set_state(_body, PhysicsServer2D.BODY_STATE_TRANSFORM, global_transform)
	PhysicsServer2D.body_attach_object_instance_id(_body, get_instance_id())
	PhysicsServer2D.body_set_space(_body, get_world_2d().space)
