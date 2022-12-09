extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var shieldMult := 1.5
export var stability := 10.0
export var arms_accuracy_modifier := 10.0
export var weight := 20
var shield := shieldMult * 1500.0

func get_image(side):
	if side == SIDE.LEFT:
		return $ShoulderLeft.texture
	elif side == SIDE.RIGHT:
		return $ShoulderRight.texture
	else:
		push_error("Not a valid side:" + str(side))

func get_collision(side):
	if side == SIDE.LEFT:
		return $ShoulderLeft/Collision.polygon
	elif side == SIDE.RIGHT:
		return $ShoulderRight/Collision.polygon
	else: 
		push_error("Not a valid side:" + str(side))
