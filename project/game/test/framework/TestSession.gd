extends RefCounted
class_name TestSession

# Runs test suites one after another and prints the report. Used by
# RunAllTests.tscn (every suite in game/test/suites/) and by a suite opened on
# its own with F6.
#
# Command-line options (after "--", see run_tests.bat):
#   --suite=Hangar,Wreck   only suites whose name contains one of these
#   --fast                 skip slow suites (whole-game simulations)
# Run headless or with --quit, the game exits when done: code 0 if everything
# passed, 1 otherwise.

const SUITES_DIR := "res://game/test/suites/"

var watch := TestErrorWatch.new()
var _results: Array = []  # {name, passed, failed, failures, seconds, skipped}
var _quieted := {}


static func get_options() -> Dictionary:
	var options := {"suites": [], "fast": false}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			options["suites"] = Array(arg.trim_prefix("--suite=").split(",", false))
		elif arg == "--fast":
			options["fast"] = true
	return options


static func should_quit() -> bool:
	return DisplayServer.get_name() == "headless" or "--quit" in OS.get_cmdline_user_args()


static func find_suite_scenes() -> Array[String]:
	var scenes: Array[String] = []
	for file in DirAccess.get_files_at(SUITES_DIR):
		if file.ends_with(".tscn"):
			scenes.append(SUITES_DIR + file)
	scenes.sort()
	return scenes


# Every suite scene, filtered by the command-line options. host keeps them in
# the tree while they run.
func run_all(host: Node) -> bool:
	var options := get_options()
	_begin()
	for path in find_suite_scenes():
		var suite_name := path.get_file().get_basename()
		if not _matches(suite_name, options["suites"]):
			continue
		var suite: TestSuite = load(path).instantiate()
		if options["fast"] and suite.slow:
			_results.append({"name": suite_name, "skipped": true})
			suite.free()
			continue
		await _run_suite(suite, host)
	return _finish(host)


func run_standalone(suite: TestSuite) -> void:
	_begin()
	await _run_suite(suite, null)
	_finish(suite)


func _begin() -> void:
	OS.add_logger(watch)
	# The game's diagnostic prints would bury the results.
	_quieted = {"verbose": Debug.debug_settings.get("verbose_logging"), "spikes": FrameSpikeDetector.enabled}
	Debug.debug_settings["verbose_logging"] = false
	FrameSpikeDetector.enabled = false
	print("\n=== Soulless Steel tests ===")


func _run_suite(suite: TestSuite, host: Node) -> void:
	print("\n[%s]" % suite.get_suite_name())
	suite.errors = watch
	watch.take_errors()
	var started := Time.get_ticks_msec()
	Engine.time_scale = suite.time_scale
	if host != null:
		host.add_child(suite)
	await suite.run_suite()
	_results.append({
		"name": suite.get_suite_name(),
		"passed": suite.passed,
		"failed": suite.failed,
		"failures": suite.failures.duplicate(),
		"known": suite.known_hits.duplicate(),
		"fixed": suite.fixed_known_issues.duplicate(),
		"seconds": (Time.get_ticks_msec() - started) / 1000.0,
	})
	if host != null:
		suite.queue_free()
		await host.get_tree().process_frame


func _finish(node: Node) -> bool:
	Engine.time_scale = 1.0
	OS.remove_logger(watch)
	Debug.debug_settings["verbose_logging"] = _quieted["verbose"]
	FrameSpikeDetector.enabled = _quieted["spikes"]
	var all_passed := true
	var checks := 0
	var seconds := 0.0
	var failed_suites := 0
	print("\n=== Summary ===")
	for result in _results:
		if result.get("skipped", false):
			print("  SKIP  %s (slow)" % result["name"])
			continue
		checks += result["passed"] + result["failed"]
		seconds += result["seconds"]
		if result["failed"] == 0:
			print("  PASS  %-24s %4d checks  %5.1fs" % [result["name"], result["passed"], result["seconds"]])
		else:
			all_passed = false
			failed_suites += 1
			print("  FAIL  %-24s %4d of %d checks failed  %5.1fs" % [result["name"], result["failed"],
					result["passed"] + result["failed"], result["seconds"]])
			for failure in result["failures"]:
				print("          - " + failure)
	if _results.is_empty():
		all_passed = false
		print("  No suites matched.")
	_print_known_issues()
	if all_passed:
		print("\nRESULT: PASSED  (%d suites, %d checks, %.1fs)" % [_results.size(), checks, seconds])
	else:
		print("\nRESULT: FAILED  (%d of %d suites)" % [failed_suites, _results.size()])
	if should_quit():
		node.get_tree().quit(0 if all_passed else 1)
	return all_passed


func _matches(suite_name: String, filters: Array) -> bool:
	if filters.is_empty():
		return true
	for filter in filters:
		if str(filter).to_lower() in suite_name.to_lower():
			return true
	return false


# Flagged problems (TestSuite.known_issues): listed so they stay visible, but
# they don't fail the run.
func _print_known_issues() -> void:
	var known := []
	var fixed := []
	for result in _results:
		for hit in result.get("known", []):
			known.append("%s: %s" % [result["name"], hit])
		for key in result.get("fixed", []):
			fixed.append("%s: %s" % [result["name"], key])
	if not known.is_empty():
		print("\n  Known issues (flagged, not failing):")
		for line in known:
			print("          - " + line)
	if not fixed.is_empty():
		print("\n  Known issues that didn't happen this run (fixed? remove them from known_issues):")
		for line in fixed:
			print("          - " + line)
