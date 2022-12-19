extends Resource

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var walk_speed_multiplier := 1.0
export var dash_distance := 2
export var dash_recharge_rate := 4
export var dash_heat := 100
export var walk_heat := 5
export var weight := 1.0

var part_id

func get_image():
	return image
