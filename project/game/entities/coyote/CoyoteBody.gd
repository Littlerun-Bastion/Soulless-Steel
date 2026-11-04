extends SandBody
class_name CoyoteBody

signal whip_struck
signal bite_closed

const WHIP_TIME := 0.8
## Fraction of the whip at which the tail lashes past the head.
const WHIP_STRIKE_AT := 0.45
const BITE_TIME := 0.25
## Carried parts (carry_shield, carry_gun): their own sprites, scaled to
## about this many px across, the shield in front of the head, the gun over
## it, each held by a loose tendril wrapped round it. Placeholders.
const SHIELD_SIZE := 70.0
const GUN_SIZE := 64.0
const SHIELD_AHEAD := 0.5     # fractions of body_length ahead of the centre
const GUN_AHEAD := 0.12
const GUN_LIFT := 26.0        # px the gun sits off the centre line, over the head
const WRAP_RADIUS := 12.0
const WRAP_SHARE := 0.3       # of the tendril, wound round the part
const HOLD_WEIGHT := 0.85

## Where the carried gun points (world), set by the Coyote.
var gun_aim := Vector2.ZERO

var _whip_t := -1.0
var _whip_side := 1.0
var _bite_t := -1.0
var _shield_sprite: Sprite2D = null
var _gun_sprite: Sprite2D = null
var _loose: Array[int] = []  # the loose tendrils: indices in _tails


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


func _ready() -> void:
	super()
	for i in _tails.size():
		if _tails[i].thrashes:
			_loose.append(i)


## Carries a shoulder as a shield (its sprite), or nothing (null).
func carry_shield(texture: Texture2D) -> void:
	_shield_sprite = _carried(_shield_sprite, texture, SHIELD_SIZE)


## Carries an arm weapon as a gun (its sprite), or nothing (null).
func carry_gun(texture: Texture2D) -> void:
	_gun_sprite = _carried(_gun_sprite, texture, GUN_SIZE)


## Where the shield is (world).
func shield_position() -> Vector2:
	return _shield_sprite.global_position if _shield_sprite != null else to_global(Vector2(body_length * SHIELD_AHEAD, 0.0))


## Where the carried gun's rounds leave it (world).
func gun_muzzle() -> Vector2:
	if _gun_sprite == null:
		return global_position
	var to_aim := gun_aim - _gun_sprite.global_position
	var dir := to_aim.normalized() if to_aim.length() > 1.0 else Vector2.from_angle(global_rotation)
	return _gun_sprite.global_position + dir * GUN_SIZE * 0.5


## The scale that makes a part's sprite about `size` px across.
func carried_scale(texture: Texture2D, size: float) -> float:
	var longest := maxf(texture.get_width(), texture.get_height())
	return size / longest if longest > 0.0 else 1.0


func _carried(sprite: Sprite2D, texture: Texture2D, size: float) -> Sprite2D:
	if sprite != null:
		sprite.queue_free()
	if texture == null or dead:
		return null
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * carried_scale(texture, size)
	sprite.z_index = 1
	_body_layer.add_child(sprite)
	return sprite


# The parts it carries sit in front of and over the head; a loose tendril
# reaches out to each and winds round it. (Mecha sprites face -Y.)
func _hold_parts() -> void:
	var holding := 0
	if _shield_sprite != null:
		_shield_sprite.position = Vector2(body_length * SHIELD_AHEAD, 0.0)
		_shield_sprite.rotation = PI * 0.5
		_wrap(holding, _shield_sprite.global_position)
		holding += 1
	if _gun_sprite != null:
		_gun_sprite.position = Vector2(body_length * GUN_AHEAD, -GUN_LIFT)
		var to_aim := gun_aim - _gun_sprite.global_position
		_gun_sprite.global_rotation = (to_aim.angle() if to_aim.length() > 1.0 else global_rotation) + PI * 0.5
		_wrap(holding, _gun_sprite.global_position)
		holding += 1
	for k in range(holding, _loose.size()):
		if _tails[_loose[k]].pose_weight > 0.0 and _whip_t < 0.0:
			_tails[_loose[k]].pose_weight = 0.0


# The k-th loose tendril: out from its root to `at`, the last WRAP_SHARE of
# it wound round the part.
func _wrap(k: int, at: Vector2) -> void:
	if k >= _loose.size():
		return
	var tail := _tails[_loose[k]]
	var root := _body_to_world(tail.root)
	var reach_end := int((TAIL_POINTS - 1) * (1.0 - WRAP_SHARE))
	var side := Vector2(0.0, -1.0 if k % 2 == 0 else 1.0).rotated(global_rotation) * 30.0
	var ctrl := root.lerp(at, 0.5) + side
	for i in TAIL_POINTS:
		if i <= reach_end:
			var t := float(i) / reach_end
			tail.pose[i] = root.lerp(ctrl, t).lerp(ctrl.lerp(at, t), t)
		else:
			var u := float(i - reach_end) / (TAIL_POINTS - 1 - reach_end)
			tail.pose[i] = at + Vector2.from_angle(u * TAU * 1.2 + _time * 2.0) * WRAP_RADIUS
	tail.pose_weight = HOLD_WEIGHT
	tail.pose_falloff = 0.0
	tail.raise = 0.6


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
	_hold_parts()
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
