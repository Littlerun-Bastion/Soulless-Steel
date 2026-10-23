class_name StageMoveActor
extends StageStep

@export var actor := ""
@export var destination_actor := ""
@export var arrive_distance := 260.0
@export var wait_for_arrival := true
@export var give_up_after := 20.0

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
	if _mech.global_position.distance_to(point) <= arrive_distance:
		_mech.stop_walking()
		_mech.scripted_aim = point
		_finish()
		return false
	_mech.walk_to(point)
	_mech.scripted_aim = point
	return true
