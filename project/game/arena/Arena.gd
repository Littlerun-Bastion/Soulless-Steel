extends Node2D

const PLAYER = preload("res://game/mecha/Player.tscn")

onready var Mechas = $Mechas 

var player


func _ready():
	add_player()


func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.position = get_start_position(1)


func get_start_position(idx):
	return $StartPositions.get_node("Pos"+str(idx)).position
