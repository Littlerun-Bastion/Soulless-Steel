extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")


var health = 100
var speed = 100
var mov_vec = Vector2()
var going_to_position = false
var logic
var all_mechas
var valid_target = false


func _ready():
	logic = LOGIC.new()
	if Debug.get_setting("ai_behaviour"):
		logic.setup(Debug.get_setting("ai_behaviour"))
	else:
		logic.setup("default")


func _process(delta):
	if paused or is_stunned():
		return

	logic.update(self)
	logic.run(self, delta)
	
	if Debug.get_setting("enemy_state"):
		$Debug/StateLabel.text = logic.get_current_state()
	else:
		$Debug/StateLabel.text = ""


func setup(arena_ref, is_tutorial):
	arena = arena_ref
	mecha_name = "Mecha " + str(randi()%2000)
	if is_tutorial:
		set_generator("type_2")
		set_chipset("type_2")
		set_core("MSV-L3J-C")
		set_head(PartManager.get_random_part_name("head"))
		set_chassis(PartManager.get_random_part_name("chassis"))
		set_arm_weapon(false, SIDE.RIGHT)
		set_arm_weapon(false, SIDE.LEFT)
		set_shoulder_weapon(false, SIDE.RIGHT)
		set_shoulder_weapon(false, SIDE.LEFT)
		set_shoulders(PartManager.get_random_part_name("shoulders"))
	else:
		set_generator("type_1")
		set_chipset("type_2")
		set_core(PartManager.get_random_part_name("core"))
		set_head(PartManager.get_random_part_name("head"))
		set_chassis(PartManager.get_random_part_name("chassis"))
		set_arm_weapon(PartManager.get_random_part_name("arm_weapon"), SIDE.RIGHT)
		set_arm_weapon(PartManager.get_random_part_name("arm_weapon"), SIDE.LEFT)
		#set_shoulder_weapon(PartManager.get_random_part_name("shoulder_weapon") if randf() > .8 else false, SIDE.RIGHT)
		#set_shoulder_weapon(PartManager.get_random_part_name("shoulder_weapon") if randf() > .9 else false, SIDE.LEFT)
		set_shoulders(PartManager.get_random_part_name("shoulders"))
	
	#For the moment hard set ies' movement type to free
	movement_type = "free"

#Combat functions

func check_for_targets(engage_distance, max_shooting_distance):
	#Check if current target is still in distance
	if valid_target and is_instance_valid(valid_target):
		if position.distance_to(valid_target.position) > max_shooting_distance:
			valid_target = false
	else:
		valid_target = false
	
	#Find new target
	if not valid_target:
		var min_distance = 99999999
		for target in arena.get_mechas():
			var distance = position.distance_to(target.position)
			if target != self and distance <= engage_distance and distance < min_distance:
				valid_target = target
				min_distance = distance


func shoot_weapons():
	try_to_shoot("arm_weapon_left")
	try_to_shoot("arm_weapon_right")
	try_to_shoot("shoulder_weapon_left")
	try_to_shoot("shoulder_weapon_right")


func try_to_shoot(weapon_name):
	var node = get_weapon_part(weapon_name)
	if node:
		if node.can_reload() == "yes" and node.is_clip_empty() and not node.is_reloading():
			node.reload()
		elif node.can_shoot():
			if can_see_target():
				shoot(weapon_name)


func can_see_target():
	if valid_target:
		var space_state = get_world_2d().direct_space_state
		var ray = PhysicsRayQueryParameters2D.create(position, valid_target.position)
		ray.exclude = [self]
		var result = space_state.intersect_ray(ray)
		if result:
			return (result.collider == valid_target)
		return false
	return true


# Navigation

#Assumes enemy has a valid target
func random_targeting_pos(min_dist, max_dist):
	var rand_pos = Vector2()
	var angle = randf_range(0, 2.0*PI)
	var direction = Vector2(cos(angle), sin(angle)).normalized()
	var rand_radius = randf_range(min_dist, max_dist)
	rand_pos = valid_target.position + direction * rand_radius
	
	return rand_pos


func get_navigation_path():
	return NavAgent.get_nav_path()


func navigate_to_target(dt):
	if going_to_position:
		var target = NavAgent.get_next_path_position()
		var pos = get_global_transform().origin
		var dir = (target - pos).normalized()
		apply_movement(dt, dir)
		if valid_target:
			apply_rotation_by_point(dt, valid_target.position, false)
		else:
			apply_rotation_by_point(dt, target, false)


func get_target_navigation_pos():
	if going_to_position:
		return NavAgent.get_final_location()
	return false


func _on_NavigationAgent2D_navigation_finished():
	going_to_position = false


func _on_NavigationAgent2D_velocity_computed(safe_velocity):
	set_velocity(safe_velocity)
	move_and_slide()
	velocity = velocity


func _on_NavigationAgent2D_target_reached():
	going_to_position = false
