class_name RibbonTrail
extends Line2D

## A round's smoke as a ribbon: a Line2D whose last point rides on the
## projectile and whose other points are laid down behind it every
## POINT_SPACING px of flight, then age, drift apart and fade out from the
## tail. A Line2D is drawn while any of its points is on screen, so the
## trail hangs in the air when its round leaves the view and the head is
## there for as long as the round is. One mesh of a few dozen vertices
## where the particle trail simulated hundreds of particles a frame.
##
## The texture tiles along the ribbon: a horizontal strip, seamless left
## to right, soft at the top and bottom, grey on alpha (the gradient tints
## and fades it). With none set in the scene a generated noise strip of the
## same shape stands in. `setup(projectile)` reads the round's
## smoke_lifetime (how long a point lasts) as the particle trail did,
## scaled by lifetime_scale. Each trail scene (SmokeTrail, SmokeTrailStable,
## SmokeTrailClean) sets the texture, the width and the knobs below.

## Flight between laid points (px).
@export var point_spacing := 14.0
## How far a laid point wanders a second, at most (px/s); 0 for a trail
## that holds its line.
@export var drift_speed := 12.0
## The tail's width as a multiple of the head's.
@export var tail_width := 1.6
## The round's smoke_lifetime is multiplied by this.
@export var lifetime_scale := 1.0
const MAX_POINTS := 256
const LIFETIME_FALLBACK := 4.0
const PLACEHOLDER_SIZE := Vector2i(256, 32)

var home_projectile = null
var lifetime := LIFETIME_FALLBACK
# Per point, oldest first: seconds since it was laid, and its drift.
var _ages := PackedFloat32Array()
var _drift := PackedVector2Array()
var _gone_for := 0.0

static var _placeholder: ImageTexture = null


func _ready() -> void:
	top_level = true
	texture_mode = Line2D.LINE_TEXTURE_TILE
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = false
	if texture == null:
		texture = placeholder_strip()
	if width_curve == null:
		width_curve = _default_width_curve()
	if gradient == null:
		gradient = _default_gradient()
	clear_points()


func setup(projectile) -> void:
	home_projectile = projectile
	var seconds = projectile.get("smoke_lifetime")
	lifetime = float(seconds) if seconds != null and float(seconds) > 0.0 else LIFETIME_FALLBACK
	lifetime *= lifetime_scale
	_start_at(projectile.global_position)


# The first laid point and the moving head, both at `at`.
func _start_at(at: Vector2) -> void:
	clear_points()
	_ages.clear()
	_drift.clear()
	add_point(at)
	_ages.append(0.0)
	_drift.append(_random_drift())
	add_point(at)
	_ages.append(0.0)
	_drift.append(Vector2.ZERO)


func _process(dt: float) -> void:
	var alive: bool = is_instance_valid(home_projectile) and home_projectile.get("dying") != true
	if get_point_count() == 0:
		if alive:
			_start_at(home_projectile.global_position)
		else:
			queue_free()
		return
	# The laid points age and wander; the oldest go once past the lifetime.
	# The head (the last point) keeps its place on the round.
	var count := get_point_count()
	for i in count - 1:
		_ages[i] += dt
		var drift := _drift[i]
		if drift != Vector2.ZERO:
			set_point_position(i, get_point_position(i) + drift * dt)
	while get_point_count() > 1 and _ages[0] >= lifetime:
		_drop_tail()
	if alive:
		var head: Vector2 = home_projectile.global_position
		var last := get_point_count() - 1
		set_point_position(last, head)
		# Far enough from the last laid point: the head is laid and a new
		# head starts from the round.
		if last >= 1 and head.distance_squared_to(get_point_position(last - 1)) >= point_spacing * point_spacing:
			_drift[last] = _random_drift()
			add_point(head)
			_ages.append(0.0)
			_drift.append(Vector2.ZERO)
			while get_point_count() > MAX_POINTS:
				_drop_tail()
	else:
		# The round is gone: the ribbon fades as a whole while its points
		# run out from the tail, and goes when the last of them has.
		_gone_for += dt
		modulate.a = clampf(1.0 - _gone_for / lifetime, 0.0, 1.0)
		if get_point_count() <= 1 or modulate.a <= 0.0:
			queue_free()


func _drop_tail() -> void:
	remove_point(0)
	_ages.remove_at(0)
	_drift.remove_at(0)


func _random_drift() -> Vector2:
	if drift_speed <= 0.0:
		return Vector2.ZERO
	return Vector2.from_angle(randf() * TAU) * randf_range(0.2, 1.0) * drift_speed


# Wide at the tail, where the smoke has spread, down to the head's width.
func _default_width_curve() -> Curve:
	var curve := Curve.new()
	curve.max_value = maxf(tail_width, 1.0)
	curve.add_point(Vector2(0.0, tail_width))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


# Faded out at the tail, dark grey along the body, bright at the head.
static func _default_gradient() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.9, 1.0])
	g.colors = PackedColorArray([
		Color(0.1, 0.1, 0.1, 0.0), Color(0.15, 0.15, 0.15, 0.45),
		Color(0.6, 0.6, 0.6, 0.6), Color(1.0, 1.0, 1.0, 1.0)])
	return g


## A stand-in for the ribbon strip until art exists: PLACEHOLDER_SIZE,
## seamless along its width, cloudy noise on alpha, soft top and bottom
## edges. Made once and shared.
static func placeholder_strip() -> ImageTexture:
	if _placeholder != null:
		return _placeholder
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var w := PLACEHOLDER_SIZE.x
	var h := PLACEHOLDER_SIZE.y
	var cloud := noise.get_seamless_image(w, h, false, false, 0.1)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		# 1 on the middle row, 0 on the edge rows.
		var across := 1.0 - absf((float(y) + 0.5) / h * 2.0 - 1.0)
		var edge := clampf(across * 1.4, 0.0, 1.0)
		for x in w:
			var puff := cloud.get_pixel(x, y).r
			var alpha := clampf((puff * 1.3 - 0.15) * edge, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_placeholder = ImageTexture.create_from_image(image)
	return _placeholder
