extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")

onready var pathing_debug = $Debug/Pathing

var debug = true

var health = 100
var speed = 100
var mov_vec = Vector2()
var going_to_position = false
var REACH_RANGE = 1
var logic
var all_mechas
var valid_target = false
var engage_distance = 2000
var shooting_distance = 3500
var random_pos_targeting_distance = 700
var current_state
var move_d_rand = 50
var pos_for_blocked
var old_region
var arena_size_y = Vector2(-2000, +2500)
var arena_size_x = Vector2(-1500, +4000)


func _ready():
	logic = LOGIC.new()
	logic.setup()
	pathing_debug.default_color = Color(randf(),randf(),randf())


func _process(delta):
	if paused or is_stunned():
		return

	var state = logic.get_current_state()
	if has_method("do_"+state):
		call("do_"+state, delta)
	logic.updateFiniteLogic(self)
	
	if going_to_position:
		var dir = NavAgent.get_next_location()
		apply_movement(delta, dir)
		if NavAgent.is_target_reached():
			going_to_position = false
			print("reached")
	
	if debug:
		$Debug/StateLabel.text = logic.get_current_state()
		update_pathing_debug_line()
	else:
		$Debug/StateLabel.text = ""


func setup(_all_mechas, is_tutorial):
	mecha_name = "Mecha " + str(randi()%2000)
	all_mechas = _all_mechas
	if is_tutorial:
		set_generator("type_2")
		set_core(PartManager.get_random_part_name("core"))
		set_head(PartManager.get_random_part_name("head"))
		set_leg(PartManager.get_random_part_name("leg_single"), SIDE.SINGLE)
		set_arm_weapon(false, SIDE.RIGHT)
		set_arm_weapon(false, SIDE.LEFT)
		set_shoulder_weapon(false, SIDE.RIGHT)
		set_shoulder_weapon(false, SIDE.LEFT)
		set_shoulder(PartManager.get_random_part_name("shoulder_left"), SIDE.LEFT)
		set_shoulder(PartManager.get_random_part_name("shoulder_right"), SIDE.RIGHT)
		scale = Vector2(0.5, 0.5)
	else:
		set_generator("type_1")
		set_core(PartManager.get_random_part_name("core"))
		set_head(PartManager.get_random_part_name("head"))
		set_leg(PartManager.get_random_part_name("leg_left"), SIDE.LEFT)
		set_leg(PartManager.get_random_part_name("leg_right"), SIDE.RIGHT)
		set_arm_weapon(PartManager.get_random_part_name("arm_weapon"), SIDE.RIGHT)
		set_arm_weapon(PartManager.get_random_part_name("arm_weapon") if randf() > .5 else false, SIDE.LEFT)
		set_shoulder_weapon(PartManager.get_random_part_name("shoulder_weapon") if randf() > .8 else false, SIDE.RIGHT)
		set_shoulder_weapon(PartManager.get_random_part_name("shoulder_weapon") if randf() > .9 else false, SIDE.LEFT)
		set_shoulder(PartManager.get_random_part_name("shoulder_left"), SIDE.LEFT)
		set_shoulder(PartManager.get_random_part_name("shoulder_right"), SIDE.RIGHT)
	
	#For the moment hard set enemies' movement type to free
	movement_type = "free"


func update_pathing_debug_line():
	var local_points = []
	var path = NavAgent.get_nav_path()
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


func random_targeting_pos():
	randomize()
	
	var rand_pos = Vector2()
	var angle = rand_range(0, 2.0*PI)
	var direction = Vector2(cos(angle), sin(angle)).normalized()
	var rand_radius = rand_range(400, 800)
	rand_pos = valid_target.position + direction * rand_radius
	
	return rand_pos




# State methods

func do_roaming(_delta):
	if not going_to_position:
		going_to_position = true
		NavAgent.set_target_location(random_valid_pos())
	
	check_for_targets()


func do_targeting(_delta):
	check_for_targets()
	if not valid_target:
		return
	
	if not going_to_position:
		going_to_position = true
		NavAgent.set_target_location(random_targeting_pos())
	
	shoot_weapons()


func do_idle(_delta):
	pass
 
