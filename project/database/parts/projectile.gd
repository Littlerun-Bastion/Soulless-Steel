extends Node2D

enum TYPE {INSTANT, REGULAR}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

@export var type : TYPE
@export var projectile_size := 1.0
@export var damage:= 100
@export var is_overtime := false
@export var decal_type:= "bullet_hole"
@export var texture_variations = []
@export var calibre := CALIBRE_TYPES.SMALL
@export var light_energy:= 0.5
@export var speed:= 400
@export var life_time = -1.0 #-1 means it won't disappear
@export var life_time_var = 0.0 #How much to vary from base life_time
@export var random_rotation := false

var part_id

func get_image():
	if texture_variations.is_empty() or randf() > 1.0/float(texture_variations.size() + 1):
		return $Image.texture
	else:
		texture_variations.shuffle()
		return texture_variations.front()


func get_collision():
	return $CollisionShape3D.polygon
