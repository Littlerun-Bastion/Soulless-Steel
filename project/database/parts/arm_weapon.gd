extends Resource

export var image: Resource
export var shooting_pos : Vector2
export var rotation_acc := 5
export var rotation_range := 10.0
export var projectile : Resource
export var damage_modifier := 1.0
export var auto_fire := true
export var fire_rate := .3
export var bullet_spread := 0

var firing_timer = 0.0
