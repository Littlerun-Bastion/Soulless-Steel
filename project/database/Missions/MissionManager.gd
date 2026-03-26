extends Node

signal objective_updated(objective)
signal mission_completed

var current_mission = null

func start_mission(mission) -> void:
	current_mission = mission

func report_kill() -> void:
	_progress_objectives("kill")

func report_extraction() -> void:
	_progress_objectives("extract")

func report_location_reached() -> void:
	_progress_objectives("reach_location")

func _progress_objectives(type: String) -> void:
	if current_mission == null:
		return
	for obj in current_mission.objectives:
		if obj.type == type and not obj.completed:
			obj.current_amount += 1
			if obj.current_amount >= obj.target_amount:
				obj.completed = true
			emit_signal("objective_updated", obj)
	_check_mission_complete()

func _check_mission_complete() -> void:
	if current_mission == null:
		return
	for obj in current_mission.objectives:
		if not obj.completed:
			return
	emit_signal("mission_completed")
