extends Resource

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var ambient_sfx := preload("res://assets/audio/sfx/generator_ambient/test.mp3")
@export var shield := 6000.0
@export var shield_regen_speed := 1
@export var shield_regen_delay := 5
@export var shield_project_cooldown := 0.5
@export var shield_project_heat := 10
@export var heat_dispersion := 10
@export var heat_capacity := 100
@export var idle_threshold := 33.0
@export var battery_capacity := 100
@export var battery_recharge_rate := 10
@export var power_output := 1.0
@export var weight := 10.0
@export var tags :Array[String] = ["generator"]
@export var item_size := [3,3]

var part_id

func get_image():
	return image
