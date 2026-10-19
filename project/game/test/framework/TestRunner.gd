extends Node

# Root of RunAllTests.tscn: runs every suite in game/test/suites/ (see
# TestSession for the command-line options). Press F6 on RunAllTests.tscn, or
# run run_tests.bat from the repo root.

var _session := TestSession.new()


func _ready() -> void:
	_session.run_all(self)
