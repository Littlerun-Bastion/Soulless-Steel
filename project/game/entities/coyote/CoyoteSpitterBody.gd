extends CoyoteBody
class_name CoyoteSpitterBody

signal fired(muzzle: Vector2, direction: Vector2)

const CHARGE_TIME := 0.6
const RECOVER_TIME := 0.4

var aim_point := Vector2.ZERO

var _fire_t := -1.0
var _fired := false


func _init() -> void:
	super()
	placeholder_head_size = Vector2(22.0, 15.0)


func _tail_layout() -> Array:
	# Has two tails instead of one
	var tails := [
		{"x": -0.12, "y": -0.06, "length": 220.0, "width": 14.0},
		{"x": -0.12, "y": 0.06, "length": 220.0, "width": 14.0},
	]
	tails.append_array(super().slice(1))
	return tails


func charge(aim: Vector2) -> void:
	if dead or _fire_t >= 0.0:
		return
	_fire_t = 0.0
	_fired = false
	aim_point = aim


func is_attacking() -> bool:
	return _fire_t >= 0.0


func _animate(delta: float) -> void:
	var attacking := is_attacking()
	thrash = move_toward(thrash, 1.0 if attacking else 0.0, delta * (8.0 if attacking else 2.5))
	if _fire_t < 0.0:
		pulse_strength = move_toward(pulse_strength, 0.0, delta * 4.0)
		body_swell = move_toward(body_swell, 0.0, delta)
		return
	_fire_t += delta
	var aim: float  # how far the tails are curled forward, 0..1
	if _fire_t < CHARGE_TIME:
		var charge_amount := _fire_t / CHARGE_TIME
		aim = smoothstep(0.0, 0.35, charge_amount)
		pulse_pos = fmod(_fire_t * lerpf(2.0, 6.0, charge_amount), 1.0)
		pulse_strength = lerpf(0.25, 0.7, charge_amount)
		body_swell = 0.07 * sin(_fire_t * TAU * lerpf(3.0, 8.0, charge_amount)) * charge_amount
	else:
		if not _fired:
			_fired = true
			var muzzle := (_tails[0].points[TAIL_POINTS - 1] + _tails[1].points[TAIL_POINTS - 1]) * 0.5
			var dir := aim_point - muzzle
			fired.emit(muzzle, dir.normalized() if dir.length() > 1.0 else Vector2.from_angle(global_rotation))
		var r := minf((_fire_t - CHARGE_TIME) / RECOVER_TIME, 1.0)
		aim = 1.0 - smoothstep(0.0, 1.0, r)
		pulse_pos = 1.0  
		pulse_strength = 0.9 * (1.0 - r)
		body_swell = 0.0
		if r >= 1.0:
			_fire_t = -1.0
	for i in 2:
		_pose_aim(_tails[i], aim, -1.0 if i == 0 else 1.0)


func _pose_aim(tail: Tail, aim: float, side: float) -> void:
	tail.pose_weight = aim
	tail.raise = aim
	var root := _body_to_world(tail.root)
	var back := Vector2.from_angle(global_rotation + PI)
	var to_target := aim_point - global_position
	to_target = to_target.normalized() if to_target.length() > 1.0 else Vector2.from_angle(global_rotation)
	var ctrl := root + back * tail.length * 0.2 + Vector2(0.0, side * body_width * 0.35).rotated(global_rotation)
	var tip := to_global(Vector2(body_length * 0.3, side * body_width * 0.12)) + to_target * tail.length * 0.3
	for i in TAIL_POINTS:
		var t := float(i) / (TAIL_POINTS - 1)
		tail.pose[i] = root.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t)
