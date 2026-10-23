class_name StageCamera
extends Node

@export var follow_speed := 6.0

var _cam: Camera2D = null
var _target_node: Node2D = null
var _target_point = null


func setup(cam: Camera2D) -> void:
	_cam = cam


func get_camera() -> Camera2D:
	return _cam


func follow(node: Node2D, snap := false) -> void:
	_target_node = node
	_target_point = null
	if snap:
		snap_to_target()


func look_at_point(point: Vector2, snap := false) -> void:
	_target_node = null
	_target_point = point
	if snap:
		snap_to_target()


func clear_target() -> void:
	_target_node = null
	_target_point = null


func get_target_position():
	if _target_node != null and is_instance_valid(_target_node):
		return _target_node.global_position
	return _target_point


func distance_to_target() -> float:
	var target = get_target_position()
	if target == null or _cam == null:
		return 0.0
	return _cam.global_position.distance_to(target)


func snap_to_target() -> void:
	var target = get_target_position()
	if target != null and _cam != null:
		_cam.global_position = target


func _process(dt: float) -> void:
	var target = get_target_position()
	if target == null or _cam == null:
		return
	_cam.global_position = _cam.global_position.lerp(target, 1.0 - exp(-follow_speed * dt))
