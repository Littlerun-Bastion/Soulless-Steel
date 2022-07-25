extends Area2D

var speed = 0
var local_scale = 1.0
var decaying_speed_ratio = 1.0
var scaling_variance = 0.0
var dir = Vector2()
var damage = 0
var decal_type = "bullet_hole"
var original_mecha_info
var weapon_name
var calibre = "test"


func _process(dt):
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
	#Check if mecha is already dead
	if not is_instance_valid(mecha):
		return
		
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
	$Light2D.energy = data.light_energy
	damage = data.damage * args.damage_mod
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
	$Light2D.scale += vec


func _on_RegularProjectile_body_shape_entered(_body_id, body, body_shape, _local_shape):
	if body.is_in_group("mecha"):
		if body.is_shape_id_legs(body_shape):
			return
		if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
			body.add_decal(body_shape, global_transform, decal_type, ($Sprite.scale*$Sprite.texture.get_size())/2)
			body.take_damage(damage, original_mecha_info, weapon_name, calibre)
			body.knockback(global_position, 100*damage/float(body.get_max_hp()))
	
	if not body.is_in_group("mecha") or (original_mecha_info and body != original_mecha_info.body):
		queue_free()


func _on_LifeTimer_timeout():
	queue_free()
