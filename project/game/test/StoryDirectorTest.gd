extends Node

# StoryDirectorTest runs self-checks against the StoryDirector autoload and
# the systems wired into it (MissionManager, messenger-style conditions,
# map triggers, save round-trip). Open StoryDirectorTest.tscn and press F6;
# results print to the Output panel.
#
# The player's real story state is snapshotted first and restored at the end,
# and autosave is off while the checks run, so the profile is never touched.

var _passed := 0
var _failed := 0


func _ready() -> void:
	var saved_state = StoryDirector.get_save_data()
	var saved_mission = MissionManager.current_mission
	StoryDirector.autosave = false

	_run("advance and history", _test_advance)
	_run("flags", _test_flags)
	_run("effects and conditions", _test_effects_and_conditions)
	_run("map trigger commands", _test_triggers)
	_run("mission completion applies story effects once", _test_mission)
	_run("contracts survive sorties until completed", _test_contract)
	_run("save data survives JSON round-trip", _test_save_round_trip)

	StoryDirector.set_save_data(saved_state)
	MissionManager.current_mission = saved_mission
	StoryDirector.autosave = true

	print("[StoryDirectorTest] %d passed, %d failed" % [_passed, _failed])


func _run(test_name: String, test: Callable) -> void:
	StoryDirector.reset(false)
	var failures_before := _failed
	test.call()
	if _failed == failures_before:
		print("  PASS ", test_name)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("[StoryDirectorTest] FAIL " + message)


func _test_advance() -> void:
	_check(StoryDirector.is_at(StoryDirector.START_CHAPTER, StoryDirector.START_BEAT), "starts at start beat")
	StoryDirector.advance_to("ch1", "arrival", false)
	StoryDirector.advance_to("ch1", "first_fight", false)
	_check(StoryDirector.is_at("ch1"), "is_at chapter")
	_check(StoryDirector.is_at("ch1", "first_fight"), "is_at beat")
	_check(StoryDirector.has_reached("ch1", "arrival"), "remembers earlier beat")
	_check(StoryDirector.has_reached("prologue"), "remembers earlier chapter")
	_check(not StoryDirector.has_reached("ch2"), "has not reached future chapter")


func _test_flags() -> void:
	var emitted := []
	var on_flag := func(flag_name, value): emitted.append([flag_name, value])
	StoryDirector.flag_changed.connect(on_flag)
	StoryDirector.set_flag("met_volk", true, false)
	StoryDirector.set_flag("met_volk", true, false)
	StoryDirector.flag_changed.disconnect(on_flag)
	_check(StoryDirector.has_flag("met_volk"), "flag set")
	_check(emitted.size() == 1, "setting same value twice emits once")
	_check(StoryDirector.get_flag("missing", 7) == 7, "get_flag default")


func _test_effects_and_conditions() -> void:
	var requires := {"reached": "ch1", "flags": {"accepted_job": true}}
	_check(not StoryDirector.meets(requires), "conditions fail before effects")
	StoryDirector.apply_effects({"advance": "ch1/job", "flags": {"accepted_job": true}})
	_check(StoryDirector.meets(requires), "conditions pass after effects")
	_check(not StoryDirector.meets({"not_reached": "ch1/job"}), "not_reached")
	_check(StoryDirector.meets({}), "empty conditions pass")


func _test_triggers() -> void:
	StoryDirector.handle_trigger("flag=saw_wreck")
	StoryDirector.handle_trigger("advance=ch2/wreck")
	_check(StoryDirector.has_flag("saw_wreck"), "flag trigger")
	_check(StoryDirector.is_at("ch2", "wreck"), "advance trigger")


func _test_mission() -> void:
	var mission := MissionData.new()
	mission.mission_name = "Story test mission"
	mission.add_objective("kill", "Kill 1", 1)
	mission.story_effects = {"advance": "ch1/mission_done", "flags": {"test_mission_done": true}}
	MissionManager.start_mission(mission)

	var completions := [0]
	var on_complete := func(_m): completions[0] += 1
	MissionManager.mission_completed.connect(on_complete)
	MissionManager.report_kill()
	MissionManager.report_kill()
	MissionManager.mission_completed.disconnect(on_complete)

	_check(completions[0] == 1, "mission_completed emitted once")
	_check(StoryDirector.is_at("ch1", "mission_done"), "mission advanced story")
	_check(StoryDirector.has_flag("test_mission_done"), "mission set flag")


func _test_contract() -> void:
	var contract := MissionData.new()
	contract.mission_name = "Story test contract"
	contract.add_objective("kill", "Kill 2", 2)
	contract.story_effects = {"flags": {"test_contract_done": true}}
	MissionManager.accept_contract(contract)

	# First sortie: one kill, then the player dies (no completion).
	MissionManager.start_default_mission(_make_default_mission())
	_check(MissionManager.current_mission == contract, "default mission doesn't replace an active contract")
	MissionManager.report_kill()

	# Next sortie starts fresh: progress resets, contract still active.
	MissionManager.start_default_mission(_make_default_mission())
	_check(MissionManager.current_mission == contract, "contract still active on the next sortie")
	_check(contract.objectives[0].current_amount == 0, "contract progress resets each sortie")
	MissionManager.report_kill()
	MissionManager.report_kill()
	_check(contract.completed, "contract completes within one sortie")
	_check(StoryDirector.has_flag("test_contract_done"), "contract story effects applied")

	# Once completed, the next sortie gets the default mission again.
	var default_mission := _make_default_mission()
	MissionManager.start_default_mission(default_mission)
	_check(MissionManager.current_mission == default_mission, "default mission used after contract completes")


func _make_default_mission() -> MissionData:
	var mission := MissionData.new()
	mission.mission_name = "Default test mission"
	mission.add_objective("extract", "Extract", 1)
	return mission


func _test_save_round_trip() -> void:
	StoryDirector.advance_to("ch3", "finale", false)
	StoryDirector.set_flag("choice", 2, false)
	var json := JSON.stringify(StoryDirector.get_save_data())
	StoryDirector.reset(false)
	StoryDirector.set_save_data(JSON.parse_string(json))
	_check(StoryDirector.is_at("ch3", "finale"), "position restored")
	_check(StoryDirector.has_reached("prologue", "start"), "history restored")
	_check(StoryDirector.get_flag("choice") == 2, "flag restored (JSON makes it a float)")
