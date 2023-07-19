extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")
const SOUND_LIFETIME = 25
const BODY_LIFETIME = 35

@export var look_ahead_range = 500
@export var num_rays = 16

var ray_directions = []
var interest = []
var danger = []
var debug_lines = []
var wait_for_map_sync = .1

var chosen_dir = Vector2()

var health = 100
var speed = 100
var mov_vec = Vector2()
var going_to_position = false
var logic
var all_mechas
var engage_distance = 2000 #How far to see other mechas
var senses = {
	"sounds": [],
	"bodies": [],
}
var valid_target = false
var is_locking = false
var under_fire_timer = 0.0


func _ready():
	super()
	
	steering_setup()
	
	logic = LOGIC.new()
	if Debug.get_setting("ai_behaviour"):
		logic.setup(Debug.get_setting("ai_behaviour"))
	else:
		logic.setup("default")
		
	if Debug.get_setting("draw_debug_lines"):
		$NavigationAgent2D.debug_enabled = true
	else:
		$NavigationAgent2D.debug_enabled = false
	


func _physics_process(dt):
	if paused:
		return
	
	if is_dead:
		return
	
	super(dt)
	
	if is_stunned():
		return
	
	update_senses(dt)
	
	wait_for_map_sync = max(wait_for_map_sync - dt, 0)
	if not wait_for_map_sync and not is_dead:
		logic.update(self)
		logic.run(self, dt)
	
	if is_locking:
		update_enemy_locking(dt, valid_target)
		
	if Debug.get_setting("enemy_state"):
		$Debug/StateLabel.text = logic.get_current_state()
	else:
		$Debug/StateLabel.text = ""
	
	under_fire_timer = max(under_fire_timer - dt, 0)


func _draw():
	if Debug.get_setting("draw_debug_lines"):
		draw_line(Vector2.ZERO, chosen_dir.rotated(-global_rotation)* 500, Color.WHITE, 5)
		for i in debug_lines:
			if i:
				draw_line(Vector2.ZERO, i.rotated(-global_rotation) * look_ahead_range, Color.DARK_GRAY, 2.0)


func setup(arena_ref, is_tutorial, design_data, _name):
	arena = arena_ref
	if _name and typeof(_name) == TYPE_STRING:
		mecha_name = _name
	else:
		mecha_name = "Mecha " + str(randi()%2000)
	if is_tutorial:
		set_generator(PartManager.get_random_part_name("generator"))
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
		print(mecha_name  + " spawned in.")


#AI METHODS

func heard_sound(sound_data):
	senses.sounds.append({
		"volume_type": sound_data.volume_type,
		"type": sound_data.type,
		"position": sound_data.position,
		"lifetime": SOUND_LIFETIME,
		"source": sound_data.source,
	})


func update_senses(dt):
	#Tick down sounds
	var to_remove = []
	for sound in senses.sounds:
		sound.lifetime -= dt
		if sound.lifetime <= 0:
			to_remove.append(sound)
	for sound in to_remove:
		senses.sounds.erase(sound)
	
	#Tick down unseen bodies
	to_remove = []
	for data in senses.bodies:
		if data.is_seen:
			data.is_seen = false
			data.lifetime = BODY_LIFETIME
		else:
			data.lifetime -= dt
			if data.lifetime <= 0:
				to_remove.append(data)
	for data in to_remove:
		senses.bodies.erase(data)
	
	#Check for nearby bodies
	for target in arena.get_mechas():
		var distance = position.distance_to(target.position)
		if target != self and distance <= engage_distance:
			var found = false
			for data in senses.bodies:
				if data.body == target:
					data.is_seen = true
					data.last_position = target.global_position
					found = true
					break
			if not found:
				senses.bodies.append({
					"body": target,
					"last_position": target.global_position,
					"is_seen": true,
					"lifetime": BODY_LIFETIME,
				})
	

func get_most_recent_loud_noise():
	return get_recent_noise("volume_type", "loud")


func get_most_recent_quiet_noise():
	return get_recent_noise("volume_type", "quiet")


func get_recent_noise(var_type, var_value):
	var recent_noise = false
	var biggest_lifetime = -99999999
	for sound in senses.sounds:
		if sound[var_type] == var_value and sound.lifetime > biggest_lifetime:
			recent_noise = sound
			biggest_lifetime = sound.lifetime
	
	return recent_noise

#COMBAT METHODS

func check_for_targets(eng_distance, max_shooting_distance):
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
			if target != self and distance <= eng_distance and distance < min_distance:
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


func navigate_to_target(dt,direction:=0.0, wander := 0.0):
	#Forward when direction = 0, Backwards when direction = 1, 
	#Clockwise when direction = -0.5, Anticlockwise when direction = 0.5
	if going_to_position:
		var target = NavAgent.get_next_path_position()
		var pos = get_global_transform().origin
		var dir = (target - pos).normalized()
		set_interest(dir.rotated(PI * direction), wander)
		set_danger()
		choose_direction()
		apply_movement(dt, chosen_dir)
		if valid_target and is_instance_valid(valid_target):
			apply_rotation_by_point(dt, valid_target.position, false)
		else:
			apply_rotation_by_point(dt, target, false)
			


func get_target_navigation_pos():
	if going_to_position:
		return NavAgent.get_final_location()
	return false


func _on_NavigationAgent2D_navigation_finished():
	going_to_position = false


func _on_NavigationAgent2D_target_reached():
	going_to_position = false

#-------- Context Steering

func steering_setup():
	interest.resize(num_rays)
	danger.resize(num_rays)
	ray_directions.resize(num_rays)
	for i in num_rays:
		var angle = i * 2 * PI / num_rays
		ray_directions[i] = Vector2.UP.rotated(angle)

func set_interest(target, wander):
	if target:
		for i in num_rays:
			var d = ray_directions[i].dot(target)
			if wander != 0.0:
				d = 1.0 - abs(d - wander)
			interest[i] = max(0, d)
	else:
		for i in num_rays:
			var d = ray_directions[i].dot(transform.y)
			interest[i] = max(0, d)
	
func set_danger():
	var space_state = get_world_2d().direct_space_state
	for i in num_rays:
		var query = PhysicsRayQueryParameters2D.create(position, position + ray_directions[i] * look_ahead_range)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		queue_redraw()

		if result:
			var distance = self.global_position.distance_to(result.position)
			danger[i] = pow((look_ahead_range - distance)/look_ahead_range,2)
		else:
			danger[i] = 0.0

func choose_direction():
	# Eliminate interest in slots with danger
	for i in num_rays:
		if danger[i] > 0.0:
			interest[i] = -danger[i]
	# Choose direction based on remaining interest
	chosen_dir = Vector2.ZERO
	debug_lines = []
	for i in num_rays:
		debug_lines.append(ray_directions[i] * interest[i])
		chosen_dir += ray_directions[i] * interest[i]
	chosen_dir = chosen_dir.normalized()
	queue_redraw()


func _on_nearby_projectile_area_entered(area):
	if area.original_mecha_info.name != mecha_name:
		under_fire_timer = 0.5

