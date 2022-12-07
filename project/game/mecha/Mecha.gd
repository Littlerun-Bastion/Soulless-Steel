extends KinematicBody2D
class_name Mecha

enum MODES {NEUTRAL, RELOAD, ACTIVATING_LOCK, LOCK}
enum SIDE {LEFT, RIGHT, SINGLE}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

const DECAL = preload("res://game/mecha/Decal.tscn")
const ARM_WEAPON_INITIAL_ROT = 9
const CHASSIS_SPEED = 20
const LOCKON_RETICLE_SIZE = 15

signal create_projectile
signal shoot
signal took_damage
signal died
signal player_kill
signal mecha_extracted

export var speed_modifier = 1.0
export var display_mode = false

onready var NavAgent = $NavigationAgent2D

onready var CoreDecals = $CoreDecals
onready var LeftShoulderDecals = $LeftShoulder/Decals
onready var RightShoulderDecals = $RightShoulder/Decals
onready var MovementAnimation = $MovementAnimation
onready var LockCollision = $LockCollision

onready var Core = $Core
onready var CoreSub = $Core/Sub
onready var CoreGlow = $Core/Glow
onready var Head = $Head
onready var HeadSub = $Head/Sub
onready var HeadGlow = $Head/Glow
onready var HeadPort = $HeadPort
onready var LeftShoulder = $LeftShoulder
onready var RightShoulder = $RightShoulder
#Weapons
onready var LeftArmWeapon = $ArmWeaponLeft
onready var LeftArmWeaponSub = $ArmWeaponLeft/Sub
onready var LeftArmWeaponGlow = $ArmWeaponLeft/Glow
onready var RightArmWeapon = $ArmWeaponRight
onready var RightArmWeaponSub = $ArmWeaponRight/Sub
onready var RightArmWeaponGlow = $ArmWeaponRight/Glow
onready var LeftShoulderWeapon = $ShoulderWeaponLeft
onready var LeftShoulderWeaponSub = $ShoulderWeaponLeft/Sub
onready var LeftShoulderWeaponGlow = $ShoulderWeaponLeft/Glow
onready var RightShoulderWeapon = $ShoulderWeaponRight
onready var RightShoulderWeaponSub = $ShoulderWeaponRight/Sub
onready var RightShoulderWeaponGlow = $ShoulderWeaponRight/Glow
#Chassis
onready var SingleChassisRoot = $Chassis/Single
onready var SingleChassis = $Chassis/Single/Main
onready var SingleChassisSub = $Chassis/Single/Sub
onready var SingleChassisGlow = $Chassis/Single/Glow
onready var LeftChassisRoot = $Chassis/Left
onready var LeftChassis = $Chassis/Left/Main
onready var LeftChassisSub = $Chassis/Left/Sub
onready var LeftChassisGlow = $Chassis/Left/Glow
onready var RightChassisRoot = $Chassis/Right
onready var RightChassis = $Chassis/Right/Main
onready var RightChassisSub = $Chassis/Right/Sub
onready var RightChassisGlow = $Chassis/Right/Glow

var mecha_name = "Mecha Name"
var paused = false
var is_dead = false
var cur_mode = MODES.NEUTRAL
var arena = false

var max_hp = 10
var hp = 10
var max_shield = 10
var shield = 10
var shield_regen_cooldown
var max_energy = 100
var energy = 100
var total_kills = 0
var mecha_heat = 0
var move_heat = 70

var movement_type = "free"
var velocity = Vector2()
var moving = false
var max_speed = 500
var friction = 0.1
var move_acc = 50
var rotation_acc = 5

var locking_targets = []
var locking_to = false
var locked_to = false

var arm_weapon_left = null
var arm_weapon_right = null
var shoulders = null
var shoulder_weapon_left = null
var shoulder_weapon_right = null
var head = null
var core = null
var generator = null
var chipset = null
var thruster = null
var chassis_single = null
var chassis_left = null
var chassis_right = null


func _ready():
	for node in [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort,
				 LeftShoulder, RightShoulder,\
				 LeftArmWeapon, LeftArmWeaponSub, LeftArmWeaponGlow,\
				 RightArmWeapon, RightArmWeaponSub, RightArmWeaponGlow,\
				 LeftShoulderWeapon, LeftShoulderWeaponSub, LeftShoulderWeaponGlow,\
				 RightShoulderWeapon, RightShoulderWeaponSub, RightShoulderWeaponGlow,\
				 SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
				 RightChassis, RightChassisSub, RightChassisGlow]:
		node.material = CoreSub.material.duplicate(true)


func _physics_process(dt):
	if paused:
		return
	
	#Handle shield
	if generator and shield < max_shield:
		shield_regen_cooldown = max(shield_regen_cooldown - dt, 0.0)
		if shield_regen_cooldown <= 0:
			shield = min(shield + generator.shield_regen_speed*dt, max_shield)
	
	#Handle collisions with other mechas and movement
	if not is_stunned():
		var all_collisions = []
		for i in get_slide_count():
			all_collisions.append(get_slide_collision(i))
		
		var collided = false
		for collision in all_collisions:
			if collision and collision.collider.is_in_group("mecha"):
				collided = true
				var mod = 2.0
				var rand = rand_range(-PI/8, PI/8)
				var dir = (global_position - collision.collider.global_position).rotated(rand)
				apply_movement(mod*dt, dir)
		if collided:
			stun(0.1)
	else:
		apply_movement(dt, Vector2())
	
	if moving and not MovementAnimation.is_playing():
		MovementAnimation.play("Walking")
	elif not moving and velocity.length() <= 2.0:
		MovementAnimation.stop()
	
	update_heat(dt)
	
	update_locking(dt)
	
	if get_locked_to():
		var target_pos = locked_to.global_position
		apply_rotation_by_point(dt, target_pos, false)
	

func is_player():
	return mecha_name == "Player"


func set_pause(value):
	paused = value


func set_speed(_max_speed, _move_acc, _friction, _rotation_acc):
	max_speed = _max_speed
	friction = _friction
	rotation_acc = _rotation_acc
	move_acc = min(_move_acc, 100.0)
	MovementAnimation.playback_speed = max_speed/200
	var animation = MovementAnimation.get_animation("Walking")
	var track = 0 #animation.find_track("Mecha:speed_modifier")
	animation.track_set_key_value(track, 2, move_acc/100.0)
	animation.track_set_key_value(track, 5, move_acc/100.0)


func update_max_life_from_parts():
	var value = 0
	if core:
		value += core.health
	if head:
		value += head.health
	#Check chassis
	if chassis_single:
		value += chassis_single.health
	elif chassis_right:
		value += chassis_right.health
	elif chassis_left:
		value += chassis_left.health
	
	set_max_life(value)


func update_max_shield_from_parts():
	var value = 0
	if core:
		value += core.shield
	if generator:
		value += generator.shield
	#Check shoulders
	if shoulders:
		value += shoulders.shield
	
	set_max_shield(value)


func set_max_life(value):
	max_hp = value
	hp = max_hp


func set_max_shield(value):
	max_shield = value
	shield = max_shield


func set_max_energy(value):
	max_energy = value
	energy = max_energy


func take_damage(amount, source_info, weapon_name := "Test", calibre := CALIBRE_TYPES.SMALL):
	if is_dead:
		return
	
	if amount > 0 and generator:
		shield_regen_cooldown = generator.shield_regen_delay
	var temp_shield = shield
	shield = max(shield - amount, 0)
	amount = max(amount - temp_shield, 0)
	
	hp = max(hp - amount, 0)
	if shield <= 0:
		select_impact(calibre, false)
	else:
		select_impact(calibre, true)
	emit_signal("took_damage", self)
	if hp <= 0:
		AudioManager.play_sfx("final_explosion", global_position, null, null, 1.25, 10000)
		die(source_info, weapon_name)


func die(source_info, weapon_name):
	is_dead = true
	TickerManager.new_message({
		"type": "mecha_died",
		"source": source_info.name,
		"self": self.mecha_name,
		"weapon_name": weapon_name,
		})
	if source_info.name == "Player":
		emit_signal("player_kill")
	emit_signal("died", self)


#Return all parts that should be generated when mecha dies
func get_scrapable_parts():
	var scraps = []
	for node in [LeftShoulder, RightShoulder, Core, LeftChassis, RightChassis]:
		if node.texture:
			scraps.append(node)
	return scraps


func is_shape_id_chassis(id):
	return shape_owner_get_owner(shape_find_owner(id)) == $ChassisSingleCollision or\
		   shape_owner_get_owner(shape_find_owner(id)) == $ChassisLeftCollision or\
		   shape_owner_get_owner(shape_find_owner(id)) == $ChassisRightCollision


func get_shape_from_id(id):
	return shape_owner_get_owner(shape_find_owner(id))


func add_decal(id, decal_position, type, size):
	var shape = get_shape_from_id(id)
	var decals_node
	if shape == $CoreCollision:
		decals_node = CoreDecals
	elif shape == $LeftShoulderCollision:
		decals_node = LeftShoulderDecals
	elif shape == $RightShoulderCollision:
		decals_node = RightShoulderDecals
	else:
		push_error("Not a valid shape id: " + str(id))
	var decal = DECAL.instance()
	
	#Transform global position into local position
	var final_pos = decal_position-decals_node.global_position
	var trans = decals_node.global_transform
	final_pos = final_pos.rotated(-trans.get_rotation())
	final_pos /= trans.get_scale()
	final_pos *= rand_range(.6,.9) #Random depth for decal on mecha
	decals_node.add_child(decal)
	decal.setup(type, size, final_pos)


func update_heat(dt):
	#Main Mecha Heat
	if display_mode == true:
		mecha_heat = 100
		return
	if generator:
		mecha_heat = max(mecha_heat - generator.heat_dispersion*dt, 0)
		for weapon in [LeftArmWeapon, RightArmWeapon, LeftShoulderWeapon, RightShoulderWeapon]:
			weapon.update_heat(generator.heat_dispersion, dt)
	for node in [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort, LeftShoulder, RightShoulder,\
				 SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
				 RightChassis, RightChassisSub, RightChassisGlow]:
		node.material.set_shader_param("heat", mecha_heat) 


#PARTS SETTERS

func set_arm_weapon(part_name, side):
	var node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
	else:
		push_error("Not a valid side: " + str(side))

	if not part_name:
		if side == SIDE.LEFT:
			arm_weapon_left = null
		else:
			arm_weapon_right = null
		node.set_images(null, null, null)
		return
	
	var part_data = PartManager.get_part("arm_weapon", part_name)
	if side == SIDE.LEFT:
		arm_weapon_left = part_data
		node.rotation_degrees = -ARM_WEAPON_INITIAL_ROT
	else:
		arm_weapon_right = part_data
		node.rotation_degrees = ARM_WEAPON_INITIAL_ROT
	node.set_images(part_data.get_image(), part_data.get_sub(), part_data.get_glow())
	node.set_offsets(-part_data.get_attach_pos())
	if core:
		node.position = core.get_arm_weapon_offset(side)
	node.set_shooting_pos(part_data.get_shooting_pos())
	node.setup(part_data)


func set_shoulder_weapon(part_name, side):
	var node
	if side == SIDE.LEFT:
		node = $ShoulderWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ShoulderWeaponRight
	else:
		push_error("Not a valid side: " + str(side))


	if not part_name:
		if side == SIDE.LEFT:
			shoulder_weapon_left = null
		else:
			shoulder_weapon_right = null
		node.set_images(null, null, null)
		return
	
	var part_data = PartManager.get_part("shoulder_weapon", part_name)
	if side == SIDE.LEFT:
		shoulder_weapon_left = part_data
	else:
		shoulder_weapon_right = part_data
	node.set_images(part_data.get_image(), part_data.get_sub(), part_data.get_glow())
	node.set_offsets(-part_data.get_attach_pos())
	if core:
		node.position = core.get_shoulder_weapon_offset(side)
	node.set_shooting_pos(part_data.get_shooting_pos())
	node.setup(part_data)


func set_core(part_name):
	var part_data = PartManager.get_part("core", part_name)
	Core.texture = part_data.get_image()
	$CoreCollision.polygon = part_data.get_collision()
	core = part_data
	if core.get_head_port() != null:
		$HeadPort.texture = core.get_head_port()
		$HeadPort.position = core.get_head_port_offset()
	else:
		$HeadPort.texture = null
	CoreSub.texture = core.get_sub()
	CoreGlow.texture = core.get_glow()
	update_max_life_from_parts()
	update_max_shield_from_parts()


func set_generator(part_name):
	var part_data = PartManager.get_part("generator", part_name)
	generator = part_data
	update_max_shield_from_parts()


func set_chipset(part_name):
	var part_data = PartManager.get_part("chipset", part_name)
	chipset = part_data


func set_thruster(part_name):
	var part_data = PartManager.get_part("thruster", part_name)
	thruster = part_data


func set_chassis(part_name, side := SIDE.LEFT):
	if not part_name:
		remove_chassis("single")
		remove_chassis("pair")
		movement_type = "free"
		return

	var main; var sub; var glow; var collision
	var pos = false
	var part_data = PartManager.get_part("chassis", part_name)
	match side:
		SIDE.RIGHT:
			main = RightChassis; sub = RightChassisSub; glow = RightChassisGlow
			collision = $ChassisRightCollision
			if core:
				pos = core.get_chassis_offset(SIDE.RIGHT)
			chassis_right = part_data
			remove_chassis("single")
		SIDE.LEFT:
			main = LeftChassis; sub = LeftChassisSub; glow = LeftChassisGlow
			collision = $ChassisLeftCollision
			if core:
				pos = core.get_chassis_offset(SIDE.LEFT)
			chassis_left = part_data
			remove_chassis("single")
		SIDE.SINGLE:
			main = SingleChassis; sub = SingleChassisSub; glow = SingleChassisGlow
			collision = $ChassisSingleCollision
			chassis_single = part_data
			remove_chassis("pair")
	if pos:
		main.position = pos
		sub.position = pos
		glow.position = pos
		collision.position = pos

	main.texture = part_data.get_image()
	sub.texture = part_data.get_sub()
	glow.texture = part_data.get_glow()
	collision.polygon = part_data.get_collision()
	movement_type = part_data.movement_type
	move_heat = part_data.move_heat
	set_speed(part_data.max_speed, part_data.move_acc, part_data.friction, part_data.rotation_acc)
	update_max_life_from_parts()

func remove_chassis(type):
	if type == "single":
		chassis_single = null
		SingleChassis.texture = null
		SingleChassisGlow.texture = null
		SingleChassisSub.texture = null
		$ChassisSingleCollision.polygon = []
	elif type == "pair":
		chassis_left = null
		LeftChassis.texture = null
		LeftChassisGlow.texture = null
		LeftChassisSub.texture = null
		$ChassisLeftCollision.polygon = []
		chassis_right = null
		RightChassis.texture = null
		RightChassisGlow.texture = null
		RightChassisSub.texture = null
		$ChassisRightCollision.polygon = []


func set_head(part_name):
	var part_data = PartManager.get_part("head", part_name)
	Head.texture = part_data.get_image()
	HeadSub.texture = part_data.get_sub()
	HeadGlow.texture = part_data.get_glow()
	head = part_data
	if core:
		Head.position = core.get_head_port_offset()
	update_max_life_from_parts()


func set_shoulders(part_name):
	var part_data = PartManager.get_part("shoulders", part_name)
	shoulders = part_data
	if core:
		$LeftShoulder.position = core.get_shoulder_offset(SIDE.LEFT)
		$LeftShoulderCollision.position = core.get_shoulder_offset(SIDE.LEFT)
		$RightShoulder.position = core.get_shoulder_offset(SIDE.RIGHT)
		$RightShoulderCollision.position = core.get_shoulder_offset(SIDE.RIGHT)
	else:
		push_error("No core for putting on shoulders.")

	$LeftShoulder.texture = part_data.get_image(SIDE.LEFT)
	$RightShoulder.texture = part_data.get_image(SIDE.RIGHT)
	$LeftShoulderCollision.polygon = part_data.get_collision(SIDE.LEFT)
	$RightShoulderCollision.polygon = part_data.get_collision(SIDE.RIGHT)
	update_max_shield_from_parts()

#ATTRIBUTE METHODS

func get_max_hp():
	return max_hp


func get_stat(stat_name):
	var total_stat = 0.0
	var parts = [arm_weapon_left, arm_weapon_right, shoulders,\
				 shoulder_weapon_left, shoulder_weapon_right,\
				 head, core, generator, chipset, thruster,\
				 chassis_single, chassis_left, chassis_right]
	for part in parts:
		if part and part.get(stat_name):
			total_stat += part[stat_name]
	return float(total_stat)
	

func get_weapon_part(part_name):
	if part_name == "arm_weapon_left":
		if arm_weapon_left:
			return $ArmWeaponLeft
	elif part_name == "arm_weapon_right":
		if arm_weapon_right:
			return $ArmWeaponRight
	elif part_name == "shoulder_weapon_left":
		if shoulder_weapon_left:
			return $ShoulderWeaponLeft
	elif part_name == "shoulder_weapon_right":
		if shoulder_weapon_right:
			return $ShoulderWeaponRight
	else:
		push_error("Not a valid weapon part name: " + str(part_name))
	
	return false


func get_clip_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.clip_ammo
	return false


func get_clip_size(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.clip_size
	return false


func get_total_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.total_ammo - (get_clip_size(part_name) - get_clip_ammo(part_name))
	return false
	
func get_max_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.max_ammo
	return false

func get_ammo_cost(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.ammo_cost
	return false

func set_ammo(part_name, target_val):
	var part = get_weapon_part(part_name)
	if typeof(target_val) == TYPE_INT:
		part.total_ammo = target_val

#MOVEMENT METHODS

func get_direction_from_vector(dir_vec, eight_directions = false):
	var margin = PI/8
	var angle = dir_vec.angle()
	if angle < 0:
		angle += 2*PI
	if not eight_directions:
		if angle > PI/4 - margin and angle <= 3*PI/4 + margin:
			return "down"
		if angle > 3*PI/4 - margin and angle <= 5*PI/4 + margin:
			return "left"
		if angle > 5*PI/4 - margin and angle <= 7*PI/4 + margin:
			return "up"
		if angle > 7*PI/4 - margin or angle <= PI/4 + margin:
			return "right"
	else:
		if angle > PI/2 - margin and angle <= PI/2 + margin:
			return "down"
		if angle >  PI/2 + PI/4 - margin and angle <= PI/2 + PI/4 + margin:
			return "downleft"
		if angle > PI - margin and angle <= PI + margin:
			return "left"
		if angle >  PI + PI/4 - margin and angle <= PI + PI/4 + margin:
			return "upleft"
		if angle > 3*PI/2 - margin and angle <= 3*PI/2 + margin:
			return "up"
		if angle > 3*PI/2 + PI/4 - margin and angle <= 3*PI/2 + PI/4 + margin:
			return "upright"
		if angle > 3*PI/2 + PI/4 + margin or angle <= margin:
			return "right"
		if angle > PI/4 - margin or angle <= PI/4 + margin:
			return "downright"


func move(vec):
	if is_player():
		NavAgent.set_velocity(vec)
		velocity = move_and_slide(vec)
	else:
		NavAgent.set_velocity(vec)


func apply_movement(dt, direction):
	if movement_type == "free":
		if direction.length() > 0:
			moving = true
			velocity = lerp(velocity, direction.normalized() * max_speed, move_acc*dt)
			mecha_heat = min(mecha_heat + move_heat*dt, 100)
		else:
			moving = false
			velocity = lerp(velocity, Vector2.ZERO, friction)
		move(velocity*speed_modifier)
	elif movement_type == "relative":
		if direction.length() > 0:
			moving = true
			match get_direction_from_vector(direction, true):
				"down":
					direction = Vector2(0,1).rotated(deg2rad(rotation_degrees))
				"downleft":
					direction = Vector2(0,1).rotated(deg2rad(rotation_degrees))
					direction += -Vector2(1,0).rotated(deg2rad(rotation_degrees))
				"left":
					direction = -Vector2(1,0).rotated(deg2rad(rotation_degrees))
				"upleft":
					direction = -Vector2(0,1).rotated(deg2rad(rotation_degrees))
					direction += -Vector2(1,0).rotated(deg2rad(rotation_degrees))
				"up":
					direction = -Vector2(0,1).rotated(deg2rad(rotation_degrees))
				"upright":
					direction = -Vector2(0,1).rotated(deg2rad(rotation_degrees))
					direction += Vector2(1,0).rotated(deg2rad(rotation_degrees))
				"right":
					direction = Vector2(1,0).rotated(deg2rad(rotation_degrees))
				"downright":
					direction = Vector2(0,1).rotated(deg2rad(rotation_degrees))
					direction += Vector2(1,0).rotated(deg2rad(rotation_degrees))
			velocity = lerp(velocity, direction.normalized() * max_speed, move_acc*dt)
			mecha_heat = min(mecha_heat + move_heat*dt, 100)
		else:
			moving = false
			velocity = lerp(velocity, Vector2.ZERO, friction)
		move(velocity*speed_modifier)
	elif movement_type == "tank":
		if direction.length() > 0:
			moving = false
			match get_direction_from_vector(direction):
				"down":
					direction = Vector2(0,1).rotated(deg2rad(rotation_degrees))
					moving = true
				"left":
					apply_rotation_by_direction(dt, "counter")
				"up":
					direction = -Vector2(0,1).rotated(deg2rad(rotation_degrees))
					moving = true
				"right":
					apply_rotation_by_direction(dt, "clock")

			if not moving:
				velocity = lerp(velocity, Vector2.ZERO, friction)
			else:
				velocity = lerp(velocity, direction.normalized() * max_speed, move_acc*dt)
				mecha_heat = min(mecha_heat + move_heat*dt, 100)
			move(velocity)

		else:
			velocity = lerp(velocity, Vector2.ZERO, friction)
			move(velocity*speed_modifier)
	else:
		push_error("Not a valid movement type: " + str(movement_type))
	update_chassis_visuals(dt)

#Rotates solely the body given a direction ('clock' or 'counter'clock wise)
func apply_rotation_by_direction(dt, direction):
	if direction == "clock":
		rotation_degrees += 90*rotation_acc*dt
	elif direction == "counter":
		rotation_degrees -= 90*rotation_acc*dt
	else:
		push_error("Not a valid direction: " + str(direction))


func apply_rotation_by_point(dt, target_pos, stand_still):
	#Rotate Body
	if not stand_still:
		rotation_degrees += get_target_rotation_diff(dt, global_position, target_pos, rotation_degrees, rotation_acc)
	
	
	#Rotate Arm Weapons
	for data in [[$ArmWeaponLeft, arm_weapon_left], [$ArmWeaponRight, arm_weapon_right],\
				 [$Head, head]]:
		var node_ref = data[1]
		if node_ref:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_target_rotation_diff(dt, node.global_position, target_pos, actual_rot, node_ref.rotation_acc)
			node.rotation_degrees = clamp(node.rotation_degrees, -node_ref.rotation_range, node_ref.rotation_range)
	

func get_target_rotation_diff(dt, origin, target_pos, cur_rotation, acc):
	var target_rot = rad2deg(origin.angle_to_point(target_pos)) + 270
	var diff = target_rot - cur_rotation
	if diff > 180:
		diff -= 360
	elif diff < -180:
		diff += 360
	
	#Rotate properly clock or counter-clockwise fastest to target rotation
	if diff > 0:
		return abs(diff)*acc*dt
	else:
		return -abs(diff)*acc*dt


func knockback(pos, strength, should_rotate = true):
	apply_movement(sqrt(strength)*2/get_stat("weight"), global_position - pos)
	if should_rotate:
		apply_rotation_by_point(sqrt(strength)*2/get_stat("weight"), pos, false)


func update_chassis_visuals(dt):
	var angulation = 25
	if chassis_left or chassis_right:
		var rot_vec = Vector2(1, 0).rotated(deg2rad(rotation_degrees))
		var vel_vec = velocity
		var left_target_angle
		var right_target_angle
		if velocity.length() > 5:
			var angle = vel_vec.angle_to(rot_vec)
			var dot = vel_vec.dot(rot_vec)
			if angle >= PI/2 - PI/4 and angle <= PI/2 + PI/4: #Forward
				left_target_angle = angulation
				right_target_angle = -angulation
			elif angle <= -PI/2 + PI/4 and angle >= -PI/2 - PI/4: #Backward
				left_target_angle = -angulation
				right_target_angle = angulation
			elif dot > 0: #Right
				left_target_angle = angulation
				right_target_angle = angulation
			else: #Left
				left_target_angle = -angulation
				right_target_angle = -angulation
		else: #Neutral
			left_target_angle = 0
			right_target_angle = 0
		
		for child in LeftChassisRoot.get_children():
			child.rotation_degrees = lerp(child.rotation_degrees, left_target_angle,\
										  dt*CHASSIS_SPEED)
		for child in RightChassisRoot.get_children():
			child.rotation_degrees = lerp(child.rotation_degrees, right_target_angle,\
										  dt*CHASSIS_SPEED)


#COMBAT METHODS

func shoot(type, is_auto_fire = false):
	var node
	var weapon_ref
	if type == "arm_weapon_left":
		node = $ArmWeaponLeft
		weapon_ref = arm_weapon_left
	elif type ==  "arm_weapon_right":
		node = $ArmWeaponRight
		weapon_ref = arm_weapon_right
	elif type == "shoulder_weapon_left":
		node = $ShoulderWeaponLeft
		weapon_ref = shoulder_weapon_left
	elif type ==  "shoulder_weapon_right":
		node = $ShoulderWeaponRight
		weapon_ref = shoulder_weapon_right
	else:
		push_error("Not a valid type of weapon to shoot: " + str(type))
	
	var amount = min(weapon_ref.number_projectiles, get_clip_ammo(type))
	amount = max(amount, 1) #Tries to shoot at least 1 projectile
	
	
	if not node.can_shoot(amount):
		if is_player() and node.clip_ammo <= 0 and not is_auto_fire:
			AudioManager.play_sfx("no_ammo", global_position)
		return
	
	node.shoot(amount)
	
	var variation = weapon_ref.bullet_spread/float(amount + 1) 
	var angle_offset = -weapon_ref.bullet_spread /2
	for _i in range(amount):
		angle_offset += variation
		emit_signal("create_projectile", self, 
					{
						"weapon_data": weapon_ref.projectile,
						"weapon_name": weapon_ref.part_name,
						"pos": node.get_shoot_position(),
						"dir": node.get_direction(angle_offset, weapon_ref.bullet_accuracy_margin),
						"damage_mod": weapon_ref.damage_modifier,
						"delay": rand_range(0, weapon_ref.bullet_spread_delay),
					})
	apply_recoil(type, weapon_ref.recoil_force)
	emit_signal("shoot")

func apply_recoil(type, recoil):
	var rotation = recoil*300/get_stat("weight")
	if "left" in type:
		rotation *= -1
	rotation_degrees += rotation


func is_stunned():
	return not $StunTimer.is_stopped()


func stun(time):
	$StunTimer.wait_time = time
	$StunTimer.start()


#LOCK ON METHODS

func get_lock_area():
	return LockCollision


func update_locking(dt):
	if cur_mode == MODES.LOCK:
		#Update locking targets
		#For now, check only using mouse, assuming its only the player that locks
		var could_lock = []
		var mouse_pos = get_global_mouse_position()
		for area in arena.get_lock_areas():
			var mecha = area.get_parent()
			var a_radius = area.get_node("CollisionShape2D").shape.radius
			if  mecha != self and\
			   mouse_pos.distance_to(area.global_position) <= chipset.lock_on_reticle_size + a_radius:
				could_lock.append(area.get_parent())
		
		for target in locking_targets:
			if not could_lock.has(target.mecha):
				locking_targets.erase(target)
			else:
				#Erase from list so we don't duplicate later
				could_lock.erase(target.mecha)
		#What remains are new locks
		for mecha in could_lock:
			locking_targets.append({
				"progress": 0,
				"mecha": mecha,
			})
		
		locking_to = false
		var min_dist = INF
		for target in locking_targets:
			if not locking_to:
				locking_to = target
				min_dist = global_position.distance_to(target.mecha.global_position)
			else:
				var dist = global_position.distance_to(target.mecha.global_position)
				if dist < min_dist:
					locking_to = target
					min_dist = dist
		if locking_to:
			locking_to.progress = min(locking_to.progress + dt*chipset.lock_on_speed, 1.0)
			if locking_to.progress >= 1.0:
				locked_to = locking_to.mecha


func get_locking_to():
	#Check if mecha has died
	if locking_to and not weakref(locking_to.mecha).get_ref():
		locking_to = false
	
	return locking_to


func get_locked_to():
	#Check if mecha has died
	if locked_to and not weakref(locked_to).get_ref():
		locked_to = false
	return locked_to


func _on_enter_lock_mode():
	locking_targets = []
	locked_to = false
	cur_mode = MODES.LOCK


# MISC METHODS

func play_step_sound(is_left := true):
	if mecha_name != "Player" or not moving:
		return
	var pitch
	if is_left:
		pitch = rand_range(.7, .72)
	else:
		pitch = rand_range(.95, .97)
	
	var volume = min(pow(velocity.length(), 1.3)/300.0 - 23.0, -5.0)
	AudioManager.play_sfx("robot_step", global_position, pitch, volume)

func extracting():
	$ExtractTimer.start()


func _on_ExtractTimer_timeout():
	if self.name == "Player":
		emit_signal("mecha_extracted", self)
	else:
		emit_signal("died", self)


func cancel_extract():
	$ExtractTimer.stop()
	$ExtractTimer.wait_time = 5

func select_impact(calibre, is_shield):
	var sfx_idx
	match calibre:
		CALIBRE_TYPES.LARGE:
			if is_shield:
				sfx_idx = "large_shield_impact" + str((randi()%2) + 1)
			else:
				sfx_idx = "large_impact" + str((randi()%2) + 1)
		CALIBRE_TYPES.MEDIUM:
			if is_shield:
				sfx_idx = "small_shield_impact" + str((randi()%3) + 1)
			else:
				sfx_idx = "medium_impact" + str((randi()%2) + 1)
		CALIBRE_TYPES.SMALL:
			if is_shield:
				sfx_idx = "small_shield_impact" + str((randi()%3) + 1)
			else:
				sfx_idx = "small_impact" + str((randi()%2) + 1)
		CALIBRE_TYPES.FIRE:
			sfx_idx = false
		_:
			push_error("Not a valid calibre type:" + str(calibre))
	
	if sfx_idx:
		AudioManager.play_sfx(sfx_idx, global_position)

