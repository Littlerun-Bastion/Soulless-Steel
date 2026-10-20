extends Node2D
class_name AcidGlob

# A Spitter's glob of acid. It's lobbed in an arc to a point on the ground
# (so it flies over cover and can't be dodged by ducking behind a wall, only
# by moving), then splashes: every mecha within splash_radius takes the hit
# through its armour (EntityAttack). Entities aren't hurt by it.
#
# Drawn as a glowing blob rising and falling over its shadow, then a
# spreading splash ring.
#
# Use: AcidGlob.new(), add to the tree, then launch().

signal splashed(glob, mechas_hit)

const COLOR := Color(0.62, 1.0, 0.3)
const ARC_HEIGHT := 160.0
const SPLASH_TIME := 0.5

var source: Node2D = null   # the Spitter: credited with the damage
var arena = null            # anything with get_mechas()
var damage := 1
var pen := 2
var splash_radius := 110.0
var mecha_name := "Spitter" # who's credited if the Spitter died mid-flight

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _flight_time := 1.0
var _t := 0.0
var _height := 0.0
var _landed := false
var _splash_t := 0.0


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


func get_landing_point() -> Vector2:
	return _to


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
	_height = sin(k * PI) * ARC_HEIGHT
	queue_redraw()
	if k >= 1.0:
		_splash()


func _splash() -> void:
	_landed = true
	_height = 0.0
	var attacker: Node2D = source if is_instance_valid(source) and not source.is_dead else self
	var mechas: Array = arena.get_mechas() if arena != null and is_instance_valid(arena) else []
	var hit := EntityAttack.hit_mechas_near(attacker, mechas, global_position, splash_radius, damage, pen)
	AudioManager.play_sfx("miss_impact_light%d" % randi_range(1, 5), global_position)
	splashed.emit(self, hit)


func _draw() -> void:
	if _landed:
		var k := _splash_t / SPLASH_TIME
		var ring := COLOR
		ring.a = 0.7 * (1.0 - k)
		draw_circle(Vector2.ZERO, splash_radius * (0.4 + 0.6 * k), Color(ring, ring.a * 0.4))
		draw_arc(Vector2.ZERO, splash_radius * (0.4 + 0.6 * k), 0.0, TAU, 24, ring, 4.0)
		return
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.35))  # shadow on the ground
	draw_circle(Vector2(0, -_height), 14.0, COLOR)
	draw_circle(Vector2(-4, -_height - 4), 5.0, COLOR.lightened(0.5))
