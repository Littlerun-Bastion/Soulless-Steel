extends Area2D

@onready var LightEffect = $Sprite2D/LightEffect
@onready var Collision = $CollisionShape2D

signal bullet_impact

var data
var proj_data
var dying = false
var speed = 0
var decaying_speed_ratio = 1.0
var scaling_variance = 0.0
var dir = Vector2()
var original_mecha_info
var seeker_target : Object = null
var mech_hit = false

var impact_effect

var seek_time_expired := false

var lifetime := 0.0



func _ready():
	if Debug.get_setting("disable_projectiles_light"):
		LightEffect.hide()
	else:
		LightEffect.show()


func _process(dt):
	if dying:
		return
	change_scaling(scaling_variance*dt)
	lifetime += dt
	speed *= decaying_speed_ratio
	position += dir*speed*dt
	# --- keeping this as an option because it's cool, but honestly i want a better missile tracking script that more accurately reflects missile trajectory
	
	
	
	if not $LifeTimer.is_stopped():
		modulate.a = min(1.0, $LifeTimer.time_left)


func setup(mecha, args, _weapon):
	data = args.weapon_data
	proj_data = data.projectile.instantiate()
	$Sprite2D.texture = proj_data.get_image()
	$CollisionShape2D.polygon = proj_data.get_collision()
	if proj_data.random_rotation:
		$Sprite2D.rotation_degrees = randf_range(0, 360)
	
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	lifetime = data.lifetime
	speed = data.bullet_velocity
	impact_effect = data.impact_effect
	$Sprite2D/LightEffect.modulate.a = proj_data.light_energy
	if args.seeker_target:
		seeker_target = args.seeker_target
	dir = args.dir.normalized()
	position = args.pos
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	change_scaling(data.projectile_size)
	
	if proj_data.life_time > 0 :
		$LifeTimer.wait_time = proj_data.life_time + randf_range(-proj_data.life_time_var, proj_data.life_time_var)
		$LifeTimer.autostart = true
	
	decaying_speed_ratio = data.bullet_drag + randf_range(-data.bullet_drag_var, data.bullet_drag_var)
	scaling_variance = data.projectile_size_scaling + randf_range(-data.projectile_size_scaling_var, data.projectile_size_scaling_var)
	


#Workaround since RigidBody3D can't have its scale changed
func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite2D.scale += vec
	$CollisionShape2D.scale += vec


func die():
	if dying:
		return
	dying = true
	if not proj_data.is_overtime:
		emit_signal("bullet_impact", self, impact_effect)

func _on_RegularProjectile_body_shape_entered(_body_id, body, body_shape_id, _local_shape):
	if body.is_in_group("mecha"):
		if body.is_shape_id_chassis(body_shape_id):
			return
		
		if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
			var shape = body.get_shape_from_id(body_shape_id)
			var collision_point
			if shape is CollisionPolygon2D:
				var points = ProjectileManager.get_intersection_points(Collision.polygon, Collision.global_transform,\
																		shape.polygon, shape.global_transform)
				if points.size() > 0:
					collision_point = points[0]
				else:
					collision_point = global_position
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
		die()


func _on_LifeTimer_timeout():
	queue_free()


