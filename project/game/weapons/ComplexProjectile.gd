extends Area2D

@onready var LightEffect = $Sprite2D/LightEffect
@onready var Collision = $CollisionShape2D

signal bullet_impact
signal create_projectile

const EXPLOSION_RESOLUTION = 60
const FUSE_RESOLUTION = 60

var data
var proj_data
var dying = false
var speed = 0
var dir = Vector2()
var target_dir = Vector2()
var true_dir = Vector2()
var original_mecha_info
var origin
var seeker_target : Object = null
var mech_hit = false
var acceleration = 0.0
var max_speed = 0.0
var turn_rate = 0.0
var seeker_type : String
var seeker_angle = 0.0
var wiggle_amount = 0.0
var wiggle_freq = 0.0
var is_seeking = false
var scaling_variance
var home_node

var explosion_ray_directions = []
var fuse_ray_directions = []


var impact_effect

var seek_time_expired := false

var lifetime := 0.0

func setup(mecha, args, weapon):
	data = args.weapon_data
	proj_data = data.projectile.instantiate()
	$Sprite2D.texture = proj_data.get_image()
	$CollisionShape2D.polygon = proj_data.get_collision()
	if proj_data.random_rotation:
		$Sprite2D.rotation_degrees = randf_range(0, 360)
	origin = mecha
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	lifetime = data.lifetime
	speed = data.bullet_velocity
	max_speed = data.bullet_velocity
	impact_effect = data.impact_effect
	$Sprite2D/LightEffect.modulate.a = proj_data.light_energy
	if args.seeker_target:
		seeker_target = args.seeker_target
	dir = args.dir.normalized()
	true_dir = args.dir.normalized()
	position = args.pos
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	change_scaling(data.projectile_size)
	home_node = weapon
	scaling_variance = data.projectile_size_scaling + randf_range(-data.projectile_size_scaling_var, data.projectile_size_scaling_var)


func _ready():
	if Debug.get_setting("disable_projectiles_light"):
		LightEffect.hide()
	else:
		LightEffect.show()


func _draw():
	if Debug.get_setting("draw_debug_lines"):
		draw_line(Vector2.ZERO, true_dir.rotated(-global_rotation)* 500, Color.WHITE, 5)
		for i in explosion_ray_directions:
			draw_line(Vector2.ZERO, i.rotated(-global_rotation), Color.WHITE, 1)
		for i in fuse_ray_directions:
			draw_line(Vector2.ZERO, i.rotated(-global_rotation), Color.DARK_GRAY, 1)


func _process(dt):
	if dying:
		return
	lifetime += dt
	propulsion(dt)
	guidance(dt)
	fuse(dt)
	if wiggle_amount > 0.0 and wiggle_freq > 0.0:
		dir = true_dir.rotated((sin(2*PI*lifetime*wiggle_freq) * dt * (wiggle_amount*5)))
	else:
		dir = true_dir
	position += dir*speed*dt
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	queue_redraw()


func get_propulsion_stage():
	var cur_stage = 0
	var total_delay = 0
	for idx in data.stages + 1:
		if lifetime < total_delay:
			return cur_stage
		total_delay += data.stage_thrust_delay[cur_stage]
		cur_stage += 1
	return cur_stage


func get_propulsion_var(var_name, stage):
	var var_data = data.get("stage_"+var_name)
	if var_data.size() >= stage:
		return var_data[stage - 1]
	#Return last position if cur stage doesn't exist
	return var_data.back()


func propulsion(dt):
	var cur_stage = get_propulsion_stage()
	if cur_stage > 0:
		acceleration = get_propulsion_var("acceleration", cur_stage)
		max_speed = get_propulsion_var("max_speed", cur_stage)
		wiggle_amount = get_propulsion_var("wiggle_amount", cur_stage)
		wiggle_freq = get_propulsion_var("wiggle_freq", cur_stage)

	if speed < max_speed:
		speed = min(speed + acceleration*dt, max_speed) 


func guidance(dt):
	var cur_stage = get_propulsion_stage()
	if cur_stage > 0:
		seeker_type = get_propulsion_var("seeker_type", cur_stage)
		seeker_angle = get_propulsion_var("seeker_angle", cur_stage)
		turn_rate = get_propulsion_var("turn_rate", cur_stage)
	
	match seeker_type:
		"IR":
			#rotation_degrees = rad_to_deg(dir.angle()) + 90
			if seeker_target and is_instance_valid(seeker_target):
				is_seeking = true
				if seeker_target.mecha_heat / seeker_target.max_heat > 0.2:
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
			var current_turn = min(abs(turn_angle), deg_to_rad(turn_rate)) * sign(turn_angle) * dt
			true_dir = true_dir.rotated(current_turn)
	
func fuse(_dt):
	var space_state = get_world_2d().direct_space_state
	fuse_ray_directions = []
	if data.fuse_arm_time < lifetime:
		for i in FUSE_RESOLUTION:
			var angle = i * 2 * PI / FUSE_RESOLUTION
			var ray = dir.rotated(angle + deg_to_rad(-data.fuse_angle/2))
			if angle < deg_to_rad(data.fuse_angle):
				var query = PhysicsRayQueryParameters2D.create(position, position + ray * data.fuse_proximity_distance)
				var result = space_state.intersect_ray(query)
				if result: 
					fuse_ray_directions.append(ray * self.global_position.distance_to(result.position))
				else:
					fuse_ray_directions.append(ray * data.fuse_proximity_distance)
				if result and result.collider and result.collider.is_in_group("mecha"):
					
					if data.fuse_detection_type == "IR":
						if result.collider.mecha_heat / result.collider.max_heat > 0.1:
							payload()
					
					elif data.fuse_detection_type == "RCS":
						payload()
						
					elif data.fuse_detection_type == "Magnetic":
						payload()
	
	if lifetime > data.fuse_arm_time + data.fuse_timer and data.fuse_timer > 0.0:
		payload()
		
	queue_redraw()

func die():
	if dying:
		return
	dying = true
	if not proj_data.is_overtime:
		emit_signal("bullet_impact", self, impact_effect)
	$Tickover.start()
	await $Tickover.timeout
	queue_free()

func payload():
	if data.payload_subprojectile:
		var accuracy = randf_range(-data.payload_subprojectile_spread, data.payload_subprojectile_spread)
		for _i in range(data.payload_subprojectile_count):
			emit_signal("create_projectile", origin,
						{
							"is_subprojectile": true,
							"weapon_data": home_node.subprojectile_data,
							"pos": global_position,
							"pos_reference": null,
							"dir": true_dir,
							"seeker_target": seeker_target,
						}, home_node)
						
	if data.payload_explosion_radius > 0.0:
		var affected_mechs = []
		var space_state = get_world_2d().direct_space_state
		for i in EXPLOSION_RESOLUTION:
			var angle = i * 2 * PI / EXPLOSION_RESOLUTION
			var ray = dir.rotated(angle + deg_to_rad(-data.payload_explosion_angle/2))
			if angle < deg_to_rad(data.payload_explosion_angle):
				var query = PhysicsRayQueryParameters2D.create(position, position + ray * data.payload_explosion_radius)
				var result = space_state.intersect_ray(query)
				if result: 
					explosion_ray_directions.append(ray * self.global_position.distance_to(result.position))
				else:
					explosion_ray_directions.append(ray * data.payload_explosion_radius)
				if result and result.collider and result.collider.is_in_group("mecha"):
					if not affected_mechs.has(result.collider):
						result.collider.take_damage(data.payload_explosion_damage, data.shield_mult, data.health_mult, data.heat_damage,\
											data.status_damage, data.status_type, data.hitstop, original_mecha_info, data.part_id, proj_data.calibre)
						result.collider.knockback(data.payload_explosion_force, ray, true)
						affected_mechs.append(result.collider)
	
	queue_redraw()
	die()

func _on_body_shape_entered(_body_id, body, body_shape_id, _local_shape):
	if body.is_in_group("mecha"):
		if body.is_shape_id_chassis(body_shape_id):
			return
			
		if not data.fuse_is_contact_enabled or lifetime < data.fuse_arm_time:
			return
			
		if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
			var shape = body.get_shape_from_id(body_shape_id)
			var points = ProjectileManager.get_intersection_points(Collision.polygon, Collision.global_transform,\
																	shape.polygon, shape.global_transform)
			
			var collision_point
			if points.size() > 0:
				collision_point = points[0]
			else:
				collision_point = global_position
			
			var size = Vector2(40,40)
			body.add_decal(body_shape_id, collision_point, proj_data.decal_type, size)
			
			var final_damage = data.damage if not proj_data.is_overtime else data.damage * get_process_delta_time()
			body.take_damage(final_damage, data.shield_mult, data.health_mult, data.heat_damage,\
								data.status_damage, data.status_type, data.hitstop, original_mecha_info, data.part_id, proj_data.calibre)
			if not proj_data.is_overtime and data.impact_force > 0.0:
				body.knockback(data.impact_force, dir, true)
			mech_hit = true
			
	if not body.is_in_group("mecha") or\
	(not proj_data.is_overtime and original_mecha_info and body != original_mecha_info.body):
		if not body.is_in_group("mecha"):
			mech_hit = false
		if data.fuse_is_contact_enabled and lifetime > data.fuse_arm_time:
			payload()
		die()


func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite2D.scale += vec
	$CollisionShape2D.scale += vec
