class_name HeatTrails
extends Node2D

## Warm marks moving mechas leave on the ground, shown in the IR view to
## everyone. One per combat scene (CombatScene._setup_heatmap), under the
## mechas.
##
## Every physics frame each living mecha that has moved a stride since its
## last mark leaves one:
##   legs     a footprint, left and right in turn (FOOT_*)
##   hover    one wide wash under it (HOVER_*)
##   others   a smear under each track or wheel set (TRACK_*)
## A jump of more than JUMP_DISTANCE (a spawn, a teleport) leaves nothing.
##
## A mark's warmth (0 to 1) at the start is the mecha's thermal signature
## (Mecha.get_thermal_signature, from its external temperature) over a floor
## of MIN_WARMTH, scaled down for a slow mecha (SLOW_WARMTH at a standstill,
## full at FULL_WARMTH_SPEED). It cools in a straight line to nothing over
## its lifetime, MIN_COOL_TIME for a mark of no warmth to MAX_COOL_TIME for
## one of full warmth. So a cold, slow mecha leaves faint, short trails.
##
## Drawn bright (BRIGHTNESS times warmth), added onto the ground, unshaded
## and off the darkness light layer: the head's heat colour map turns it into
## heat, in the dark too. Marks are a fixed pool of MAX_MARKS (the oldest is
## reused), drawn in one MultiMesh, with no node per mark. Their colours are
## refreshed every REFRESH_TIME s.
##
## For NPC code: HeatTrails.find(node).marks_near(point, radius).

const MARK_TEXTURE := preload("res://assets/images/light_sources/light_point_soft.png")
const MAX_MARKS := 4096
const MIN_COOL_TIME := 20.0
const MAX_COOL_TIME := 40.0
const MIN_WARMTH := 0.15
const SLOW_WARMTH := 0.5
const FULL_WARMTH_SPEED := 400.0
const BRIGHTNESS := 0.55
const REFRESH_TIME := 0.2
const JUMP_DISTANCE := 400.0
## Footprints: one every FOOT_STRIDE px, FOOT_SPACING px either side of the
## mecha's path, FOOT_SIZE (across, along) px.
const FOOT_STRIDE := 70.0
const FOOT_SPACING := 28.0
const FOOT_SIZE := Vector2(34, 50)
## Track or wheel smears: a pair every TRACK_STRIDE px, TRACK_SPACING px
## either side, TRACK_SIZE each; long enough to run into the next pair.
const TRACK_STRIDE := 40.0
const TRACK_SPACING := 55.0
const TRACK_SIZE := Vector2(30, 70)
## Hover: one wash every HOVER_STRIDE px, HOVER_SIZE.
const HOVER_STRIDE := 50.0
const HOVER_SIZE := Vector2(110, 90)

enum Kind { FOOT, TRACK, HOVER }
const KIND_NAMES := ["foot", "track", "hover"]

var now := 0.0

var _pos := PackedVector2Array()
var _heading := PackedVector2Array()
var _size := PackedVector2Array()
var _born := PackedFloat32Array()
var _warmth := PackedFloat32Array()
var _life := PackedFloat32Array()
var _kind := PackedByteArray()
var _count := 0
var _next := 0
# Mecha instance id -> {"at": where it last left a mark, "left": next foot}.
var _walkers := {}
var _refresh := 0.0
var _multimesh := MultiMesh.new()


## The scene's heat trails, or null.
static func find(node: Node) -> HeatTrails:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("heat_trails") as HeatTrails


## How warm a mark left now by a mecha with this thermal signature, going at
## `speed` px/s, starts (0 to 1).
static func start_warmth(signature: float, speed: float) -> float:
	var heat := MIN_WARMTH + (1.0 - MIN_WARMTH) * clampf(signature, 0.0, 1.0)
	return heat * lerpf(SLOW_WARMTH, 1.0, clampf(speed / FULL_WARMTH_SPEED, 0.0, 1.0))


## How long (s) a mark of this starting warmth takes to cool.
static func cool_time(warmth: float) -> float:
	return lerpf(MIN_COOL_TIME, MAX_COOL_TIME, clampf(warmth, 0.0, 1.0))


func _ready() -> void:
	add_to_group("heat_trails")
	light_mask = 0
	var material_add := CanvasItemMaterial.new()
	material_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_pos.resize(MAX_MARKS)
	_heading.resize(MAX_MARKS)
	_size.resize(MAX_MARKS)
	_born.resize(MAX_MARKS)
	_warmth.resize(MAX_MARKS)
	_life.resize(MAX_MARKS)
	_kind.resize(MAX_MARKS)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_MARKS
	_multimesh.visible_instance_count = 0
	var drawn := MultiMeshInstance2D.new()
	drawn.multimesh = _multimesh
	drawn.texture = MARK_TEXTURE
	drawn.material = material_add
	drawn.light_mask = 0
	add_child(drawn)


func _physics_process(dt: float) -> void:
	now += dt
	for mecha in get_tree().get_nodes_in_group("mecha"):
		if mecha is Node2D and mecha.get("is_dead") != true:
			_walk(mecha)
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = REFRESH_TIME
		_redraw()


## The marks within `radius` of `point` still warm: {"position", "age" (s),
## "warmth" (now, 0 to 1), "heading" (the way the mecha was going), "kind"
## ("foot", "track", "hover")}. Nothing says whose they are.
func marks_near(point: Vector2, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var radius_sq := radius * radius
	for i in _count:
		if _pos[i].distance_squared_to(point) > radius_sq:
			continue
		var warmth := warmth_of(i)
		if warmth <= 0.0:
			continue
		found.append({"position": _pos[i], "age": now - _born[i], "warmth": warmth,
				"heading": _heading[i], "kind": KIND_NAMES[_kind[i]]})
	return found


## How many marks are still warm.
func warm_count() -> int:
	var warm := 0
	for i in _count:
		if warmth_of(i) > 0.0:
			warm += 1
	return warm


## Mark i's warmth now (0 once cooled).
func warmth_of(i: int) -> float:
	var age := now - _born[i]
	return maxf(_warmth[i] * (1.0 - age / _life[i]), 0.0)


## Leaves one mark (for tests and scripted scenes).
func add_mark(at: Vector2, heading: Vector2, size: Vector2, warmth: float, kind: Kind) -> void:
	var i := _next
	_next = (_next + 1) % MAX_MARKS
	_count = mini(_count + 1, MAX_MARKS)
	_pos[i] = at
	_heading[i] = heading
	_size[i] = size
	_born[i] = now
	_warmth[i] = warmth
	_life[i] = cool_time(warmth)
	_kind[i] = kind
	_multimesh.visible_instance_count = _count
	_multimesh.set_instance_transform_2d(i, _mark_transform(i))
	_multimesh.set_instance_color(i, _mark_color(i))


func _walk(mecha: Node2D) -> void:
	var id := mecha.get_instance_id()
	var at := mecha.global_position
	var walker: Dictionary = _walkers.get(id, {})
	if walker.is_empty():
		_walkers[id] = {"at": at, "left": true}
		return
	var moved: Vector2 = at - walker.at
	var chassis = mecha.build.chassis if mecha.get("build") != null else null
	var kind := Kind.TRACK
	if chassis != null and chassis.is_legs:
		kind = Kind.FOOT
	elif chassis != null and chassis.hover_particles:
		kind = Kind.HOVER
	var stride: float = [FOOT_STRIDE, TRACK_STRIDE, HOVER_STRIDE][kind]
	if moved.length() > JUMP_DISTANCE:
		walker.at = at
		return
	if moved.length() < stride:
		return
	walker.at = at
	var heading := moved.normalized()
	var side := heading.orthogonal()
	var speed: float = (mecha.velocity as Vector2).length() if mecha.get("velocity") is Vector2 else 0.0
	var signature: float = mecha.get_thermal_signature() if mecha.has_method("get_thermal_signature") else 0.0
	var warmth := start_warmth(signature, speed)
	match kind:
		Kind.FOOT:
			var offset := FOOT_SPACING if walker.left else -FOOT_SPACING
			walker.left = not walker.left
			add_mark(at + side * offset, heading, FOOT_SIZE, warmth, kind)
		Kind.HOVER:
			add_mark(at, heading, HOVER_SIZE, warmth, kind)
		_:
			add_mark(at + side * TRACK_SPACING, heading, TRACK_SIZE, warmth, kind)
			add_mark(at - side * TRACK_SPACING, heading, TRACK_SIZE, warmth, kind)


func _redraw() -> void:
	for i in _count:
		_multimesh.set_instance_color(i, _mark_color(i))
	# Mechas that are gone leave their entry behind; drop those.
	if Engine.get_physics_frames() % 600 == 0:
		for id in _walkers.keys():
			if not is_instance_id_valid(id):
				_walkers.erase(id)


func _mark_transform(i: int) -> Transform2D:
	var angle := _heading[i].angle() + PI * 0.5
	return Transform2D(angle, _size[i], 0.0, _pos[i])


func _mark_color(i: int) -> Color:
	return Color(1.0, 1.0, 1.0, warmth_of(i) * BRIGHTNESS)
