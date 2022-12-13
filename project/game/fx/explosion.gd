extends Node2D

onready var Player = $AnimationPlayer

func _ready():
	self.rotate(randi())
	var num = randi() % 2
	Player.play("impact" + str(num + 1))


func _on_AnimationPlayer_animation_finished(_anim_name):
	queue_free()
