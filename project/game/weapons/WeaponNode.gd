extends Node2D


enum SIDE {LEFT, RIGHT, SINGLE}

signal reloading_signal
signal finished_reloading

const WEAPON_HEAT_DECAY := 30.0

@onready var Main = $Main
@onready var Sub = $Sub
@onready var Glow = $Glow

var timer:= 0.0
var mecha_ref
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
var do_burst = false
## An energy weapon's (data.uses_battery) improvement from the generator's
## WPOR (Mecha.weapon_power_boost): its times between shots and its reload
## time are divided by 1 + power_boost, its clip size multiplied (rounded
## down). 0 for any other weapon. Its reserve is the mecha's battery, not
## total_ammo: a reload puts in as many shots as the battery pays for at
## data.battery_drain kWh each.
var power_boost := 0.0


func _process(dt):
	timer = max(timer - dt, 0.0)


func setup(mecha, weapon_ref, core, _side):
	mecha_ref = mecha
	data = weapon_ref
	side = _side
	total_ammo = data.total_ammo
	power_boost = mecha.weapon_power_boost() if data.uses_battery and mecha.has_method("weapon_power_boost") else 0.0
	clip_ammo = get_clip_size()
	# A new weapon starts fresh, not with the previous one's cooldown or burst.
	timer = 0.0
	burst_count = 0
	do_burst = false
	heat = 0.0
	
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


# The heat values last written to the sprites' shaders (see update_heat).
var _shown_mecha_heat := -1.0
var _shown_heat := -1.0


## `show` false (the mecha is off screen) skips the shader writes; they
## catch up on the next shown frame, as each is compared with the last value
## written.
func update_heat(_heat_dispersion, mecha_heat, dt, show_heat := true):
	heat = max(heat - WEAPON_HEAT_DECAY * dt, 0.0)
	if not show_heat:
		return
	if mecha_heat != _shown_mecha_heat:
		_shown_mecha_heat = mecha_heat
		Main.material.set_shader_parameter("heat", mecha_heat)
	if heat != _shown_heat:
		_shown_heat = heat
		Sub.material.set_shader_parameter("heat", heat)
		Glow.material.set_shader_parameter("heat", heat)


func add_time(time):
	timer += time


func can_reload():
	if reloading or clip_ammo >= get_clip_size() or is_underpowered():
		return "no"
	if reserve_shots() <= 0:
		#Eventually put a sfx here? Should only do it for the player
		return "empty"
	return "yes"


func is_clip_empty():
	return clip_ammo == 0


func reload():
	if can_reload() != "yes" or reloading:
		return

	reloading = true
	var reload_time := get_reload_time()
	emit_signal("reloading_signal", reload_time)
	# Spawn a one-shot Timer as a child so it gets cleaned up automatically
	# if the weapon (and so the parent mecha) dies mid-reload. Explicitly
	# queue_free after the timeout to prevent in-tree accumulation — over a
	# long session, dozens of expired reload timers would otherwise pile up
	# on each weapon node.
	var temp_timer = Timer.new()
	add_child(temp_timer)
	temp_timer.start(reload_time); await temp_timer.timeout
	# Guard against the weapon being freed during the await before touching
	# temp_timer — temp_timer is a child of self, so if self was freed the
	# timer is gone too and calling queue_free on it would error.
	if not is_instance_valid(self):
		return
	temp_timer.queue_free()
	var room: int = maxi(get_clip_size() - clip_ammo, 0)
	if data.uses_battery:
		clip_ammo += mecha_ref.draw_battery_shots(room, data.battery_drain)
	else:
		var ammo = min(room, total_ammo)
		total_ammo -= ammo
		clip_ammo += ammo
	reloading = false
	burst_count = 0
	timer = 0
	emit_signal("finished_reloading")


## The weapon's stats with power_boost (none for a weapon that isn't an energy
## weapon).
func get_fire_rate() -> float:
	return data.fire_rate / (1.0 + power_boost)


func get_burst_fire_rate() -> float:
	return data.burst_fire_rate / (1.0 + power_boost)


func get_reload_time() -> float:
	return data.reload_speed / (1.0 + power_boost)


func get_clip_size() -> int:
	return floori(data.clip_size * (1.0 + power_boost) + 0.0001)


## A new boost (the generator changed). A clip now over its size is cut to it;
## returns how many shots were cut.
func set_power_boost(boost: float) -> int:
	power_boost = boost if data.uses_battery else 0.0
	var size := get_clip_size()
	if clip_ammo is int and clip_ammo > size:
		var cut: int = clip_ammo - size
		clip_ammo = size
		return cut
	return 0


## Shots the reserve can still put in the clip: what the mecha's battery
## pays for, for an energy weapon; else the rounds left.
func reserve_shots() -> int:
	if data.uses_battery:
		return mecha_ref.battery_shots(data.battery_drain)
	return int(total_ammo)


## An energy weapon on a generator whose WPOR is below its min_power_rating:
## it neither fires nor reloads.
func is_underpowered() -> bool:
	return data.uses_battery and mecha_ref.weapon_power_rating + 0.0001 < data.min_power_rating


func is_reloading():
	return reloading

func can_shoot(amount := 1):
	if timer > 0.0 or (clip_ammo is not bool and clip_ammo < amount) or is_reloading():
		return false
	
	if mecha_ref.internal_temp >= mecha_ref.overheat_temp or mecha_ref.external_temp > 110.0:
		# Jam chance scales with external temp (0% at 110°C ext, abt 30% at 200°C ext)
		var jam_chance = clamp(mecha_ref.external_temp / 600.0, 0.0, 0.3)
		if randf() < jam_chance:
			add_time(get_fire_rate() * 3.0)  # Jam delays next shot by 3x fire rate
			return false
	
	return true


func light_attack():
	add_time(melee_anim.get_animation("light_attack").length)
	$MeleeHitboxes.attack_id = randi()
	melee_anim.play("light_attack")


func shoot(amount := 1):
	FrameSpikeDetector.mark("shoot")
	burst_count += 1
	add_time(get_burst_fire_rate())
	clip_ammo -= amount
	heat = min(heat + data.muzzle_heat*4, 200)
	mecha_ref.increase_heat(data.muzzle_heat)
		
	if data.shoot_single_sfx:
		AudioManager.play_sfx(data.shoot_single_sfx, get_shoot_position().global_position, null, null, data.sound_att, data.sound_max_range)
		mecha_ref.create_sound("loud", "shooting", data.sound_max_range)
	if burst_count >= data.burst_size:
		burst_cooldown()


# One designator salvo (Mecha.fire_at_point): one clip round, the weapon's
# fire_rate as cooldown, and the salvo's heat added to the mecha once.
func shoot_salvo(heat_kj: float) -> void:
	FrameSpikeDetector.mark("shoot")
	clip_ammo -= 1
	add_time(get_fire_rate())
	heat = min(heat + data.muzzle_heat*4, 200)
	mecha_ref.increase_heat(heat_kj)


func play_shot_sound(at: Vector2) -> void:
	if data.shoot_single_sfx:
		AudioManager.play_sfx(data.shoot_single_sfx, at, null, null, data.sound_att, data.sound_max_range)
		mecha_ref.create_sound("loud", "shooting", data.sound_max_range)


func burst_cooldown():
	add_time(get_fire_rate() + get_burst_fire_rate())
	burst_count = 0
	do_burst = false


func set_shooting_pos(pos):
	shooting_pos_array.append(pos)

func clear_shooting_pos():
	for marker in shooting_pos_array:
		if is_instance_valid(marker):
			marker.queue_free()
	shooting_pos_array = []
	shooting_pos_idx = 0  # the next weapon may have fewer barrels than this one

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
