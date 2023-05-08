extends Node2D

const HITBOX = preload("res://game/mecha/Hitbox.tscn")

signal create_hitbox_signal

@onready var part = get_parent()

var attack_id = -1

func create_hitbox(pos : Vector2, radius : float, damage_mul : float, knockback_mul : float,\
					id : String, priority := 0, dur := .1):
	emit_signal("create_hitbox_signal", {
		"id": str(attack_id) + "_" + str(id),
		"priority": priority,
		"origin": get_origin(),
		"pos": pos,
		"radius": radius,
		"data": get_parent().data,
		"damage_mul": damage_mul,
		"knockback_mul": knockback_mul,
		"dur": dur,
	})


#Disgusting function, but gambiarra it is for now
func get_origin():
	return get_parent().get_parent()
