extends Node2D

onready var Player = $AnimationPlayer

func _ready():
	var num = randi() % 2
	Player.play("impact" + str(num + 1))

func setup(size, rot, isMech, vel):
	if isMech:
		$sparks_mech.emitting = true
		$sparks_miss.visible = false
		$hit_smoke.amount = 8*size
		$hit_smoke.emitting = true
	else:
		$sparks_miss.emitting = true
		$sparks_mech.visible = false
		$miss_smoke.amount = 12*size
		$miss_smoke.emitting = true
	
	scale = Vector2(size,size)
	self.global_rotation = rot


func _on_AnimationPlayer_animation_finished(_anim_name):
	queue_free()
