extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var shield := 1500.0
@export var stability := 1.0
@export var arms_accuracy_modifier := 1.0
@export var melee_modifier := 0.8
@export var weight := 20.0
@export var rotation_acc := 5
@export var rotation_range := 10.0
@export var tags :Array[String] = ["shoulder"]
@export var item_size := [4,4]
@export var front_armor := 1
@export var side_armor := 1
@export var rear_armor := 1
@export var additional_components: Array[Dictionary] = [
	#{ EXAMPLE OF ADDITIONAL COMPONENTS (do not delete)
	#	"name": "core_shell",   OVERRIDE default
	#	"hp": 3,               Heavier armor than default (3)
	#	"max_hp": 3,
	#	"tags": ["internal"],
	#	"weight": 3.0          Bigger, easier to hit
	#},
	#{
	#	"name": "shield_emitter",   NEW component
	#	"hp": 2,
	#	"max_hp": 2,
	#	"tags": ["internal", "shield"],
	#	"weight": 1.0
	#}
]

var part_id

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
