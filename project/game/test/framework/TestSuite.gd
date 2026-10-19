extends Node
class_name TestSuite

# Base for the automated test suites in game/test/suites/. RunAllTests.tscn
# runs them all (or run_tests.bat from the repo root); to run one suite alone,
# open its scene and press F6.
#
# A suite overrides run_tests() and calls case() for each test case; inside a
# case, check() / check_eq() record results. A case fails if a check fails or
# Godot reports any error while it runs (see TestErrorWatch). Cases may await:
# wait_frames(), wait_seconds() and wait_until() help with that.
#
# Every suite starts from the player's real state and puts it back afterwards:
# progress, story and the current mission are restored, autosave is off and
# FileManager refuses to save, so the real profile is never written. Mech OS is
# reset after each suite.

## Whole-game simulations set this; the fast run (pre-commit hook) skips them.
var slow := false
## How fast game time runs during the suite (Engine.time_scale). Physics-heavy
## simulations can lower it.
var time_scale := 4.0

## Problems already reported but not fixed yet (often in a teammate's code).
## A failure whose text contains a key is listed as a known issue instead of
## failing the run. Key -> who flagged it and why. Set in _init(); remove the
## entry once it's fixed (the report says when one stops happening).
var known_issues := {}

var passed := 0
var failed := 0
var failures: Array[String] = []
var known_hits: Array[String] = []
var fixed_known_issues: Array[String] = []
var errors: TestErrorWatch = null

var _case_name := ""
var _known_seen := {}
var _saved := {}
var _session: TestSession = null  # kept while running alone (F6)


# Override: the suite's cases, in order.
func run_tests() -> void:
	pass


# Override: runs before every case (e.g. to reset state).
func before_each() -> void:
	pass


func get_suite_name() -> String:
	return get_script().resource_path.get_file().get_basename()


# ---- Running ----

func _ready() -> void:
	# Opened on its own (F6): run just this suite.
	if get_tree().current_scene == self:
		_session = TestSession.new()
		_session.run_standalone(self)


func run_suite() -> void:
	_save_state()
	_take_errors_as("setup")
	await run_tests()
	_take_errors_as("outside a case")
	await _restore_state()
	_take_errors_as("teardown")
	_report_fixed_known_issues()


func case(case_name: String, test: Callable) -> void:
	_case_name = case_name
	var failed_before := failed
	_take_errors_as("before " + case_name)
	await before_each()
	await test.call()
	for error in errors.take_errors():
		_fail("unexpected error: " + error)
	print("  %s %s" % ["PASS" if failed == failed_before else "FAIL", case_name])
	_case_name = ""


# ---- Checks ----

func check(condition: bool, message: String) -> bool:
	if condition:
		passed += 1
	else:
		_fail(message)
	return condition


func check_eq(actual, expected, message: String) -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


# The next error containing this text is part of the test, not a failure.
func expect_error(substring: String) -> void:
	if errors != null:
		errors.expect(substring)


# ---- Waiting ----

func wait_frames(count := 1) -> void:
	for _i in count:
		await get_tree().process_frame


# Game time: shorter when the runner speeds the game up (Engine.time_scale).
func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# Waits until condition returns true; false if it didn't within timeout
# (game-time seconds).
func wait_until(condition: Callable, timeout := 5.0) -> bool:
	var waited := 0.0
	while not condition.call():
		if waited >= timeout:
			return false
		await get_tree().process_frame
		waited += get_process_delta_time()  # already scaled by Engine.time_scale
	return true


# ---- Internals ----

func _fail(message: String, where := "") -> void:
	if where == "":
		where = _case_name if _case_name != "" else "suite"
	for key in known_issues:
		if key in message:
			_known_seen[key] = true
			known_hits.append("%s  (%s)" % [message, known_issues[key]])
			print("    KNOWN [%s] %s" % [where, message])
			return
	failed += 1
	failures.append("%s: %s" % [where, message])
	printerr("    FAIL [%s] %s" % [where, message])


func _take_errors_as(where: String) -> void:
	if errors == null:
		return
	for error in errors.take_errors():
		_fail("unexpected error: " + error, where)


# Known issues that didn't come up this run were probably fixed.
func _report_fixed_known_issues() -> void:
	for key in known_issues:
		if not _known_seen.has(key):
			fixed_known_issues.append(key)


func _save_state() -> void:
	_saved = {
		"progress": JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data())),
		"story": JSON.parse_string(JSON.stringify(StoryDirector.get_save_data())),
		"mission": MissionManager.current_mission,
		"profile_loaded": FileManager.profile_loaded,
	}
	FileManager.profile_loaded = false
	PlayerProgress.autosave = false
	StoryDirector.autosave = false


func _restore_state() -> void:
	MechOS.close_all()
	MechOS.set_player(null)
	MechOS.recycling_enabled = false
	MechOS.set_equipment_customizable(true)
	MechOS.set_app_available("materials", false)
	get_tree().paused = false
	await wait_frames(2)  # let freed nodes go before restoring state
	PlayerProgress.set_save_data(_saved["progress"])
	StoryDirector.set_save_data(_saved["story"])
	MissionManager.current_mission = _saved["mission"]
	PlayerProgress.autosave = true
	StoryDirector.autosave = true
	FileManager.profile_loaded = _saved["profile_loaded"]
