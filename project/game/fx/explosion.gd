extends Node2D

onready var Player = $AnimationPlayer
export var light_decay_rate := 1.0
var lifetime := 5.0

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
		$sparks_mech.emitting = true
		$sparks_miss.visible = false
		$hit_smoke.amount = 8*size
		$hit_smoke.emitting = true
		lifetime = $hit_smoke.lifetime / $hit_smoke.speed_scale
	else:
		$sparks_miss.emitting = true
		$sparks_mech.visible = false
		$miss_smoke.amount = 12*size
		$miss_smoke.emitting = true
		lifetime = $miss_smoke.lifetime / $miss_smoke.speed_scale
	
	scale = Vector2(size,size)
	self.global_rotation = rot

