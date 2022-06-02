extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

export (SIDE) var side
export(String, "free", "tank", "relative") var movement_type = "free"
export var max_speed = 500
export var move_acc = 50
export var friction = 0.1
export var rotation_acc = 5.0


func get_image():
	return $Legs.texture


func get_sub():
	return $LegsSub.texture


func get_glow():
	return $LegsGlow.texture


func get_collision():
	return $Collision.polygon
