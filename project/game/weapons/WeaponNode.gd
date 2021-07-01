extends Sprite

onready var ShootingPos = $ShootingPos

var timer:= 0.0

func _process(delta):
	timer = max(timer - delta, 0.0)


func add_time(time):
	timer += time


func can_shoot():
	return timer <= 0.0


func set_shooting_pos(pos):
	ShootingPos.position = pos


func get_direction():
	return (ShootingPos.global_position - global_position).normalized()


func get_shoot_position():
	return ShootingPos.global_position
