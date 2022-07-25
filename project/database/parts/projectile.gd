extends Node2D

enum TYPE {INSTANT, REGULAR}

export (TYPE) var type
export var damage:= 10
export var decal_type:= "bullet_hole"
export var light_energy:= 0.5
export var speed:= 400
export var decaying_speed_ratio := 1.0
export var life_time = -1.0 #-1 means it won't disappear
export var life_time_rand = 0.0 #How much to vary from base life_time


func get_image():
	return $Image.texture


func get_scale():
	return $Image.scale


func get_collision():
	return $CollisionShape.polygon
