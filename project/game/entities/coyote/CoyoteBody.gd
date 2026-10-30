extends SandBody
class_name CoyoteBody

signal whip_struck
signal bite_closed

const WHIP_TIME := 0.8
## Fraction of the whip at which the tail lashes past the head.
const WHIP_STRIKE_AT := 0.45
const BITE_TIME := 0.25

var _whip_t := -1.0
var _whip_side := 1.0
var _bite_t := -1.0


func _init() -> void:
	body_shape = BodyShape.NONE
	# I feel like there could be a better way of doing this honestly...
	body_length = 100.0
	body_width = 100.0
	neck_position = 0.02
	knot_radius = 17.0
	knot_x = -0.07
	body_strands = 7
	placeholder_head_size = Vector2(24.0, 15.0)
	limb_length = 170.0
	limb_points = 10
	limb_width = 22.0
	upper_leg = 0.42
	lower_leg = 0.46
	ankle_leg = 0.3
	ankle_angle = 55.0
	rest_reach = 0.5
	hip_height = 0.5
	step_height = 0.25
	knee_tilt = 30.0
	stride = 0.9
	run_stride = 1.9
	duty_walk = 0.68
	gallop_from = 220.0
	gallop_at = 480.0
	duty_run = 0.4
	max_airborne = 4
	swing_reach = 0.3
	spine_flex = 0.1
	foot_scatter = 3.0
	waddle = 2.0
	claw_count = 3
	claw_length = 13.0
	paw_size = 1.0
	hunt_flow = 4.0


func _leg_layout() -> Array:
	# Front limbs: out from under the head, back to a shoulder behind and
	# to the side, then forward to plant ahead. Their knees (elbows) lean
	# back and out, which carries the limb round in a loop.
	# Hind limbs: out from under the head and back.
	# Walk: a dog's four-beat lateral walk, each foot a quarter cycle after
	# the last: left hind, left fore, right hind, right fore. (A leg with a
	# later phase lifts sooner, so the phases count down in that order.)
	# Run: a rotary gallop.
	var legs := []
	for side in [-1.0, 1.0]:
		var right: bool = side > 0.0
		legs.append({"x": -0.22, "y": 0.2 * side, "root": Vector2(-0.04, 0.05 * side),
				"side": side, "angle": 35.0, "width": 24.0,
				"walk": 0.0 if right else 0.5, "run": 0.65 if right else 0.55})
		legs.append({"x": -0.34, "y": 0.14 * side, "root": Vector2(-0.08, 0.04 * side),
				"side": side, "angle": 165.0, "width": 21.0,
				"walk": 0.25 if right else 0.75, "run": 0.1 if right else 0.0})
	return legs


func _tail_layout() -> Array:
	var tails := [{"x": -0.12, "y": 0.0, "length": 300.0, "width": 13.0,
			"sway": 0.5, "waves": 1.0, "speed": 2.2, "stiffness": 0.14, "damping": 0.95,
			"run_sway": 0.8, "run_speed": 4.5, "run_stiffness": 0.2}]
	for i in randi_range(4, 6):
		var side := -1.0 if i % 2 == 0 else 1.0
		tails.append({"x": randf_range(-0.14, -0.02), "y": randf_range(0.0, 0.06) * side,
				"length": randf_range(100.0, 180.0), "width": randf_range(7.0, 10.0),
				"angle": side * randf_range(100.0, 160.0), "sway": randf_range(0.6, 0.85),
				"waves": randf_range(1.2, 1.8), "speed": randf_range(1.4, 2.2),
				"run_sway": randf_range(1.1, 1.4), "run_speed": randf_range(4.5, 6.0),
				"run_stiffness": 0.5, "floaty": 1.0, "stiffness": 0.08, "damping": 0.97,
				"thrash": true, "shed": false})
	return tails


func whip() -> void:
	if dead or _whip_t >= 0.0:
		return
	_whip_t = 0.0
	_whip_side = -_whip_side  # alternate sides


func bite() -> void:
	if dead or _bite_t >= 0.0:
		return
	_bite_t = 0.0


func is_attacking() -> bool:
	return _whip_t >= 0.0 or _bite_t >= 0.0


func _animate(delta: float) -> void:
	# Tendrils thrash for the whole attack, easing in fast and out slower.
	var attacking := is_attacking()
	thrash = move_toward(thrash, 1.0 if attacking else 0.0, delta * (8.0 if attacking else 2.5))
	if _whip_t >= 0.0:
		var before := _whip_t
		_whip_t = minf(_whip_t + delta / WHIP_TIME, 1.0)
		_pose_whip(_tails[0], _whip_t)
		if before < WHIP_STRIKE_AT and _whip_t >= WHIP_STRIKE_AT:
			whip_struck.emit()
		if _whip_t >= 1.0:
			_whip_t = -1.0
			_tails[0].pose_weight = 0.0
			_tails[0].raise = 0.0
	if _bite_t >= 0.0:
		var before := _bite_t
		_bite_t = minf(_bite_t + delta / BITE_TIME, 1.0)
		head_lunge = sin(_bite_t * PI)
		if before < 0.5 and _bite_t >= 0.5:
			bite_closed.emit()
		if _bite_t >= 1.0:
			_bite_t = -1.0
			head_lunge = 0.0


# Wind up (0-0.3): the tail swings back and out to the far side.
# Strike (0.3-0.5): it lashes round the near side to point past the head.
# Hold (0.5-0.65): it stays out, so the strike reads.
# Recover (0.65-1): it sweeps back the way it came, then lets go. (Letting
# go while folded double would leave it crumpled.)
func _pose_whip(tail: Tail, w: float) -> void:
	var sweep: float  # direction of the tail's tip, from forward, on the whip side
	var weight: float
	if w < 0.3:
		var e := smoothstep(0.0, 0.3, w)
		sweep = lerpf(PI, PI * 1.25, e)
		weight = e
	elif w < 0.5:
		var e := smoothstep(0.3, 0.5, w)
		sweep = lerpf(PI * 1.25, 0.1, e * e)
		weight = 1.0
	else:
		sweep = lerpf(0.1, PI, smoothstep(0.65, 0.95, w))
		weight = 1.0 - smoothstep(0.9, 1.0, w)
	tail.pose_weight = weight
	tail.raise = weight
	# The pose pulls the root end hardest and the rest is flung after it, so the strike travels down the tail to crack at the tip.
	tail.pose_falloff = 0.45
	var seg := tail.length / (TAIL_POINTS - 1)
	var p := _body_to_world(tail.root)
	tail.pose[0] = p
	for i in range(1, TAIL_POINTS):
		var t := float(i) / (TAIL_POINTS - 1)
		var a := lerpf(PI, sweep, smoothstep(0.0, 0.35, t))
		p += Vector2.from_angle(global_rotation + _whip_side * a) * seg
		tail.pose[i] = p
