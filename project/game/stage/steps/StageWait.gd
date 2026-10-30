class_name StageWait
extends StageStep

@export var seconds := 1.0

var _elapsed := 0.0


func _start() -> void:
	_elapsed = 0.0
	if seconds <= 0.0:
		_finish()


func _process(dt: float) -> void:
	if not is_running():
		return
	_elapsed += dt
	if _elapsed >= seconds:
		_finish()
