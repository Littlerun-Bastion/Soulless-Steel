class_name ObstacleField
extends Node2D

# Gives the generator's ground obstacles (MapObstacles: pipe runs and racks,
# open pools) collision that mechas and Entities move against and rays ignore.
#
# Every outline goes on MapSenses.BARRIER_LAYER as segments. Every ray pays
# for each static body along its path, whatever its mask, so the outlines of
# all obstacles whose centre is in one CELL_SIZE square share one static body
# with one segment shape, made directly in the physics server (no node), as
# BuildingField does for walls.
#
# NPCs: BuildingField's route grid blocks the squares the outlines cover, and
# NPC steering treats them as hard obstacles, both through outlines() (global
# space, grown by nothing; the reader grows them). The field builds in
# _ready, so it must come before BuildingField in the scene.

const CELL_SIZE := 5000.0

@export var obstacles: MapObstacles

var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _global: Array[PackedVector2Array] = []
var _kinds := PackedByteArray()


func _ready() -> void:
	add_to_group("obstacle_field")
	if obstacles == null or Engine.is_editor_hint():
		return
	for i in obstacles.count():
		var poly := obstacles.polygon(i)
		if poly.size() < 3:
			continue
		_global.append(global_transform * poly)
		_kinds.append(obstacles.kind_of(i))
	_build_bodies()


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer2D.free_rid(rid)
	for rid in _shapes:
		PhysicsServer2D.free_rid(rid)
	_bodies.clear()
	_shapes.clear()


static func find(node: Node) -> ObstacleField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("obstacle_field") as ObstacleField


func count() -> int:
	return _global.size()


func body_count() -> int:
	return _bodies.size()


# Every obstacle outline, in global space.
func outlines() -> Array[PackedVector2Array]:
	return _global


# Obstacle i's kind (MapObstacles.PIPE or POOL).
func kind_of(i: int) -> int:
	return _kinds[i]


# Whether a global position is inside an obstacle outline.
func is_blocked(global_pos: Vector2) -> bool:
	for poly in _global:
		if Geometry2D.is_point_in_polygon(global_pos, poly):
			return true
	return false


func _build_bodies() -> void:
	var cells := {}
	for i in _global.size():
		var poly := _global[i]
		var centre := Vector2.ZERO
		for p in poly:
			centre += p
		centre /= poly.size()
		var key := Vector2i((centre / CELL_SIZE).floor())
		var segments: PackedVector2Array = cells.get(key, PackedVector2Array())
		for k in poly.size():
			segments.append(poly[k])
			segments.append(poly[(k + 1) % poly.size()])
		cells[key] = segments
	var space := get_world_2d().space
	for key in cells:
		var shape := PhysicsServer2D.concave_polygon_shape_create()
		PhysicsServer2D.shape_set_data(shape, cells[key])
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_collision_layer(body, MapSenses.BARRIER_MASK)
		PhysicsServer2D.body_set_collision_mask(body, 0)
		PhysicsServer2D.body_attach_object_instance_id(body, get_instance_id())
		PhysicsServer2D.body_set_space(body, space)
		_bodies.append(body)
		_shapes.append(shape)
