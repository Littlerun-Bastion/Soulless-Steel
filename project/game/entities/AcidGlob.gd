extends Node2D
class_name AcidGlob

# A Spitter's glob of acid. It's lobbed in an arc to a point on the ground
# (so it flies over cover and can't be dodged by ducking behind a wall, only
# by moving), then splashes: every mecha within splash_radius takes the hit
# through its armour (EntityAttack). Entities aren't hurt by it.
#
# Drawn as a drop of fluid (the blood droplet sprite, tinted `color`) with
# two smaller drops trailing it, turned along its flight as it rises and
# falls over its shadow. On landing it bursts: a splat that spreads and fades,
# and a spray of droplets (a one-shot CPUParticles2D) thrown out all round,
# each pointing the way it flies and slowing to a stop.
#
# Use: AcidGlob.new(), add to the tree, then launch().

signal splashed(glob, mechas_hit)

const COLOR := Color(0.62, 1.0, 0.3)
const ARC_HEIGHT := 160.0
## The drop: 6 x 27 px, its round head at the top (-Y).
const DROPLET := preload("res://assets/images/fx/blood_particle1.png")
## A round splat with lobes, for where it lands (the pool BloodStains
## uses), drawn smoothed: it's scaled down a long way.
const SPLAT := preload("res://assets/images/fx/blood_pool1.png")
## How big the flying drop is drawn, and the two drops behind it: how far
## back (px), how big and how opaque each is.
const DROP_SCALE := 2.0
const TRAIL := [Vector3(22.0, 1.3, 0.7), Vector3(40.0, 0.9, 0.45)]
const SHADOW_RADIUS := 10.0
## The splash. Placeholders.
const SPLASH_TIME := 0.55
const SPLASH_DROPS := 18
const SPLASH_SPEED := Vector2(160.0, 460.0)   # px/s, at a splash_radius of 60
const SPLASH_DAMPING := Vector2(700.0, 1100.0)
const SPLASH_DROP_SCALE := Vector2(0.7, 1.6)
const SPLASH_LIFETIME := 0.45
## The splat grows from this fraction of splash_radius to all of it.
const SPLAT_START := 0.3
const REFERENCE_RADIUS := 60.0

static var _splash_drop: Texture2D = null

var source: Node2D = null   # the Spitter: credited with the damage
var arena = null            # anything with get_mechas()
var damage := 1
var pen := 2
var splash_radius := 110.0
var mecha_name := "Spitter" # who's credited if the Spitter died mid-flight
## Its look: the colour, and how high the arc goes (a lower arc reads as a
## shot rather than a lob).
var color := COLOR
var arc_height := ARC_HEIGHT

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _flight_time := 1.0
var _t := 0.0
var _height := 0.0
var _landed := false
var _splash_t := 0.0
var _heading := 0.0         # the drop's on-screen direction of travel
var _spray: CPUParticles2D = null


func launch(spitter: Node2D, arena_ref, from: Vector2, to: Vector2, flight_time: float) -> void:
	source = spitter
	arena = arena_ref
	if is_instance_valid(spitter):
		mecha_name = spitter.mecha_name
	_from = from
	_to = to
	_flight_time = maxf(flight_time, 0.05)
	global_position = from
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_heading = _travel(0.0).angle()


func get_landing_point() -> Vector2:
	return _to


## The splash's droplets (null until it lands).
func get_splash() -> CPUParticles2D:
	return _spray


func _physics_process(dt: float) -> void:
	if _landed:
		_splash_t += dt
		queue_redraw()
		if _splash_t >= SPLASH_TIME:
			queue_free()
		return
	_t += dt
	var k := clampf(_t / _flight_time, 0.0, 1.0)
	global_position = _from.lerp(_to, k)
	_height = sin(k * PI) * arc_height
	_heading = _travel(k).angle()
	queue_redraw()
	if k >= 1.0:
		_splash()


# Its on-screen velocity at k through the flight: along the ground, plus the
# arc's climb or fall (up the screen is -Y).
func _travel(k: float) -> Vector2:
	var along := (_to - _from) / _flight_time
	var climb := cos(k * PI) * PI * arc_height / _flight_time
	var v := along + Vector2(0.0, -climb)
	return v if v.length() > 1.0 else Vector2.DOWN


func _splash() -> void:
	_landed = true
	_height = 0.0
	_burst()
	var attacker: Node2D = source if is_instance_valid(source) and not source.is_dead else self
	var mechas: Array = arena.get_mechas() if arena != null and is_instance_valid(arena) else []
	var hit := EntityAttack.hit_mechas_near(attacker, mechas, global_position, splash_radius, damage, pen)
	AudioManager.play_sfx("miss_impact_light%d" % randi_range(1, 5), global_position)
	splashed.emit(self, hit)


# Droplets thrown out all round, each pointing the way it flies.
func _burst() -> void:
	var reach := splash_radius / REFERENCE_RADIUS
	_spray = CPUParticles2D.new()
	_spray.texture = _drop_tail_first()
	_spray.amount = SPLASH_DROPS
	_spray.one_shot = true
	_spray.explosiveness = 1.0
	_spray.lifetime = SPLASH_LIFETIME
	_spray.local_coords = false
	_spray.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_spray.emission_sphere_radius = splash_radius * 0.15
	_spray.direction = Vector2.RIGHT
	_spray.spread = 180.0
	_spray.gravity = Vector2.ZERO
	_spray.initial_velocity_min = SPLASH_SPEED.x * reach
	_spray.initial_velocity_max = SPLASH_SPEED.y * reach
	_spray.damping_min = SPLASH_DAMPING.x * reach
	_spray.damping_max = SPLASH_DAMPING.y * reach
	_spray.particle_flag_align_y = true
	_spray.scale_amount_min = SPLASH_DROP_SCALE.x
	_spray.scale_amount_max = SPLASH_DROP_SCALE.y
	_spray.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	_spray.color_ramp = fade
	add_child(_spray)
	_spray.emitting = true


# CPUParticles2D's align_y points a particle's +Y along its velocity, so the
# drop is flipped to lead with its round head.
static func _drop_tail_first() -> Texture2D:
	if _splash_drop == null:
		var image := DROPLET.get_image()
		if image == null:
			return DROPLET
		if image.is_compressed():
			image.decompress()
		image.flip_y()
		_splash_drop = ImageTexture.create_from_image(image)
	return _splash_drop


func _draw() -> void:
	if _landed:
		var k := clampf(_splash_t / SPLASH_TIME, 0.0, 1.0)
		var size := splash_radius * 2.0 * lerpf(SPLAT_START, 1.0, 1.0 - pow(1.0 - k, 3.0))
		draw_texture_rect(SPLAT, Rect2(Vector2(-size, -size * 0.8) * 0.5, Vector2(size, size * 0.8)),
				false, Color(color, 0.8 * (1.0 - k)))
		return
	draw_circle(Vector2.ZERO, SHADOW_RADIUS, Color(0, 0, 0, 0.35))  # shadow on the ground
	var head := Vector2(0.0, -_height)
	var back := Vector2.from_angle(_heading + PI)
	for drop: Vector3 in TRAIL:
		_draw_drop(head + back * drop.x, drop.y, drop.z)
	_draw_drop(head, DROP_SCALE, 1.0)


func _draw_drop(at: Vector2, drop_scale: float, alpha: float) -> void:
	draw_set_transform(at, _heading + PI * 0.5, Vector2.ONE * drop_scale)
	var size := DROPLET.get_size()
	draw_texture(DROPLET, Vector2(-size.x * 0.5, -size.y * 0.3), Color(color, alpha))
	draw_set_transform(Vector2.ZERO)
