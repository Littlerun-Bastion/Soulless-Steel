class_name StageCameraLookAt
extends StageStep

@export var snap := false
@export var wait_until_reached := false
@export var reach_distance := 16.0


func _start() -> void:
	var camera := director.get_camera()
	if camera == null:
		_finish()
		return
	camera.look_at_point(global_position, snap)
	if not wait_until_reached:
		_finish()


func _process(_dt: float) -> void:
	if not is_running():
		return
	var camera := director.get_camera()
	if camera == null or camera.distance_to_target() <= reach_distance:
		_finish()


func _skip_to_end() -> void:
	var camera := director.get_camera()
	if camera != null:
		camera.look_at_point(global_position, true)
	_finish()
