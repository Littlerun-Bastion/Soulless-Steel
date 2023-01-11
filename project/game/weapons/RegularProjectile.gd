extends Area2D

onready var LightEffect = $Sprite/LightEffect
onready var Collision = $CollisionShape2D

signal bullet_impact

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
var status_damage = 0.0
var status_type
var is_overtime = false
var decal_type = "bullet_hole"
var original_mecha_info
var weapon_name
var calibre
var seeker_target : Object = null
var mech_hit = false

var trail_enabled := false
var trail_lifetime := 1.0
var trail_lifetime_range := 0.25
var trail_eccentricity := 5.0
var trail_min_spawn_distance := 20.0
var trail_width := 20

var has_wiggle := false
var wiggle_amount := 2.0
var is_seeker := false
var seek_agility := 0.01
var seek_time := 1.0
var seeker_angle := 90.0
var seek_time_expired := false


var impact_size := 1.0

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
	rotation_degrees = rad2deg(dir.angle()) + 90
	# --- keeping this as an option because it's cool, but honestly i want a better missile tracking script that more accurately reflects missile trajectory
	if is_seeker:
		if seeker_target and is_instance_valid(seeker_target):
			if lifetime < seek_time:
				dir = lerp(dir.rotated(rand_range(-wiggle_amount, wiggle_amount)), position.direction_to(seeker_target.position), seek_agility)
			elif not seek_time_expired:
				dir = lerp(dir, position.direction_to(seeker_target.position), seek_agility)
				wiggle_amount = wiggle_amount/2
				seek_time_expired = true
	if has_wiggle:
		if not seeker_target or not is_seeker or not is_instance_valid(seeker_target) or lifetime > seek_time:
			dir = dir.rotated(rand_range(-wiggle_amount, wiggle_amount))
	
	
	
	if not $LifeTimer.is_stopped():
		modulate.a = min(1.0, $LifeTimer.time_left)


func setup(mecha, args):
	var data = args.weapon_data.instance()
	$Sprite.texture = data.get_image()
	$CollisionShape2D.polygon = data.get_collision()
	if data.random_rotation:
		$Sprite.rotation_degrees = rand_range(0, 360)
	
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	weapon_name = args.weapon_name
	decal_type = data.decal_type
	speed = args.bullet_velocity
	$Sprite/LightEffect.modulate.a = data.light_energy
	damage = data.damage * args.damage_mod
	shield_mult = args.shield_mult
	health_mult = args.health_mult
	heat_damage = args.heat_damage
	status_damage = args.status_damage
	status_type = args.status_type
	is_overtime = data.is_overtime
	trail_lifetime = args.trail_lifetime
	trail_lifetime_range = args.trail_lifetime_range
	trail_eccentricity = args.trail_eccentricity
	trail_min_spawn_distance = args.trail_min_spawn_distance
	trail_width = args.trail_width
	has_wiggle = args.has_wiggle
	wiggle_amount = args.wiggle_amount
	calibre = data.calibre
	impact_size = args.impact_size
	is_seeker = args.is_seeker
	seek_agility = args.seek_agility
	seek_time = args.seek_time
	seeker_angle = args.seeker_angle
	local_scale = args.projectile_size
	if args.seeker_target:
		seeker_target = args.seeker_target
	dir = args.dir.normalized()
	position = args.pos
	rotation_degrees = rad2deg(dir.angle()) + 90
	change_scaling(local_scale)
	
	if data.life_time > 0 :
		$LifeTimer.wait_time = data.life_time + rand_range(-data.life_time_var, data.life_time_var)
		$LifeTimer.autostart = true
	
	decaying_speed_ratio = args.bullet_drag + rand_range(-args.bullet_drag_var, args.bullet_drag_var)
	scaling_variance = args.projectile_size_scaling + rand_range(-args.projectile_size_scaling_var, args.projectile_size_scaling_var)
	


#Workaround since RigidBody can't have its scale changed
func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite.scale += vec
	$CollisionShape2D.scale += vec


func die():
	if dying:
		return
	dying = true
	if not is_overtime:
		emit_signal("bullet_impact", self)
	#var dur = rand_range(.2, .4)
	#$Tween.interpolate_property(self, "modulate:a", null, 0.0, dur)
	#$Tween.start()
	#yield($Tween, "tween_completed")
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
			body.take_damage(final_damage, shield_mult, health_mult, heat_damage, status_damage, status_type, original_mecha_info, weapon_name, calibre)
			if not is_overtime:
				pass
				#body.knockback(collision_point, 0*final_damage/float(body.get_max_hp()))
			mech_hit = true
			
	if not body.is_in_group("mecha") or\
	  (not is_overtime and original_mecha_info and body != original_mecha_info.body):
		if not body.is_in_group("mecha"):
			mech_hit = false
		die()


func _on_LifeTimer_timeout():
	queue_free()


