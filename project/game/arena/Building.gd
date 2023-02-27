extends Node2D

const ALPHA_SPEED = 2.3

onready var FG = $Foreground
onready var Lights = $Lights

var player_inside = false


func _process(dt):
	if player_inside:
		FG.modulate.a = max(0, FG.modulate.a - ALPHA_SPEED*dt)
	else:
		FG.modulate.a = min(1, FG.modulate.a + ALPHA_SPEED*dt)


func player_entered():
	player_inside = true
	for child in Lights.get_children():
		child.enabled = true


func player_exited():
	player_inside = false
	for child in Lights.get_children():
		child.enabled = false


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


func _on_Perimeter_body_entered(body):
	if body.is_in_group("mecha"):
		body.entering_building(true)


func _on_Perimeter_body_exited(body):
	if body.is_in_group("mecha"):
		body.entering_building(false)
