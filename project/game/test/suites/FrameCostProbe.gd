extends TestSuite

# FrameCostProbe: where a frame's script time goes on the real map, by
# system (FrameProfiler). It loads the Expedition (Helwan) with NPC_COUNT
# NPCs (nobody can die: every mecha keeps its Flag grace), runs MEASURE_SECONDS
# with the profiler on, and prints the mean and worst milliseconds per frame
# of every instrumented system beside the engine's process and physics
# totals. The numbers are headless (no rendering), so they say nothing about
# the GPU side. It never fails on a timing.

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const NPC_COUNT := 12
const NEAR_COUNT := 6
const NEAR_DISTANCE := 1500.0
const MEASURE_SECONDS := 20.0

var _scene = null


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 120


func run_tests() -> void:
	await case("a frame's script time by system on Helwan", _test_probe)
	await case("the engine's step with twelve scripted walkers", _test_walkers)


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
