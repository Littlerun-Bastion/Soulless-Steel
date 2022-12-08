extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var is_legs := false
export(String, "free", "tank", "relative") var movement_type = "free"
export var max_speed = 500
export var move_acc = 50
export var accuracy_modifier = 1.0
export var friction = 0.1
export var rotation_acc = 5.0
export var health := 5
export var move_heat = 70
export var has_thrusters = false
export var weight := 300.0
export var weight_capacity := 1000.0



func get_image(side = false):
	if is_legs:
		if side == SIDE.LEFT:
			return $LeftSide/Chassis.texture
		elif side == SIDE.RIGHT:
			return $RightSide/Chassis.texture
		else:
			push_error("Not a valid side:" + str(side))
	else:
		return $SingleSide/Chassis.texture


func get_sub(side = false):
	if is_legs:
		if side == SIDE.LEFT:
			return $LeftSide/ChassisSub.texture
		elif side == SIDE.RIGHT:
			return $RightSide/ChassisSub.texture
		else:
			push_error("Not a valid side:" + str(side))
	else:
		return $SingleSide/ChassisSub.texture


func get_glow(side = false):
	if is_legs:
		if side == SIDE.LEFT:
			return $LeftSide/ChassisGlow.texture
		elif side == SIDE.RIGHT:
			return $RightSide/ChassisGlow.texture
		else:
			push_error("Not a valid side:" + str(side))
	else:
		return $SingleSide/ChassisGlow.texture


func get_collision(side = false):
	if is_legs:
		if side == SIDE.LEFT:
			return $LeftSide/Collision.polygon
		elif side == SIDE.RIGHT:
			return $RightSide/Collision.polygon
		else:
			push_error("Not a valid side:" + str(side))
	else:
		return $SingleSide/Collision.polygon
