extends Node2D

enum TYPE {INSTANT, REGULAR}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

export (TYPE) var type
export var projectile_size := 1.0
export var damage:= 100
export var is_overtime := false
export var decal_type:= "bullet_hole"
export var texture_variations = []
export (CALIBRE_TYPES) var  calibre := CALIBRE_TYPES.SMALL
export var light_energy:= 0.5
export var speed:= 400
export var decaying_speed_ratio := 1.0 # If 1.0 it doesn't decay
export var decaying_speed_ratio_var := 0.0
export var change_scaling = 0.0 #How much scaling it gets overtime
export var change_scaling_var = 0.0 #How much to vary scaling
export var life_time = -1.0 #-1 means it won't disappear
export var life_time_var = 0.0 #How much to vary from base life_time

var part_id

func get_image():
	if texture_variations.empty() or randf() > 1.0/float(texture_variations.size() + 1):
		return $Image.texture
	else:
		texture_variations.shuffle()
		return texture_variations.front()


func get_collision():
	return $CollisionShape.polygon
