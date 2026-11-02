class_name VehicleField
extends Node2D

# Gives a map's vehicle props bodies, so mechas can push them and they can
# stop shots, without a node per vehicle.
#
# Every spawn of `kinds` from the PropSpawner can have a box (the vehicle's
# length by its width) as a static body made directly in the physics server,
# on MapSenses.VEHICLE_LAYER. Mechas collide with that layer. Entities don't:
# they slip round and under vehicles. Sight rays ignore it (MapSenses).
#
# Streaming: every ray pays for each body along its path, whatever its mask,
# so with `stream` on, only vehicles in the CELL_SIZE cells within
# stream_radius of a mecha have boxes. The cells are checked every
# STREAM_INTERVAL physics frames. A shot that passes a vehicle far from every
# mecha (more than stream_radius from both the shooter and the target) goes
# through it.
#
# Pushing: Mecha.move() calls push_from() after it moves. The mecha counts
# as MECHA_KG_PER_WEIGHT kg per point of its weight. When it first runs into
# a vehicle, the two collide like bodies with RESTITUTION bounce. While it
# keeps pushing, the vehicle moves at the speed the two would share as one
# body (the mecha's speed times mecha mass / both masses). The mecha can only
# follow as fast as the vehicle in front of it moves, so a light car barely
# slows it and slides on a few metres when it stops; a heavy truck barely
# moves and holds it back. A push off the vehicle's centre turns it, scaled
# by SPIN.
#
# Waking: a pushed vehicle wakes. Its static body is removed and a
# RigidBody2D takes its place, and its sprite moves off the PropSpriteLayer
# onto that body. A moving vehicle wakes the sleeping ones it is about to
# hit, so a shoved car can shunt the next one.
#
# Settling: a woken vehicle that has stopped for SETTLE_TIME, with no mecha
# near it, becomes a static body again where it stopped, and its sprite goes
# back to the layer there. At most MAX_AWAKE vehicles are awake at once.
#
# masses, shot_blocks: kind -> PackedFloat32Array, one value per sprite
# variant (from sprite_catalogue.json). A shot_block is the chance that a
# shot passing through the vehicle stops in it (MapSenses.trace_shot).

const MECHA_KG_PER_WEIGHT := 50.0
const RESTITUTION := 0.3
const SPIN := 0.35
const MAX_AWAKE := 24
## A woken vehicle slower than this (px/s) counts as stopped.
const SETTLE_SPEED := 8.0
const SETTLE_TIME := 0.6
## A woken vehicle doesn't settle while a mecha is within this distance (px)
## of its edge.
const SETTLE_CLEARANCE := 150.0
## How far ahead (s of travel) a moving vehicle wakes the ones in its way.
const WAKE_LOOKAHEAD := 0.25
const CELL_SIZE := 1000.0
const STREAM_INTERVAL := 10

@export var spawner_path: NodePath
## The PropSpriteLayer that draws these vehicles.
@export var layer_path: NodePath
@export var kinds := PackedStringArray()
@export var masses := {}
@export var shot_blocks := {}
## Mass (kg) for a kind or variant missing from `masses`.
@export var default_mass := 1500.0
@export var default_shot_block := 0.5
## Boxes only near mechas (see above). Off: every vehicle always has a box.
@export var stream := true
@export var stream_radius := 2000.0
@export var linear_damp := 3.5
@export var angular_damp := 6.0

var _layer: PropSpriteLayer
var _spawn_index := PackedInt32Array()
var _pos := PackedVector2Array()
var _rot := PackedFloat32Array()
var _size := PackedVector2Array()
var _mass := PackedFloat32Array()
var _block := PackedFloat32Array()
var _moved := PackedByteArray()
var _static_bodies: Array[RID] = []
var _static_shapes: Array[RID] = []
var _rid_to_index := {}
# Cell -> PackedInt32Array of vehicle indices, by resting position.
var _cells := {}
# Cells whose sleeping vehicles have boxes (with `stream` on).
var _active_cells := {}
var _built := false
# Vehicle index -> RigidBody2D, how long it has been still, and the physics
# frame it was last pushed in (a mecha can move more than once a frame).
var _awake := {}
var _still := {}
var _pushed_on := {}


func _ready() -> void:
	add_to_group("vehicle_field")
	_build.call_deferred()


func _exit_tree() -> void:
	for i in _static_bodies.size():
		_free_static(i)


# Called by a mecha after it moves with `intended` velocity (px/s).
static func push_from(mecha: CharacterBody2D, intended: Vector2) -> void:
	if mecha.get_slide_collision_count() == 0 or not mecha.is_inside_tree():
		return
	var field := mecha.get_tree().get_first_node_in_group("vehicle_field") as VehicleField
	if field:
		field.push(mecha, intended)


func push(mecha: CharacterBody2D, intended: Vector2) -> void:
	var weight: float = mecha.get_total_weight() if mecha.has_method("get_total_weight") else 50.0
	var pusher := maxf(weight, 1.0) * MECHA_KG_PER_WEIGHT
	var frame := Engine.get_physics_frames()
	for c in mecha.get_slide_collision_count():
		var col := mecha.get_slide_collision(c)
		var i := index_of(col.get_collider(), col.get_collider_rid())
		if i < 0 or _pushed_on.get(i, -1) == frame:
			continue
		var n := -col.get_normal()
		var v_n := intended.dot(n)
		if v_n <= 0.0:
			continue
		var body := _wake(i)
		if body == null:
			continue
		var m := _mass[i]
		var u := body.linear_velocity.dot(n)
		var target := pusher * v_n / (pusher + m)
		if _pushed_on.get(i, -10) < frame - 1:
			target = (pusher * v_n + m * u + pusher * RESTITUTION * (v_n - u)) / (pusher + m)
		_pushed_on[i] = frame
		_still[i] = 0.0
		if target > u:
			# The change in momentum, applied at the contact point: the
			# vehicle speeds up along the push and turns if pushed off-centre.
			var dv := target - u
			var arm := col.get_position() - body.global_position
			body.linear_velocity += n * dv
			body.angular_velocity += SPIN * arm.cross(n * m * dv) / _inertia(i)


# The vehicle index of a collider from a ray or a collision, or -1.
func index_of(collider: Object, rid: RID) -> int:
	if collider == self:
		return _rid_to_index.get(rid, -1)
	if collider is RigidBody2D and collider.get_parent() == self:
		return collider.get_meta("vehicle_index", -1)
	return -1


# The chance that a shot passing through this collider stops in it.
func shot_block_for(collider: Object, rid: RID) -> float:
	var i := index_of(collider, rid)
	return _block[i] if i >= 0 else default_shot_block


func vehicle_count() -> int:
	return _pos.size()


func awake_count() -> int:
	return _awake.size()


func is_awake(i: int) -> bool:
	return _awake.has(i)


# Where vehicle i is now (global position and rotation).
func vehicle_transform(i: int) -> Transform2D:
	if _awake.has(i):
		return (_awake[i] as Node2D).global_transform
	return Transform2D(_rot[i], _pos[i])


func vehicle_mass(i: int) -> float:
	return _mass[i]


# The vehicle nearest a global position, or -1 if none within max_distance.
func nearest_vehicle(pos: Vector2, max_distance := 400.0) -> int:
	var best := -1
	var best_d := max_distance
	for i in _pos.size():
		var d := vehicle_transform(i).origin.distance_to(pos)
		if d < best_d:
			best = i
			best_d = d
	return best


func static_body_count() -> int:
	return _rid_to_index.size()


func _physics_process(delta: float) -> void:
	if not _built:
		return
	var mechas := get_tree().get_nodes_in_group("mecha")
	if stream and Engine.get_physics_frames() % STREAM_INTERVAL == 0:
		_update_streaming(mechas)
	if _awake.is_empty():
		return
	for i in _awake.keys():
		if not _awake.has(i):
			continue
		var body: RigidBody2D = _awake[i]
		var speed := body.linear_velocity.length()
		if speed > SETTLE_SPEED:
			_wake_in_path(i, body, speed)
		if speed < SETTLE_SPEED and absf(body.angular_velocity) < 0.1 and not _mecha_near(body, mechas):
			_still[i] = _still.get(i, 0.0) + delta
			if _still[i] >= SETTLE_TIME:
				_settle(i)
		else:
			_still[i] = 0.0
	while _awake.size() > MAX_AWAKE:
		_settle(_stillest())


func _build() -> void:
	_layer = get_node_or_null(layer_path) as PropSpriteLayer
	var spawner := get_node_or_null(spawner_path) as PropSpawner
	if spawner == null or _layer == null:
		push_warning("VehicleField: spawner or layer not found")
		return
	if not _layer.rebuilt.is_connected(_on_layer_rebuilt):
		_layer.rebuilt.connect(_on_layer_rebuilt)
	var spawns := spawner.get_spawns()
	for si in spawns.size():
		var s: Dictionary = spawns[si]
		if not kinds.has(s.kind):
			continue
		var variant := _layer.variant_of(s)
		var kind_masses: PackedFloat32Array = masses.get(s.kind, PackedFloat32Array())
		var kind_blocks: PackedFloat32Array = shot_blocks.get(s.kind, PackedFloat32Array())
		_spawn_index.append(si)
		_pos.append(spawner.to_global(s.position))
		_rot.append(s.rotation + spawner.global_rotation)
		_size.append(s.size)
		_mass.append(kind_masses[variant] if variant >= 0 and variant < kind_masses.size() else default_mass)
		_block.append(kind_blocks[variant] if variant >= 0 and variant < kind_blocks.size() else default_shot_block)
		_moved.append(0)
		_static_bodies.append(RID())
		_static_shapes.append(RID())
	for i in _pos.size():
		_add_to_cell(i)
		if not stream:
			_make_static(i)
	_built = true
	if stream:
		_update_streaming(get_tree().get_nodes_in_group("mecha"))


func _make_static(i: int) -> void:
	var shape := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(shape, _size[i] / 2.0)
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_collision_layer(body, MapSenses.VEHICLE_MASK)
	PhysicsServer2D.body_set_collision_mask(body, 0)
	PhysicsServer2D.body_attach_object_instance_id(body, get_instance_id())
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(_rot[i], _pos[i]))
	PhysicsServer2D.body_set_space(body, get_world_2d().space)
	_static_bodies[i] = body
	_static_shapes[i] = shape
	_rid_to_index[body] = i


func _free_static(i: int) -> void:
	var body := _static_bodies[i]
	if not body.is_valid():
		return
	_rid_to_index.erase(body)
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(_static_shapes[i])
	_static_bodies[i] = RID()
	_static_shapes[i] = RID()


func _wake(i: int) -> RigidBody2D:
	if _awake.has(i):
		return _awake[i]
	if _awake.size() >= MAX_AWAKE:
		_settle(_stillest())
	_free_static(i)
	_remove_from_cell(i)
	var body := RigidBody2D.new()
	body.gravity_scale = 0.0
	body.mass = _mass[i]
	body.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.linear_damp = linear_damp
	body.angular_damp = angular_damp
	body.collision_layer = MapSenses.VEHICLE_MASK
	# Not layer 1: the physics engine would let a mecha shove the vehicle
	# like an unstoppable body. Mechas push only through push().
	body.collision_mask = MapSenses.WALL_MASK | MapSenses.VEHICLE_MASK
	body.set_meta("vehicle_index", i)
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size[i]
	col.shape = rect
	body.add_child(col)
	var info := _layer.sprite_info(_spawn_index[i])
	if not info.is_empty():
		var sprite := Sprite2D.new()
		sprite.texture = info.texture
		sprite.scale = info.scale
		sprite.modulate = Color(info.tone, info.tone, info.tone)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		body.add_child(sprite)
	add_child(body)
	body.global_transform = Transform2D(_rot[i], _pos[i])
	_layer.hide_sprite(_spawn_index[i])
	_awake[i] = body
	_still[i] = 0.0
	return body


func _settle(i: int) -> void:
	if not _awake.has(i):
		return
	var body: RigidBody2D = _awake[i]
	_awake.erase(i)
	_still.erase(i)
	_pushed_on.erase(i)
	_pos[i] = body.global_position
	_rot[i] = body.global_rotation
	_moved[i] = 1
	remove_child(body)
	body.queue_free()
	_add_to_cell(i)
	if not stream or _active_cells.has(_cell_of(_pos[i])):
		_make_static(i)
	_layer.place_sprite(_spawn_index[i], _layer.to_local(_pos[i]), _rot[i] - _layer.global_rotation)


# Wakes the sleeping vehicles that a moving one is about to run into, so the
# two meet as moving bodies and the push carries on.
func _wake_in_path(i: int, body: RigidBody2D, speed: float) -> void:
	var reach := _size[i].length() / 2.0 + speed * WAKE_LOOKAHEAD
	var pos := body.global_position
	var cell := _cell_of(pos)
	var span := ceili(reach / CELL_SIZE) + 1
	for cx in range(cell.x - span, cell.x + span + 1):
		for cy in range(cell.y - span, cell.y + span + 1):
			for j in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if j != i and not _awake.has(j) and _awake.size() < MAX_AWAKE \
						and _pos[j].distance_to(pos) < reach + _size[j].length() / 2.0:
					_wake(j)


# Moment of inertia of vehicle i as a solid box.
func _inertia(i: int) -> float:
	return _mass[i] * _size[i].length_squared() / 12.0


func _mecha_near(body: RigidBody2D, mechas: Array) -> bool:
	var i: int = body.get_meta("vehicle_index")
	var reach := _size[i].length() / 2.0 + SETTLE_CLEARANCE
	for m in mechas:
		if m is Node2D and (m as Node2D).global_position.distance_to(body.global_position) < reach + 100.0:
			return true
	return false


func _stillest() -> int:
	var best := -1
	var best_speed := INF
	for i in _awake:
		var speed: float = (_awake[i] as RigidBody2D).linear_velocity.length()
		if speed < best_speed:
			best = i
			best_speed = speed
	return best


func _on_layer_rebuilt() -> void:
	for i in _pos.size():
		if _awake.has(i):
			_layer.hide_sprite(_spawn_index[i])
		elif _moved[i]:
			_layer.place_sprite(_spawn_index[i], _layer.to_local(_pos[i]), _rot[i] - _layer.global_rotation)


# Gives boxes to the sleeping vehicles in cells near a mecha, and removes
# them from cells that no mecha is near any more.
func _update_streaming(mechas: Array) -> void:
	var wanted := {}
	var span := ceili(stream_radius / CELL_SIZE)
	for m in mechas:
		if not (m is Node2D) or not (m as Node2D).is_inside_tree():
			continue
		var c := _cell_of((m as Node2D).global_position)
		for cx in range(c.x - span, c.x + span + 1):
			for cy in range(c.y - span, c.y + span + 1):
				wanted[Vector2i(cx, cy)] = true
	for key in _active_cells.keys():
		if not wanted.has(key):
			_active_cells.erase(key)
			for j in _cells.get(key, PackedInt32Array()):
				_free_static(j)
	for key in wanted:
		if _active_cells.has(key):
			continue
		_active_cells[key] = true
		for j in _cells.get(key, PackedInt32Array()):
			if not _awake.has(j) and not _static_bodies[j].is_valid():
				_make_static(j)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))


func _add_to_cell(i: int) -> void:
	var key := _cell_of(_pos[i])
	var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
	list.append(i)
	_cells[key] = list


func _remove_from_cell(i: int) -> void:
	var key := _cell_of(_pos[i])
	var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
	var at := list.find(i)
	if at >= 0:
		list.remove_at(at)
		_cells[key] = list
