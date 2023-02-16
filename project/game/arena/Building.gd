extends Node2D

const ALPHA_SPEED = 2.3

onready var FG = $Foreground

var player_inside = false


func _process(dt):
	if player_inside:
		FG.modulate.a = max(0, FG.modulate.a - ALPHA_SPEED*dt)
	else:
		FG.modulate.a = min(1, FG.modulate.a + ALPHA_SPEED*dt)



func player_entered():
	player_inside = true


func player_exited():
	player_inside = false


func _on_BuildingArea_body_entered(body):
	if body.is_in_group("mecha"):
		body.entered_building()
		if body.is_player():
			player_entered()


func _on_BuildingArea_body_exited(body):
	if body.is_in_group("mecha"):
		body.exited_building()
		if body.is_player():
			player_exited()
