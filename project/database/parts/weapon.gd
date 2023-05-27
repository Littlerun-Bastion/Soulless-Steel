extends Node

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var muzzle_flash : PackedScene
@export var muzzle_flash_size := 1.0
@export var muzzle_flash_speed := 1.0
@export var rotation_acc := 5
@export var rotation_range := 10.0
@export var projectile : PackedScene
@export var parallax_offset := 0.0
@export var number_projectiles := 1
@export var burst_ammo_cost := 1
@export var requires_lock := false
@export var uses_battery := false
@export var recoil_force := 0.0
@export var bloom_reset_time := 1.0
@export var fire_rate := .3
@export var burst_size := 1
@export var burst_fire_rate := 0.0
@export var auto_fire := true
@export var base_accuracy := 0.0
@export var accuracy_bloom := 0.0
@export var max_bloom_angle := 2.5
@export var bullet_spread := PI/4 #Relevant for multi-shot
@export var bullet_spread_delay := 0.0 #Relevant for multi-shot
@export var total_ammo := 270
@export var max_ammo := 270
@export var clip_size := 30
@export var reload_speed := 3.0
@export var muzzle_heat := 3.8
@export var ammo_cost := 10 #the monetary cost of the ammunition, not the ammo used when firing.
@export var sound_effect := "test"
@export var sound_max_range := 2000
@export var sound_att := 1.00
@export var battery_drain := 1.00
@export var weight := 1.0
@export var impact_force := 0.0
@export var eject_casings := false
@export var casing_size := 1.0
@export var show_idle_projectile := false


#---BEAM BEHAVIOUR---#
@export var beam_range := 0.0
@export var constant_beam := false
@export var beam_effect : Resource

#---MELEE BEHAVIOURS---
@export var is_melee := false
@export var melee_knockback := 20

var cur_stage = 0
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
	assert($ShootingPosArray.get_child_count() >= idx + 1,"Not a valid shooting pos index: " + str(idx))
	return $ShootingPosArray.get_child(idx)


func get_attach_pos():
	return $AttachPos.position


func get_attack_animation():
	return $AttackAnimation.duplicate()


func get_stat(stat_name):
	var stat
	stat = get(stat_name)
	return stat

	


