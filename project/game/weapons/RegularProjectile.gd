extends Area2D

onready var LightEffect = $Sprite/LightEffect
onready var Collision = $CollisionShape2D

var dying = false
var speed = 0
var local_scale = 1.0
var decaying_speed_ratio = 1.0
var scaling_variance = 0.0
var dir = Vector2()
var damage = 0
var shield_mult = 0.0
var health_mult = 0.0
var heat_damage = 0.0
var is_overtime = false
var decal_type = "bullet_hole"
var original_mecha_info
var weapon_name
var calibre


func _ready():
	if Debug.get_setting("disable_projectiles_light"):
		LightEffect.hide()
	else:
		LightEffect.show()


func _process(dt):
	if dying:
		return
	change_scaling(scaling_variance*dt)
	if decaying_speed_ratio < 1.0:
		var time_elapsed = dt
		while time_elapsed > 1.0:
			speed *= decaying_speed_ratio
			time_elapsed -= 1.0
		speed *= decaying_speed_ratio*(1.0 - dt)
	position += dir*speed*dt
	
	if not $LifeTimer.is_stopped():
		modulate.a = min(1.0, $LifeTimer.time_left)


func setup(mecha, args):
	var data = args.weapon_data.instance()
	$Sprite.texture = data.get_image()
	$CollisionShape2D.polygon = data.get_collision()
	
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	weapon_name = args.weapon_name
	decal_type = data.decal_type
	speed = data.speed
	$Sprite/LightEffect.modulate.a = data.light_energy
	damage = data.damage * args.damage_mod
	shield_mult = args.shield_mult
	health_mult = args.health_mult
	heat_damage = args.heat_damage
	is_overtime = data.is_overtime
	calibre = data.calibre
	dir = args.dir.normalized()
	position = args.pos
	rotation_degrees = rad2deg(dir.angle()) + 90
	
	if data.life_time > 0 :
		$LifeTimer.wait_time = data.life_time + rand_range(-data.life_time_var, data.life_time_var)
		$LifeTimer.autostart = true
	
	decaying_speed_ratio = data.decaying_speed_ratio + rand_range(-data.decaying_speed_ratio_var, data.decaying_speed_ratio_var)
	scaling_variance = data.change_scaling + rand_range(-data.change_scaling_var, data.change_scaling_var)


#Workaround since RigidBody can't have its scale changed
func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite.scale += vec
	$CollisionShape2D.scale += vec


func die():
	if dying:
		return
	dying = true
	var dur = rand_range(.2, .4)
	$Tween.interpolate_property(self, "modulate:a", null, 0.0, dur)
	$Tween.start()
	yield($Tween, "tween_completed")
	queue_free()

func _on_RegularProjectile_body_shape_entered(_body_id, body, body_shape_id, _local_shape):
	if body.is_in_group("mecha"):
		if body.is_shape_id_chassis(body_shape_id):
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
			body.add_decal(body_shape_id, collision_point, decal_type, size)
	
			var final_damage = damage if not is_overtime else damage * get_process_delta_time()
			body.take_damage(final_damage, shield_mult, health_mult, heat_damage, original_mecha_info, weapon_name, calibre)
			if not is_overtime:
				pass
				#body.knockback(collision_point, 0*final_damage/float(body.get_max_hp()))
			
	if not body.is_in_group("mecha") or\
	  (not is_overtime and original_mecha_info and body != original_mecha_info.body):
		die()


func _on_LifeTimer_timeout():
	queue_free()
