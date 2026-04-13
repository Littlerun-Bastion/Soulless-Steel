extends Node2D

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var heatmap : Resource
@export var rotation_acc := 8
@export var rotation_range := 45.0
@export var accuracy_modifier := -1.0 
@export var visual_range := 450 
@export var health := 1500
@export var weight := 1.0 
@export var tags :Array[String] = ["head"]
@export var item_size := [3,3]
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

func get_image():
	return $Main.texture


func get_sub():
	return $Sub.texture


func get_glow():
	return $Glow.texture
