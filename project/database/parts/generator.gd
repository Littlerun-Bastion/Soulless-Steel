extends Resource

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var shield := 5
export var shield_regen_speed := 1
export var shield_regen_delay := 5
export var heat_dispersion := 10


func get_image():
	return image
