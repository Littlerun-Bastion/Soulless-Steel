extends Area2D

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
# Fired by an Entity (a Coyote's carried gun, Coyote.fire_gun): it flies
# through Entities, its shooter and its pack included, as a Spitter's glob
# doesn't hurt them either (AcidGlob). A mecha's round still stops in the
# first Entity it meets.
var _from_entity := false
## How many things the movement ray meets and looks past in one step (walls
## crossed, vehicles that didn't stop it, Entities for an Entity's round, a
## bubble that went down) before the round just flies the rest of the step.
const MAX_HOPS := 32
## How far (px) a round flies before it is removed, when it meets nothing.
@export var max_flight_distance := 20000.0

# The movement ray and the inside-a-mecha check, made once per round (_fly);
# both skip the shooter's body (_skip_shooter).
var _ray: PhysicsRayQueryParameters2D = null
var _point: PhysicsPointQueryParameters2D = null
var _skip: Array[RID] = []

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
	
	if not _fly(dir * speed * dt):
		return

	distance += speed*dt
	# A round that met nothing doesn't fly on for ever.
	if distance >= max_flight_distance:
		queue_free()
		return
	speed = max(speed - (bullet_drag + randf_range(-bullet_drag_var, bullet_drag_var)) * dt, min_speed)
	final_damage = base_damage * (pow(dropoff_modifier, distance/1000))
	if not $LifeTimer.is_stopped():
		modulate.a = min(1.0, ($LifeTimer.time_left/(life_time/4)))


# One step of flight along `step`, on one ray that meets what is in the way
# in order, nearest first:
#   a building wall    costs 1 AP; the round stops where its AP runs out
#   a vehicle          stops it by chance (both by MapSenses.cover_hit)
#   a mecha            a parry, its raised shield, or an armour hit on the
#                      part there (_meet_mecha); in the deflection cooldown
#                      the round flies through mechas
#   an Entity          a hit; an Entity's round flies through Entities
#   anything else      stops it (terrain, a wreck, a device, which is hit)
# The shooter is never in the way (_skip). A round already inside a mecha's
# outline when the step starts (the mecha walked onto it, or the muzzle was
# inside it) meets that mecha where it is. Returns whether the round flew the
# whole step.
func _fly(step: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	if deflection_cooldown <= 0.0 and not has_impacted:
		var inside := _mecha_at(space, position)
		if not inside.is_empty():
			_meet_mecha(inside.collider, position, inside.part)
			return false
	var length_sq := step.length_squared()
	if length_sq < 0.0001:
		return true
	var origin := position
	var skip: Array[RID] = _skip
	_ray.from = position
	_ray.to = position + step
	for _i in MAX_HOPS:
		_ray.exclude = skip
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			break
		var collider = hit.collider
		if MapSenses.is_cover(hit):
			var cover := MapSenses.cover_hit(hit, armor_pen, false, true)
			armor_pen = cover.ap
			if cover.stop != null:
				position = cover.stop - dir * 2.0
				speed = 0
				die(null)
				return false
			_ray.from = hit.position + dir * 0.5
		elif collider is Node and collider.is_in_group("mecha"):
			if deflection_cooldown > 0.0:
				skip = _skipping(skip, hit.rid)
				continue
			var part: String = collider.get_part_name_from_shape(hit.shape)
			# A bubble whose shield went down this frame (its shape goes off
			# at the end of the frame) stops nothing: look past it, from
			# inside the bubble, where the ray doesn't meet it again.
			if part == "shield" and not collider.shield_blocks(position):
				_ray.from = hit.position + dir * 2.0
			else:
				_meet_mecha(collider, hit.position, part)
				return false
		elif _from_entity and collider is Node and collider.is_in_group("entity"):
			skip = _skipping(skip, hit.rid)
			continue
		else:
			position = hit.position
			speed = 0
			hit_entity(collider)
			die(collider)
			return false
		if origin.distance_squared_to(_ray.from) >= length_sq:
			break
	position += step
	return true


# `skip` with `rid` added, as a new array: the round's own _skip stays as it
# is for the next step.
func _skipping(skip: Array[RID], rid: RID) -> Array[RID]:
	var more: Array[RID] = skip.duplicate()
	more.append(rid)
	return more


# The mecha whose outline (a part, not the shield bubble) holds `point`, other
# than the shooter: {"collider", "part"}, or empty.
func _mecha_at(space: PhysicsDirectSpaceState2D, point: Vector2) -> Dictionary:
	_point.position = point
	_point.exclude = _skip
	for result in space.intersect_point(_point, 8):
		var body = result.collider
		if body is Node and body.is_in_group("mecha"):
			var part: String = body.get_part_name_from_shape(result.shape)
			if part != "shield":
				return {"collider": body, "part": part}
	return {}


# The round meets mecha `body` at `point` on `part`: a parry sends it back (a
# chassis can't parry); a raised shield met from outside takes it
# (handle_shield_hit); anything else is an armour hit there
# (handle_mecha_raycast_hit).
func _meet_mecha(body, point: Vector2, part: String) -> void:
	if body.is_parrying and not is_overtime and part != "chassis":
		position = point
		_parried_by(body)
		return
	if not has_impacted and body.shield_blocks(position):
		handle_shield_hit(body, body.shield_entry_point(position, point))
		return
	position = point
	handle_mecha_raycast_hit(body, point)


# A parry sends the round straight back, as the parrying mecha's round: it
# can hit its first shooter now, and never the mecha that sent it back.
func _parried_by(body) -> void:
	dir = -dir
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	original_mecha_info.body = body
	original_mecha_info.name = body.mecha_name
	_skip_shooter(body)


# The ray and the inside check never meet `shooter`.
func _skip_shooter(shooter) -> void:
	_skip = []
	if shooter is CollisionObject2D:
		_skip.append(shooter.get_rid())

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
	_from_entity = mecha is Node and mecha.is_in_group("entity")
	_ray = PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO,
			MapSenses.SHOT_MASK | MapSenses.WALL_MASK | MapSenses.VEHICLE_MASK)
	_point = PhysicsPointQueryParameters2D.new()
	_point.collision_mask = collision_mask
	_skip_shooter(mecha)
	# Hits are the movement ray's (_fly). The Area stays only so others can
	# sense the round (an NPC's NearbyProjectile, to dodge); it watches nothing.
	monitoring = false
	change_scaling(projectile_size)

	part_id = _weapon
	$Sprite2D/LightEffect.modulate.a = light_energy
	if life_time > 0 :
		$LifeTimer.wait_time = life_time + randf_range(-life_time_var, life_time_var)
		$LifeTimer.autostart = true
	
	instance_trail()

# Handle mecha hits detected by raycast
func handle_mecha_raycast_hit(body, collision_point: Vector2):
	FrameSpikeDetector.mark("hit")
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
			var hit_name = body.get_part_name_from_shape(result.shape)
			var priority = priority_order.find(hit_name)
			if priority != -1 and priority < best_priority:
				best_priority = priority
				best_part = hit_name
	
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
		body.add_decal(0, collision_point, decal_type, Vector2(40, 40))
		emit_signal("bullet_impact", self, impact_effect, false, body)
		_deflected_off(body)
		return
	
	# If penetrated, damage component (if one was selected)
	if pen_result.penetrated:
		# Record attribution before damage: a cockpit kill inside
		# damage_component() calls die(), which reads last_damage_source.
		body.last_damage_source = original_mecha_info
		body.last_damage_weapon = part_id
		# NEW: Only damage component if one was actually selected
		if pen_result.component_name != "":
			body.damage_component(pen_result.part_name, pen_result.component_name, base_damage, dir)
		
		body.add_decal(0, collision_point, decal_type, Vector2(40, 40))
		emit_signal("bullet_impact", self, impact_effect, false, body)
		
		if not is_overtime and impact_force > 0.0:
			body.knockback(impact_force, dir, true)
		
		speed = 0
		has_impacted = true
		die(body)
		return

	# Neither through nor off: the armour stopped the round (or the part it
	# met has come off). It ends there.
	speed = 0
	has_impacted = true
	die(body)


# The round meets a raised shield's bubble at `point`, coming from outside it
# (Mecha.shield_check). Deflected, it bounces off the bubble the way it would
# off armour; otherwise it stops there, the SC lost. Neither reaches the hull.
func handle_shield_hit(body, point: Vector2) -> void:
	var result: String = body.shield_check(position, armor_pen, base_damage)
	position = point
	shield_hit = true
	if result == "deflect":
		handle_deflection(body, point, "bounce", "shield")
		emit_signal("bullet_impact", self, impact_effect, false, body)
		_deflected_off(body)
		return
	speed = 0
	has_impacted = true
	die(body)


# After a bounce: mechas don't stop the round for a moment, and it ends a
# little later wherever it is.
func _deflected_off(body) -> void:
	deflection_cooldown = 0.2
	deflected_from_body = body
	var kill_timer = Timer.new()
	add_child(kill_timer)
	kill_timer.wait_time = 0.5
	kill_timer.one_shot = true
	# Named method + bind, NOT a lambda: a lambda capturing `body` makes
	# the engine print "Lambda capture at index 0 was freed" whenever the
	# mecha dies during the 0.5s window — Godot validates captures before
	# our guard can run. Bound args skip that check; is_instance_valid
	# handles the freed case. Self-safety is structural: the timer is our
	# child, so if this projectile is freed the timer never fires.
	kill_timer.timeout.connect(_on_deflect_kill_timeout.bind(body))
	kill_timer.start()


# Entities (creatures) have no armour parts: one hit, armour pen against their
# armour rating. Safe to call with anything; only Entities and devices (wards,
# drones: Device) are hurt, once.
func hit_entity(body) -> void:
	if has_impacted or dying or not is_instance_valid(body):
		return
	if not body.is_in_group("entity") and not body.is_in_group("device"):
		return
	has_impacted = true
	mech_hit = true
	body.take_hit(base_damage, armor_pen, dir, original_mecha_info, impact_force)

func handle_deflection(body, collision_point: Vector2, deflection_type: String, hit_part: String):
	match deflection_type:
		"bounce":
			var surface_normal = get_deflection_normal(body, collision_point, hit_part)
			# Off a shield's bubble (its normal points outwards) the round
			# mirrors off the surface and always leaves it, never turning
			# back inside.
			var off_bubble: bool = hit_part == "shield"
			var base_reflect = dir.bounce(surface_normal) if off_bubble else dir.reflect(surface_normal)
			var random_angle = randf_range(-45, 45)
			dir = base_reflect.rotated(deg_to_rad(random_angle)).normalized()
			if off_bubble and dir.dot(surface_normal) < 0.0:
				dir = dir.bounce(surface_normal)
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
	if hit_part == "shield":
		return body.shield_normal(collision_point)
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

# Deflection kill-timer callback. `deflected_body` arrives via bind() and
# may be a freed instance if the mecha died during the 0.5s delay.
func _on_deflect_kill_timeout(deflected_body):
	if is_instance_valid(deflected_body):
		die(deflected_body)
	else:
		queue_free()


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
