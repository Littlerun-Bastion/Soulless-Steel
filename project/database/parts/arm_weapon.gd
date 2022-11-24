extends Node

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var type: String
export var image : Texture
export var rotation_acc := 5
export var rotation_range := 10.0
export var projectile : Resource
export var number_projectiles := 1
export var damage_modifier := 1.0
export var recoil_force := 0.0
export var fire_rate := .3
export var auto_fire := true
export var bullet_accuracy_margin := 0
export var bullet_spread := PI/4 #Relevant for multi-shot
export var bullet_spread_delay := 0.0 #Relevant for multi-shot
export var total_ammo := 270
export var max_ammo := 270
export var clip_size := 30
export var reload_speed := 3.0
export var muzzle_heat := 60
export var ammo_cost := 10
export var soundEffect := "test"
export var sound_max_range := 2000
export var sound_att := 1.00
export var weight := 1.0
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


