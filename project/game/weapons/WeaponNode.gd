extends Node2D


enum SIDE {LEFT, RIGHT, SINGLE}

signal reloading_signal
signal finished_reloading

@onready var Main = $Main
@onready var Sub = $Sub
@onready var Glow = $Glow

var timer:= 0.0
var data
var total_ammo = false
var clip_ammo = false
var reloading := false
var heat = 0.0
var shotPos = false
var melee_damage = 0
var melee_knockback = 0
var melee_anim = null
var shooting_pos_array = []
var shooting_pos_idx = 0
var offset = Vector2()
var cur_shooting_pos
var side
var burst_count = 0


func _process(dt):
	timer = max(timer - dt, 0.0)


func setup(weapon_ref, core, _side):
	data = weapon_ref
	side = _side
	total_ammo = data.total_ammo
	clip_ammo = data.clip_size
	
	if data.is_melee:
		add_child(weapon_ref.get_attack_animation())
		melee_anim = $AttackAnimation
		melee_damage = weapon_ref.damage
		melee_knockback = weapon_ref.melee_knockback
	else:
		if has_node("AttackAnimation"):
			$AttackAnimation.queue_free()
		melee_anim = null
	
	set_images(weapon_ref.get_image(), weapon_ref.get_sub(), weapon_ref.get_glow())
	position = core.get_arm_weapon_offset(side)
	set_offsets(-weapon_ref.get_attach_pos())
	
	if not data.is_melee:
		clear_shooting_pos()
		if weapon_ref.get_num_shooting_pos() > 0:
			for idx in weapon_ref.get_num_shooting_pos():
				var defined_pos = weapon_ref.get_shooting_pos(idx)
				var shooting_position = Marker2D.new()
				shooting_position.position = defined_pos.position + offset
				add_child(shooting_position)
				set_shooting_pos(shooting_position)
	

func set_images(main_image, sub_image, glow_image):
	Main.texture = main_image
	Sub.texture = sub_image
	Glow.texture = glow_image


func set_offsets(off):
	Main.position = off
	Sub.position = off
	Glow.position = off
	if data.is_melee:
		$MeleeHitboxes.position = off 
	offset = off


func update_heat(heat_dispersion,mecha_heat, dt):
	heat = max(heat - heat_dispersion*dt/4, 0)
	Main.material.set_shader_parameter("heat", mecha_heat) 
	Sub.material.set_shader_parameter("heat", heat)
	Glow.material.set_shader_parameter("heat", heat)


func add_time(time):
	timer += time


func can_reload():
	if reloading or clip_ammo == data.clip_size:
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
	emit_signal("reloading_signal", data.reload_speed)
	var temp_timer = Timer.new()
	add_child(temp_timer)
	temp_timer.start(data.reload_speed); await temp_timer.timeout
	var ammo = min(data.clip_size - clip_ammo, total_ammo)
	total_ammo -= ammo
	clip_ammo += ammo
	reloading = false
	burst_count = 0
	timer = 0
	emit_signal("finished_reloading")


func is_reloading():
	return reloading


func can_shoot(amount := 1):
	return timer <= 0.0 and (clip_ammo is bool or clip_ammo >= amount) and not is_reloading()


func can_shoot_battery(drain, battery):
	if drain <= battery:
		return timer <= 0.0

func light_attack():
	add_time(melee_anim.get_animation("light_attack").length)
	$MeleeHitboxes.attack_id = randi()
	melee_anim.play("light_attack")


func shoot(amount := 1):
	burst_count += 1
	add_time(data.burst_fire_rate)
	clip_ammo -= amount
	heat = min(heat + data.muzzle_heat*4, 200)
	if data.shoot_single_sfx:
		AudioManager.play_sfx(data.shoot_single_sfx, get_shoot_position().global_position, null, null, data.sound_att, data.sound_max_range)

func burst_cooldown():
	add_time(data.fire_rate + data.burst_fire_rate)
	burst_count = 0


func shoot_battery():
	burst_count += 1
	add_time(data.burst_fire_rate)
	heat = min(heat + data.muzzle_heat*4, 200)
	if data.shoot_single_sfx:
		AudioManager.play_sfx(data.shoot_single_sfx, get_shoot_position().global_position, null, null, data.sound_att, data.sound_max_range)


func set_shooting_pos(pos):
	shooting_pos_array.append(pos)

func clear_shooting_pos():
	shooting_pos_array = []

func get_direction(multishot_offset := 0.0, angle := 0.0):
	var angle_offset = randf_range(-multishot_offset, multishot_offset)
	var dirA = global_rotation + deg_to_rad(angle) + deg_to_rad(angle_offset)
	if side == SIDE.LEFT:
		dirA -= (PI/2)
	else:
		dirA += (PI/2)
	var dir = Vector2(cos(dirA), sin(dirA)).normalized()
	return dir


func get_shoot_position():
	cur_shooting_pos = shooting_pos_array[shooting_pos_idx]
	shooting_pos_idx += 1
	if shooting_pos_idx > (shooting_pos_array.size() - 1):
		shooting_pos_idx = 0
	return cur_shooting_pos
