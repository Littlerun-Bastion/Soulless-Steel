extends Resource

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var description : String
@export var price := 0.0
@export var image : Texture2D
@export var thrust_speed_multiplier := 3.0
@export var thrust_max_speed := 400
@export var sprinting_heat := 100
@export var dash_strength := 2
@export var dash_cooldown := 4
@export var dash_heat := 100
@export var walk_heat := 5
@export var weight := 1.0
@export var tags :Array[String] = ["thruster"]

var part_id

func get_image():
	return image
