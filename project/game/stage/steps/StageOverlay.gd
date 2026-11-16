class_name StageOverlay
extends StageStep

## Plays a full-screen piece over the scene and waits for it to end: a scene
## whose root has play() and a finished signal.
@export var overlay: PackedScene

var _shown: Node = null


func _start() -> void:
	if overlay == null:
		_finish()
		return
	_shown = overlay.instantiate()
	director.add_child(_shown)
	_shown.finished.connect(_finish, CONNECT_ONE_SHOT)
	_shown.play()


func _finish() -> void:
	if is_instance_valid(_shown):
		_shown.queue_free()
	_shown = null
	super()
