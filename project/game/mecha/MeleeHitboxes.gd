extends Node2D

const HITBOX = preload("res://game/mecha/Hitbox.tscn")

onready var part = get_parent()

func create_hitbox(pos : Vector2, radius : float, damage_mul : float, dur := .1):
	var hitbox = HITBOX.instance()
	hitbox.setup(pos, radius, get_melee_damage(damage_mul), dur)
	add_child(hitbox)

#Disgusting function, but gambiarra it is for now
func get_melee_damage(mul):
	return get_parent().melee_damage*mul
