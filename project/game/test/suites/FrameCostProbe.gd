extends TestSuite

# FrameCostProbe: where a frame's script time goes on the real map, by
# system (FrameProfiler). It loads the Expedition (Helwan) with NPC_COUNT
# NPCs (nobody can die: every mecha keeps its Flag grace), runs MEASURE_SECONDS
# with the profiler on, and prints the mean and worst milliseconds per frame
# of every instrumented system beside the engine's process and physics
# totals; and the sight circle's costs with the camera panned (see
# _test_sight_circle). The numbers are headless (no rendering), so they say
# nothing about the GPU side. It never fails on a timing.

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const NPC_COUNT := 12
const NEAR_COUNT := 6
const NEAR_DISTANCE := 1500.0
const MEASURE_SECONDS := 20.0

var _scene = null


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 240


func run_tests() -> void:
	await case("a frame's script time by system on Helwan", _test_probe)
	await case("the engine's step with twelve scripted walkers", _test_walkers)
	await case("the sight circle: senses, streaming and shadows with the camera panned", _test_sight_circle)


## The sight circle case: every head's visual_range set to each of
## SIGHT_RANGES (m) in turn, on the player and every NPC alike, and three
## camera pans: none, the full pan held to one side, and the full pan going
## round at PAN_TURN_RATE rad/s. The full pan is the player's sight radius
## (its head's visual_range in px where the pan doesn't read metres). Each
## case runs PAN_SECONDS.
const SIGHT_RANGES := [850, 150]
const PAN_SECONDS := 8.0
const PAN_TURN_RATE := 1.0


## The random seed the probe runs with, so two runs get the same designs,
## personalities and spawn spots (the NPCs' decisions still drift apart).
const SEED := 20261104


func _start() -> void:
	Debug.debug_settings["skip_intro"] = true
	seed(SEED)
	PlayerProgress.reset()
	_scene = EXPEDITION.instantiate()
	add_child(_scene)
	var populated := await wait_until(func(): return _enemies().size() > 0, 20.0)
	check(populated, "enemies spawned")
	_scene.ExpeditionDirector.set_process(false)
	await wait_frames(2)
	var n := 0
	while _enemies().size() < NPC_COUNT and n < NPC_COUNT:
		_scene.add_enemy(NPCManager.random_design_data(), "Probe_%d" % n)
		n += 1
	var near := 0
	for enemy in _enemies():
		if near >= NEAR_COUNT:
			break
		var offset := Vector2.from_angle(TAU * near / NEAR_COUNT) * NEAR_DISTANCE
		enemy.global_position = _scene._clear_spawn_spot(_scene.player.global_position + offset)
		near += 1
	for m in _scene.all_mechas:
		m.flag_grace = 1.0e9
	var field: BuildingField = BuildingField.find(_scene)
	if field:
		await wait_until(func(): return field.routes_ready(), 30.0)
	await wait_seconds(2.0)


# The physics engine's own load, with the NPCs' decisions taken out: every
# NPC is a scripted walker (no senses, no thinking, no shooting) sent from
# one seeded random point to the next, so two runs put the same bodies
# through the same motions. The number to compare when a change is to the
# collision shapes or the physics rate: the physics time per frame and the
# collision pairs. The walkers still run at their LOD tier's rate.
func _test_walkers() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	await _start()
	for enemy in _enemies():
		enemy.set_scripted(true)
		enemy.walk_to(_scene.get_random_position())
	FrameProfiler.reset()
	FrameProfiler.enabled = true
	var physics := PackedFloat32Array()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(MEASURE_SECONDS * 1000.0):
		await get_tree().process_frame
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for enemy in _enemies():
			if enemy.scripted_destination == null \
					or enemy.global_position.distance_to(enemy.scripted_destination) < 500.0:
				enemy.walk_to(_scene.get_random_position())
	FrameProfiler.enabled = false
	var script_ms := 0.0
	for row in FrameProfiler.report():
		if not row.key.begins_with(" "):
			script_ms += row.mean_ms
	print("[FrameCostProbe] %d scripted walkers, %.0f s: physics %s (ms per frame: mean / median / 95th pc / worst); scripts %.2f ms of it; simple collision %s" % [
			NPC_COUNT, MEASURE_SECONDS, _stats(physics), script_ms, "on" if Mecha.SIMPLE_COLLISION else "off"])
	print("  physics: %d active objects, %d collision pairs, %d islands" % [
			Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
			Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)])
	check(physics.size() > 0, "frames were measured")
	FrameProfiler.reset()
	_scene.queue_free()
	await wait_frames(2)
	_scene = null
	Debug.debug_settings["skip_intro"] = saved_skip_intro


func _test_sight_circle() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	await _start()
	var heads := {}
	for id in PartManager.get_parts("head"):
		var head = PartManager.get_part("head", id)
		if head != null:
			heads[head] = head.visual_range
	var lines := PackedStringArray(["[FrameCostProbe] sight circle: %d NPCs, %.0f s a case (ms per frame; the rest are means over the frames)" % [NPC_COUNT, PAN_SECONDS]])
	lines.append("  range   pan      senses  streamer  buildings  occluders  scenes  tier-0")
	for range_m in SIGHT_RANGES:
		for head in heads:
			head.visual_range = range_m
		for pan in ["none", "held", "moving"]:
			var row := await _measure_pan(pan)
			lines.append("  %4d m  %-7s  %6.3f  %8.3f  %9.3f  %9.1f  %6.1f  %6.1f" % [range_m, pan,
					row.senses, row.streamer, row.buildings, row.occluders, row.scenes, row.tier0])
	for head in heads:
		head.visual_range = heads[head]
	print("\n".join(lines))
	check(lines.size() > 2, "every case was measured")
	_scene.queue_free()
	await wait_frames(2)
	_scene = null
	Debug.debug_settings["skip_intro"] = saved_skip_intro


func _measure_pan(pan: String) -> Dictionary:
	var player = _scene.player
	var cam = player.get_cam()
	var limit: float = player.sight_radius() if player.has_method("sight_radius") else float(player.build.head.visual_range)
	var field: BuildingField = BuildingField.find(_scene)
	var scenes_all := get_tree().get_nodes_in_group("streamed_scene")
	var sums := {"occluders": 0.0, "scenes": 0.0, "tier0": 0.0}
	var samples := 0
	var angle := 0.0
	FrameProfiler.reset()
	FrameProfiler.enabled = true
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(PAN_SECONDS * 1000.0):
		await get_tree().process_frame
		var offset := Vector2.ZERO
		if pan == "held":
			offset = Vector2(limit, 0.0)
		elif pan == "moving":
			angle += PAN_TURN_RATE * get_process_delta_time()
			offset = Vector2.from_angle(angle) * limit
		if "pan_offset" in cam:
			cam.pan_offset = offset
		else:
			cam.offset = offset
		sums.occluders += field.occluder_count() if field else 0
		sums.scenes += scenes_all.filter(func(s): return is_instance_valid(s) and s.is_loaded()).size()
		sums.tier0 += _enemies().filter(func(e): return e.lod_tier() == 0).size()
		samples += 1
	FrameProfiler.enabled = false
	var times := {}
	for row in FrameProfiler.report():
		times[row.key] = row.mean_ms
	if "pan_offset" in cam:
		cam.pan_offset = Vector2.ZERO
	else:
		cam.offset = Vector2.ZERO
	var n := float(maxi(samples, 1))
	return {"senses": times.get("npc_senses", 0.0), "streamer": times.get("map_streamer", 0.0),
			"buildings": times.get("buildings", 0.0), "occluders": sums.occluders / n,
			"scenes": sums.scenes / n, "tier0": sums.tier0 / n}


# "mean / median / 95th percentile / worst" of a run's per-frame times.
static func _stats(samples: PackedFloat32Array) -> String:
	if samples.is_empty():
		return "-"
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted:
		total += s
	var n := sorted.size()
	@warning_ignore("integer_division")
	return "%.2f / %.2f / %.2f / %.2f" % [total / n, sorted[n / 2], sorted[mini(int(n * 0.95), n - 1)], sorted[n - 1]]


func _enemies() -> Array:
	if not is_instance_valid(_scene):
		return []
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


func _test_probe() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	await _start()
	FrameProfiler.reset()
	FrameProfiler.enabled = true
	# Every frame's engine times (ms). The physics time includes every
	# script's _physics_process; the median and the 95th percentile say more
	# than the mean, which one hitch (a route plan, the garbage collector)
	# drags about.
	var process := PackedFloat32Array()
	var physics := PackedFloat32Array()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(MEASURE_SECONDS * 1000.0):
		await get_tree().process_frame
		process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	FrameProfiler.enabled = false
	var frames := physics.size()
	var lines := PackedStringArray(["[FrameCostProbe] %d NPCs, %.0f s, %d frames: engine process %s, physics %s (ms per frame: mean / median / 95th pc / worst)" % [
			NPC_COUNT, MEASURE_SECONDS, frames, _stats(process), _stats(physics)]])
	lines.append(FrameProfiler.report_text())
	var mechas := get_tree().get_nodes_in_group("mecha").size()
	lines.append("  on the map: %d mechas, %d entities, %d devices, %d nodes" % [mechas, _scene.all_entities.size(),
			get_tree().get_nodes_in_group("device").size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	# The physics engine's own load (outside any script): bodies and areas
	# awake, the pairs it tests for contact each step, and the islands.
	lines.append("  physics: %d active objects, %d collision pairs, %d islands" % [
			Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
			Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)])
	print("\n".join(lines))
	check(FrameProfiler.frames() > 0, "frames were profiled")
	FrameProfiler.reset()
	_scene.queue_free()
	await wait_frames(2)
	_scene = null
	Debug.debug_settings["skip_intro"] = saved_skip_intro
