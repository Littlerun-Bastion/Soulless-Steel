extends Sprite

onready var ShootingPos = $ShootingPos


func set_shooting_pos(pos):
	ShootingPos.position = pos


func get_direction():
	return (ShootingPos.global_position - global_position).normalized()


func get_shoot_position():
	return ShootingPos.global_position
