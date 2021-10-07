extends Resource

export var image: Resource
export var shooting_pos : Vector2
export var rotation_acc := 5
export var rotation_range := 10.0
export var projectile : Resource
export var damage_modifier := 1.0
export var recoil_force := 0.0
export var fire_rate := .3
export var auto_fire := true
export var bullet_accuracy_margin := 0
export var bullet_spread := 0
export var total_ammo := 270
export var clip_size := 30
export var reload_speed := 3.0

var firing_timer = 0.0
