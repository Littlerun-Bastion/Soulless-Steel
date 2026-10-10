extends Node

# ExpeditionHudTest runs self-checks on the in-run feedback: the mission
# tracker following MissionManager, the load readout, and the extraction
# summary. Open ExpeditionHudTest.tscn and press F6; results print to Output.
#
# MissionManager's current mission is restored at the end.

const MISSION_TRACKER := preload("res://game/ui/MissionTracker.tscn")
const EXTRACTION_SUMMARY := preload("res://game/expedition/ExtractionSummary.tscn")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var saved_mission = MissionManager.current_mission

	_run("mission_started signal", _test_mission_started)
	_run("mission tracker follows the mission", _test_tracker)
	_run("load readout", _test_load)
	_run("extraction summary", _test_summary)

	MissionManager.current_mission = saved_mission
	print("[ExpeditionHudTest] %d passed, %d failed" % [_passed, _failed])


func _run(test_name: String, test: Callable) -> void:
	var failures_before := _failed
	test.call()
	if _failed == failures_before:
		print("  PASS ", test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("[ExpeditionHudTest] FAIL " + message)


func _make_mission() -> MissionData:
	var mission := MissionData.new()
	mission.mission_name = "Survive and Extract"
	mission.add_objective("kill", "Eliminate enemies", 3)
	mission.add_objective("extract", "Reach an exit and extract", 1)
	return mission


func _test_mission_started() -> void:
	var started := []
	var on_started := func(m): started.append(m)
	MissionManager.mission_started.connect(on_started)

	var mission := _make_mission()
	MissionManager.start_mission(mission)
	_check(started == [mission], "start_mission announces the mission")

	var contract := _make_mission()
	MissionManager.accept_contract(contract)
	MissionManager.report_kill()
	started.clear()
	MissionManager.start_default_mission(_make_mission())
	_check(started == [contract], "a kept contract is announced again for the new sortie")
	_check(contract.objectives[0].current_amount == 0, "with its progress reset")

	MissionManager.mission_started.disconnect(on_started)
	contract.completed = true  # don't leave an active contract behind


func _test_tracker() -> void:
	MissionManager.current_mission = null
	var tracker: MissionTracker = MISSION_TRACKER.instantiate()
	add_child(tracker)
	_check(not tracker.visible, "hidden with no mission")

	MissionManager.start_mission(_make_mission())
	_check(tracker.visible and tracker.title_label.text == "Survive and Extract", "shows the mission")
	var lines := _lines(tracker)
	_check(lines.size() == 2 and lines[0] == "[ ] Eliminate enemies  0/3", "objective with progress")
	_check(lines[1] == "[ ] Reach an exit and extract", "single-step objective has no counter")

	MissionManager.report_kill()
	_check(_lines(tracker)[0] == "[ ] Eliminate enemies  1/3", "updates on kills")
	MissionManager.report_kill()
	MissionManager.report_kill()
	MissionManager.report_extraction()
	_check(_lines(tracker)[0] == "[X] Eliminate enemies  3/3", "objective ticked when done")
	_check(tracker.title_label.text.ends_with("[COMPLETE]"), "mission marked complete")

	var contract := _make_mission()
	MissionManager.accept_contract(contract)
	_check(tracker.title_label.text.begins_with("CONTRACT: "), "contracts are labelled")
	contract.completed = true
	tracker.queue_free()


func _lines(tracker: MissionTracker) -> Array:
	var lines := []
	for child in tracker.objective_list.get_children():
		if not child.is_queued_for_deletion():
			lines.append(child.text)
	return lines


func _test_load() -> void:
	_check(LoadIndicator.format_load(412.4, 500.0) == "LOAD 412 / 500", "load text")
	_check(LoadIndicator.color_for(100.0, 500.0) == LoadIndicator.NORMAL_COLOR, "normal under 90%")
	_check(LoadIndicator.color_for(460.0, 500.0) == LoadIndicator.WARN_COLOR, "amber from 90%")
	_check(LoadIndicator.color_for(501.0, 500.0) == LoadIndicator.OVER_COLOR, "red when overweight")


func _test_summary() -> void:
	var mission := _make_mission()
	mission.objectives[1].current_amount = 1
	mission.objectives[1].completed = true
	var text := ExtractionSummary.format_summary(["Fusion Cell", "Scrap Plating x2"], 2, mission)
	_check("Cargo secured: Fusion Cell, Scrap Plating x2" in text, "lists the cargo")
	_check("Kills: 2" in text, "counts kills")
	_check("Mission: Survive and Extract - incomplete" in text, "mission status")
	_check("[X] Reach an exit and extract" in text and "[ ] Eliminate enemies  0/3" in text, "objectives listed")
	_check("Cargo secured: nothing" in ExtractionSummary.format_summary([], 0, null), "empty run")

	var summary: ExtractionSummary = EXTRACTION_SUMMARY.instantiate()
	add_child(summary)
	_check(not summary.visible, "hidden until shown")
	summary.show_summary(["Fusion Cell"], 1, mission)
	_check(summary.visible and summary.body_label.text.begins_with("Cargo secured: Fusion Cell"), "shows the summary")
	var continued := [false]
	summary.continued.connect(func(): continued[0] = true)
	summary.continue_button.pressed.emit()
	_check(continued[0], "Continue emits continued")
	MouseManager.force_pointer(false)
	summary.queue_free()
