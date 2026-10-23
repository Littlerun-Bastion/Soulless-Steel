class_name StageWait
extends StageStep

@export var seconds := 1.0


func _start() -> void:
	if seconds <= 0.0:
		_finish()
		return
	get_tree().create_timer(seconds).timeout.connect(_finish)
