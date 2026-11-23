class_name StageMoveActor
extends StageStep

@export var actor := ""
@export var destination_actor := ""
@export var arrive_distance := 260.0
@export var wait_for_arrival := true
@export var give_up_after := 20.0
@export var straight := false
## Ends the walk once the actor is out of the camera's frame, body and all.
@export var until_out_of_frame := false

const OUT_OF_FRAME_MARGIN := 150.0

var _mech: Node = null
var _elapsed := 0.0


func _start() -> void:
	_mech = director.find_actor(actor)
	if not director.take_actor(_mech):
		_finish()
		return
	_elapsed = 0.0
	if not _push():
		return
	if not wait_for_arrival:
		_finish()


func _skip_to_end() -> void:
	if is_instance_valid(_mech) and _mech.has_method("stop_walking"):
		var point = _destination()
		if point != null:
			_mech.global_position = point
		_mech.stop_walking()
	_finish()


func _process(dt: float) -> void:
	if not is_running():
		return
	if not is_instance_valid(_mech):
		_finish()
		return
	_elapsed += dt
	if give_up_after > 0.0 and _elapsed >= give_up_after:
		_mech.stop_walking()
		_finish()
		return
	_push()


func _destination():
	if destination_actor == "":
		return global_position
	var target := director.find_actor(destination_actor)
	if target is Node2D:
		return target.global_position
	return null


func _push() -> bool:
	var point = _destination()
	if point == null:
		_mech.stop_walking()
		_finish()
		return false
	var slide: float = _mech.stopping_distance() if _mech.has_method("stopping_distance") else 0.0
	if _mech.global_position.distance_to(point) <= arrive_distance + slide:
		_mech.stop_walking()
		_mech.scripted_aim = point
		_finish()
		return false
	if until_out_of_frame and not _in_frame(_mech.global_position):
		_mech.stop_walking()
		_finish()
		return false
	if straight and _mech.has_method("walk_straight_to"):
		_mech.walk_straight_to(point)
	else:
		_mech.walk_to(point)
	_mech.scripted_aim = point
	return true


func _in_frame(point: Vector2) -> bool:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return true
	var size := get_viewport().get_visible_rect().size / cam.zoom
	var frame := Rect2(cam.get_screen_center_position() - size / 2.0, size)
	return frame.grow(OUT_OF_FRAME_MARGIN).has_point(point)
