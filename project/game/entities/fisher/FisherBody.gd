extends SandBody
class_name FisherBody

enum Stage { DORMANT, ALERT, ACTIVE }
enum HarpoonMode { NONE, FLYING, LATCHED, REELING }
enum LeapPhase { NONE, CROUCH, AIR, LAND }

const ANTENNA_ANGLES := [-38.0, -13.0, 13.0, 38.0]
const ANTENNAE := 4
## Index of the harpoon tendril in _tails, after the antennae.
const HARPOON := 4

@export_group("Fisher")
@export var shell_texture: Texture2D
@export var shell_radius := 60.0
## the distance at which the Fisher's tether breaks
@export var harpoon_length := 1200.0
@export var recoil_kick := 12.0
@export var recoil_time := 0.35
@export var leap_height := 90.0

var stage := Stage.DORMANT:
	set(value):
		if value == stage:
			return
		stage = value
		_stage_t = 0.0
		# Set before _ready() (straight after instancing), there are no legs
		# to stagger yet; they come out together.
		if value == Stage.ACTIVE and _leg_delay.size() == _limbs.size():
			# The legs come out one after another, in a random order.
			var order := range(_limbs.size())
			order.shuffle()
			for k in order.size():
				_leg_delay[order[k]] = 0.15 + k * 0.07
var focus_point := Vector2.ZERO
var has_focus := false
var harpoon_mode := HarpoonMode.NONE
var harpoon_tip := Vector2.ZERO
var drain_phase := 0.0

var _shell: Sprite2D
var _shell_scale := 1.0
var _stage_t := 0.0
var _leg_delay: Array[float] = []
var _antenna_base: Array[float] = []
var _antenna_aim: Array[float] = []
var _antenna_goal: Array[float] = []
var _antenna_timer: Array[float] = []
var _recoil_t := -1.0
var _recoil_dir := Vector2.RIGHT
var _leap_phase := LeapPhase.NONE
var _leap_crouch := 0.0


func _init() -> void:
	body_shape = BodyShape.ROUND
	body_length = 120.0
	body_width = 120.0
	body_strands = 0
	has_head = false
	limb_length = 160.0
	limb_width = 13.0
	rest_reach = 0.78
	hip_height = 0.36
	knee_tilt = 35.0
	stride = 0.6
	duty_walk = 0.72
	duty_run = 0.6
	max_airborne = 3
	waddle = 1.5
	idle_flow = 0.3


func _leg_layout() -> Array:
	var legs := []
	for i in 3:
		var angle := lerpf(140.0, 40.0, i / 2.0)
		var a := deg_to_rad(angle)
		for side in [-1.0, 1.0]:
			var tripod := 0.5 * ((i + (0 if side < 0.0 else 1)) % 2)
			legs.append({"x": cos(a) * 0.1, "y": sin(a) * 0.1 * side, "root": Vector2.ZERO,
					"side": side, "angle": angle, "walk": tripod + (2 - i) * 0.04, "run": tripod})
	return legs


func _tail_layout() -> Array:
	var tails := []
	for k in ANTENNAE:
		var angle: float = ANTENNA_ANGLES[k]
		var a := deg_to_rad(angle)
		tails.append({"x": cos(a) * 0.4, "y": sin(a) * 0.4, "length": randf_range(70.0, 95.0),
				"width": 6.0, "angle": angle, "sway": 0.1, "waves": 0.5, "speed": 3.0,
				"stiffness": 0.55, "damping": 0.75, "shed": false})
	tails.append({"x": 0.0, "y": 0.0, "length": harpoon_length, "width": 11.0, "angle": 0.0,
			"sway": 0.0, "stiffness": 0.04, "damping": 0.6, "shed": true})
	return tails


func _ready() -> void:
	super()
	for limb in _limbs:
		limb.extend = 0.0
		_leg_delay.append(0.0)
	for tail in _tails:
		tail.extend = 0.0
	for k in ANTENNAE:
		_antenna_base.append(_tails[k].rest_angle)
		_antenna_aim.append(0.0)
		_antenna_goal.append(0.0)
		_antenna_timer.append(0.0)
	body_lift = 0.0
	_grains.emitting = false
	_build_shell()


# The shell replaces the body; nothing is drawn underneath it.
func _draw() -> void:
	pass


## How far out the legs are, 0..1. The Entity waits for 1 before moving.
func legs_out() -> float:
	var total := 0.0
	for limb in _limbs:
		total += limb.extend
	return total / maxi(_limbs.size(), 1)


## Where the harpoon tendril leaves the shell (world).
func harpoon_root() -> Vector2:
	return _body_to_world(_tails[HARPOON].root)


## Firing kicks the shell back against the shot (direction: the way it fired).
func recoil(direction: Vector2) -> void:
	_recoil_t = 0.0
	_recoil_dir = direction.normalized() if direction.length() > 0.01 else Vector2.from_angle(global_rotation)
	kick = maxf(kick, 0.4)


## The leap pose, u 0..1 through the phase, direction the way it's going.
func set_leap(phase: LeapPhase, u: float, direction: Vector2) -> void:
	var entering := phase != _leap_phase
	_leap_phase = phase
	if phase == LeapPhase.CROUCH:
		_leap_crouch = sin(u * PI * 0.5)
	elif phase == LeapPhase.AIR:
		if entering:
			kick = maxf(kick, 0.6)
		air_height = 4.0 * leap_height * u * (1.0 - u)
		airborne = true
		_leap_crouch = 1.0 - smoothstep(0.0, 0.25, u)
		leg_tuck = smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.55, 0.9, u)) * 0.8
		foot_lead = direction.normalized() * limb_length * 0.3 * smoothstep(0.5, 0.9, u)
	elif phase == LeapPhase.LAND:
		if entering:
			kick = 1.0
		_end_air()
		_leap_crouch = sin((1.0 - u) * PI * 0.5) * 0.7
	else:
		_end_air()
		_leap_crouch = 0.0


func _end_air() -> void:
	airborne = false
	air_height = 0.0
	leg_tuck = 0.0
	foot_lead = Vector2.ZERO


func die() -> void:
	if dead:
		return
	super()
	var world := _world_parent()
	if world != null:
		_shell.reparent(world)
	_shell.modulate = Color(0.85, 0.85, 0.85)
	_shell.material = null
	_shell.z_index = -1


func _animate(delta: float) -> void:
	_stage_t += delta
	kick = move_toward(kick, 0.0, delta * 3.0)
	_update_legs(delta)
	_update_antennae(delta)
	_draw_harpoon()
	_grains.emitting = stage == Stage.ACTIVE
	(_shell.material as ShaderMaterial).set_shader_parameter("flash", flash)
	_shell.scale = Vector2.ONE * _shell_scale * (1.0 + 0.04 * body_lift + 0.25 * air_height / leap_height)
	_update_recoil(delta)


func _update_legs(delta: float) -> void:
	var out := stage == Stage.ACTIVE
	for i in _limbs.size():
		var limb := _limbs[i]
		if out:
			if _stage_t > _leg_delay[i]:
				limb.extend = move_toward(limb.extend, 1.0, delta / 0.32)
		else:
			limb.extend = move_toward(limb.extend, 0.0, delta / 0.28)
	body_lift = legs_out() * (1.0 - 0.6 * maxf(_leap_crouch, _recoil_dip()))


func _update_antennae(delta: float) -> void:
	var legs_in := legs_out() < 0.1
	for k in ANTENNAE:
		var tail := _tails[k]
		if stage != Stage.DORMANT:
			if _stage_t > k * 0.12 or stage == Stage.ACTIVE:
				tail.extend = move_toward(tail.extend, 1.0, delta * 1.6)
		elif legs_in:
			tail.extend = move_toward(tail.extend, 0.0, delta * 3.0)
		_antenna_timer[k] -= delta
		if _antenna_timer[k] <= 0.0:
			var spread := 0.75 if stage == Stage.ALERT else 0.35
			_antenna_goal[k] = randf_range(-spread, spread)
			_antenna_timer[k] = randf_range(0.35, 0.9) if stage == Stage.ALERT else randf_range(0.6, 1.4)
		_antenna_aim[k] = lerp_angle(_antenna_aim[k], _antenna_goal[k], clampf(9.0 * delta, 0.0, 1.0))
		var lean := 0.0
		if has_focus and stage == Stage.ACTIVE:
			var to_focus := angle_difference(global_rotation + _antenna_base[k], (focus_point - global_position).angle())
			lean = clampf(to_focus, -0.6, 0.6) * 0.6
		tail.rest_angle = _antenna_base[k] + _antenna_aim[k] + lean

func _draw_harpoon() -> void:
	var tail := _tails[HARPOON]
	tail.pulse_pos = -1.0
	var root := harpoon_root()
	var to_tip := harpoon_tip - root
	var length := to_tip.length() if harpoon_mode != HarpoonMode.NONE else 0.0
	tail.extend = minf(length / harpoon_length, 1.0)
	tail.pose_weight = 0.0 if harpoon_mode == HarpoonMode.NONE else 1.0
	tail.raise = 0.25
	if harpoon_mode == HarpoonMode.NONE or length < 1.0:
		return
	if harpoon_mode == HarpoonMode.LATCHED:
		tail.pulse_pos = 1.0 - fmod(drain_phase, 1.0)
		tail.pulse_strength = 0.75
	var dir := to_tip / length
	var perp := dir.orthogonal()
	for i in TAIL_POINTS:
		var t := float(i) / (TAIL_POINTS - 1)
		var wob := 0.0
		if harpoon_mode == HarpoonMode.FLYING:
			wob = sin(t * 3.0 * TAU - _time * 40.0) * 10.0
		elif harpoon_mode == HarpoonMode.LATCHED:
			wob = sin(t * 2.0 * TAU - _time * 12.0) * 3.0
		else:
			wob = sin(t * 4.0 * TAU + _time * 30.0) * 8.0
		tail.pose[i] = root + to_tip * t + perp * wob * sin(t * PI)


func _recoil_left() -> float:
	return 1.0 - _recoil_t / recoil_time if _recoil_t >= 0.0 else 0.0


func _recoil_dip() -> float:
	var r := _recoil_left()
	return 0.5 * r * r


func _update_recoil(delta: float) -> void:
	if _recoil_t < 0.0:
		_shell.position = Vector2.ZERO
		_shell.rotation = 0.0
		return
	_recoil_t += delta
	var r := _recoil_left()
	if r <= 0.0:
		_recoil_t = -1.0
		return
	var back := (-_recoil_dir).rotated(-global_rotation)  # in the Entity's own space
	var shake := Vector2(sin(_recoil_t * 95.0), cos(_recoil_t * 77.0)) * 3.5 * r
	_shell.position = back * recoil_kick * r * r + shake
	_shell.rotation = sin(_recoil_t * 60.0) * 0.06 * r


func _build_shell() -> void:
	_shell = Sprite2D.new()
	_shell.texture = shell_texture if shell_texture else _placeholder_shell()
	_shell_scale = shell_radius * 2.0 / _shell.texture.get_width()
	_shell.scale = Vector2.ONE * _shell_scale
	var shader := Shader.new()
	shader.code = HEAD_FLASH_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_shell.material = mat
	_body_layer.add_child(_shell)  # over the legs and tendrils


# placeholder draw function for now, lowkey it actually kinda rocks! (haha)
func _placeholder_shell() -> ImageTexture:
	var radius := int(shell_radius)
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var bumps := FastNoiseLite.new()
	bumps.seed = randi()
	bumps.frequency = 0.09
	bumps.fractal_octaves = 3
	var cracks := FastNoiseLite.new()
	cracks.seed = randi()
	cracks.frequency = 0.035
	var centre := Vector2(size, size) * 0.5
	var light := Vector3(-Vector2.from_angle(deg_to_rad(light_angle)).x,
			-Vector2.from_angle(deg_to_rad(light_angle)).y, 0.9).normalized()
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - centre
			var a := p.angle()
			var edge := radius * (0.9 + 0.05 * sin(a * 3.0 + 1.0) + 0.03 * sin(a * 7.0 + 2.0)
					+ 0.04 * bumps.get_noise_2d(cos(a) * 30.0, sin(a) * 30.0))
			var d := p.length()
			if d > edge:
				continue
			var u := d / edge
			var normal := Vector3(p.x / edge, p.y / edge, sqrt(maxf(1.0 - u * u, 0.0)) * 1.4).normalized()
			var shade := 0.17 + 0.22 * clampf(normal.dot(light), 0.0, 1.0) + 0.06 * bumps.get_noise_2d(x, y)
			if absf(cracks.get_noise_2d(x, y)) < 0.035:
				shade *= 0.55  # cracks
			shade *= lerpf(1.0, 0.75, smoothstep(0.85, 1.0, u))  # darker rim
			img.set_pixel(x, y, Color(shade, shade, shade, clampf(edge - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
