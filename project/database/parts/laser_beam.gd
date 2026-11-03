extends Node2D

# A laser shot, fired by a weapon with a "rect" designator (Mecha.fire_at_point
# through the usual create_projectile signal). The beam runs from the muzzle
# towards args.target_pos and stops at the first wall or solid body
# (MapSenses.solid_hit), args.beam_width wide. Its lit front sweeps from the
# muzzle to the far end over sweep_time; every mecha or Entity the front
# passes over is hit once, for one fixed amount: an armour check with
# armor_pen and base_damage pips on its core, from the side facing the
# beam, plus heat_damage kJ of heat. The firer is never hit. The beam stays
# lit for linger_time after the sweep, then is gone.
#
# Only the mechas and Entities near the beam when it fires are checked, by
# plain maths each frame: no physics queries after the first frame's wall
# ray.

signal bullet_impact

## How far (px) from its centre a mecha or Entity counts as touched by the
## beam: about half a mecha.
const BODY_REACH := 90.0

@export var part_name : String
@export var sweep_time := 0.5
@export var linger_time := 0.15
@export var base_damage := 2
@export var armor_pen := 5
@export var heat_damage := 300.0
@export var beam_color := Color(1.0, 1.0, 1.0)
@export var core_color := Color(1.0, 1.0, 1.0)

var original_mecha_info := {}
var part_id
var shield_hit := false
var impact_size := 1.0

var _origin := Vector2.ZERO
var _end := Vector2.ZERO
var _dir := Vector2.RIGHT
var _width := 40.0
var _length := -1.0
var _wall_stopped := false
var _front := 0.0
var _elapsed := 0.0
var _firer = null
var _bodies: Array = []
var _hit := {}


func setup(mecha, args, weapon) -> void:
	_firer = mecha
	original_mecha_info = {"body": mecha, "name": mecha.mecha_name}
	part_id = weapon
	_origin = args.pos
	_dir = (args.dir as Vector2).normalized()
	_end = args.get("target_pos", _origin + _dir * 1000.0)
	_width = maxf(float(args.get("beam_width", _width)), 1.0)
	position = _origin
	rotation = _dir.angle()
	z_index = 10


func _physics_process(dt: float) -> void:
	if _length < 0.0:
		_start()
	_elapsed += dt
	var prev_front := _front
	_front = _length if sweep_time <= 0.0 else minf(_length * _elapsed / sweep_time, _length)
	_hit_bodies(prev_front)
	if _elapsed >= sweep_time + linger_time:
		queue_free()
	queue_redraw()


# On the first frame in the tree: where the beam stops, and what is near it.
func _start() -> void:
	var exclude: Array[RID] = []
	if is_instance_valid(_firer) and _firer is CollisionObject2D:
		exclude.append(_firer.get_rid())
	var hit = MapSenses.solid_hit(get_world_2d(), _origin, _end, exclude)
	_wall_stopped = hit != null
	_length = _origin.distance_to(hit if hit != null else _end)
	var reach := _length + BODY_REACH + _width
	for group in ["mecha", "entity", "device"]:
		for body in get_tree().get_nodes_in_group(group):
			if body != _firer and body is Node2D and _origin.distance_to(body.global_position) <= reach:
				_bodies.append(body)


# Hits what the front passed over since last frame. A body behind a wall
# that stopped the beam isn't reached.
func _hit_bodies(prev_front: float) -> void:
	for body in _bodies:
		if not is_instance_valid(body) or _hit.has(body):
			continue
		var offset: Vector2 = body.global_position - _origin
		var along := offset.dot(_dir)
		if absf(offset.dot(_dir.orthogonal())) > _width * 0.5 + BODY_REACH:
			continue
		if along + BODY_REACH < prev_front or along - BODY_REACH > _front:
			continue
		if along < -BODY_REACH or (_wall_stopped and along > _length):
			continue
		_hit[body] = true
		_hit_body(body, _origin + _dir * clampf(along - BODY_REACH * 0.5, 0.0, _length))


func _hit_body(body, at: Vector2) -> void:
	if body.is_in_group("entity") or body.is_in_group("device"):
		body.take_hit(base_damage, armor_pen, _dir, original_mecha_info, 0.0)
		return
	var pen_result: Dictionary = body.armor_check("core", at, _dir, armor_pen, base_damage)
	if pen_result.penetrated:
		# Attribution before damage: a cockpit kill calls die(), which reads it.
		body.last_damage_source = original_mecha_info
		body.last_damage_weapon = part_id
		if pen_result.component_name != "":
			body.damage_component(pen_result.part_name, pen_result.component_name, base_damage)
	body.increase_heat(heat_damage)


func is_hit(body) -> bool:
	return _hit.has(body)


func get_length() -> float:
	return _length


func _draw() -> void:
	if _length <= 0.0:
		return
	var fade := 1.0
	if _elapsed > sweep_time and linger_time > 0.0:
		fade = clampf(1.0 - (_elapsed - sweep_time) / linger_time, 0.0, 1.0)
	var glow := beam_color
	glow.a *= 0.35 * fade
	var core := core_color
	core.a *= fade
	draw_rect(Rect2(0.0, -_width * 0.5, _front, _width), glow)
	draw_line(Vector2.ZERO, Vector2(_front, 0.0), core, maxf(_width * 0.25, 2.0))
