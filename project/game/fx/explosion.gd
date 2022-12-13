extends Node2D

onready var Player = $AnimationPlayer

func _ready():
	var num = randi() % 2
	Player.play("impact" + str(num + 1))

func setup(size, rot, isMech, vel):
	if isMech:
		$sparks_mech.visible = true
		$sparks_miss.visible = false
	else:
		$sparks_miss.visible = true
		$sparks_mech.visible = false
	$sparks_mech.initial_velocity = vel/16
	$sparks_mech.linear_accel = -(vel/64)
	
	scale = Vector2(size,size)
	self.global_rotation = rot


func _on_AnimationPlayer_animation_finished(_anim_name):
	queue_free()
