extends Node

enum SIDE {LEFT, RIGHT, SINGLE}

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var health := 4500.0
@export var shield := 4500.0
@export var stability := 1.0
@export var rotation_range := 20.0
@export var has_left_shoulder := false 
@export var has_right_shoulder := false 
@export var weight:= 300.0
@export var tags :Array[String] = ["core"]

var part_id

func get_image():
	return $Core.texture


func get_collision():
	return $Collision.polygon


func get_sub():
	return $CoreSub.texture


func get_glow():
	return $CoreGlow.texture


func get_head_port():
	return $HeadPort.texture

func get_headport_offset():
	return $HeadPort.position

func get_head_offset():
	return $HeadOffset.position


func get_shoulder_offset(side):
	if side == SIDE.LEFT:
		return $LeftShoulderOffset.position
	elif side == SIDE.RIGHT:
		return $RightShoulderOffset.position
	else:
		push_error("Not a valid side: " + str(side))


func get_arm_weapon_offset(side):
	if side == SIDE.LEFT:
		return $LeftArmWeaponOffset.position
	elif side == SIDE.RIGHT:
		return $RightArmWeaponOffset.position
	else:
		push_error("Not a valid side: " + str(side))


func get_shoulder_weapon_offset(side):
	if side == SIDE.LEFT:
		return $LeftShoulderWeaponOffset.position
	elif side == SIDE.RIGHT:
		return $RightShoulderWeaponOffset.position
	else:
		push_error("Not a valid side: " + str(side))


func get_chassis_offset(side):
	if side == SIDE.LEFT:
		return $LeftChassisOffset.position
	elif side == SIDE.RIGHT:
		return $RightChassisOffset.position
	else:
		push_error("Not a valid side: " + str(side))
		
func get_overheat_offset(num):
	var node = get_node_or_null("OverheatOffset" + str(num))
	if node:
		return node.position
	
