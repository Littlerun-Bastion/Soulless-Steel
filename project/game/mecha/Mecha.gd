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
	else:
		arm_weapon_right = part_data
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
