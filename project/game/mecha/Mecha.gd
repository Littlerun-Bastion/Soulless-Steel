extends KinematicBody2D
class_name Mecha

enum SIDE {LEFT, RIGHT}

const ARM_WEAPON_INITIAL_ROT = 9

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


func set_core(part_name):
	var part_data = PartManager.get_part("core", part_name)
	$Core.texture = part_data.image


func set_head(part_name):
	var part_data = PartManager.get_part("head", part_name)
	$Head.texture = part_data.image


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
	for data in [[$ArmWeaponLeft, arm_weapon_left], [$ArmWeaponRight, arm_weapon_right]]:
		var node = data[0]
		var arm_ref = data[1]
		var actual_rot = node.rotation_degrees + rotation_degrees
		node.rotation_degrees += get_target_rotation_diff(dt, node.global_position, target_pos, actual_rot, arm_ref.rotation_acc)
		node.rotation_degrees = clamp(node.rotation_degrees, -arm_ref.rotation_range, arm_ref.rotation_range)


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

func shoot():
	pass
