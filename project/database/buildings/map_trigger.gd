extends Area2D

signal trigger_entered
@export var trigger := "1"
@export var one_time := false

var disabled = false

# Called when the node enters the scene tree for the first time.

func _on_body_entered(body):
	if body.name == "Player" and not disabled:
		if one_time:
			disabled = true
		emit_signal("trigger_entered", trigger)
