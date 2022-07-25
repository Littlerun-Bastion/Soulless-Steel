extends Node2D

enum TYPE {INSTANT, REGULAR}

export (TYPE) var type
export var damage:= 10
export var decal_type:= "bullet_hole"
export var speed:= 400
export var decaying_ratio := 1.0
export var light_energy:= 0.5


func get_image():
	return $Image.texture


func get_scale():
	return $Image.scale


func get_collision():
	return $CollisionShape.polygon
