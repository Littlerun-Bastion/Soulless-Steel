extends Line2D

var lifetime := 1
var lifetime_range := 0.25
var eccentricity := 15.0
var tick_speed := 0.02
var tick := 0.0
var ecc_speed := 0.1
var home_projectile 
var point_age := [0.0]
var min_spawn_distance := 20

onready var tween := $Decay

func _ready():
	set_as_toplevel(true)
	tween.interpolate_property(self, "modulate:a", 1.0, 0.0, rand_range((lifetime - (lifetime*lifetime_range)), (lifetime+(lifetime*lifetime_range))), Tween.TRANS_CIRC, Tween.EASE_OUT)
	clear_points()
	tween.start()

func setup(trail_lifetime, trail_lifetime_range, trail_eccentricity, trail_min_spawn_distance, trail_width, target):
	lifetime = trail_lifetime
	lifetime_range = trail_lifetime_range
	eccentricity = trail_eccentricity
	min_spawn_distance = trail_min_spawn_distance
	self.width = trail_width
	home_projectile = target
	add_point(home_projectile.global_position)

func _process(dt):
	if tick > tick_speed:
		tick = 0
		if is_instance_valid(home_projectile):
			add_point(home_projectile.global_position)
			for point in range(get_point_count()):
				point_age[point] += 5*dt
				var rand_vector := Vector2(rand_range(-ecc_speed, ecc_speed), rand_range(-ecc_speed, ecc_speed))
				points[point] += rand_vector * eccentricity * point_age[point]
	else:
		tick += dt

func add_point(point_pos:Vector2, at_pos := -1):
	if get_point_count() > 0 and point_pos.distance_to(points[get_point_count()-1]) < min_spawn_distance:
		return
	
	point_age.append(0.0)
	.add_point(point_pos, at_pos)

func _on_Tween_tween_all_completed():
	queue_free()
