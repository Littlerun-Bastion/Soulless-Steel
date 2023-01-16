extends Node2D

signal reloading
signal finished_reloading

onready var ShootingPos = $ShootingPos
onready var Main = $Main
onready var Sub = $Sub
onready var Glow = $Glow

var timer:= 0.0
var total_ammo = false
var max_ammo = false
var clip_size = false
var clip_ammo = false
var reload_time = false
var reloading := false
var fire_rate = false
var ammo_cost = false
var muzzle_heat = 0
var heat = 0.0
var soundEffect = "test"
var shotPos = false
var sfx_max_range = 4000
var sfx_att = 1.0
var uses_battery = false
var battery_drain = 0.00
var is_melee = false
var melee_anim = null
var shooting_pos_array = []
var shooting_pos_idx = 0
var offset = Vector2()


func _process(dt):
	timer = max(timer - dt, 0.0)


func setup(weapon_ref):
	total_ammo = weapon_ref.total_ammo
	clip_size = weapon_ref.clip_size
	clip_ammo = clip_size
	reload_time = weapon_ref.reload_speed
	fire_rate = weapon_ref.fire_rate
	max_ammo = weapon_ref.max_ammo
	ammo_cost = weapon_ref.ammo_cost
	muzzle_heat = weapon_ref.muzzle_heat
	soundEffect = weapon_ref.soundEffect
	sfx_max_range = weapon_ref.sound_max_range
	sfx_att = weapon_ref.sound_att
	uses_battery = weapon_ref.uses_battery
	battery_drain = weapon_ref.battery_drain
	is_melee = weapon_ref.get("is_melee")
	
	if is_melee:
		melee_anim = $AttackAnimation
	else:
		melee_anim = null
	

func set_images(main_image, sub_image, glow_image):
	Main.texture = main_image
	Sub.texture = sub_image
	Glow.texture = glow_image


func set_offsets(off):
	Main.position = off
	Sub.position = off
	Glow.position = off
	offset = off


func update_heat(heat_dispersion, dt):
	heat = max(heat - heat_dispersion*dt, 0)
	Main.material.set_shader_param("heat", heat) 
	Sub.material.set_shader_param("heat", heat)
	Glow.material.set_shader_param("heat", heat)


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


func can_shoot_battery(drain, battery):
	if drain <= battery:
		return timer <= 0.0

func light_attack():
	add_time(.9)
	melee_anim.play("light_attack")


func shoot(amount := 1):
	add_time(fire_rate)
	clip_ammo -= amount
	heat = min(heat + muzzle_heat, 100)
	if soundEffect:
		AudioManager.play_sfx(soundEffect, get_shoot_position(), null, null, sfx_att, sfx_max_range)


func shoot_battery():
	add_time(fire_rate)
	heat = min(heat + muzzle_heat, 100)
	if soundEffect:
		AudioManager.play_sfx(soundEffect, get_shoot_position(), null, null, sfx_att, sfx_max_range)


func set_shooting_pos(pos):
	shooting_pos_array.append(pos+offset)

func clear_shooting_pos():
	shooting_pos_array = []

func get_direction(angle_offset := 0.0, accuracy_margin := 0.0):
	var offset = Vector2()
	var dir = (ShootingPos.global_position - global_position).normalized()
	if accuracy_margin > 0:
		offset = dir.rotated(PI/2)*rand_range(-accuracy_margin, accuracy_margin)
		dir = (ShootingPos.global_position + offset - global_position).rotated(angle_offset).normalized()
	return dir


func get_shoot_position():
	ShootingPos.position = shooting_pos_array[shooting_pos_idx]
	shooting_pos_idx += 1
	if shooting_pos_idx > (shooting_pos_array.size() - 1):
		shooting_pos_idx = 0
	return ShootingPos.global_position
