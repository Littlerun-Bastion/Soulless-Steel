extends Node2D

const PLAYER = preload("res://game/mecha/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")

onready var Mechas = $Mechas 

var player
var all_mechas = []
var ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]


func _ready():
	add_player()
	add_enemy(1)
	

func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.position = get_start_position(1)
	player.connect("create_projectile", self, "_on_mecha_create_projectile")
	all_mechas.push_back(player)
	player.id = ids.pop_front()

func add_enemy(id):
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position = get_start_position(2)
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")
	all_mechas.push_back(enemy)
	enemy.set_id_and_enemies(all_mechas, id)
	enemy.id = ids.pop_front()
	

func get_start_position(idx):
	return $StartPositions.get_node("Pos"+str(idx)).position


func _on_mecha_create_projectile(_dir, _projectile):
	pass
