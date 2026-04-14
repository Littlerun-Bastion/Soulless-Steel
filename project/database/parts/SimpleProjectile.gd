extends Node2D

enum TYPE {INSTANT, REGULAR, COMPLEX}

var LightEffect
var Collision

signal bullet_impact
signal create_trail

#ITEM ATTRIBUTES
@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var tags :Array[String] = ["arm_weapon"]
@export var price := 0.0
@export var weight := 1.0
@export var description : String
@export var image : Texture2D
@export var item_size := [3,2]

#PROJECTILE ATTRIBUTES
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
@export var life_time = -1.0
@export var life_time_var = 0.0
@export var random_rotation := false

@export var impact_effect : PackedScene
@export var impact_size := 1.0
@export var hitstop := false
@export var trail : PackedScene

#---TRAILS AND IMPACTS---#
@export var smoke_density = 200
@export var smoke_lifetime = 10.0

#---DAMAGE---#
@export var base_damage := 1
@export var armor_pen := 1
@export var health_mult := 1.0
@export var shield_mult := 1.0
@export var dropoff_modifier := 0.8 
@export var heat_damage := 10.0
@export var status_damage := 0.0
@export var status_type : String
@export var impact_force := 0.0
@export var damage_tags :Array[String] = []

var args
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
var deflection_cooldown = 0.0
var deflected_from_body = null

func _ready():
	LightEffect = get_node("Sprite2D/LightEffect")
	Collision = get_node("CollisionShape2D")

func _physics_process(dt):
	if dying:
		return
	lifetime += dt
	
	# Reduce deflection cooldown
	if deflection_cooldown > 0:
		deflection_cooldown -= dt
		if deflection_cooldown <= 0:
			deflected_from_body = null
	
	# Raycast movement to catch high-speed collisions
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(position, position + (dir*speed*dt))
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		var is_mecha = result.collider.is_in_group("mecha")
		var distance_to_hit = result.position.distance_to(position)
		
		# Ignore hits that are too close (self-collision)
		if distance_to_hit < 15:
			position += dir*speed*dt
		# If we hit a mecha, manually trigger armor check
		elif is_mecha and not has_impacted and deflection_cooldown <= 0:
			position = result.position
			if original_mecha_info and original_mecha_info.has("body") and result.collider != original_mecha_info.body:
				handle_mecha_raycast_hit(result.collider, result.position)
		# During cooldown, pass through mechas
		elif is_mecha and deflection_cooldown > 0:
			position += dir*speed*dt
		else:
			# Stop for non-mecha obstacles (walls, terrain) and die
			position = result.position
			speed = 0
			die(result.collider)  # NEW: Die when hitting terrain
			return  # NEW: Exit immediately
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

# Handle mecha hits detected by raycast
func handle_mecha_raycast_hit(body, collision_point: Vector2):
	# Find which part was hit
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = collision_point
	query.collide_with_bodies = true
	query.collision_mask = self.collision_mask
	
	var results = space_state.intersect_point(query, 10)
	var priority_order = ["head", "left_shoulder", "right_shoulder", "chassis", "core"]
	var best_part = "core"
	var best_priority = 999
	
	for result in results:
		if result.collider == body:
			var part_name = body.get_part_name_from_shape(result.shape)
			var priority = priority_order.find(part_name)
			if priority != -1 and priority < best_priority:
				best_priority = priority
				best_part = part_name
	
	# Armor check
	var pen_result = body.armor_check(
		best_part,
		collision_point,
		dir,
		armor_pen,
		base_damage
	)
	
	# Handle deflection
	if pen_result.has("deflection_type") and pen_result.deflection_type != "":
		handle_deflection(body, collision_point, pen_result.deflection_type, best_part)
		deflection_cooldown = 0.2
		deflected_from_body = body
		
		body.add_decal(0, collision_point, decal_type, Vector2(40, 40))
		emit_signal("bullet_impact", self, impact_effect, false, body)
		
		var kill_timer = Timer.new()
		add_child(kill_timer)
		kill_timer.wait_time = 0.5
		kill_timer.one_shot = true
		kill_timer.timeout.connect(func(): die(body))
		kill_timer.start()
		return
	
	# If penetrated, damage component (if one was selected)
	if pen_result.penetrated:
		# NEW: Only damage component if one was actually selected
		if pen_result.component_name != "":
			body.damage_component(pen_result.part_name, pen_result.component_name, base_damage)
		
		body.add_decal(0, collision_point, decal_type, Vector2(40, 40))
		emit_signal("bullet_impact", self, impact_effect, false, body)
		
		if not is_overtime and impact_force > 0.0:
			body.knockback(impact_force, dir, true)
		
		speed = 0
		has_impacted = true
		die(body)

func _on_Projectile_body_shape_entered(_body_id, body, body_shape_id, _local_shape):
	# This now only handles shields and parries, armor system uses raycast
	if body.is_in_group("mecha"):
		if deflection_cooldown > 0:
			return
		if body.is_shape_id_chassis(body_shape_id):
			return
		
		if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
			# Shield parry
			if body.is_parrying and not is_overtime:
				dir = -dir
				rotation_degrees = rad_to_deg(dir.angle()) + 90
				original_mecha_info.body = body
				original_mecha_info.name = body.mecha_name
				return
			
			# Shield reflect
			if body.is_shielding and not has_impacted:
				var reflect_vector = global_position.direction_to(body.global_position)
				dir = (dir.reflect(reflect_vector.rotated(deg_to_rad(90)))).normalized()
				rotation_degrees = rad_to_deg(dir.angle()) + 90
				original_mecha_info.body = body
				original_mecha_info.name = body.mecha_name
				shield_hit = true
				speed = muzzle_speed
				emit_signal("bullet_impact", self, impact_effect, false, body)
				return
	
	# Hit non-mecha
	if not body.is_in_group("mecha") or\
	(not is_overtime and original_mecha_info and body != original_mecha_info.body):
		if not body.is_in_group("mecha"):
			mech_hit = false
		die(body)

func handle_deflection(body, collision_point: Vector2, deflection_type: String, hit_part: String):
	match deflection_type:
		"bounce":
			var surface_normal = get_deflection_normal(body, collision_point, hit_part)
			var base_reflect = dir.reflect(surface_normal)
			var random_angle = randf_range(-45, 45)
			dir = base_reflect.rotated(deg_to_rad(random_angle)).normalized()
			rotation_degrees = rad_to_deg(dir.angle()) + 90
			
			# Restore speed if it was zeroed
			if speed < muzzle_speed * 0.6:
				speed = muzzle_speed * 0.6
			else:
				speed *= 0.6
			
			position += surface_normal * 50
			has_impacted = false
			
		"glancing":
			var surface_normal = get_deflection_normal(body, collision_point, hit_part)
			var base_reflect = dir.reflect(surface_normal)
			var random_angle = randf_range(-15, 15)
			dir = base_reflect.rotated(deg_to_rad(random_angle)).normalized()
			rotation_degrees = rad_to_deg(dir.angle()) + 90
			
			# Restore speed if it was zeroed
			if speed < muzzle_speed * 0.85:
				speed = muzzle_speed * 0.85
			else:
				speed *= 0.85
			
			position += surface_normal * 50
			has_impacted = false

func get_deflection_normal(body, collision_point: Vector2, hit_part: String) -> Vector2:
	var collision_shape = body.get_collision_shape_for_part(hit_part)
	if collision_shape:
		return body.get_surface_normal_at_point(collision_point, collision_shape)
	else:
		return (collision_point - body.global_position).normalized()

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

func change_scaling(sc):
	var vec = Vector2(sc,sc)
	$Sprite2D.scale *= vec
	$CollisionShape2D.scale *= vec

func instance_trail():
	emit_signal("create_trail", self, trail)
