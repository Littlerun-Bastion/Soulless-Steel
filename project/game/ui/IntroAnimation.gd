extends Node2D

signal animation_ending


func play(name):
	$AnimationPlayer.play(name)


func entrance_animation_ending():
	emit_signal("animation_ending")
