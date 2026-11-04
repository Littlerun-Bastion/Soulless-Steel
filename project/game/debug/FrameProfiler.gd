class_name FrameProfiler
extends RefCounted

## Where a frame's script time goes, by system. Off unless the Debug setting
## "frame_profile" is on (or a test turns it on): then the instrumented
## systems add the microseconds each of their callbacks took under a key
## (add), and report() gives the mean and worst per frame for every key over
## the frames since reset(). The whole-frame ablation that FrameCostProbe
## tried first drifted too much from window to window to attribute anything;
## timing inside the callbacks holds up under load because every system is
## measured in the same frames.
##
## Instrumented: "mecha" (Mecha._physics_process, the base of every mecha,
## with "sounds", "mines", "anim" and "heat" under it), "npc_think" (an
## NPC's thinking frame: "npc_senses", "npc_scores" and "npc_behaviour",
## the last with "targets", "pick", "fire", "steer", "steer_build" and
## "navigate", which holds "route", "move", "dashes" and "rotate"),
## "npc_drive" (a scripted NPC's walk, or the coasting between thinks),
## "player" (Player._physics_process without the Mecha base), "buildings"
## (BuildingField), "vehicles" (VehicleField), "heat_trails", "blood",
## "devices", "entities" (Entity._physics_process), "sand_bodies" (a sand
## creature's animation, in _process), "hud" (PlayerHUD), "map_streamer",
## "prop_layers", "overhead_paths". An indented key is part of the key
## above it, so the keys' sum counts it twice. A system's own callback time
## only; what the engine does between callbacks (the physics step,
## navigation, rendering) is the frame total less the sum.
##
## Cost when off: one static bool read per instrumented callback.

static var enabled := false
static var _usec := {}
static var _calls := {}
static var _worst := {}
static var _frame_usec := {}
static var _frames := 0
static var _last_frame := -1


static func start() -> int:
	return Time.get_ticks_usec() if enabled else 0


## Adds the time since `started` (from start()) under `key`.
static func add(key: String, started: int) -> void:
	if not enabled:
		return
	var frame := Engine.get_physics_frames()
	if frame != _last_frame:
		_last_frame = frame
		_frames += 1
		for k in _frame_usec:
			_worst[k] = maxi(int(_worst.get(k, 0)), int(_frame_usec[k]))
		_frame_usec.clear()
	var took := Time.get_ticks_usec() - started
	_usec[key] = int(_usec.get(key, 0)) + took
	_calls[key] = int(_calls.get(key, 0)) + 1
	_frame_usec[key] = int(_frame_usec.get(key, 0)) + took


static func reset() -> void:
	_usec.clear()
	_calls.clear()
	_worst.clear()
	_frame_usec.clear()
	_frames = 0
	_last_frame = -1


## Mean ms per frame, worst ms in one frame and calls per frame, by key,
## heaviest first.
static func report() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key in _usec:
		rows.append({"key": key, "mean_ms": float(_usec[key]) / maxi(_frames, 1) / 1000.0,
				"worst_ms": float(_worst.get(key, 0)) / 1000.0,
				"calls_per_frame": float(_calls[key]) / maxi(_frames, 1)})
	rows.sort_custom(func(a, b): return a.mean_ms > b.mean_ms)
	return rows


static func frames() -> int:
	return _frames


static func report_text() -> String:
	var lines := PackedStringArray(["[FrameProfiler] %d frames, ms per frame by system:" % _frames])
	var total := 0.0
	for row in report():
		total += row.mean_ms
		lines.append("  %-16s mean %6.3f  worst %6.2f  calls/frame %6.1f" % [row.key, row.mean_ms, row.worst_ms, row.calls_per_frame])
	lines.append("  %-16s mean %6.3f" % ["(sum)", total])
	return "\n".join(lines)
