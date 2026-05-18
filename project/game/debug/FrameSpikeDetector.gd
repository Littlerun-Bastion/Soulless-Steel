extends Node

# Frame-time spike detector. Watches frame delta every _process tick and
# prints a console line when any frame exceeds SPIKE_THRESHOLD_MS. Pair with
# FrameSpikeDetector.mark("doing thing X") sprinkled in suspected hot paths
# to see what was running when the spike fired.
#
# Add to autoloads in project.godot:
#   FrameSpikeDetector="*res://game/debug/FrameSpikeDetector.gd"
#
# Output line shape:
#   [SPIKE] 34.2 ms at t=12.45s — last_action: spawn_explosion(core)
#                                                   ^ whatever you last marked

const SPIKE_THRESHOLD_MS := 20.0       # Anything above this is logged.
const COOLDOWN_MS := 100               # Avoid double-logging within a single
                                        # cluster of bad frames.
const TRAIL_LENGTH := 5                # How many recent marks to keep around
                                        # so the spike log has context.

var enabled: bool = true
var last_action: String = "idle"

var _last_print_ms: int = -10000
var _action_trail: Array[String] = []


func _process(delta: float) -> void:
	if not enabled:
		return
	var delta_ms: float = delta * 1000.0
	if delta_ms < SPIKE_THRESHOLD_MS:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_print_ms < COOLDOWN_MS:
		return
	_last_print_ms = now_ms
	var t_sec: float = now_ms / 1000.0
	var trail_str: String = " <- ".join(_action_trail) if _action_trail.size() > 0 else "(no marks)"
	print("[SPIKE] %.1f ms at t=%.2fs — last_action: %s — trail: %s" \
			% [delta_ms, t_sec, last_action, trail_str])


# Tag what the game is doing right now. Call this from any suspect hot path
# so spike logs tell us *what* was running when the spike fired.
# Example:  FrameSpikeDetector.mark("spawn_component_explosion(%s)" % part_name)
func mark(action: String) -> void:
	last_action = action
	_action_trail.push_back(action)
	if _action_trail.size() > TRAIL_LENGTH:
		_action_trail.pop_front()
