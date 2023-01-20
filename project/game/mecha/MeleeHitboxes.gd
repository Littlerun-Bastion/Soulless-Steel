extends Node2D

const HITBOX = preload("res://game/mecha/Hitbox.tscn")

func create_hitbox(pos : Vector2, radius : float, damage_mul : float, dur := .1):
	var hitbox = HITBOX.instance()
	hitbox.setup(pos, radius, damage_mul, dur)
	add_child(hitbox)
