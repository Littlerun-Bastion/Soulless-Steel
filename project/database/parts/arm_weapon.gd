extends Node

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var type: String
export var image : Texture
export (PackedScene) var muzzle_flash
export var muzzle_flash_size := 1.0
export var muzzle_flash_speed := 1.0
export var rotation_acc := 5
export var rotation_range := 10.0
export var projectile : Resource
export var projectile_type : String
export var parallax_offset := 0.0
export var number_projectiles := 1
export var burst_ammo_cost := 1
export var damage_modifier := 1.0
export var requires_lock := false
export var uses_battery := false
export var shield_mult := 1.0
export var health_mult := 1.0
export var heat_damage := 10.0
export var status_damage := 0.0
export var status_type : String
export var recoil_force := 0.0
export var bloom_reset_time := 1.0
export var fire_rate := .3
export var burst_size := 1
export var burst_fire_rate := 0.0
export var auto_fire := true
export var base_accuracy := 0.0
export var accuracy_bloom := 0.0
export var max_bloom_angle := 2.5
export var bullet_spread := PI/4 #Relevant for multi-shot
export var bullet_spread_delay := 0.0 #Relevant for multi-shot
export var total_ammo := 270
export var max_ammo := 270
export var clip_size := 30
export var reload_speed := 3.0
export var muzzle_heat := 3.8
export var ammo_cost := 10 #the monetary cost of the ammunition, not the ammo used when firing.
export var soundEffect := "test"
export var sound_max_range := 2000
export var sound_att := 1.00
export var battery_drain := 1.00
export var weight := 1.0
export var bullet_velocity := 2000
export var bullet_drag := 1.0
export var bullet_drag_var := 0.0
export var projectile_size := 1.0
export var projectile_size_scaling := 0.0
export var projectile_size_scaling_var := 0.0
export var lifetime := 2.0
export var impact_force := 0.0
export var eject_casings := false
export var casing_size := 1.0


#---BEAM BEHAVIOUR---#
export var beam_range := 0.0
export var constant_beam := false
export var beam_effect : Resource

#---TRAILS AND IMPACTS---
export (PackedScene) var has_trail
export var trail_lifetime := 1.0
export var trail_lifetime_range := 0.25
export var trail_eccentricity := 5.0
export var trail_min_spawn_distance := 20.0
export var trail_width := 20

export (PackedScene) var has_smoke
export var smoke_density := 400
export var smoke_lifetime := 5.0

export (PackedScene) var impact_effect
export var impact_size := 1.0
export var hitstop := false
#---MISSILE/ROCKET BEHAVIOURS---
export var has_wiggle := false
export var wiggle_amount := 2.0
export var is_seeker := false
export var seeker_agility := 0.01
export var seek_time := 1.0
export var seeker_angle := 90

#---MELEE BEHAVIOURS---
export var is_melee := false
export var melee_damage := 0

var firing_timer = 0.0
var part_id


func get_sub():
	return $Sub.texture


func get_image():
	return $Main.texture


func get_glow():
	return $Glow.texture


func get_num_shooting_pos():
	return $ShootingPosArray.get_children().size()


func get_shooting_pos(idx):	
	if idx == 1:
		return get_node_or_null("ShootingPosArray/ShootingPos")
	else: 
		return get_node_or_null("ShootingPosArray/ShootingPos" + str(idx))


func get_attach_pos():
	return $AttachPos.position


func get_attack_animation():
	return $AttackAnimation


func get_stat(stat_name):
	var stat
	if stat_name == "armor_damage":
		stat = 100 * damage_modifier * health_mult
	elif stat_name == "shield_damage":
		stat = 100 * damage_modifier * shield_mult
	else:
		stat = get(stat_name)
	return stat

	


