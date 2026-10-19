extends Logger
class_name TestErrorWatch

# Collects every error Godot reports while tests run (script errors,
# push_error, failed loads, engine errors), so a test fails on errors its
# checks never looked at. Warnings are ignored.
#
# ALLOWED lists known harmless engine noise; a test that triggers an error on
# purpose calls TestSuite.expect_error() first. Godot may log from other
# threads, hence the mutex.

const ALLOWED := [
	# Shader compiler noise printed whenever certain canvas shaders compile.
	# Harmless and outside the project's control.
	"actions.custom_samplers.has",
]

var _mutex := Mutex.new()
var _errors: Array[String] = []
var _expected: Array[String] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := ("%s %s" % [code, rationale]).strip_edges()
	var where := "%s:%d" % [file.get_file(), line]
	# push_error and engine errors raised from a script: point at the script.
	if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
		var bt: ScriptBacktrace = script_backtraces[0]
		where = "%s:%d" % [bt.get_frame_file(0).get_file(), bt.get_frame_line(0)]
	elif function != "":
		where = "%s (%s)" % [where, function]
	_mutex.lock()
	if not _is_allowed(text):
		_errors.append("%s  [%s]" % [text, where])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


# Allow one error containing this text (until take_errors).
func expect(substring: String) -> void:
	_mutex.lock()
	_expected.append(substring)
	_mutex.unlock()


# The errors since the last call, and forget them and any unused expect().
func take_errors() -> Array[String]:
	_mutex.lock()
	var result := _errors.duplicate()
	_errors.clear()
	_expected.clear()
	_mutex.unlock()
	return result


func _is_allowed(text: String) -> bool:
	for allowed in ALLOWED:
		if allowed in text:
			return true
	for i in _expected.size():
		if _expected[i] in text:
			_expected.remove_at(i)
			return true
	return false
