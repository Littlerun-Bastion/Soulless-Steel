extends Sprite

signal reloading
signal finished_reloading

onready var ShootingPos = $ShootingPos

var timer:= 0.0
var total_ammo = false
var max_ammo = false
var clip_size = false
var clip_ammo = false
var reload_time = false
var reloading := false
var fire_rate = false
var ammo_cost = false
var heat_dispersion = 0
var muzzle_heat = 0
var heat = 0.0
var soundEffect = "test"
var shotPos = false
var sfx_max_range = 4000
var sfx_att = 1.0

func _process(dt):
	timer = max(timer - dt, 0.0)
	update_heat(dt)


func setup(weapon_ref):
	total_ammo = weapon_ref.total_ammo
	clip_size = weapon_ref.clip_size
	clip_ammo = clip_size
	reload_time = weapon_ref.reload_speed
	fire_rate = weapon_ref.fire_rate
	max_ammo = weapon_ref.max_ammo
	ammo_cost = weapon_ref.ammo_cost
	muzzle_heat = weapon_ref.muzzle_heat
	heat_dispersion = weapon_ref.heat_dispersion
	soundEffect = weapon_ref.soundEffect
	sfx_max_range = weapon_ref.sound_max_range
	sfx_att = weapon_ref.sound_att
	


func update_heat(dt):
	heat = max(heat - heat_dispersion*dt, 0)
	material.set_shader_param("heat", heat) 


func add_time(time):
	timer += time


func can_reload():
	if reloading or clip_ammo == clip_size:
		return "no"
	if total_ammo == 0:
		#Eventually put a sfx here? Should only do it for the player
		return "empty"
	return "yes"


func is_clip_empty():
	return clip_ammo == 0


func reload():
	if can_reload() != "yes" or reloading:
		return
	
	reloading = true
	emit_signal("reloading", reload_time)
	var temp_timer = Timer.new()
	add_child(temp_timer)
	temp_timer.start(reload_time); yield(temp_timer, "timeout")
	var ammo = min(clip_size - clip_ammo, total_ammo)
	total_ammo -= ammo
	clip_ammo += ammo
	reloading = false
	emit_signal("finished_reloading")


func is_reloading():
	return reloading


func can_shoot(amount := 1):
	return timer <= 0.0 and (clip_ammo is bool or clip_ammo >= amount) and not is_reloading()


func shoot(amount := 1):
	add_time(fire_rate)
	AudioManager.play_sfx(soundEffect, get_shoot_position(), null, null, sfx_att, sfx_max_range)
	clip_ammo -= amount
	heat = min(heat + muzzle_heat, 100)


func set_shooting_pos(pos):
	ShootingPos.position = pos


func get_direction(angle_offset := 0.0, accuracy_margin := 0.0):
	var offset = Vector2()
	var dir = (ShootingPos.global_position - global_position).normalized()
	if accuracy_margin > 0:
		offset = dir.rotated(PI/2)*rand_range(-accuracy_margin, accuracy_margin)
		dir = (ShootingPos.global_position + offset - global_position).rotated(angle_offset).normalized()
	return dir


func get_shoot_position():
	return ShootingPos.global_position
