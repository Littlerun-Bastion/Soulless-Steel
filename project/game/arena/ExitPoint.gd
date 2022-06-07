extends Node2D

signal mecha_extracting
signal extracting_cancelled


func _on_Area2D_body_entered(body):
	if body is Mecha:
		emit_signal("mecha_extracting", body)


func _on_Area2D_body_exited(body):
	if body is Mecha:
		emit_signal("extracting_cancelled", body)
