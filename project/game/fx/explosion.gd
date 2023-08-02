extends Node2D

@onready var Player = $AnimationPlayer
@export var light_decay_rate := 1.0
@export var on_hit_sfxs : Array[String] = []
@export var on_shield_sfxs : Array[String] = []
@export var on_miss_sfxs : Array[String] = []

var lifetime := 10.0

func _ready():
	var num = randi() % 2
	Player.play("impact" + str(num + 1))

func _process(delta):
	if lifetime <= 0.0:
		queue_free()
	else:
		lifetime -= delta
	$LightEffect.modulate.a -= delta * light_decay_rate

func setup(size, rot, isMech, isShield):
	if isMech and isShield:
		for child in get_node("OnShield").get_children():
			child.amount = child.amount * size
			child.emitting = true
			if on_hit_sfxs.size() > 0:
				var play_audio = on_shield_sfxs.pick_random()
				if play_audio:
					AudioManager.play_sfx(play_audio, global_position)
	elif isMech:
		for child in get_node("OnHit").get_children():
			child.amount = child.amount * size
			child.emitting = true
			if on_hit_sfxs.size() > 0:
				var play_audio = on_hit_sfxs.pick_random()
				if play_audio:
					AudioManager.play_sfx(play_audio, global_position)
	else:
		for child in get_node("OnMiss").get_children():
			child.amount = child.amount * size
			child.emitting = true
			if on_miss_sfxs.size() > 0:
				var play_audio = on_miss_sfxs.pick_random()
				if play_audio:
					AudioManager.play_sfx(play_audio, global_position)
	
	scale = Vector2(size,size)
	self.global_rotation = rot

