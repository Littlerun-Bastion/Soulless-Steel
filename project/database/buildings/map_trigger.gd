extends Area2D

signal trigger_entered
@export var trigger := "1"
@export var one_time := false

var disabled = false


func _on_body_entered(body):
	if body.name == "Player" and not disabled:
		if one_time:
			disabled = true
		emit_signal("trigger_entered", trigger)
