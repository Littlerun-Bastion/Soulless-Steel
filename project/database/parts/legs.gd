extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export (SIDE) var side
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



func get_image():
	return $Chassis.texture


func get_sub():
	return $ChassisSub.texture


func get_glow():
	return $ChassisGlow.texture


func get_collision():
	return $Collision.polygon
