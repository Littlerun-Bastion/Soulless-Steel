extends Node2D

const PLAYER = preload("res://game/mecha/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")


onready var Mechas = $Mechas 
onready var Projectiles = $Projectiles
onready var PlayerHUD = $PlayerHUD
onready var ArenaCam = $ArenaCamera

var player
var current_cam
var all_mechas = []


func _ready():
	randomize()
	add_player()
	add_enemy()
	add_enemy()
	add_enemy()


func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.position = get_start_position(1)
	player.connect("create_projectile", self, "_on_mecha_create_projectile")
	player.connect("died", self, "_on_mecha_died")
	all_mechas.push_back(player)
	PlayerHUD.setup(player)
	current_cam = player.get_cam()


func add_enemy():
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position = get_random_start_position([1])
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")
	enemy.connect("died", self, "_on_mecha_died")
	all_mechas.push_back(enemy)
	enemy.setup(all_mechas, $Navigation2D)


func player_died():
	player = null
	ArenaCam.current = true
	current_cam = ArenaCam


func get_random_start_position(exclude_idx := []):
	var n_pos = $StartPositions.get_child_count()
	var idx = randi()%n_pos + 1
	while exclude_idx.has(idx):
		idx = randi()%n_pos + 1
	return $StartPositions.get_node("Pos"+str(idx)).position


func get_start_position(idx):
	return $StartPositions.get_node("Pos"+str(idx)).position


func _on_mecha_create_projectile(mecha, args):
	var data = ProjectileManager.create(mecha, args)
	if data.create_node:
		Projectiles.add_child(data.node)


func _on_mecha_died(mecha):
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove(idx)
	if mecha == player:
		player_died()
