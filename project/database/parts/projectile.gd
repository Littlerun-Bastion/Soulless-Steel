extends Node2D

enum TYPE {INSTANT, REGULAR}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

export (TYPE) var type
export var damage:= 10
export var is_overtime := false
export var decal_type:= "bullet_hole"
export (CALIBRE_TYPES) var  calibre := CALIBRE_TYPES.SMALL
export var light_energy:= 0.5
export var speed:= 400
export var decaying_speed_ratio := 1.0 # If 1.0 it doesn't decay
export var decaying_speed_ratio_var := 0.0
export var change_scaling = 0.0 #How much scaling it gets overtime
export var change_scaling_var = 0.0 #How much to vary scaling
export var life_time = -1.0 #-1 means it won't disappear
export var life_time_var = 0.0 #How much to vary from base life_time


func get_image():
	return $Image.texture


func get_collision():
	return $CollisionShape.polygon
