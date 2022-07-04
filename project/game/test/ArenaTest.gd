extends Node2D

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")
const SCRAP_PART = preload("res://game/arena/ScrapPart.tscn")
const PLAYER_POS = Vector2(-100, 0)
const ENEMY_POS = Vector2(100, 0)

onready var Mechas = $Mechas 
onready var Projectiles = $Projectiles
onready var PlayerHUD = $PlayerHUD
onready var ScrapParts = $ScrapParts

var player
var all_mechas = []

func _ready():
	Debug.window_debug_mode()
	add_player()
	add_enemy()


func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.setup()
	player.position = PLAYER_POS
	player.connect("create_projectile", self, "_on_mecha_create_projectile")
	player.connect("died", self, "_on_mecha_died")
	player.get_camera().zoom = Vector2(.5,.5)
	all_mechas.push_back(player)
	PlayerHUD.setup(player, all_mechas)


func add_enemy():
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position =  ENEMY_POS
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")
	enemy.connect("died", self, "_on_mecha_died")
	all_mechas.push_back(enemy)
	enemy.setup(all_mechas, null, false)
	enemy.set_pause(true)

func _on_mecha_died(mecha):
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove(idx)
	
	create_mecha_scraps(mecha)
	mecha.queue_free()

func _on_mecha_create_projectile(mecha, args):
	#To avoid warning when mecha is killed during delay
	if args.delay > 0:
		var timer = Timer.new()
		timer.wait_time = args.delay
		add_child(timer)
		timer.start()
		yield(timer, "timeout")
		timer.queue_free()
	var data = ProjectileManager.create(mecha, args)
	if data.create_node:
		Projectiles.add_child(data.node)


func create_mecha_scraps(mecha):
	for texture in mecha.get_scraps():
		var scrap = SCRAP_PART.instance()
		scrap.setup(texture)
		scrap.position = mecha.position
		scrap.set_scale(mecha.scale)

		var impulse_dir = Vector2(rand_range(-1.0, 1.0), rand_range(-1.0, 1.0)).normalized()
		var impulse_force = rand_range(400,700)
		var impulse_torque = rand_range(5, 15)
		if randf() > .5:
			impulse_torque = -impulse_torque
		scrap.apply_impulse(Vector2(), impulse_dir*impulse_force)
		scrap.apply_torque_impulse(impulse_torque)
		ScrapParts.call_deferred("add_child", scrap)
