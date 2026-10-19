extends TestSuite

# ExpeditionHudTest: the in-run feedback — the mission tracker following
# MissionManager, the load readout, and the extraction summary.

const MISSION_TRACKER := preload("res://game/ui/MissionTracker.tscn")
const EXTRACTION_SUMMARY := preload("res://game/expedition/ExtractionSummary.tscn")


func run_tests() -> void:
	await case("mission_started signal", _test_mission_started)
	await case("mission tracker follows the mission", _test_tracker)
	await case("load readout", _test_load)
	await case("extraction summary", _test_summary)


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
	check(started == [mission], "start_mission announces the mission")

	var contract := _make_mission()
	MissionManager.accept_contract(contract)
	MissionManager.report_kill()
	started.clear()
	MissionManager.start_default_mission(_make_mission())
	check(started == [contract], "a kept contract is announced again for the new sortie")
	check(contract.objectives[0].current_amount == 0, "with its progress reset")

	MissionManager.mission_started.disconnect(on_started)
	contract.completed = true  # don't leave an active contract behind


func _test_tracker() -> void:
	MissionManager.current_mission = null
	var tracker: MissionTracker = MISSION_TRACKER.instantiate()
	add_child(tracker)
	check(not tracker.visible, "hidden with no mission")

	MissionManager.start_mission(_make_mission())
	check(tracker.visible and tracker.title_label.text == "Survive and Extract", "shows the mission")
	var lines := _lines(tracker)
	check(lines.size() == 2 and lines[0] == "[ ] Eliminate enemies  0/3", "objective with progress")
	check(lines[1] == "[ ] Reach an exit and extract", "single-step objective has no counter")

	MissionManager.report_kill()
	check(_lines(tracker)[0] == "[ ] Eliminate enemies  1/3", "updates on kills")
	MissionManager.report_kill()
	MissionManager.report_kill()
	MissionManager.report_extraction()
	check(_lines(tracker)[0] == "[X] Eliminate enemies  3/3", "objective ticked when done")
	check(tracker.title_label.text.ends_with("[COMPLETE]"), "mission marked complete")

	var contract := _make_mission()
	MissionManager.accept_contract(contract)
	check(tracker.title_label.text.begins_with("CONTRACT: "), "contracts are labelled")
	contract.completed = true
	tracker.queue_free()


func _lines(tracker: MissionTracker) -> Array:
	var lines := []
	for child in tracker.objective_list.get_children():
		if not child.is_queued_for_deletion():
			lines.append(child.text)
	return lines


func _test_load() -> void:
	check(LoadIndicator.format_load(412.4, 500.0) == "LOAD 412 / 500", "load text")
	check(LoadIndicator.color_for(100.0, 500.0) == LoadIndicator.NORMAL_COLOR, "normal under 90%")
	check(LoadIndicator.color_for(460.0, 500.0) == LoadIndicator.WARN_COLOR, "amber from 90%")
	check(LoadIndicator.color_for(501.0, 500.0) == LoadIndicator.OVER_COLOR, "red when overweight")


func _test_summary() -> void:
	var mission := _make_mission()
	mission.objectives[1].current_amount = 1
	mission.objectives[1].completed = true
	var text := ExtractionSummary.format_summary(["Damaged NT Engine", "Armor Plate Fragment x2"], 2, mission)
	check("Cargo secured: Damaged NT Engine, Armor Plate Fragment x2" in text, "lists the cargo")
	check("Kills: 2" in text, "counts kills")
	check("Mission: Survive and Extract - incomplete" in text, "mission status")
	check("[X] Reach an exit and extract" in text and "[ ] Eliminate enemies  0/3" in text, "objectives listed")
	check("Cargo secured: nothing" in ExtractionSummary.format_summary([], 0, null), "empty run")

	var summary: ExtractionSummary = EXTRACTION_SUMMARY.instantiate()
	add_child(summary)
	check(not summary.visible, "hidden until shown")
	summary.show_summary(["Damaged NT Engine"], 1, mission)
	check(summary.visible and summary.body_label.text.begins_with("Cargo secured: Damaged NT Engine"), "shows the summary")
	var continued := [false]
	summary.continued.connect(func(): continued[0] = true)
	summary.continue_button.pressed.emit()
	check(continued[0], "Continue emits continued")
	MouseManager.force_pointer(false)
	summary.queue_free()
