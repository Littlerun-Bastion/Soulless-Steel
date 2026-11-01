class_name BuildingField
extends Node2D

# Makes a map's generated buildings enterable without a node per building.
#
# The buildings exist only as footprints (a BuildingFootprints resource) and
# as merged interior and roof meshes. Each physics frame this node finds
# which footprint every mecha is in or near, and calls the same mecha methods
# that Building.gd's areas call: entering_building(true/false) while within
# `perimeter` of a footprint (the mecha slows), and entered_building() /
# exited_building() when it goes in or comes out (the player's camera zooms).
#
# While the player is in or near a building, every roof within reveal_radius
# fades out, so the player sees the interiors round them. Each roof vertex
# carries its building's id in UV.x; the roof material reads one fade value
# per id from a small texture that this node keeps up to date.
#
# Each building also gets its outline as a wall: a static body made directly
# in the physics server (no node), with the outline as segments on
# MapSenses.WALL_LAYER. Nothing collides with that layer, so mechas still walk
# through walls; rays see it, so walls stop shots by AP and block sight (see
# MapSenses).

const CELL_SIZE := 2000.0
const FADE_SPEED := 2.3
const FADE_TEX_SIZE := 128

@export var footprints: BuildingFootprints
@export var roof_material: ShaderMaterial
## Roofs within this distance (px) of the player fade out. 300 px is 15 m.
@export var reveal_radius := 300.0
## Within this distance (px) of a footprint a mecha counts as entering and is
## slowed, as with Building.tscn's Perimeter area.
@export var perimeter := 70.0
## A mecha this close (px) to a footprint still counts as inside, so the
## narrow gaps between neighbouring houses don't flicker the camera zoom.
@export var inside_margin := 30.0

var _polys: Array[PackedVector2Array] = []
var _rects: Array[Rect2] = []
# Grid cell -> ids of buildings close enough to matter for a point in it.
var _cells := {}
# Mecha instance id -> [inside, near].
var _mecha_state := {}
# Building id -> current roof alpha, for roofs that are not fully shown.
var _fade := {}
var _fade_image: Image
var _fade_texture: ImageTexture
var _wall_bodies: Array[RID] = []
var _wall_shapes: Array[RID] = []


func _ready() -> void:
	if footprints == null:
		push_warning("BuildingField has no footprints.")
		set_physics_process(false)
		return
	if footprints.count() > FADE_TEX_SIZE * FADE_TEX_SIZE:
		push_warning("BuildingField: more buildings than the fade texture holds.")
	var reach := maxf(maxf(perimeter, inside_margin), reveal_radius)
	for i in footprints.count():
		var poly := footprints.polygon(i)
		var rect := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			rect = rect.expand(p)
		_polys.append(poly)
		_rects.append(rect)
		var grown := rect.grow(reach)
		var c0 := _cell_of(grown.position)
		var c1 := _cell_of(grown.end)
		for cx in range(c0.x, c1.x + 1):
			for cy in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cy)
				if not _cells.has(key):
					_cells[key] = PackedInt32Array()
				_cells[key].append(i)
	if not Engine.is_editor_hint():
		_build_walls()
	_fade_image = Image.create(FADE_TEX_SIZE, FADE_TEX_SIZE, false, Image.FORMAT_R8)
	_fade_image.fill(Color.WHITE)
	_fade_texture = ImageTexture.create_from_image(_fade_image)
	if roof_material:
		roof_material.set_shader_parameter("fade_tex", _fade_texture)
		roof_material.set_shader_parameter("use_fade", true)


func _exit_tree() -> void:
	for rid in _wall_bodies:
		PhysicsServer2D.free_rid(rid)
	for rid in _wall_shapes:
		PhysicsServer2D.free_rid(rid)
	_wall_bodies.clear()
	_wall_shapes.clear()


# Id of the building whose wall body `rid` is, or -1.
func building_of_wall(rid: RID) -> int:
	return _wall_bodies.find(rid)


func _build_walls() -> void:
	var space := get_world_2d().space
	var xform := global_transform
	for i in _polys.size():
		var poly := _polys[i]
		var segments := PackedVector2Array()
		for k in poly.size():
			segments.append(poly[k])
			segments.append(poly[(k + 1) % poly.size()])
		var shape := PhysicsServer2D.concave_polygon_shape_create()
		PhysicsServer2D.shape_set_data(shape, segments)
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_collision_layer(body, MapSenses.WALL_MASK)
		PhysicsServer2D.body_set_collision_mask(body, 0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
		PhysicsServer2D.body_attach_object_instance_id(body, get_instance_id())
		PhysicsServer2D.body_set_space(body, space)
		_wall_bodies.append(body)
		_wall_shapes.append(shape)


func _physics_process(delta: float) -> void:
	var reveal_at = null
	var seen := {}
	for mech in get_tree().get_nodes_in_group("mecha"):
		if not (mech is Node2D) or not mech.has_method("entered_building"):
			continue
		var id: int = mech.get_instance_id()
		seen[id] = true
		var pos := to_local(mech.global_position)
		var dist := _nearest_distance(pos)
		var inside := dist <= inside_margin
		var near := dist <= perimeter
		var state: Array = _mecha_state.get(id, [false, false])
		if near != state[1]:
			mech.entering_building(near)
		if inside != state[0]:
			if inside:
				mech.entered_building()
			else:
				mech.exited_building()
		_mecha_state[id] = [inside, near]
		if near and mech.has_method("is_player") and mech.is_player():
			reveal_at = pos
	for id in _mecha_state.keys():
		if not seen.has(id):
			_mecha_state.erase(id)
	_update_fades(reveal_at, delta)


# Building ids within `radius` of a map position.
func buildings_near(pos: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _cells.get(_cell_of(pos), PackedInt32Array()):
		if _rects[i].grow(radius).has_point(pos) and _distance_to(i, pos) <= radius:
			out.append(i)
	return out


func _update_fades(reveal_at, delta: float) -> void:
	var targets := {}
	if reveal_at != null:
		for i in buildings_near(reveal_at, reveal_radius):
			targets[i] = true
			if not _fade.has(i):
				_fade[i] = 1.0
	var changed := false
	for i in _fade.keys():
		var target := 0.0 if targets.has(i) else 1.0
		var a := move_toward(_fade[i], target, FADE_SPEED * delta)
		if a != _fade[i]:
			_fade_image.set_pixel(i % FADE_TEX_SIZE, i / FADE_TEX_SIZE, Color(a, a, a))
			changed = true
		if a >= 1.0:
			_fade.erase(i)
		else:
			_fade[i] = a
	if changed:
		_fade_texture.update(_fade_image)


func _nearest_distance(pos: Vector2) -> float:
	var best := INF
	for i in _cells.get(_cell_of(pos), PackedInt32Array()):
		if best < INF and not _rects[i].grow(best).has_point(pos):
			continue
		best = minf(best, _distance_to(i, pos))
		if best == 0.0:
			break
	return best


func _distance_to(i: int, pos: Vector2) -> float:
	var poly := _polys[i]
	if Geometry2D.is_point_in_polygon(pos, poly):
		return 0.0
	var best := INF
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)))
	return best


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
