extends Resource

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var can_lock := false
export var lock_on_speed := .2
export var lock_on_duration := 5
export var lock_on_distance := 5000
export var lock_on_reticle_size := 15 #Radius of the reticle
export var lock_on_strength := 5
export var ECM := 10
export var ECM_frequency := .3
export var has_radar := false


func get_image():
	return image
