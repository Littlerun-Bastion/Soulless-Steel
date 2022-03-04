extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")

onready var pathing_debug = $Debug/Pathing

var debug = true

var health = 100
var speed = 100
var mov_vec = Vector2()
var final_pos = false
var REACH_RANGE = 1
var logic
var all_mechas
var valid_target = false
var engage_distance = 800
var shooting_distance = 200
var random_pos_targeting_distance = 400
var current_state
var move_d_rand = 50
var navigation_node
var path : Array = []
var pos_for_blocked
var old_region
var arena_size_y = Vector2(-2000, +2500)
var arena_size_x = Vector2(-1500, +4000)


func _ready():
	logic = LOGIC.new()
	logic.setup()
	pathing_debug.default_color = Color(randf(),randf(),randf())


func _process(delta):
	if not is_stunned():
		var state = logic.get_current_state()
		check_for_targets()
		
		if has_method("do_"+state):
			call("do_"+state, delta)
		
		logic.updateFiniteLogic(self)
		
	if debug:
		$Debug/StateLabel.text = logic.get_current_state()
		update_pathing_debug_line()


func setup(_all_mechas, _path_stuff):
	mecha_name = "Mecha " + str(randi()%2000)
	all_mechas = _all_mechas
	navigation_node = _path_stuff
	set_max_life(100)
	set_core("core_test")
	set_head("head_test")
	set_legs(false)
	set_arm_weapon("test_weapon1", SIDE.RIGHT)
	set_arm_weapon("test_weapon1", SIDE.LEFT)
	set_shoulder_weapon("test_weapon1", SIDE.RIGHT)
	set_shoulder_weapon("test_weapon1", SIDE.LEFT)
	set_shoulder("shoulder_test1_left", SIDE.LEFT)
	set_shoulder("shoulder_test1_right", SIDE.RIGHT)


func update_pathing_debug_line():
	var local_points = []
	if path:
		local_points.append(position-global_position)
		for point in path:
			local_points.append(point-global_position)
	
	pathing_debug.points = local_points
	pathing_debug.global_rotation = 0

func shoot_weapons():
	try_to_shoot("arm_weapon_left")
	try_to_shoot("arm_weapon_right")
	try_to_shoot("shoulder_weapon_left")
	try_to_shoot("shoulder_weapon_right")


func try_to_shoot(name):
	var node = get_weapon_part(name)
	if node:
		if node.can_reload() == "yes" and node.is_clip_empty() and not node.is_reloading():
			node.reload()
		elif node.can_shoot():
			shoot(name)


func random_valid_pos(navigation : Navigation2D):
	randomize()
	#var polygon = navigation.get_node("NavigationPolygonInstance").navpoly.get_polygon()
	var point = Vector2(rand_range(arena_size_x[0], arena_size_x[1]),\
						rand_range(arena_size_y[0], arena_size_y[1]))
	#while not Geometry.is_point_in_polygon(point, polygon):
	#	print("Not a valid point, getting a new one")
	#	point = Vector2(rand_range(arena_size_x[0], arena_size_x[1]),\
	#					rand_range(arena_size_y[0], arena_size_y[1]))
	return point
	#return navigation.get_closest_point(point)
	

func random_pos_targeting():
	randomize()
	
	var rand_pos = Vector2()
	var angle = rand_range(0, 2.0*PI)
	var direction = Vector2(cos(angle), sin(angle))
	var rand_radius = rand_range(300, 500)
	rand_pos = valid_target.position + direction * rand_radius
	
	return navigation_node.get_closest_point(rand_pos)
	
	## ifs to check where the enemy is and add the proper distance between them
#	if position.x - valid_target.position.x < 0:
#		v_closeness.x = -random_pos_targeting_distance
#	else:
#		v_closeness.x = random_pos_targeting_distance
#
#	if position.x - valid_target.position.y < 0:
#		v_closeness.y = -random_pos_targeting_distance
#	else:
#		v_closeness.y = random_pos_targeting_distance
#
#	rand_pos = Vector2(rand_range(max(move_d_rand, valid_target.position.x-move_d_rand+v_closeness.x),\
#				   (move_d_rand)),\
#				   rand_range(max(move_d_rand, valid_target.position.y-move_d_rand+v_closeness.y),\
#				   (move_d_rand)))
#
#	return navigation_node.get_closest_point(rand_pos)


func do_roaming(delta):
	if not final_pos:
		final_pos = random_valid_pos(navigation_node)
	
	if not path or path.empty():
		path = navigation_node.get_simple_path(global_position, final_pos)
	
	if path.size() > 0:
		apply_rotation_by_point(delta, path[0], false)
		apply_movement(delta, path[0] - position)
		if position.distance_to(path[0]) <= 10:
			path.pop_front()
			if path.size() == 0:
				final_pos = false
				path = []
	
	if not valid_target:
		check_for_targets()

	
	
func do_targeting(delta):
	if not valid_target:
		return
	
	var enemy_area_point
	
	if not final_pos or position.distance_to(final_pos) < 10:
		enemy_area_point = random_pos_targeting()
	
	if not path:
		path = navigation_node.get_simple_path(self.position, enemy_area_point)
	
	if path.size() > 0:
		for place in path:
			apply_rotation_by_point(delta, valid_target.position, false)
			apply_movement(delta,  Vector2(path[0].x-position.x,\
				   			  	   path[0].y-position.y))

	if global_position.distance_to(path[0]) <= 10:
			path.pop_front()
			if path.size() == 0:
				final_pos = random_pos_targeting()
				path = navigation_node.get_simple_path(self.global_position, final_pos)

	shoot_weapons()


func do_idle(_delta):
	pass


func check_for_targets():
	var target_to_return
	
	for target in all_mechas:
		if target != self and position.distance_to(target.position) < engage_distance:
			target_to_return = target
		
	for target in all_mechas:
		if target_to_return:
			if position.distance_to(target_to_return.position) > position.distance_to(target.position):
				target_to_return = target				
		
	if target_to_return:
		valid_target = target_to_return
	else:
		valid_target = false

 
