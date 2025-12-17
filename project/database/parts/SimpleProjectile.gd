extends Node2D

enum TYPE {INSTANT, REGULAR, COMPLEX}

var LightEffect
var Collision

signal bullet_impact
signal create_trail

@export var projectile_size := 1.0
@export var projectile_size_scaling := 0.0
@export var projectile_size_scaling_var := 0.0
@export var bullet_drag := 1.0
@export var bullet_drag_var := 0.0
@export var min_speed := 0.0
@export var is_overtime := false
@export var decal_type:= "bullet_hole"
@export var texture_variations = []
@export var light_energy:= 0.5
@export var muzzle_speed:= 400
@export var life_time = -1.0 #-1 means it won't disappear
@export var life_time_var = 0.0 #How much to vary from base life_time
@export var random_rotation := false

@export var impact_effect : PackedScene
@export var impact_size := 1.0
@export var hitstop := false
@export var trail : PackedScene

#---TRAILS AND IMPACTS---#
@export var smoke_density = 200
@export var smoke_lifetime = 10.0
#---DAMAGE---#

@export var base_damage := 100
@export var health_mult := 1.0
@export var shield_mult := 1.0
@export var dropoff_modifier := 0.8 
@export var heat_damage := 10.0
@export var status_damage := 0.0
@export var status_type : String
@export var impact_force := 0.0


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
var lifetime = 0
var speed = 0.0
var dir
var mech_hit
var shield_hit
var final_damage = 0.0
var distance = 0.0
var has_impacted = false

func _ready():
	LightEffect = get_node("Sprite2D/LightEffect")
	Collision = get_node("CollisionShape2D")

func _process(dt):
	if dying:
		return
	lifetime += dt
	
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(position, position + (dir*speed*dt))
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	if result and result.collider:
		position = result.position
		speed = 0
	else:
		position += dir*speed*dt
		
	distance += speed*dt
	speed = max(speed - (bullet_drag + randf_range(-bullet_drag_var, bullet_drag_var)) * dt, min_speed)
	final_damage = base_damage * (pow(dropoff_modifier, distance/1000))
	if not $LifeTimer.is_stopped():
		modulate.a = min(1.0, ($LifeTimer.time_left/(life_time/4)))

func setup(mecha, _args, _weapon):
	if random_rotation:
		$Image.rotation_degrees = randf_range(0,360)
	args = _args
	position = args.pos
	dir = args.dir.normalized()
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	seeker_target = args.seeker_target
	speed = muzzle_speed
	original_mecha_info = {
		"body": mecha,
		"name": mecha.mecha_name,
	}
	change_scaling(projectile_size)
	
	part_id = _weapon
	$Sprite2D/LightEffect.modulate.a = light_energy
	if life_time > 0 :
		$LifeTimer.wait_time = life_time + randf_range(-life_time_var, life_time_var)
		$LifeTimer.autostart = true
	
	instance_trail()
		

func _on_Projectile_body_shape_entered(_body_id, body, body_shape_id, _local_shape):
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
				if body.is_shielding and not has_impacted:
					var reflect_vector = global_position.direction_to(body.global_position)
					dir = (dir.reflect(reflect_vector.rotated(deg_to_rad(90)))).normalized()
					rotation_degrees = rad_to_deg(dir.angle()) + 90
					original_mecha_info.body = body
					original_mecha_info.name = body.mecha_name
					shield_hit = true
					speed = muzzle_speed
					emit_signal("bullet_impact", self, impact_effect, false, body)
				elif not body.is_shielding:
					emit_signal("bullet_impact", self, impact_effect, false, body)
				has_impacted = true
			if not is_overtime and impact_force > 0.0:
				body.knockback(impact_force, dir, true)
			mech_hit = true
			
	if not body.is_in_group("mecha") or\
	(not is_overtime and original_mecha_info and body != original_mecha_info.body):
		if not body.is_in_group("mecha"):
			mech_hit = false
		die(body)
	
func get_image():
	if texture_variations.is_empty() or randf() > 1.0/float(texture_variations.size() + 1):
		return $Image.texture
	else:
		texture_variations.shuffle()
		return texture_variations.front()

func get_collision():
	return $CollisionShape3D.polygon

func die(body):
	if dying:
		return
	dying = true
	if not is_overtime:
		emit_signal("bullet_impact", self, impact_effect, true, body)

	queue_free()

func _on_LifeTimer_timeout():
	queue_free()
	

#Workaround since RigidBody3D can't have its scale changed
func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite2D.scale *= vec
	$CollisionShape2D.scale *= vec

func instance_trail():
	emit_signal("create_trail", self, trail)
