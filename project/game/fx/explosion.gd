extends Node2D

@onready var Player = $AnimationPlayer
@export var light_decay_rate := 1.0


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

func setup(size, rot, isMech):
	if isMech: 
		for child in get_node("OnHit").get_children():
			child.amount = child.amount * size
			child.emitting = true
	else:
		for child in get_node("OnMiss").get_children():
			child.amount = child.amount * size
			child.emitting = true
	
	scale = Vector2(size,size)
	self.global_rotation = rot

