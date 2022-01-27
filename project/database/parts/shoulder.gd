extends Node

enum SIDE {LEFT, RIGHT}

export (SIDE) var side


func get_image():
	return $Shoulder.texture


func get_collision():
	return $Collision.polygon
