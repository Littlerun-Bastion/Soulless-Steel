extends Node2D

const MECHA = preload("res://game/mecha/Mecha.tscn")
const PLAYER_SCRIPT = preload("res://game/mecha/Player.gd")

onready var Mechas = $Mechas 

var player


func _ready():
	add_player()


func add_player():
	player = MECHA.instance()
	player.script = PLAYER_SCRIPT
	Mechas.add_child(player)
	player.position = get_start_position(1)


func get_start_position(idx):
	return $StartPositions.get_node("Pos"+str(idx)).position
