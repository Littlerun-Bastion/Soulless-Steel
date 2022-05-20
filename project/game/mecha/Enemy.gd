extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")

onready var pathing_debug = $Debug/Pathing

var debug = false

var health = 100
var speed = 100
var mov_vec = Vector2()
var final_pos = false
var REACH_RANGE = 1
var logic
var all_mechas
var valid_target = false
var engage_distance = 2000
var shooting_distance = 3500
var random_pos_targeting_distance = 700
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
		
		if has_method("do_"+state):
			call("do_"+state, delta)
		
		logic.updateFiniteLogic(self)
		
	if debug:
		$Debug/StateLabel.text = logic.get_current_state()
		update_pathing_debug_line()
	else:
		$Debug/StateLabel.text = ""


func setup(_all_mechas, _path_stuff):
	mecha_name = "Mecha " + str(randi()%2000)
	all_mechas = _all_mechas
	navigation_node = _path_stuff
	if get_tree().get_current_scene().get_name() == "testingGrounds":
		set_max_life(100)
		set_max_shield(50)
		set_core(PartManager.get_random_part_name("core"))
		set_head(PartManager.get_random_part_name("head"))
		set_legs(PartManager.get_random_part_name("legs"))
		scale = Vector2(0.5, 0.5)
	else:
		set_max_life(150)
		set_max_shield(100)
		set_core(PartManager.get_random_part_name("core"))
		set_head(PartManager.get_random_part_name("head"))
		set_legs(PartManager.get_random_part_name("legs"))
		set_arm_weapon(PartManager.get_random_part_name("arm_weapon"), SIDE.RIGHT)
		set_arm_weapon(PartManager.get_random_part_name("arm_weapon") if randf() > .5 else false, SIDE.LEFT)
		set_shoulder_weapon(PartManager.get_random_part_name("shoulder_weapon") if randf() > .8 else false, SIDE.RIGHT)
		set_shoulder_weapon(PartManager.get_random_part_name("shoulder_weapon") if randf() > .9 else false, SIDE.LEFT)
		set_shoulder(PartManager.get_random_part_name("shoulder_left"), SIDE.LEFT)
		set_shoulder(PartManager.get_random_part_name("shoulder_right"), SIDE.RIGHT)



func update_pathing_debug_line():
	var local_points = []
	if path:
		local_points.append(position-global_position)
		for point in path:
			local_points.append(point-global_position)
	
	pathing_debug.points = local_points
	pathing_debug.global_rotation = 0


#Auxiliary functions

func check_for_targets():
	#Check if current target is still in distance
	if valid_target and is_instance_valid(valid_target):
		if position.distance_to(valid_target.position) > shooting_distance:
			valid_target = false
	else:
		valid_target = false
	
	#Find new target
	if not valid_target:
		var min_distance = 99999999
		for target in all_mechas:
			var distance = position.distance_to(target.position)
			if target != self and distance <= engage_distance and distance < min_distance:
				valid_target = target
				min_distance = distance


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


func random_valid_pos():
	randomize()
	var point = Vector2(rand_range(arena_size_x[0], arena_size_x[1]),\
						rand_range(arena_size_y[0], arena_size_y[1]))

	return point


func random_pos_targeting():
	randomize()
	
	var rand_pos = Vector2()
	var angle = rand_range(0, 2.0*PI)
	var direction = Vector2(cos(angle), sin(angle))
	var rand_radius = rand_range(400, 800)
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


func path_movement(delta, target_position, look_pos = false):
	if not path or path.empty():
		path = navigation_node.get_simple_path(global_position, target_position)
	
	if path.size() > 0:
		if not look_pos:
			look_pos = path[0]
		apply_rotation_by_point(delta, look_pos, false)
		apply_movement(delta, path[0] - position)
		if position.distance_to(path[0]) <= 10:
			path.pop_front()
			if path.size() == 0:
				final_pos = false
				path = []


# State methods

func do_roaming(delta):
	if not final_pos:
		final_pos = random_valid_pos()
	
	path_movement(delta, final_pos)
	
	check_for_targets()

	
	
func do_targeting(delta):
	check_for_targets()
	if not valid_target:
		return
	
	if not final_pos:
		final_pos = random_pos_targeting()
	
	path_movement(delta, final_pos, valid_target.position)
	shoot_weapons()


func do_idle(_delta):
	pass
 
