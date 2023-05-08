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

func _ready():
	set_as_top_level(true)
	clear_points()
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, randf_range((lifetime - min((lifetime*lifetime_range), lifetime)), (lifetime+(lifetime*lifetime_range))))
	tween.tween_callback(self.queue_free)

func setup(data, projectile):
	lifetime = data.trail_lifetime
	lifetime_range = data.trail_lifetime_range
	eccentricity = data.trail_eccentricity
	min_spawn_distance = data.trail_min_spawn_distance
	width = data.trail_width
	home_projectile = projectile
	add_point(home_projectile.global_position)

func _process(dt):
	if tick > tick_speed:
		tick = 0
		if is_instance_valid(home_projectile):
			add_new_point(home_projectile.global_position)
			for point in range(get_point_count()):
				point_age[point] += 5*dt
				var rand_vector := Vector2(randf_range(-ecc_speed, ecc_speed), randf_range(-ecc_speed, ecc_speed))
				points[point] += rand_vector * eccentricity * point_age[point]
	else:
		tick += dt

func add_new_point(point_pos:Vector2, at_pos := -1):
	if get_point_count() > 0 and point_pos.distance_to(points[get_point_count()-1]) < min_spawn_distance:
		return
	
	point_age.append(0.0)
	add_new_point(point_pos, at_pos) #TODO: CHECK IF THIS IS RIGHT
