extends Node2D

const HITBOX = preload("res://game/mecha/Hitbox.tscn")

signal create_hitbox

onready var part = get_parent()

var attack_id = -1

func create_hitbox(pos : Vector2, radius : float, damage_mul : float, knockback_mul : float,\
				   id : String, priority := 0, dur := .1):
	emit_signal("create_hitbox", {
		"id": str(attack_id) + "_" + str(id),
		"priority": priority,
		"pos": pos,
		"radius": radius,
		"damage": get_melee_damage(damage_mul),
		"knockback": get_melee_knockback(knockback_mul),
		"dur": dur,
	})


#Disgusting function, but gambiarra it is for now
func get_melee_damage(mul):
	return get_parent().melee_damage*mul


#Disgusting function, but gambiarra it is for now
func get_melee_knockback(mul):
	return get_parent().melee_knockback*mul
