extends KinematicBody2D
class_name Mecha

enum SIDE {LEFT, RIGHT}

const ARM_WEAPON_INITIAL_ROT = 9

signal create_projectile
signal took_damage
signal died

var max_hp = 10
var hp = 10

var movement_type = "free"
var velocity = Vector2()
var max_speed = 200
var friction = 0.1
var move_acc = 50
var rotation_acc = 5

var arm_weapon_left = null
var arm_weapon_right = null
var shoulder_weapon_left = null
var shoulder_weapon_right = null
var head = null

func set_max_life(value):
	max_hp = value
	hp = max_hp


func take_damage(amount):
	hp = max(hp - amount, 0)
	
	emit_signal("took_damage", self)
	
	if hp <= 0:
		die()


func die():
	emit_signal("died", self)
	queue_free()


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
		node.texture = null
		return
	
	var part_data = PartManager.get_part("arm_weapon", part_name)
	if side == SIDE.LEFT:
		arm_weapon_left = part_data
		node.rotation_degrees = -ARM_WEAPON_INITIAL_ROT
	else:
		arm_weapon_right = part_data
		node.rotation_degrees = ARM_WEAPON_INITIAL_ROT
	node.texture = part_data.image
	node.set_shooting_pos(part_data.shooting_pos)


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
		node.texture = null
		return
	
	var part_data = PartManager.get_part("shoulder_weapon", part_name)
	if side == SIDE.LEFT:
		shoulder_weapon_left = part_data
	else:
		shoulder_weapon_right = part_data
	node.texture = part_data.image
	node.set_shooting_pos(part_data.shooting_pos)


func set_core(part_name):
	var part_data = PartManager.get_part("core", part_name)
	$Core.texture = part_data.image


func set_head(part_name):
	var part_data = PartManager.get_part("head", part_name)
	$Head.texture = part_data.image
	head = part_data


func set_shoulder(part_name, side):
	var part_data = PartManager.get_part("shoulder", part_name)
	var node
	if side == SIDE.LEFT:
		node = $LeftShoulder
	elif side == SIDE.RIGHT:
		node = $RightShoulder
	else:
		push_error("Not a valid side: " + str(side))
	
	node.texture = part_data.image

#MOVEMENT METHODS

func apply_movement(dt, direction):
	if movement_type == "free":
		if direction.length() > 0:
			velocity = lerp(velocity, direction.normalized() * max_speed, move_acc*dt)
		else:
			velocity = lerp(velocity, Vector2.ZERO, friction)
		
		velocity = move_and_slide(velocity)
	elif movement_type == "tank":
		pass
	else:
		push_error("Not a valid movement type: " + str(movement_type))


func apply_rotation(dt, target_pos, stand_still):
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
	var target_rot = fmod(rad2deg(origin.angle_to_point(target_pos)) + 270, 360)
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

#COMBAT METHODS

func shoot(type):
	var node
	var weapon_ref
	if type == "left_arm_weapon":
		node = $ArmWeaponLeft
		weapon_ref = arm_weapon_left
	elif type ==  "right_arm_weapon":
		node = $ArmWeaponRight
		weapon_ref = arm_weapon_right
	elif type == "left_shoulder_weapon":
		node = $ShoulderWeaponLeft
		weapon_ref = shoulder_weapon_left
	elif type ==  "right_shoulder_weapon":
		node = $ShoulderWeaponRight
		weapon_ref = shoulder_weapon_right
	else:
		push_error("Not a valid type of weapon to shoot: " + str(type))
	
	if not node.can_shoot():
		return
	node.add_time(weapon_ref.fire_rate) 
	
	emit_signal("create_projectile", self, 
				{
					"weapon_data": weapon_ref.projectile,
					"pos": node.get_shoot_position(),
					"dir": node.get_direction(weapon_ref.bullet_accuracy_margin),
					"damage_mod": weapon_ref.damage_modifier,
				})
	
	apply_recoil(type, weapon_ref.recoil_force)


func apply_recoil(type, recoil):
	var rotation = recoil
	if "left" in type:
		rotation *= -1
	rotation_degrees += rotation
