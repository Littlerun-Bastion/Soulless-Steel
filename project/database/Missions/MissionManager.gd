extends Node

# MissionManager holds the one active mission and advances its objectives.
#
# Two kinds of mission:
#   - contracts: accepted outside a match (the messenger) via accept_contract.
#     They stay active across sorties until completed.
#   - default missions: each combat scene offers one via start_default_mission
#     when the sortie begins. It's only used if no contract is active.
#
# Every sortie is a fresh attempt: an active contract's progress is reset
# when a sortie starts, so its objectives must be met within one run.

signal objective_updated(objective)
signal mission_completed(mission)

var current_mission = null

# Replaces whatever mission is active.
func start_mission(mission) -> void:
	current_mission = mission

# Starts a mission that survives until completed (see header).
func accept_contract(mission) -> void:
	mission.is_contract = true
	start_mission(mission)

func has_active_contract() -> bool:
	return current_mission != null and current_mission.is_contract and not current_mission.completed

# Called by combat scenes when a sortie begins.
func start_default_mission(default_mission) -> void:
	if has_active_contract():
		_reset_progress(current_mission)
		if Debug.get_setting("verbose_logging"):
			print("[MissionManager] contract active, keeping: ", current_mission.mission_name)
		return
	start_mission(default_mission)

func report_kill() -> void:
	_progress_objectives("kill")

func report_extraction() -> void:
	_progress_objectives("extract")

func report_location_reached() -> void:
	_progress_objectives("reach_location")

func _reset_progress(mission) -> void:
	for obj in mission.objectives:
		obj.current_amount = 0
		obj.completed = false

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
	if current_mission == null or current_mission.completed:
		return
	for obj in current_mission.objectives:
		if not obj.completed:
			return
	current_mission.completed = true
	emit_signal("mission_completed", current_mission)
