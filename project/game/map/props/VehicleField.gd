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
# Pushing: Mecha.move() calls push_from() after it moves. A mecha's mass
# grows faster than its weight (pusher_mass): a mecha of MASS_PIVOT_WEIGHT
# counts as MECHA_KG_PER_WEIGHT kg per point, and the mass scales with weight
# to the power MASS_CURVE, so heavy builds are much less held back by what
# they push. When it first runs into a vehicle, the two collide like bodies
# with RESTITUTION bounce. While it keeps pushing, the vehicle moves at the
# speed the two would share as one body (the mecha's speed times mecha mass /
# both masses). The mecha can only follow as fast as the vehicle in front of
# it moves, so a light car barely slows it and slides on a few metres when it
# stops; a heavy truck barely moves and holds it back. A push off the
# vehicle's centre turns it, scaled by SPIN.
#
# Trampling: a mecha with tank movement that keeps pushing a vehicle no
# heavier than trample_max_mass drives over it after trample_time() of
# pushing (shorter for a heavier tank or a lighter car). A trampled vehicle
# has no body any more: mechas drive over it, shots pass over it, and NPC
# steering ignores it. It is drawn with the sprite "<sprite>_trampled.png"
# next to its normal sprite when that file exists (for example
# vehicle_hatchback_trampled.png, same image size as vehicle_hatchback.png),
# otherwise with its normal sprite darkened to TRAMPLED_TONE.
#
# Cars (vehicles up to trample_max_mass) sit on MapSenses.VEHICLE_LAYER and
# heavier vans and trucks on HEAVY_VEHICLE_LAYER, so a sprinting mecha can
# drop the car layer and pass over cars (Mecha.move) while trucks still stop
# it.
#
# Destroying: a car has vehicle_hp points. Each shot that meets it costs 1
# (MapSenses.trace_shot), a blast costs BLAST_DAMAGE to every car in its
# radius (damage_in_radius), and a mecha dashing into it (dash speed over
# DASH_DESTROY_SPEED) destroys it at once. A destroyed car loses its body
# like a trampled one and is drawn with "<sprite>_destroyed.png" when that
# file exists, otherwise darkened to DESTROYED_TONE. Vans and trucks can't be
# destroyed.
#
# Steering: NPC mechas read vehicles straight from this node
# (vehicles_near, vehicle_transform, vehicle_size, vehicle_mass), so they
# steer round vehicles that have no box streamed in. last_pushed_by() tells
# an NPC which vehicle it last pushed.
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
# Car alarms: when a mecha first runs into an intact car (each new push
# contact, not every frame it keeps pushing), the car starts its alarm with
# chance alarm_chance (ALARM_CHANCE), at most once per car. Vans, trucks and
# trampled or destroyed cars never do. An alarm lasts ALARM_TIME s: a light
# on the car blinks (ALARM_BLINK s on, ALARM_BLINK off; a glow drawn in the
# dark plus a 2D light on the ground), chirping each time it comes on, and
# alarm_started tells the scene, which makes it a loud sound heard within
# ALARM_SOUND_RANGE (CombatScene._on_car_alarm). start_alarm() sets one off
# directly. A car trampled or destroyed while its alarm sounds goes quiet.
#
# masses, shot_blocks: kind -> PackedFloat32Array, one value per sprite
# variant (from sprite_catalogue.json). A shot_block is the chance that a
# shot passing through the vehicle stops in it (MapSenses.trace_shot).

const MECHA_KG_PER_WEIGHT := 50.0
## Weight at which a mecha counts as exactly MECHA_KG_PER_WEIGHT kg per point.
const MASS_PIVOT_WEIGHT := 45.0
## Mass grows with weight to this power (1 = linear).
const MASS_CURVE := 2.5
## Seconds a tank pushes a car of its own mass before it drives over it.
const TRAMPLE_TIME := 2.0
## A push pause longer than this (s) restarts the trample count. Shorter
## pauses (the tank bouncing off the car before it pushes steadily) don't.
const TRAMPLE_GAP := 0.6
## Brightness of a trampled vehicle drawn with its normal sprite.
const TRAMPLED_TONE := 0.55
## Brightness of a destroyed vehicle drawn with its normal sprite.
const DESTROYED_TONE := 0.3
## Damage every car in a blast's radius takes.
const BLAST_DAMAGE := 3.0
## A mecha dashing faster than this (px/s) destroys a car it runs into.
const DASH_DESTROY_SPEED := 600.0
## Vehicle states.
const INTACT := 0
const TRAMPLED := 1
const DESTROYED := 2
## last_pushed_by() forgets a push after this many physics frames.
const PUSH_MEMORY_FRAMES := 30
## Floats per vehicle in steering_obstacles().
const STEER_STRIDE := 7
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
## Car alarms (see above).
const ALARM_CHANCE := 0.05
const ALARM_TIME := 10.0
const ALARM_SOUND_RANGE := 3000.0
const ALARM_BLINK := 0.4
const ALARM_SFX := "rapid_beep"
const ALARM_GLOW := preload("res://assets/images/light_sources/light_point_soft.png")
const ALARM_GLOW_SCALE := 1.6
const ALARM_LIGHT_SCALE := 6.0
const ALARM_LIGHT_ENERGY := 1.4

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
## Vehicles up to this mass (kg) are cars: tanks drive over them, sprinting
## mechas pass over them, and they can be destroyed. Heavier vehicles (vans,
## trucks) can only be pushed.
@export var trample_max_mass := 3000.0
## Damage points a car takes before it is destroyed.
@export var vehicle_hp := 5.0
## The chance a push contact starts a car's alarm.
var alarm_chance := ALARM_CHANCE

signal vehicle_trampled(index: int, by: Node)
signal vehicle_destroyed(index: int, by: Node)
## A car's alarm went off, at `at`.
signal alarm_started(index: int, at: Vector2)

var _layer: PropSpriteLayer
var _spawn_index := PackedInt32Array()
var _kind := PackedStringArray()
var _variant := PackedInt32Array()
# Vehicle index -> INTACT, TRAMPLED or DESTROYED.
var _state := PackedByteArray()
var _damage := PackedFloat32Array()
# Vehicle index -> Sprite2D drawing its trampled or destroyed sprite.
var _flat_sprites := {}
# Sprite path with "_trampled" or "_destroyed" -> Texture2D, or null when
# there is none.
var _flat_textures := {}
# Vehicle index -> seconds a tank has pushed it, and the last frame it did.
var _trample_push := {}
var _trample_frame := {}
# Mecha instance id -> [vehicle index, physics frame] of its last push.
var _last_pushed := {}
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
# Car alarms: index -> true once a car has sounded; index -> seconds left
# and its light node while it sounds.
var _alarm_done := {}
var _alarm_left := {}
var _alarm_lights := {}


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


# The mass (kg) a mecha of this weight pushes with.
static func pusher_mass(weight: float) -> float:
	var w := maxf(weight, 1.0)
	return MECHA_KG_PER_WEIGHT * w * pow(w / MASS_PIVOT_WEIGHT, MASS_CURVE - 1.0)


static func mecha_mass(mecha: Node) -> float:
	var weight: float = mecha.get_total_weight() if mecha.has_method("get_total_weight") else 50.0
	return pusher_mass(weight)


# The fraction of its own speed a mecha of `pusher` kg keeps while it pushes
# a vehicle of `vehicle_kg`.
static func push_speed_fraction(pusher: float, vehicle_kg: float) -> float:
	return pusher / (pusher + maxf(vehicle_kg, 0.0))


static func find(node: Node) -> VehicleField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("vehicle_field") as VehicleField


func push(mecha: CharacterBody2D, intended: Vector2) -> void:
	var pusher := mecha_mass(mecha)
	var tank: bool = mecha.get("movement_type") == "tank"
	var dash_vel = mecha.get("dash_velocity")
	var dashing: bool = dash_vel is Vector2 and (dash_vel as Vector2).length() > DASH_DESTROY_SPEED
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
		_last_pushed[mecha.get_instance_id()] = [i, frame]
		if dashing and is_car(i):
			_flatten(i, DESTROYED, mecha)
			continue
		if tank and _count_trample(i, pusher, frame):
			_trample(i, mecha)
			continue
		var body := _wake(i)
		if body == null:
			continue
		var m := _mass[i]
		var u := body.linear_velocity.dot(n)
		var target := pusher * v_n / (pusher + m)
		if _pushed_on.get(i, -10) < frame - 1:
			target = (pusher * v_n + m * u + pusher * RESTITUTION * (v_n - u)) / (pusher + m)
			if can_alarm(i) and randf() < alarm_chance:
				start_alarm(i)
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


# False until the vehicles are read from the spawner (a frame after load).
func is_built() -> bool:
	return _built


# The nearest point to `pos` (searched in rings out to max_search px) with no
# vehicle within `clearance` px of its edge, so a mecha put there doesn't
# start inside one. `pos` itself when it is already clear or nothing is.
func clear_spot(pos: Vector2, clearance: float, max_search := 1500.0) -> Vector2:
	if not _built or is_clear(pos, clearance):
		return pos
	var ring := clearance
	while ring <= max_search:
		var count := maxi(8, ceili(TAU * ring / clearance))
		for k in count:
			var p := pos + Vector2.from_angle(TAU * k / count) * ring
			if is_clear(p, clearance):
				return p
		ring += clearance * 0.75
	return pos


# Whether no vehicle is within `clearance` px of a global position.
func is_clear(pos: Vector2, clearance: float) -> bool:
	for i in vehicles_near(pos, clearance + 150.0):
		var xf := vehicle_transform(i)
		var local := xf.affine_inverse() * pos
		var half := _size[i] * 0.5
		var outside := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.y) - half.y, 0.0))
		if outside.length() < clearance:
			return false
	return true


func awake_count() -> int:
	return _awake.size()


func is_awake(i: int) -> bool:
	return _awake.has(i)


## Whether car i can still start its alarm: an intact car that hasn't yet.
func can_alarm(i: int) -> bool:
	return _state[i] == INTACT and is_car(i) and not _alarm_done.has(i)


## Sets off car i's alarm now (see Car alarms above), if it can.
func start_alarm(i: int) -> void:
	if not can_alarm(i):
		return
	_alarm_done[i] = true
	_alarm_left[i] = ALARM_TIME
	var light := Node2D.new()
	light.light_mask = 0
	var glow := Sprite2D.new()
	glow.texture = ALARM_GLOW
	glow.scale = Vector2.ONE * ALARM_GLOW_SCALE
	glow.light_mask = 0
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = add
	light.add_child(glow)
	var lamp := PointLight2D.new()
	lamp.texture = ALARM_GLOW
	lamp.texture_scale = ALARM_LIGHT_SCALE
	lamp.energy = ALARM_LIGHT_ENERGY
	# Added, like the illuminators (see Illumination), so it doesn't paint over
	# their light.
	lamp.blend_mode = Light2D.BLEND_MODE_ADD
	lamp.range_item_cull_mask = MapSenses.SIGHT_LIGHT_MASK
	light.add_child(lamp)
	light.z_index = 5
	light.visible = false
	add_child(light)
	light.global_position = vehicle_transform(i).origin
	_alarm_lights[i] = light
	_blink_alarm(i)
	alarm_started.emit(i, vehicle_transform(i).origin)


## Whether car i's alarm is sounding now.
func is_alarm_on(i: int) -> bool:
	return _alarm_left.has(i)


## The cars sounding now.
func sounding_alarms() -> Array:
	return _alarm_left.keys()


# Where vehicle i is now (global position and rotation).
func vehicle_transform(i: int) -> Transform2D:
	if _awake.has(i):
		return (_awake[i] as Node2D).global_transform
	return Transform2D(_rot[i], _pos[i])


func vehicle_mass(i: int) -> float:
	return _mass[i]


# Length (x) by width (y) in px.
func vehicle_size(i: int) -> Vector2:
	return _size[i]


func is_trampled(i: int) -> bool:
	return _state[i] == TRAMPLED


func is_destroyed(i: int) -> bool:
	return _state[i] == DESTROYED


# Whether vehicle i is a car (see trample_max_mass).
func is_car(i: int) -> bool:
	return _mass[i] <= trample_max_mass


# Whether a tank can drive over vehicle i.
func can_trample(i: int) -> bool:
	return _state[i] == INTACT and is_car(i)


# Damages vehicle i; a car destroyed by it is gone. Vans and trucks ignore it.
func damage(i: int, amount: float, by: Node = null) -> void:
	if _state[i] != INTACT or not is_car(i):
		return
	_damage[i] += amount
	if _damage[i] >= vehicle_hp:
		_flatten(i, DESTROYED, by)


# Damages every car whose centre is within `radius` of a global position.
func damage_in_radius(pos: Vector2, radius: float, amount: float, by: Node = null) -> void:
	for i in vehicles_near(pos, radius + 100.0):
		if vehicle_transform(i).origin.distance_to(pos) <= radius + _size[i].x * 0.5:
			damage(i, amount, by)


# Seconds a tank of `pusher` kg must push vehicle i before it drives over it.
func trample_time(i: int, pusher: float) -> float:
	return TRAMPLE_TIME * clampf(_mass[i] / maxf(pusher, 1.0), 0.5, 2.0)


# Vehicles (awake or asleep, not trampled) whose centres are within `radius`
# of a global position.
func vehicles_near(pos: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not _built:
		return out
	var r2 := radius * radius
	var c0 := _cell_of(pos - Vector2(radius, radius))
	var c1 := _cell_of(pos + Vector2(radius, radius))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for j in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if _pos[j].distance_squared_to(pos) <= r2:
					out.append(j)
	for j in _awake:
		if (_awake[j] as Node2D).global_position.distance_squared_to(pos) <= r2:
			out.append(j)
	return out


# Steering data for the vehicles (awake or asleep, not trampled) that come
# within `radius` of a global position, STEER_STRIDE floats each:
# x, y, rotation, length, width, mass, vehicle index. One call per NPC
# update, so steering doesn't pay a method call per vehicle.
func steering_obstacles(pos: Vector2, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	steering_obstacles_into(pos, radius, out)
	return out


# The same, written into `out` (cleared first), so an NPC can reuse one
# buffer rebuild after rebuild.
func steering_obstacles_into(pos: Vector2, radius: float, out: PackedFloat32Array) -> void:
	out.clear()
	if not _built:
		return
	var reach := radius + 120.0
	var c0 := _cell_of(pos - Vector2(reach, reach))
	var c1 := _cell_of(pos + Vector2(reach, reach))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for j in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				var p := _pos[j]
				var r := radius + _size[j].x * 0.5
				if p.distance_squared_to(pos) <= r * r:
					_append_obstacle(out, j, p, _rot[j])
	for j in _awake:
		var body: Node2D = _awake[j]
		var p := body.global_position
		var r := radius + _size[j].x * 0.5
		if p.distance_squared_to(pos) <= r * r:
			_append_obstacle(out, j, p, body.global_rotation)


func _append_obstacle(out: PackedFloat32Array, j: int, p: Vector2, rot: float) -> void:
	var n := out.size()
	out.resize(n + STEER_STRIDE)
	out[n] = p.x
	out[n + 1] = p.y
	out[n + 2] = rot
	out[n + 3] = _size[j].x
	out[n + 4] = _size[j].y
	out[n + 5] = _mass[j]
	out[n + 6] = j


# The vehicle this mecha pushed in the last PUSH_MEMORY_FRAMES physics
# frames, or -1. A vehicle trampled since counts only with include_trampled.
func last_pushed_by(mecha: Node, include_trampled := false) -> int:
	var rec: Array = _last_pushed.get(mecha.get_instance_id(), [])
	if rec.is_empty() or Engine.get_physics_frames() - int(rec[1]) > PUSH_MEMORY_FRAMES:
		return -1
	var i: int = rec[0]
	return -1 if _state[i] != INTACT and not include_trampled else i


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
	if not _alarm_left.is_empty():
		_update_alarms(delta)
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
		_kind.append(s.kind)
		_variant.append(variant)
		_state.append(INTACT)
		_damage.append(0.0)
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
	PhysicsServer2D.body_set_collision_layer(body, _layer_mask(i))
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
	body.collision_layer = _layer_mask(i)
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
		sprite.light_mask = _layer.light_mask
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
		if _awake.has(i) or _flat_sprites.has(i):
			_layer.hide_sprite(_spawn_index[i])
		elif _state[i] != INTACT:
			_layer.place_sprite(_spawn_index[i], _layer.to_local(_pos[i]), _rot[i] - _layer.global_rotation, _flat_tone(i))
		elif _moved[i]:
			_layer.place_sprite(_spawn_index[i], _layer.to_local(_pos[i]), _rot[i] - _layer.global_rotation)


# Counts the time a tank of `pusher` kg has been pushing vehicle i. Returns
# true when it has pushed long enough to drive over it.
func _count_trample(i: int, pusher: float, frame: int) -> bool:
	if not can_trample(i):
		return false
	var step := get_physics_process_delta_time()
	var t: float = _trample_push.get(i, 0.0)
	if frame - int(_trample_frame.get(i, -100000)) > maxi(1, ceili(TRAMPLE_GAP / step)):
		t = 0.0
	t += step
	_trample_push[i] = t
	_trample_frame[i] = frame
	return t >= trample_time(i, pusher)


func _trample(i: int, by: Node) -> void:
	_flatten(i, TRAMPLED, by)


# The physics layer for vehicle i: cars and heavy vehicles apart.
func _layer_mask(i: int) -> int:
	return MapSenses.CAR_MASK if is_car(i) else MapSenses.HEAVY_VEHICLE_MASK


func _update_alarms(delta: float) -> void:
	for i in _alarm_left.keys():
		_alarm_left[i] -= delta
		if _alarm_left[i] <= 0.0 or _state[i] != INTACT:
			_stop_alarm(i)
			continue
		(_alarm_lights[i] as Node2D).global_position = vehicle_transform(i).origin
		_blink_alarm(i)


# The light is on for the first ALARM_BLINK s of every 2 × ALARM_BLINK, and
# chirps as it comes on.
func _blink_alarm(i: int) -> void:
	var light: Node2D = _alarm_lights[i]
	var elapsed: float = ALARM_TIME - float(_alarm_left[i])
	var on := fmod(elapsed, ALARM_BLINK * 2.0) < ALARM_BLINK
	if on and not light.visible:
		AudioManager.play_sfx(ALARM_SFX, light.global_position, null, null, null, ALARM_SOUND_RANGE)
	light.visible = on


func _stop_alarm(i: int) -> void:
	_alarm_left.erase(i)
	var light: Node2D = _alarm_lights.get(i)
	_alarm_lights.erase(i)
	if is_instance_valid(light):
		light.queue_free()


# Trampled or destroyed where it is: its body goes, and its sprite changes.
func _flatten(i: int, state: int, by: Node) -> void:
	if _state[i] != INTACT:
		return
	if _awake.has(i):
		var body: RigidBody2D = _awake[i]
		_pos[i] = body.global_position
		_rot[i] = body.global_rotation
		_awake.erase(i)
		_still.erase(i)
		_pushed_on.erase(i)
		remove_child(body)
		body.queue_free()
	else:
		_free_static(i)
		_remove_from_cell(i)
	_moved[i] = 1
	_state[i] = state
	_trample_push.erase(i)
	_trample_frame.erase(i)
	_show_flat(i)
	if state == TRAMPLED:
		vehicle_trampled.emit(i, by)
	else:
		vehicle_destroyed.emit(i, by)


func _flat_tone(i: int) -> float:
	return DESTROYED_TONE if _state[i] == DESTROYED else TRAMPLED_TONE


func _show_flat(i: int) -> void:
	var info := _layer.sprite_info(_spawn_index[i])
	var tex := _flat_texture(i)
	if tex == null or info.is_empty():
		_layer.place_sprite(_spawn_index[i], _layer.to_local(_pos[i]), _rot[i] - _layer.global_rotation, _flat_tone(i))
		return
	_layer.hide_sprite(_spawn_index[i])
	var normal: Texture2D = info.texture
	var size: Vector2 = Vector2(info.scale) * normal.get_size()
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = size / tex.get_size()
	sprite.modulate = Color(info.tone, info.tone, info.tone)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.light_mask = _layer.light_mask
	add_child(sprite)
	sprite.global_position = _pos[i]
	sprite.global_rotation = _rot[i]
	_flat_sprites[i] = sprite


# The "<sprite>_trampled" or "<sprite>_destroyed" texture for vehicle i's
# normal sprite, by its state, or null.
func _flat_texture(i: int) -> Texture2D:
	var list: Array = _layer.textures.get(_kind[i], [])
	var v := _variant[i]
	if v < 0 or v >= list.size() or not (list[v] is Texture2D):
		return null
	var path: String = (list[v] as Texture2D).resource_path
	if path.is_empty():
		return null
	var suffix := "_destroyed." if _state[i] == DESTROYED else "_trampled."
	var flat_path := path.get_basename() + suffix + path.get_extension()
	if not _flat_textures.has(flat_path):
		_flat_textures[flat_path] = load(flat_path) as Texture2D if ResourceLoader.exists(flat_path) else null
	return _flat_textures[flat_path]


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
