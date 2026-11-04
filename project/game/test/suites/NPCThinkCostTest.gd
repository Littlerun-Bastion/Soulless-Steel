extends TestSuite

# NPCThinkCostTest: the think-time probe on the real map. It loads the
# Expedition (Helwan), brings the NPC count to NPC_COUNT, lets them think for
# MEASURE_SECONDS of real time with the "ai_log" setting on, and prints what
# AICombatLog measured: microseconds per NPC per thinking frame, near the
# player and far from it, with the median, the 95th percentile and the
# worst. The numbers go in each phase's changelog. Nothing here fails on a
# timing: machines differ, and a flaky suite is worse than none.

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const NPC_COUNT := 12
## How many of them start near the player, and how far from it (px).
const NEAR_COUNT := 6
const NEAR_DISTANCE := 1500.0
const MEASURE_SECONDS := 20.0

var _scene = null


func _init() -> void:
	slow = true
	time_scale = 1.0


func run_tests() -> void:
	await case("twelve NPCs think on Helwan: the cost per thinking frame", _test_cost)
	await case("twelve NPCs walk Helwan's streets: the cost of steering alone", _test_walk)


# The real Expedition with NPC_COUNT NPCs, the director stopped, half of the
# NPCs round the player, and the player safe from harm.
func _start() -> void:
	Debug.debug_settings["skip_intro"] = true
	Debug.debug_settings["ai_log"] = true
	PlayerProgress.reset()
	_scene = EXPEDITION.instantiate()
	add_child(_scene)
	var populated := await wait_until(func(): return _enemies().size() > 0, 20.0)
	check(populated, "enemies spawned")
	_scene.ExpeditionDirector.set_process(false)
	await wait_frames(2)
	var n := 0
	while _enemies().size() < NPC_COUNT and n < NPC_COUNT:
		_scene.add_enemy(NPCManager.get_design_data(NPCManager.get_random_npc()), "Probe_%d" % n)
		n += 1
	check_eq(_enemies().size(), NPC_COUNT, "%d NPCs on the map" % NPC_COUNT)
	# Half of them are put round the player, so NPCs near it (thinking every
	# frame, steering rebuilt often) are measured too, not only far ones.
	var near := 0
	for enemy in _enemies():
		if near >= NEAR_COUNT:
			break
		var offset := Vector2.from_angle(TAU * near / NEAR_COUNT) * NEAR_DISTANCE
		enemy.global_position = _scene._clear_spawn_spot(_scene.player.global_position + offset)
		near += 1
	# The player is left out of the fight: with its grace window held, nothing
	# hurts it, so the run doesn't end in a death screen halfway through.
	_scene.player.flag_grace = 1.0e9
	var field: BuildingField = BuildingField.find(_scene)
	if field:
		await wait_until(func(): return field.routes_ready(), 30.0)


func _stop(saved_skip_intro, saved_log) -> void:
	AICombatLog.reset()
	_scene.queue_free()
	await wait_frames(2)
	_scene = null
	Debug.debug_settings["skip_intro"] = saved_skip_intro
	Debug.debug_settings["ai_log"] = saved_log


func _test_cost() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	var saved_log = Debug.debug_settings.get("ai_log")
	await _start()
	AICombatLog.reset()
	# Whole-frame costs too (the navigation server's avoidance and paths run
	# outside the NPCs' own thinking): the engine's physics and navigation
	# monitors, sampled every frame over the window, in ms.
	var physics := PackedFloat32Array()
	var navigation := PackedFloat32Array()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(MEASURE_SECONDS * 1000.0):
		await get_tree().process_frame
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		navigation.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
	var lines := PackedStringArray(["[NPCThinkCostTest] %d NPCs, %.0f s:" % [NPC_COUNT, MEASURE_SECONDS]])
	lines.append("  per frame: physics %s, navigation %s" % [_describe(physics), _describe(navigation)])
	var any := false
	for kind in ["think_near", "think_far"]:
		var stats := AICombatLog.think_stats(kind)
		if stats.is_empty():
			lines.append("  %s: no samples" % kind)
			continue
		any = true
		lines.append("  %-10s n=%-6d median %6.0f us  p95 %6.0f us  max %6.0f us" % [kind, stats.n, stats.median, stats.p95, stats.max])
	lines.append("  intent switches in the last minute: %d" % AICombatLog.switches_per_minute())
	print("\n".join(lines))
	check(any, "thinking frames were timed")
	await _stop(saved_skip_intro, saved_log)


# Steering alone: every NPC is a scripted walker (no senses, no decisions,
# no shooting) sent from one random point of the map to the next, so the
# per-frame cost and the per-NPC drive time measure movement and steering
# and nothing else.
func _test_walk() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	var saved_log = Debug.debug_settings.get("ai_log")
	await _start()
	for enemy in _enemies():
		enemy.set_scripted(true)
		enemy.walk_to(_scene.get_random_position())
	AICombatLog.reset()
	var physics := PackedFloat32Array()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(MEASURE_SECONDS * 1000.0):
		await get_tree().process_frame
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for enemy in _enemies():
			if enemy.scripted_destination == null \
					or enemy.global_position.distance_to(enemy.scripted_destination) < 500.0:
				enemy.walk_to(_scene.get_random_position())
	var stats := AICombatLog.think_stats("think_scripted")
	var lines := PackedStringArray(["[NPCThinkCostTest] %d walkers, %.0f s:" % [NPC_COUNT, MEASURE_SECONDS]])
	lines.append("  per frame: physics %s" % _describe(physics))
	if stats.is_empty():
		lines.append("  think_scripted: no samples")
	else:
		lines.append("  %-14s n=%-6d median %6.0f us  p95 %6.0f us  max %6.0f us" % ["think_scripted", stats.n, stats.median, stats.p95, stats.max])
	var stuck := AICombatLog.report()
	if stuck.contains("stuck:"):
		lines.append("  " + stuck.substr(stuck.find("stuck:")).split("\n")[0])
	print("\n".join(lines))
	check(not stats.is_empty(), "walkers were timed")
	await _stop(saved_skip_intro, saved_log)


func _enemies() -> Array:
	if not is_instance_valid(_scene):
		return []
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


# "mean 1.23 ms, p95 2.1 ms, max 4.0 ms" of a sample list.
func _describe(samples: PackedFloat32Array) -> String:
	if samples.is_empty():
		return "no samples"
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	return "mean %.2f ms, p95 %.2f ms, max %.2f ms" % [total / sorted.size(),
			sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], sorted[sorted.size() - 1]]
