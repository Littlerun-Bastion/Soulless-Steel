extends Node2D

const ALPHA_SPEED = 2.3
const OUTLINE_SHADER = preload("res://assets/shaders/OutlineShader.tres")
const LIGHT_MASK = 32

onready var FG = $Foreground
onready var LightEffect = $Light2D
onready var Background = $Background

var player_inside = false
var outline_node = null

func _ready():
	outline_node = Background.duplicate()
	outline_node.material = OUTLINE_SHADER
	outline_node.light_mask = LIGHT_MASK
	Background.add_child(outline_node)


func _process(dt):
	if player_inside:
		FG.modulate.a = max(0, FG.modulate.a - ALPHA_SPEED*dt)
		if outline_node:
			outline_node.modulate.a = max(0, outline_node.modulate.a - 2*ALPHA_SPEED*dt)
	else:
		FG.modulate.a = min(1, FG.modulate.a + ALPHA_SPEED*dt)
		if outline_node:
			outline_node.modulate.a = min(1, outline_node.modulate.a + 2*ALPHA_SPEED*dt)


func player_entered():
	player_inside = true
	LightEffect.enabled = true


func player_exited():
	player_inside = false
	LightEffect.enabled = false


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
