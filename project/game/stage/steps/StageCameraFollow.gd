class_name StageCameraFollow
extends StageStep

@export var actor := ""
@export var snap := false


func _start() -> void:
	_aim(snap)
	_finish()


func _skip_to_end() -> void:
	_aim(true)
	_finish()


func _aim(snap_now: bool) -> void:
	var camera := director.get_camera()
	if camera == null:
		return
	var target := director.find_actor(actor)
	if target is Node2D:
		camera.follow(target, snap_now)
