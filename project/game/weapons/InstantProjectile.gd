extends RayCast2D

var original_mecha_info

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
var decal_type = "bullet_hole_small"
var weapon_name
var calibre 
var seeker_target : Object = null
var hit = false
var miss = false
var mech_hit = false
var impact_size := 1.0
var effect_data 
var lifetime = 2.0
var lifetime_tick = 1.0
var body

signal bullet_impact


func _physics_process(dt): 
	var cast_point := cast_to
	if not hit:
		body = get_collider()
		force_raycast_update()
		if body:
			if body.is_in_group("mecha"):
				if body.is_shape_id_chassis(get_collider_shape()):
					add_exception(body)
					pass
				if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
					force_raycast_update()
					var body_shape_id = get_collider_shape()
					var collision_point = get_collision_point()
					
					var size = Vector2(40,40)
					if collision_point:
						body.add_decal(body_shape_id, collision_point, decal_type, size)
			
					var final_damage = damage if not is_overtime else damage * get_process_delta_time()
					body.take_damage(final_damage, shield_mult, health_mult, heat_damage, original_mecha_info, weapon_name, calibre)
					if not is_overtime:
						body.knockback(collision_point, 0*final_damage/float(body.get_max_hp()))
					mech_hit = true
					hit = true
			if not body.is_in_group("mecha") or\
			  (not is_overtime and original_mecha_info and body != original_mecha_info.body):
				if not body.is_in_group("mecha"):
					force_raycast_update()
					mech_hit = false
					hit = true
			cast_point = to_local(get_collision_point())
			force_raycast_update()
			if cast_point != cast_to:
				effect_data.points[1] = (cast_point)
			else:
				force_raycast_update()
				miss = true
		else:
			effect_data.points[1] = (cast_point)
	if miss:
		effect_data.points[1] = (cast_point)
	
	lifetime_tick = max(lifetime_tick - dt, 0.0)
	if lifetime_tick <= 0.0:
		die()

func setup(mecha, args):
	effect_data = args.weapon_data.instance()
	if effect_data:
		self.add_child(effect_data)
	else:
		effect_data = $Basic
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	weapon_name = args.weapon_name
	damage = effect_data.damage * args.damage_mod
	calibre = effect_data.calibre
	shield_mult = args.shield_mult
	health_mult = args.health_mult
	heat_damage = args.heat_damage
	impact_size = args.impact_size
	effect_data.width = args.projectile_size*10
	lifetime = args.lifetime
	lifetime_tick = lifetime
	dir = args.dir.normalized()
	position = args.pos
	cast_to = dir*args.beam_range
	add_exception(original_mecha_info.body)


func die():
	if dying:
		return
	dying = true
	$DeathTween.interpolate_property(self, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
	$DeathTween.start()
	yield($DeathTween, "tween_completed")
	queue_free()
