extends Node2D

const PLAYER = preload("res://game/mecha/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")

onready var Mechas = $Mechas 

var player


func _ready():
	add_player()
	add_enemy()


func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.position = get_start_position(1)
	player.connect("create_projectile", self, "_on_mecha_create_projectile")


func add_enemy():
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position = get_start_position(2)
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")


func get_start_position(idx):
	return $StartPositions.get_node("Pos"+str(idx)).position


func _on_mecha_create_projectile(_dir, _projectile):
	pass
