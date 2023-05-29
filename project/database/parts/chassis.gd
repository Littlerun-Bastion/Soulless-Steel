extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var is_legs := false
@export var movement_type = "free" # (String, "free", "tank", "relative")
@export var max_speed = 500
@export var move_acc = 1.0
@export var accuracy_modifier = 1.0
@export var friction = 0.1 
@export var rotation_acc = 5.0
@export var trim_acc = 1.0
@export var rotation_range = 10.0
@export var health := 1000.0
@export var move_heat = 35
@export var weight := 300.0
@export var weight_capacity := 1000.0
@export var stability := 1.0
@export var hover_particles := false
@export var tags :Array[String] = ["chassis"]

var part_id

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
