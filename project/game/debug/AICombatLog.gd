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
#   - intents: how many intent switches happened in the last minute across
#     all NPCs (flip-flop detection), the seconds spent in each intent, and
#     the most common switches.
#   - think cost: microseconds one NPC spends in one thinking frame (its
#     senses, intent scoring, behaviour and illuminator), near the player
#     and far from it (Enemy.is_near_player), with the median and the worst.
#   - flags and mines, and squad events (record_flag, record_squad), by kind.
# Everything is static, so any script can record without a reference. When
# "ai_log" is off, every record call returns at once.

const REPORT_INTERVAL := 30.0
## Distance band edges in metres (MapSenses.PX_PER_METRE px each).
const BANDS := [25.0, 50.0, 75.0, 100.0]
const MAX_SAMPLES := 4000
## Stuck positions kept for the report.
const STUCK_KEEP := 8
## Intent switches are counted over this window (s, real time).
const SWITCH_WINDOW := 60.0
## Most common intent switches shown.
const SWITCH_PAIRS_SHOWN := 6

static var _distances := {}
static var _stuck_counts := {}
static var _stuck_recent: Array = []
static var _last_report_ms := 0
static var _switch_times: Array = []
static var _switch_pairs := {}
static var _intent_seconds := {}
static var _think := {}
static var _flags := {}
static var _squads := {}
static var _info := {}


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


# An NPC switched from intent `from` to `to` after `seconds` in `from`.
static func record_intent_change(_npc, from: String, to: String, seconds: float) -> void:
	if not enabled():
		return
	var now := Time.get_ticks_msec()
	_switch_times.append(now)
	while not _switch_times.is_empty() and now - int(_switch_times[0]) > int(SWITCH_WINDOW * 1000.0):
		_switch_times.pop_front()
	var pair := from + ">" + to
	_switch_pairs[pair] = _switch_pairs.get(pair, 0) + 1
	_intent_seconds[from] = float(_intent_seconds.get(from, 0.0)) + seconds
	_maybe_report()


# One NPC's thinking frame took `usec` microseconds. `kind` is "near" or
# "far" (Enemy.is_near_player), or "scripted" for a cutscene actor's drive
# (steering only, no senses or decisions).
static func record_think(usec: int, kind: String) -> void:
	if not enabled():
		return
	kind = "think_" + kind
	if not _think.has(kind):
		_think[kind] = PackedFloat32Array()
	var list: PackedFloat32Array = _think[kind]
	if list.size() < MAX_SAMPLES:
		list.append(float(usec))
		_think[kind] = list
	_maybe_report()


# A Flag event or a mine event, counted by kind: raised_voluntary,
# raised_emergency, surrender, ignored (a Flag not respected), traitor (a
# treachery mark), executed, spared, mine_seen, mine_missed.
static func record_flag(kind: String) -> void:
	if not enabled():
		return
	_flags[kind] = int(_flags.get(kind, 0)) + 1
	_maybe_report()


static func flag_count(kind: String) -> int:
	return int(_flags.get(kind, 0))


# A squad event, counted by kind: flank_reached (the flanker got to its
# angle), covered (support smoke for a squadmate), held / avenge / broke (a
# member's answer to its leader's death), abandoned / betrayed (a Rat
# leaving), grudge (a kill record read off a fallen member's wreck);
# companions: offered, accepted, declined, offer_lapsed, order_<kind>, left,
# betrayed_player, joined_npc (a Guardian joining a pilot it saw attacked).
static func record_squad(kind: String) -> void:
	if not enabled():
		return
	_squads[kind] = int(_squads.get(kind, 0)) + 1
	_maybe_report()


static func squad_count(kind: String) -> int:
	return int(_squads.get(kind, 0))


# An information event, counted by kind: lead_need_help / lead_found_loot
# (a Local lead read), help_answered, vultured, scouted, rat_lie (a fake
# shout or call), swept_back, trail_found, trail_lost, alarm_investigated.
static func record_info(kind: String) -> void:
	if not enabled():
		return
	_info[kind] = int(_info.get(kind, 0)) + 1
	_maybe_report()


static func info_count(kind: String) -> int:
	return int(_info.get(kind, 0))


## Intent switches in the last SWITCH_WINDOW s, across all NPCs.
static func switches_per_minute() -> int:
	var now := Time.get_ticks_msec()
	var count := 0
	for t in _switch_times:
		if now - int(t) <= int(SWITCH_WINDOW * 1000.0):
			count += 1
	return count


## Median and worst think time (microseconds) for "think_near", "think_far"
## or "think_scripted", or {} with no samples.
static func think_stats(kind: String) -> Dictionary:
	if not _think.has(kind) or _think[kind].is_empty():
		return {}
	var list: PackedFloat32Array = _think[kind]
	var sorted := list.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	return {"n": list.size(), "median": sorted[sorted.size() / 2],
			"p95": sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], "max": sorted[sorted.size() - 1]}


static func _add(kind: String, distance_px: float) -> void:
	if not _distances.has(kind):
		_distances[kind] = PackedFloat32Array()
	var list: PackedFloat32Array = _distances[kind]
	if list.size() < MAX_SAMPLES:
		list.append(distance_px / MapSenses.PX_PER_METRE)
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
	if not _intent_seconds.is_empty() or not _switch_times.is_empty():
		lines.append("  intent switches in the last minute: %d" % switches_per_minute())
		var spent := PackedStringArray()
		for intent in _intent_seconds:
			spent.append("%s %.0fs" % [intent, _intent_seconds[intent]])
		lines.append("  time in intents: " + ", ".join(spent))
		var pairs: Array = _switch_pairs.keys()
		pairs.sort_custom(func(a, b): return _switch_pairs[a] > _switch_pairs[b])
		var shown := PackedStringArray()
		for pair in pairs.slice(0, SWITCH_PAIRS_SHOWN):
			shown.append("%s x%d" % [pair, _switch_pairs[pair]])
		lines.append("  common switches: " + ", ".join(shown))
	if not _flags.is_empty():
		var parts := PackedStringArray()
		for kind in _flags:
			parts.append("%s x%d" % [kind, _flags[kind]])
		lines.append("  flags and mines: " + ", ".join(parts))
	if not _squads.is_empty():
		var parts := PackedStringArray()
		for kind in _squads:
			parts.append("%s x%d" % [kind, _squads[kind]])
		lines.append("  squads: " + ", ".join(parts))
	if not _info.is_empty():
		var parts := PackedStringArray()
		for kind in _info:
			parts.append("%s x%d" % [kind, _info[kind]])
		lines.append("  information: " + ", ".join(parts))
	for kind in ["think_near", "think_far", "think_scripted"]:
		var stats := think_stats(kind)
		if stats.is_empty():
			continue
		lines.append("  %-10s n=%-5d median %5.0f us  p95 %5.0f us  max %5.0f us" % [kind, stats.n, stats.median, stats.p95, stats.max])
	return "\n".join(lines)


static func reset() -> void:
	_distances.clear()
	_stuck_counts.clear()
	_stuck_recent.clear()
	_switch_times.clear()
	_switch_pairs.clear()
	_intent_seconds.clear()
	_think.clear()
	_flags.clear()
	_squads.clear()
	_info.clear()
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
	@warning_ignore("integer_division")
	return sorted[sorted.size() / 2]
