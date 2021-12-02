extends Resource

export var name: String
export var type: String
export var image: Resource
export var shooting_pos : Vector2
export var projectile : Resource
export var number_projectiles := 1
export var damage_modifier := 1.0
export var recoil_force := 0.0
export var fire_rate := .3
export var auto_fire := true
export var bullet_accuracy_margin := 0
export var bullet_spread := 0
export var total_ammo := 5
export var clip_size := 1
export var reload_speed := 2.0

var firing_timer = 0.0
