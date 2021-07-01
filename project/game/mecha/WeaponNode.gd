extends Sprite

onready var ShootingPos = $ShootingPos


func set_shooting_pos(pos):
	ShootingPos.position = pos


func get_direction():
	return Vector2(cos(deg2rad(rotation_degrees)), sin(deg2rad(rotation_degrees)))


func get_shoot_position():
	return ShootingPos.global_position
