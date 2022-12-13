extends Node

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var type: String
export var projectile : Resource
export var projectile_type : String
export var requires_lock := false
export var number_projectiles := 1
export var damage_modifier := 1.0
export var shield_mult := 1.0
export var health_mult := 1.0
export var heat_damage := 10.0
export var recoil_force := 0.0
export var fire_rate := .3
export var auto_fire := true
export var bullet_accuracy_margin := 0
export var bullet_spread := PI/4 #Relevant for multi-shot
export var bullet_spread_delay := 0.0 #Relevant for multi-shot
export var total_ammo := 5
export var max_ammo := 5
export var clip_size := 1
export var reload_speed := 2.0
export var muzzle_heat := 100
export var ammo_cost := 5
export var soundEffect := "test"
export var sound_max_range := 2000
export var sound_att := 1.00
export var weight := 1.0
export var battery_drain := 0

#---TRAILS---
export var has_trail := false
export var trail_lifetime := 1.0
export var trail_lifetime_range := 0.25
export var trail_eccentricity := 5.0
export var trail_min_spawn_distance := 20.0
export var trail_width := 20

#---MISSILE/ROCKET BEHAVIOURS---
export var has_wiggle := false
export var wiggle_amount := 2.0


var firing_timer = 0.0


func get_sub():
	return $Sub.texture


func get_image():
	return $Main.texture


func get_glow():
	return $Glow.texture


func get_shooting_pos():
	return $ShootingPos.position


func get_attach_pos():
	return $AttachPos.position
