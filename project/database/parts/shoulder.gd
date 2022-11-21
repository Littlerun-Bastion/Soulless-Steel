extends Node

enum SIDE {LEFT, RIGHT}

export var part_name : String
export var manufacturer_name : String
export var image : Texture
export (SIDE) var side
export var shield := 10


func get_image():
	return $Shoulder.texture


func get_collision():
	return $Collision.polygon
