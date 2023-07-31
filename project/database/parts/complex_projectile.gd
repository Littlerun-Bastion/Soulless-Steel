extends Node2D

enum TYPE {INSTANT, REGULAR, COMPLEX}

var LightEffect
var Collision
var thrusters_on = false

signal bullet_impact
signal create_projectile
signal create_trail

@export var type : TYPE
@export var projectile_size := 1.0
@export var projectile_size_scaling := 0.0
@export var projectile_size_scaling_var := 0.0
@export var bullet_drag := 1.0
@export var bullet_drag_var := 0.0
@export var muzzle_min_speed := 0.0
@export var is_overtime := false
@export var decal_type:= "bullet_hole"
@export var texture_variations = []
@export var light_energy:= 0.5
@export var muzzle_speed:= 400
@export var life_time = -1.0 #-1 means it won't disappear
@export var life_time_var = 0.0 #How much to vary from base life_time
@export var random_rotation := false
@export var release_aligned := true
@export var momentum_corrected := false
@export var inherit_velocity := false

@export var impact_effect : PackedScene
@export var impact_size := 1.0
@export var hitstop := false
@export var trail : PackedScene

#---TRAILS AND IMPACTS---#
@export var smoke_density = 500
@export var smoke_lifetime = 10.0
#---DAMAGE---#

@export var 	base_damage := 100
@export var health_mult := 1.0
@export var shield_mult := 1.0
@export var dropoff_modifier := 0.8 
@export var heat_damage := 10.0
@export var status_damage := 0.0
@export var status_type : String
@export var impact_force := 0.0

#----COMPLEX PROJECTILE BEHAVIOURS----#

#---PROPULSION---#
@export var stages := 1
@export var stage_max_speed :Array[int] = [0] ##Max Speed: Maximum possible speed the projectile can accelerate to.
@export var stage_min_speed :Array[int] = [0] ##Max Speed: Maximum possible speed the projectile can accelerate to.
@export var stage_acceleration :Array[float] = [0] ##Acceleration: Amount speed is increased by per second..
@export var stage_deceleration :Array[float] = [0] ##Acceleration: Amount speed is increased by per second.
@export var stage_thrust_delay :Array[float] = [0.0] ##Thrust Delay: Number of seconds before Acceleration is applied.
@export var stage_turn_rate :Array[float] = [0.0] ##Turn Rate: Number of degrees per second a projectile can turn by if it is tracking a target.
@export var stage_wiggle_amount :Array[float] = [0.0] ##Wiggle Amount: Maximum number of degrees a projectile can turn off its course.
@export var stage_wiggle_freq :Array[float] = [0.0] ##Wiggle Freq: Number of wiggles per second (based on cosine).
@export var stage_wiggle_err :Array[float] = [0.0] ##Wiggle Err: Randomness of wiggles by percentage.
@export var stage_seeker_type :Array[String] = ["IR"] ##Seeker Type: Detection method the projectile will use to see if it is allowed to track a target./
	## (IR: based on mecha_heat, RCS: based on mecha rcs (not implemented), Laser: based on the endpoint of a raycast from player's mech to the direction of the target (not implemented))
@export var stage_seeker_delay :Array[float] = [0.0] ##Seeker Delay: Time in seconds before the stage of that seeker kicks in.
@export var stage_seeker_angle :Array[float] = [0.0] ##Seeker Angle: Angle beyond which the seeker will not chase the target.


#---FUSE---#
@export var fuse_arm_time := 0.0 ##Time in seconds before the projectile can impact an object or deploy its 'payload'
@export var fuse_timer := 3.0 ##Time in seconds (after fuse arm time) until the projectile deploys its 'payload'
@export var fuse_proximity_distance := 0.0 ##Distance at which the projectile detects an enemy.
@export var fuse_detection_type : String ##Detection method the projectile uses to see if it is allowed to deploy its 'payload'.
@export var fuse_angle := 360.0 ##Angle beyond which the projectile no longer detects enemies to trigger the fuse.
@export var fuse_is_contact_enabled := true ##Whether or not the projectile can directly hit a mecha. If false, projectile will fly past a mecha.

#---PAYLOAD---#
@export var payload_explosion : Resource ##Visual effect for the explosion.
@export var payload_explosion_damage := 0.0 ##Total damage of the explosion.
@export var payload_explosion_shield_mult := 1.0 ##Shield damage multiplier of explosion.
@export var payload_explosion_health_mult := 1.0 ##Health damage multiplier of explosion.
@export var payload_explosion_heat_damage := 0.0 ##Heat damage of explosion.
@export var payload_explosion_status_damage := 0.0 ##Amount of status explosion inflicts.
@export var payload_explosion_status_type : String ##Explosion status type.
@export var payload_explosion_force := 0.0 ##Amount of knockback explosion performs against a target.
@export var payload_explosion_radius := 0.0 ##Distance from impact center an explosion hits a target.
@export var payload_explosion_angle := 360.0 ##Angle from center an explosion hits.
@export var payload_explosion_hitstop := false ##Hitstop of explosion in seconds.
@export var payload_subprojectile : PackedScene ##What subprojectile the payload spawns.
@export var payload_subprojectile_count := 0 ##How many subprojectiles the payload spawns.
@export var payload_subprojectile_spread := 0.0 #In degrees
@export var payload_subprojectile_rate := 0.0 #Time taken to release each subprojectile



var args
#weapon_data - reference to the weapon
#projectile - the projectile packed scene
#pos - global position of the bullet at time of firing
#dir - direction of the weapon's aim point
#seeker_target - locked target
var original_mecha_info
var part_id	
var seeker_target
var dying
var lifetime = 0.0
var wiggle_lifetime = 0.0
var wiggle_error_lifetime = 0.0
var speed = 0.0
var dir
var mech_hit
var final_damage = 0.0
var distance = 0.0
var acceleration = 0.0
var deceleration = 0.0
var max_speed = 0.0
var min_speed = 0.0
var wiggle_amount = 0.0
var wiggle_freq = 0.0
var wiggle_err = 0.0
var cur_wiggle_err = 0.0
var seeker_angle = 0.0
var seeker_type : String
var turn_rate = 0.0
var is_seeking = false
var target_dir : Vector2
var true_dir : Vector2
var inherited_velocity : Vector2
var velocity : Vector2
var payload_expended = false
var explosion_targets = []
var fuse_waiting = false
var has_impacted = false
var is_trail_created = false

func _ready():
	LightEffect = get_node("Sprite2D/LightEffect")
	Collision = get_node("CollisionShape2D")

func _process(dt):
	if not is_trail_created:
		instance_trail()
		is_trail_created = true

	if dying:
		return
	propulsion(dt)
	guidance(dt)
	lifetime += dt
	wiggle_lifetime += dt
	if wiggle_error_lifetime < 1/wiggle_freq:
		wiggle_error_lifetime += dt
	else:
		wiggle_error_lifetime = 0
		cur_wiggle_err = randf_range(-wiggle_amount * wiggle_err,wiggle_amount * wiggle_err)
	position += velocity*dt
	distance += speed*dt
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	if wiggle_amount > 0.0 and wiggle_freq > 0.0:
		dir = true_dir.rotated((cos(2*PI*wiggle_lifetime*wiggle_freq) * deg_to_rad(wiggle_amount)))
	else:
		dir = true_dir
	final_damage = base_damage * (pow(dropoff_modifier, distance/1000))
	
	if lifetime > fuse_timer and fuse_timer > 0.0:
		payload()
	
	if fuse_waiting == true:
		var in_range_targets = $Fuse.get_overlapping_bodies()
		for body in in_range_targets:	
			if not body.is_in_group("mecha"):
				in_range_targets.erase(body)
			else:
				fuse(null, body, null, null)
				

func setup(mecha, _args, _weapon):
	if random_rotation:
		$Image.rotation_degrees = randf_range(0,360)
	args = _args
	position = args.pos
	dir = args.dir.normalized()
	true_dir = args.dir.normalized()
	if release_aligned:
		rotation_degrees = rad_to_deg(dir.angle()) + 90
	else:
		rotation_degrees = rad_to_deg(args.align_dir.angle()) + 90
	seeker_target = args.seeker_target
	speed = muzzle_speed
	if inherit_velocity:
		inherited_velocity = args.inherited_velocity
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	change_scaling(projectile_size)
	$Sprite2D/LightEffect.modulate.a = light_energy
	
	part_id = _weapon
	min_speed = muzzle_min_speed
	wiggle_lifetime += randf()
	if get_node_or_null("Fuse/FuseSensor"):
		var fuse_radius = CircleShape2D.new()
		fuse_radius.radius = fuse_proximity_distance
		$Fuse/FuseSensor.shape = fuse_radius
	if get_node_or_null("Explosion/ExplosionSensor"):
		var explosion_radius = CircleShape2D.new()
		explosion_radius.radius = payload_explosion_radius
		$Explosion/ExplosionSensor.shape = explosion_radius
	
	instance_trail()

func _on_Projectile_body_shape_entered(_body_id, body, body_shape_id, _local_shape):
	if body.is_in_group("mecha"):
		if body.is_shape_id_chassis(body_shape_id) or not fuse_is_contact_enabled:
			return
		
		if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
			var shape = body.get_shape_from_id(body_shape_id)
			var shape_polygon
			if shape is CollisionShape2D:
				shape_polygon = ProjectileManager.generate_circle_polygon(shape.shape.radius, shape.global_position)
			else:
				shape_polygon = shape.polygon
			var points = ProjectileManager.get_intersection_points(Collision.polygon, Collision.global_transform,\
																	shape_polygon, shape.global_transform)
			
			var collision_point
			if points.size() > 0:
				collision_point = points[0]
			else:
				collision_point = global_position
			
			var size = Vector2(40,40)
			if not has_impacted:
				body.take_damage(final_damage, shield_mult, health_mult, heat_damage,\
									status_damage, status_type, hitstop, original_mecha_info, part_id)
			if body.is_parrying and not is_overtime:
				dir = -dir
				rotation_degrees = rad_to_deg(dir.angle()) + 90
				original_mecha_info.body = body
				original_mecha_info.name = body.mecha_name
			else:
				body.add_decal(body_shape_id, collision_point, decal_type, size)
				if body.is_shielding and not has_impacted and not fuse_is_contact_enabled:
					var reflect_vector = global_position.direction_to(body.global_position)
					dir = (dir.reflect(reflect_vector.rotated(deg_to_rad(90)))).normalized()
					rotation_degrees = rad_to_deg(dir.angle()) + 90
					original_mecha_info.body = body
					original_mecha_info.name = body.mecha_name
					emit_signal("bullet_impact", self, impact_effect, false)
				has_impacted = true
			if not is_overtime and impact_force > 0.0:
				body.knockback(impact_force, dir, true)
			mech_hit = true
			
	if not body.is_in_group("mecha") or\
	(not is_overtime and original_mecha_info and body != original_mecha_info.body):
		if not body.is_in_group("mecha"):
			mech_hit = false
		die()
	
func get_image():
	if texture_variations.is_empty() or randf() > 1.0/float(texture_variations.size() + 1):
		return $Image.texture
	else:
		texture_variations.shuffle()
		return texture_variations.front()

func get_collision():
	return $CollisionShape3D.polygon

func die():
	if dying:
		return
	dying = true
	if not is_overtime:
		emit_signal("bullet_impact", self, impact_effect, true)

	queue_free()


#Workaround since RigidBody3D can't have its scale changed
func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite2D.scale = vec
	$CollisionShape2D.scale = vec


func get_propulsion_stage():
	var cur_stage = 0
	var total_delay = 0
	for idx in stages:
		total_delay += stage_thrust_delay[cur_stage]
		if lifetime < total_delay:
			break
		cur_stage += 1
	return cur_stage


func get_propulsion_var(var_name, stage):
	var var_data = get("stage_"+var_name)
	if var_data.size() >= stage:
		return var_data[stage - 1]
	#Return last position if cur stage doesn't exist
	return var_data.back()


func propulsion(dt):
	var cur_stage = get_propulsion_stage()
	if cur_stage > 0:
		velocity = (speed + inherited_velocity.length()) * dir 
		acceleration = get_propulsion_var("acceleration", cur_stage)
		deceleration = get_propulsion_var("deceleration", cur_stage)
		max_speed = get_propulsion_var("max_speed", cur_stage)
		min_speed = get_propulsion_var("min_speed", cur_stage)
		wiggle_amount = get_propulsion_var("wiggle_amount", cur_stage)
		wiggle_freq = get_propulsion_var("wiggle_freq", cur_stage)
		wiggle_amount += cur_wiggle_err
		wiggle_err = get_propulsion_var("wiggle_err", cur_stage)
		if not momentum_corrected:
			true_dir = args.align_dir
			momentum_corrected = true
		release_aligned = true
		if thrusters_on:
			speed += acceleration*dt
		else:
			speed -= deceleration*dt
		if speed > max_speed:
			speed = max_speed
		elif speed < min_speed:
			speed = min_speed
	elif cur_stage == 0:
		speed = max(speed - (bullet_drag + randf_range(-bullet_drag_var, bullet_drag_var)) * dt, muzzle_min_speed)
		velocity = (speed * true_dir) + inherited_velocity
		

func guidance(dt):
	var cur_stage = get_propulsion_stage()
	if release_aligned:
		$Sprite2D.global_rotation_degrees = rad_to_deg(dir.angle()) + 90
		$CollisionShape2D.global_rotation_degrees = rad_to_deg(dir.angle()) + 90
	else:
		$Sprite2D.global_rotation_degrees = rad_to_deg(args.align_dir.angle()) + 90
		$CollisionShape2D.global_rotation_degrees = rad_to_deg(args.align_dir.angle()) + 90
	if cur_stage > 0:
		seeker_type = get_propulsion_var("seeker_type", cur_stage)
		seeker_angle = get_propulsion_var("seeker_angle", cur_stage)
		turn_rate = get_propulsion_var("turn_rate", cur_stage)
	
	match seeker_type:
		"IR":
			if seeker_target and is_instance_valid(seeker_target):
				is_seeking = true
				if seeker_target.mecha_heat / seeker_target.max_heat > 0.1:
					is_seeking = true
				else:
					is_seeking = false
	
		"RCS":
			rotation_degrees = rad_to_deg(dir.angle()) + 90
			if seeker_target and is_instance_valid(seeker_target):
				pass
	
		"Laser":
			rotation_degrees = rad_to_deg(dir.angle()) + 90
			if seeker_target and is_instance_valid(seeker_target):
				pass
	
		_:
			is_seeking = false
	
	if is_seeking and seeker_target and is_instance_valid(seeker_target):
		target_dir = seeker_target.position - position
		var turn_angle = true_dir.angle_to(target_dir)
		if abs(turn_angle) < deg_to_rad(seeker_angle):
			var current_turn = deg_to_rad(turn_rate) * sign(turn_angle) * dt
			true_dir = true_dir.rotated(current_turn)
		if abs(turn_angle) < deg_to_rad(10) and is_instance_valid(seeker_target):
			thrusters_on = true
		elif not is_instance_valid(seeker_target) or seeker_target == null:
			thrusters_on = true
		else:
			thrusters_on = false

func fuse(_body_rid, body, _body_shape_index, _local_shape_index):
	if body.is_in_group("mecha") and fuse_proximity_distance > 0.0:
		if lifetime < fuse_arm_time:
			fuse_waiting = true
			return
		var enemy_direction = body.position - position
		var detection_angle = dir.angle_to(enemy_direction)
		if abs(detection_angle) < deg_to_rad(fuse_angle):
			var space_state = get_world_2d().direct_space_state
			var query = PhysicsRayQueryParameters2D.create(position, body.position)
			query.exclude = [self]
			var result = space_state.intersect_ray(query)
			if result and result.collider and result.collider.is_in_group("mecha"):
				if fuse_detection_type == "IR":
					if result.collider.mecha_heat / result.collider.max_heat > 0.1:
						payload()
						return
				
				elif fuse_detection_type == "RCS":
					payload()
					return
					
				elif fuse_detection_type == "Magnetic":
					payload()
					return

func payload():
	if payload_expended:
		return
	else:
		payload_expended = true
	if payload_subprojectile and payload_subprojectile_count > 0:
		for _i in range(payload_subprojectile_count):
			await get_tree().create_timer(max(payload_subprojectile_rate,0.01)).timeout
			var accuracy = deg_to_rad(randf_range(-payload_subprojectile_spread, payload_subprojectile_spread))
			emit_signal("create_projectile", original_mecha_info.body,
						{
							"projectile":payload_subprojectile,
							"pos": global_position,
							"pos_reference": null,
							"dir": dir.rotated(accuracy),
							"align_dir":dir,
							"seeker_target": seeker_target,
							"inherited_velocity": speed*dir,
							"node_reference": null,
							"bullet_spread_delay": 0,
							"muzzle_flash": null,
						}, part_id)
	explosion()

func explosion():
	var space_state = get_world_2d().direct_space_state
	for body in explosion_targets:
		var ray = body.position - position
		ray = ray.normalized()
		var explosion_angle = dir.angle_to(ray)
		if abs(explosion_angle) < deg_to_rad(payload_explosion_angle):
			var query = PhysicsRayQueryParameters2D.create(position,body.position)
			query.exclude = [self]
			var result = space_state.intersect_ray(query)
			if result and result.collider and result.collider.is_in_group("mecha"):
				result.collider.take_damage(payload_explosion_damage, payload_explosion_shield_mult, payload_explosion_health_mult, payload_explosion_heat_damage,\
									payload_explosion_status_damage, payload_explosion_status_type, payload_explosion_hitstop, original_mecha_info, part_id)
				result.collider.knockback(payload_explosion_force, ray, true)
	die()
	
func _on_explosion_body_entered(body):
	if not body.is_in_group("mecha"):
		return
	if not explosion_targets.has(body):
		explosion_targets.append(body)


func _on_explosion_body_exited(body):
	if not body.is_in_group("mecha"):
		return
	if explosion_targets.has(body):
		explosion_targets.erase(body)


func _on_fuse_body_shape_exited(_body_rid, body, _body_shape_index, _local_shape_index):
	var in_range = $Fuse.get_overlapping_bodies()
	for i in in_range:
		if not i.is_in_group("mecha"):
			in_range.erase(body)
	if in_range == []:
		fuse_waiting = false

func instance_trail():
	emit_signal("create_trail", self, trail)
