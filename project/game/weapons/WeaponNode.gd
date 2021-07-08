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


func get_direction(accuracy_margin := 0.0):
	var offset = Vector2()
	var dir = (ShootingPos.global_position - global_position).normalized()
	if accuracy_margin > 0:
		offset = dir.rotated(PI/2)*rand_range(-accuracy_margin, accuracy_margin)
		dir = (ShootingPos.global_position + offset - global_position).normalized()
	return dir


func get_shoot_position():
	return ShootingPos.global_position
