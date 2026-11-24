extends TestSuite

# DistantTierProbe: what the distant tier (Enemy, Distant tier) saves on the
# real map, and what the spawn-area preload (MapStreamer.preload_around)
# does. It loads the Expedition with NPC_COUNT NPCs (NEAR_COUNT of them put
# NEAR_DISTANCE px round the player, the rest where they spawned; nobody can
# die), runs MEASURE_SECONDS with the profiler on, once with the tier at
# its default line and once with it off (the same seed, so the same
# designs and spawn spots; the NPCs' decisions still drift apart), and
# prints for each: the engine's physics time per frame, the NPCs' script
# time per frame (FrameProfiler: "mecha", which is every mecha's base step,
# the player's included, "npc_think" and "npc_drive"), how many NPCs ran
# in each LOD tier on average, and what one NPC's whole step costs in each
# tier (Enemy.TIER_PROFILE_KEYS) per frame: the steps' time over the frames
# and the tier's NPCs. A second case runs the same with every NPC far
# from the player (FAR_DISTANCE and more). A third prints how many chunk
# meshes the loading screen loaded, how long that took, and how many waits
# for a chunk on screen happened in the first PLAY_SECONDS of play. The
# numbers are headless. It never fails on a timing. A probe, not a test:
# it runs only when named (--suite=DistantTierProbe), so the full run stays
# within TestSession.MAX_RUN_SECONDS.

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const SEED := 20261121
const NPC_COUNT := 12
const NEAR_COUNT := 6
const NEAR_DISTANCE := 1500.0
const FAR_DISTANCE := 14000.0
const MEASURE_SECONDS := 12.0
const PLAY_SECONDS := 12.0
const NPC_KEYS := ["mecha", "npc_think", "npc_drive"]
const ENEMY_SCRIPT := preload("res://game/mecha/Enemy.gd")
const TIER_NAMES := ["near", "far", "very far", "distant"]
var Enemy_TIER_KEYS: Array = ENEMY_SCRIPT.TIER_PROFILE_KEYS

var _scene = null


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 300


func run_tests() -> void:
	if not asked_for():
		return
	await case("the distant tier on the real map: half the NPCs round the player", _test_mixed)
	await case("the distant tier on the real map: every NPC far from the player", _test_far)
	await case("the spawn area loads during the loading screen", _test_preload)

# Whether this probe should run: opened on its own (F6), or named in
# --suite=... on the command line.
func asked_for() -> bool:
	if get_tree().current_scene == self:
		return true
	for filter in TestSession.get_options()["suites"]:
		if str(filter).to_lower() in get_suite_name().to_lower():
			return true
	print("  (a probe: run it with --suite=%s)" % get_suite_name())
	return false


func _start(near_count: int) -> void:
	Debug.debug_settings["skip_intro"] = true
	seed(SEED)
	PlayerProgress.reset()
	_scene = EXPEDITION.instantiate()
	# The director's starting counts unscaled (6-10 NPCs), so the top-up below
	# brings exactly NPC_COUNT.
	_scene.get_node("ExpeditionDirector").max_population_scale = 1.0
	add_child(_scene)
	var populated := await wait_until(func(): return _enemies().size() > 0, 20.0)
	check(populated, "enemies spawned")
	_scene.ExpeditionDirector.set_process(false)
	await wait_frames(2)
	var n := 0
	while _enemies().size() < NPC_COUNT and n < NPC_COUNT:
		_scene.add_enemy(NPCManager.random_design_data(), "Probe_%d" % n)
		n += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var k := 0
	for enemy in _enemies():
		if k < near_count:
			var offset := Vector2.from_angle(TAU * k / maxi(near_count, 1)) * NEAR_DISTANCE
			enemy.global_position = _scene._clear_spawn_spot(_scene.player.global_position + offset)
		elif near_count == 0 and enemy.global_position.distance_to(_scene.player.global_position) < FAR_DISTANCE:
			var offset := Vector2.from_angle(rng.randf() * TAU) * (FAR_DISTANCE + rng.randf() * 20000.0)
			enemy.global_position = _scene._clear_spawn_spot(_scene.player.global_position + offset)
		k += 1
	for m in _scene.all_mechas:
		m.flag_grace = 1.0e9
	var field: BuildingField = BuildingField.find(_scene)
	if field:
		await wait_until(func(): return field.routes_ready(), 30.0)
	await wait_seconds(2.0)


func _stop() -> void:
	_scene.queue_free()
	await wait_frames(2)
	_scene = null


# One run with the tier's line at `metres` (0: off).
func _run(near_count: int, metres: float) -> Dictionary:
	var saved_line = Debug.debug_settings.get("distant_tier_m")
	Debug.debug_settings["distant_tier_m"] = metres
	await _start(near_count)
	FrameProfiler.reset()
	FrameProfiler.enabled = true
	var physics := PackedFloat32Array()
	var distant := 0.0
	var tiers := [0.0, 0.0, 0.0, 0.0]
	var samples := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(MEASURE_SECONDS * 1000.0):
		await get_tree().process_frame
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for e in _enemies():
			tiers[e.lod_tier()] += 1.0
			if e.is_distant():
				distant += 1.0
		samples += 1
	FrameProfiler.enabled = false
	var per_npc := {}
	for row in FrameProfiler.report():
		var k: int = Enemy_TIER_KEYS.find(row.key)
		if k >= 0:
			per_npc[k] = row.mean_ms / maxf(tiers[k] / maxi(samples, 1), 0.001)
	var npc_ms := 0.0
	var npc_worst := 0.0
	var script_ms := 0.0
	for row in FrameProfiler.report():
		if not row.key.begins_with(" "):
			script_ms += row.mean_ms
		if row.key in NPC_KEYS:
			npc_ms += row.mean_ms
			npc_worst = maxf(npc_worst, row.worst_ms)
	var out := {"physics": _stats(physics), "physics_mean": _mean(physics), "npc_ms": npc_ms, "npc_worst": npc_worst,
			"script_ms": script_ms, "distant": distant / maxi(samples, 1), "alive": _enemies().size(),
			"entities": _scene.all_entities.size(), "per_npc": per_npc,
			"tiers": tiers.map(func(t): return t / maxi(samples, 1))}
	FrameProfiler.reset()
	await _stop()
	Debug.debug_settings["distant_tier_m"] = saved_line
	return out


func _report(title: String, on: Dictionary, off: Dictionary) -> void:
	var lines := PackedStringArray(["[DistantTierProbe] %s, %d NPCs, %d Entities, %.0f s a run" % [title, NPC_COUNT, int(on.entities), MEASURE_SECONDS]])
	lines.append("  tier   NPCs distant  NPC scripts/frame (mean, worst key)  all scripts  physics/frame mean / median / 95th pc / worst")
	for row in [["on", on], ["off", off]]:
		var r: Dictionary = row[1]
		lines.append("  %-4s   %5.1f of %2d   %6.2f ms (%5.2f ms)                %6.2f ms    %s ms" % [row[0], r.distant, r.alive, r.npc_ms, r.npc_worst, r.script_ms, r.physics])
	lines.append("  NPC script saving %.2f ms a frame (%.0f%%); physics frame %.2f -> %.2f ms" % [
			off.npc_ms - on.npc_ms, 100.0 * (off.npc_ms - on.npc_ms) / maxf(off.npc_ms, 0.001), off.physics_mean, on.physics_mean])
	for row in [["on", on], ["off", off]]:
		var r: Dictionary = row[1]
		var parts := PackedStringArray()
		for k in 4:
			if r.per_npc.has(k):
				parts.append("%s %.1f NPCs, %.3f ms each" % [TIER_NAMES[k], r.tiers[k], r.per_npc[k]])
		lines.append("  tier %-3s per NPC per frame (whole step): %s" % [row[0], ", ".join(parts)])
	print("\n".join(lines))


func _test_mixed() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	var on := await _run(NEAR_COUNT, 500.0)
	var off := await _run(NEAR_COUNT, 0.0)
	_report("half round the player", on, off)
	check(on.alive > 0 and off.alive > 0, "both runs had NPCs")
	Debug.debug_settings["skip_intro"] = saved_skip_intro


func _test_far() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	var on := await _run(0, 500.0)
	var off := await _run(0, 0.0)
	_report("every NPC far from the player", on, off)
	check(on.alive > 0 and off.alive > 0, "both runs had NPCs")
	Debug.debug_settings["skip_intro"] = saved_skip_intro


func _test_preload() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true
	PlayerProgress.reset()
	_scene = EXPEDITION.instantiate()
	add_child(_scene)
	var report: Dictionary = _scene.preload_report
	var streamer := MapStreamer.find(_scene)
	var at_start: int = streamer.loaded_mesh_count() if streamer else 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(PLAY_SECONDS * 1000.0):
		await get_tree().process_frame
	print("[DistantTierProbe] spawn-area preload: %d chunk meshes loaded during the loading screen in %.1f ms (%d loaded at the first frame); waits for a chunk near the view in the first %.0f s of play: %d (%.1f ms in all); %d of %d chunk meshes loaded at the end" % [
			int(report.get("chunks", 0)), float(report.get("ms", 0.0)), at_start, PLAY_SECONDS,
			streamer.waited_loads if streamer else -1, streamer.waited_ms if streamer else 0.0,
			streamer.loaded_mesh_count() if streamer else 0, streamer.chunk_mesh_count() if streamer else 0])
	check(streamer != null and int(report.get("chunks", 0)) > 0, "the loading screen loaded the spawn area's chunks")
	check(streamer != null and streamer.waited_loads == 0, "no chunk near the view was waited for in play")
	await _stop()
	Debug.debug_settings["skip_intro"] = saved_skip_intro


func _enemies() -> Array:
	if not is_instance_valid(_scene):
		return []
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


static func _mean(samples: PackedFloat32Array) -> float:
	var total := 0.0
	for s in samples:
		total += s
	return total / maxi(samples.size(), 1)


# "mean / median / 95th percentile / worst".
static func _stats(samples: PackedFloat32Array) -> String:
	if samples.is_empty():
		return "-"
	var sorted := samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	@warning_ignore("integer_division")
	return "%.2f / %.2f / %.2f / %.2f" % [_mean(samples), sorted[n / 2], sorted[mini(int(n * 0.95), n - 1)], sorted[n - 1]]
