extends TestSuite

# RouteCostProbe: what route planning costs on the real map. It loads the
# Expedition, gives the map the MapBounds the generator writes (contracts 3)
# if it has none, builds the route grid again over the play area, and prints:
#   - the grid's size, and for SOLVE_PAIRS seeded random trips across the
#     play area how long one search takes on the solver thread (median, 95th
#     percentile, worst, in ms) and what asking and collecting cost the main
#     thread;
#   - with NPC_COUNT scripted walkers sent to random points and made to plan
#     again every REPLAN_SECONDS, the route planning time in each physics
#     frame (FrameProfiler's "route (in navigate)"), the physics frame time,
#     how many physics frames an NPC waits for its route, and the solver's
#     own numbers, over MEASURE_SECONDS.
# The numbers are headless. It never fails on a timing. A probe, not a
# test: it runs only when named (--suite=RouteCostProbe), so the full run
# stays within TestSession.MAX_RUN_SECONDS.

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const SEED := 20261120
const SOLVE_PAIRS := 40
const NPC_COUNT := 12
const MEASURE_SECONDS := 20.0
const REPLAN_SECONDS := 2.0

var _scene = null


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 240


func run_tests() -> void:
	if not asked_for():
		return
	await case("one route search on the big map: the time it takes", _test_solve_times)
	await case("walkers planning routes: the route time in each frame", _test_frames)

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


func _start() -> BuildingField:
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
	for m in _scene.all_mechas:
		m.flag_grace = 1.0e9
	var field: BuildingField = BuildingField.find(_scene)
	if field == null:
		return null
	await wait_until(func(): return field.routes_ready(), 30.0)
	if MapBounds.find(_scene) == null:
		var bounds := MapBounds.new()
		bounds.name = "MapBounds"
		_scene.get_node("Map").add_child(bounds)
		field._route_grid = null
		field._start_route_build()
		await wait_until(func(): return field.routes_ready(), 30.0)
	return field


func _stop(saved_skip_intro) -> void:
	_scene.queue_free()
	await wait_frames(2)
	_scene = null
	Debug.debug_settings["skip_intro"] = saved_skip_intro


func _test_solve_times() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	var field := await _start()
	if not check(field != null and field.routes_ready(), "the route grid is built"):
		await _stop(saved_skip_intro)
		return
	var area := MapBounds.find(_scene).global_play_rect().grow(-500.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var asks := PackedFloat32Array()
	var lengths := PackedFloat32Array()
	var before: int = field.route_stats().searches
	for k in SOLVE_PAIRS:
		var a := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var b := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		await get_tree().physics_frame
		var started := Time.get_ticks_usec()
		var ticket := field.request_route(a, b)
		var main_us := Time.get_ticks_usec() - started
		var waited := 0
		while not field.is_route_solved(ticket) and waited < 600:
			await get_tree().physics_frame
			waited += 1
		started = Time.get_ticks_usec()
		var route := field.take_route(ticket)
		main_us += Time.get_ticks_usec() - started
		asks.append(main_us / 1000.0)
		lengths.append(a.distance_to(b) / 20.0)
		check(not route.is_empty(), "trip %d has a route" % k)
	var stats := field.route_stats()
	var grid: BuildingField.RouteGrid = field._route_grid
	print("[RouteCostProbe] grid %d x %d squares of %.0f px; %d trips of %.0f-%.0f m: one route on the solver thread %.2f / %.2f / %.2f ms (median / 95th pc / worst, %d routes), of which the grid search %.2f / %.2f / %.2f ms; asking and collecting on the main thread %s ms" % [
			grid.size.x, grid.size.y, BuildingField.ROUTE_CELL, SOLVE_PAIRS, _min(lengths), _max(lengths),
			stats.median_ms, stats.p95_ms, stats.worst_ms, int(stats.searches) - before,
			stats.search_median_ms, stats.search_p95_ms, stats.search_worst_ms, _stats(asks)])
	await _stop(saved_skip_intro)


func _test_frames() -> void:
	var saved_skip_intro = Debug.debug_settings.get("skip_intro")
	var field := await _start()
	var n := 0
	while _enemies().size() < NPC_COUNT and n < NPC_COUNT:
		_scene.add_enemy(NPCManager.random_design_data(), "Route_%d" % n)
		n += 1
	for enemy in _enemies():
		enemy.flag_grace = 1.0e9
		enemy.set_scripted(true)
		enemy.walk_to(_scene.get_random_position())
	await wait_frames(2)
	FrameProfiler.reset()
	FrameProfiler.enabled = true
	var physics := PackedFloat32Array()
	var replan_at := {}
	# Physics frames each wait for a route took, from the NPC's own ticket.
	var waits := PackedFloat32Array()
	var waiting := {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(MEASURE_SECONDS * 1000.0):
		await get_tree().process_frame
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var now := Time.get_ticks_msec()
		var frame := Engine.get_physics_frames()
		var i := 0
		for enemy in _enemies():
			if enemy.scripted_destination == null \
					or enemy.global_position.distance_to(enemy.scripted_destination) < 500.0:
				enemy.walk_to(_scene.get_random_position())
			# Each walker plans again every REPLAN_SECONDS, staggered.
			var due: int = replan_at.get(enemy, now + int(REPLAN_SECONDS * 1000.0 * i / NPC_COUNT))
			if now >= due:
				enemy._route_replan = true
				due = now + int(REPLAN_SECONDS * 1000.0)
			replan_at[enemy] = due
			var ticket: int = enemy._route_ticket
			if ticket != 0 and not waiting.has(ticket):
				waiting[ticket] = frame
			i += 1
		for ticket in waiting.keys():
			var still := false
			for enemy in _enemies():
				if enemy._route_ticket == ticket:
					still = true
			if not still:
				waits.append(frame - int(waiting[ticket]))
				waiting.erase(ticket)
	FrameProfiler.enabled = false
	var route_row := {}
	for row in FrameProfiler.report():
		if row.key.strip_edges() == "route (in navigate)":
			route_row = row
	var stats := field.route_stats() if field else {}
	print("[RouteCostProbe] %d walkers planning every %.0f s, %.0f s, %d frames: route planning per frame mean %.3f ms, worst %.2f ms; physics per frame %s ms (mean / median / 95th pc / worst)" % [
			_enemies().size(), REPLAN_SECONDS, MEASURE_SECONDS, FrameProfiler.frames(),
			float(route_row.get("mean_ms", 0.0)), float(route_row.get("worst_ms", 0.0)), _stats_mean(physics)])
	print("  physics frames from asking to having the route: %s (median / 95th pc / worst, %d routes); solver: %d searches, %.2f / %.2f / %.2f ms (median / 95th pc / worst), %d queued at the end" % [
			_stats(waits), waits.size(), int(stats.get("searches", 0)), float(stats.get("median_ms", 0.0)),
			float(stats.get("p95_ms", 0.0)), float(stats.get("worst_ms", 0.0)), int(stats.get("queued", 0))])
	check(FrameProfiler.frames() > 0, "frames were profiled")
	FrameProfiler.reset()
	await _stop(saved_skip_intro)


func _enemies() -> Array:
	if not is_instance_valid(_scene):
		return []
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


# "median / 95th percentile / worst".
static func _stats(samples: PackedFloat32Array) -> String:
	if samples.is_empty():
		return "-"
	var sorted := samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	@warning_ignore("integer_division")
	return "%.2f / %.2f / %.2f" % [sorted[n / 2], sorted[mini(int(n * 0.95), n - 1)], sorted[n - 1]]


static func _stats_mean(samples: PackedFloat32Array) -> String:
	if samples.is_empty():
		return "-"
	var total := 0.0
	for s in samples:
		total += s
	return "%.2f / %s" % [total / samples.size(), _stats(samples)]


static func _min(samples: PackedFloat32Array) -> float:
	var best := INF
	for s in samples:
		best = minf(best, s)
	return best


static func _max(samples: PackedFloat32Array) -> float:
	var best := -INF
	for s in samples:
		best = maxf(best, s)
	return best
