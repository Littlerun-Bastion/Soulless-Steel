extends Sprite

signal reloading
signal finished_reloading

onready var ShootingPos = $ShootingPos

var timer:= 0.0
var total_ammo = false
var clip_size = false
var clip_ammo = false
var reload_time = false
var reloading := false
var fire_rate = false

func _process(delta):
	timer = max(timer - delta, 0.0)


func setup(weapon_ref):
	total_ammo = weapon_ref.total_ammo
	clip_size = weapon_ref.clip_size
	clip_ammo = clip_size
	reload_time = weapon_ref.reload_speed
	fire_rate = weapon_ref.fire_rate


func add_time(time):
	timer += time


func can_reload():
	if reloading or clip_ammo == clip_size:
		return "no"
	if total_ammo == 0:
		#Eventually put a sfx here
		return "empty"
	return "yes"


func reload():
	if can_reload() != "yes":
		return
	
	reloading = true
	emit_signal("reloading", reload_time)
	yield(get_tree().create_timer(reload_time), "timeout")
	var ammo = min(clip_size - clip_ammo, total_ammo)
	total_ammo -= ammo
	clip_ammo += ammo
	reloading = false
	emit_signal("finished_reloading")


func can_shoot():
	return timer <= 0.0 and (clip_ammo is bool or clip_ammo > 0)


func shoot():
	add_time(fire_rate) 
	clip_ammo -= 1


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
