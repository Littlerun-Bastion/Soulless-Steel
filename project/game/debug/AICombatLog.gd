class_name AICombatLog
extends RefCounted

# Collects numbers about NPC fights while the Debug setting "ai_log" is on,
# and prints a summary every REPORT_INTERVAL seconds (real time):
#   - shot distances: NPCs firing at what they see, NPCs firing blind
#     (through walls, at a last-known position), and the player's shots that
#     pass near an NPC. Each is counted in distance bands, with the median.
#   - engage distances: how far away the target was when an NPC entered
#     combat.
#   - stuck events: each time an NPC is blocked, soft-reset or teleported,
#     with the cause and where it happened.
# Everything is static, so any script can record without a reference. When
# "ai_log" is off, every record call returns at once.

const REPORT_INTERVAL := 30.0
## Distance band edges in metres (20 px = 1 m).
const BANDS := [25.0, 50.0, 75.0, 100.0]
const PX_PER_M := 20.0
const MAX_SAMPLES := 4000
## Stuck positions kept for the report.
const STUCK_KEEP := 8

static var _distances := {}
static var _stuck_counts := {}
static var _stuck_recent: Array = []
static var _last_report_ms := 0


static func enabled() -> bool:
	return Debug.get_setting("ai_log")


# An NPC fired at a target `distance_px` away. `blind`: at a last-known
# position, out of sight.
static func record_shot(_npc, distance_px: float, blind: bool) -> void:
	if not enabled():
		return
	_add("npc_blind" if blind else "npc_seen", distance_px)
	_maybe_report()


# A player shot passed near an NPC; `distance_px` from the player to it.
static func record_player_shot(distance_px: float) -> void:
	if not enabled():
		return
	_add("player", distance_px)
	_maybe_report()


# An NPC entered combat with a target `distance_px` away.
static func record_engage(distance_px: float) -> void:
	if not enabled():
		return
	_add("engage", distance_px)
	_maybe_report()


# An NPC got stuck. `cause` is a short label (for example "blocked: car").
static func record_stuck(npc, cause: String) -> void:
	if not enabled():
		return
	_stuck_counts[cause] = _stuck_counts.get(cause, 0) + 1
	var name: String = npc.mecha_name if is_instance_valid(npc) and "mecha_name" in npc else "?"
	var pos: Vector2 = npc.global_position if is_instance_valid(npc) else Vector2.ZERO
	_stuck_recent.append("%s %s at (%d, %d)" % [name, cause, int(pos.x), int(pos.y)])
	if _stuck_recent.size() > STUCK_KEEP:
		_stuck_recent.pop_front()
	_maybe_report()


static func _add(kind: String, distance_px: float) -> void:
	if not _distances.has(kind):
		_distances[kind] = PackedFloat32Array()
	var list: PackedFloat32Array = _distances[kind]
	if list.size() < MAX_SAMPLES:
		list.append(distance_px / PX_PER_M)
		_distances[kind] = list


static func _maybe_report() -> void:
	var now := Time.get_ticks_msec()
	if _last_report_ms == 0:
		_last_report_ms = now
		return
	if now - _last_report_ms >= int(REPORT_INTERVAL * 1000.0):
		_last_report_ms = now
		print(report())


# The summary as text. Counts are since the game started or since reset().
static func report() -> String:
	var lines := PackedStringArray(["[AICombatLog] distances in m, bands " + _band_header()])
	for kind in ["engage", "npc_seen", "npc_blind", "player"]:
		if not _distances.has(kind) or _distances[kind].is_empty():
			continue
		var list: PackedFloat32Array = _distances[kind]
		lines.append("  %-9s n=%-5d median %5.1f  %s" % [kind, list.size(), _median(list), _band_counts(list)])
	if not _stuck_counts.is_empty():
		var parts := PackedStringArray()
		for cause in _stuck_counts:
			parts.append("%s x%d" % [cause, _stuck_counts[cause]])
		lines.append("  stuck: " + ", ".join(parts))
		for entry in _stuck_recent:
			lines.append("    " + entry)
	return "\n".join(lines)


static func reset() -> void:
	_distances.clear()
	_stuck_counts.clear()
	_stuck_recent.clear()
	_last_report_ms = 0


static func _band_header() -> String:
	var parts := PackedStringArray()
	var low := 0.0
	for edge in BANDS:
		parts.append("%d-%d" % [int(low), int(edge)])
		low = edge
	parts.append("%d+" % int(low))
	return " | ".join(parts)


static func _band_counts(list: PackedFloat32Array) -> String:
	var counts := []
	counts.resize(BANDS.size() + 1)
	counts.fill(0)
	for d in list:
		var i := 0
		while i < BANDS.size() and d >= BANDS[i]:
			i += 1
		counts[i] += 1
	var parts := PackedStringArray()
	for c in counts:
		parts.append(str(c))
	return " | ".join(parts)


static func _median(list: PackedFloat32Array) -> float:
	var sorted := list.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
