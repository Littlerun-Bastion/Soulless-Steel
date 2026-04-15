extends Node2D

@onready var Player = $AnimationPlayer
@onready var sparks = $sparks_mech
@onready var sparks2 = $sparks_mech2
@onready var hitsmoke = $hit_smoke
@export var light_decay_rate := 1.0

var lifetime := 10.0
var is_mecha = false
var is_shield = false

func _ready():
	var num = randi() % 2
	Player.play("impact" + str(num + 1))
	sparks.emitting = true
	sparks2.emitting = true
	hitsmoke.emitting = true
	play_sfx()


func _process(delta):
	if lifetime <= 0.0:
		queue_free()
	else:
		lifetime -= delta
	$LightEffect.modulate.a -= delta * light_decay_rate

func play_sfx():
	pass
