extends TestSuite

# RoutePlanningTest: BuildingField's route grid and its solver thread, and
# how NPCs use them (Enemy, Routes). A route asked for arrives a frame or a
# few later from the solver thread, and no physics frame waits for the
# search, however long it takes; the grid covers the MapBounds play area
# only, routes end inside it and an NPC's goal in the border band is moved
# inside; without a MapBounds the grid reaches past the map's content as
# before; and the ObstacleField's pipes and pools block the grid's squares
# and are hard obstacles for NPC steering.

const ENEMY := preload("res://game/mecha/Enemy.tscn")


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null
var _field: BuildingField = null


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("a route arrives from the solver thread; no frame waits for the search", _test_async)
	await case("the route grid covers the play area only", _test_play_area)
	await case("without a MapBounds the grid reaches past the map's content", _test_no_bounds)
	await case("pipes and pools block the grid and NPC steering", _test_obstacles)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)


# A map: an optional MapBounds (map_rect, border), the ObstacleField's
# outlines ([kind, points]) and building footprints, then waits for the
# route grid. Every map has one small building far off, so the field exists.
func _map(map_rect: Rect2, border: float, obstacles: Array = [], buildings: Array = []) -> bool:
	_arena = FakeArena.new()
	add_child(_arena)
	if map_rect.has_area():
		var bounds := MapBounds.new()
		bounds.map_rect = map_rect
		bounds.border = border
		_arena.add_child(bounds)
	if not obstacles.is_empty():
		var data := MapObstacles.new()
		var starts := PackedInt32Array([0])
		for o in obstacles:
			data.points.append_array(PackedVector2Array(o[1]))
			starts.append(data.points.size())
			data.kind.append(int(o[0]))
		data.starts = starts
		var field := ObstacleField.new()
		field.obstacles = data
		_arena.add_child(field)
	var footprints := BuildingFootprints.new()
	var starts := PackedInt32Array([0])
	var all := [[Vector2(-9000, -9000), Vector2(-8900, -9000), Vector2(-8900, -8900), Vector2(-9000, -8900)]]
	all.append_array(buildings)
	for b in all:
		footprints.points.append_array(PackedVector2Array(b))
		starts.append(footprints.points.size())
	footprints.starts = starts
	_field = BuildingField.new()
	_field.footprints = footprints
	_arena.add_child(_field)
	return await wait_until(func(): return _field.routes_ready(), 10.0)


func _enemy(pos: Vector2) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Route test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(false)
	enemy.paused = true
	_arena.mechas.append(enemy)
	return enemy


func _wall(rect: Rect2) -> void:
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	wall.add_child(shape)
	wall.position = rect.get_center()
	_arena.add_child(wall)


func _test_async() -> void:
	# A 5 km play area (the real grid's size) and a wall across almost all of
	# it: the way round is long, so the search takes a while.
	var ok := await _map(Rect2(-52000, -52000, 104000, 104000), 2000.0)
	if not check(ok, "the route grid builds"):
		return
	_wall(Rect2(-100, -50000, 200, 90000))
	_field._route_grid = null
	_field._start_route_build()
	if not check(await wait_until(func(): return _field.routes_ready(), 10.0), "it builds again with the wall"):
		return
	var started := Time.get_ticks_usec()
	var ticket := _field.request_route(Vector2(-20000, -30000), Vector2(20000, -30000))
	var ask_us := Time.get_ticks_usec() - started
	check(ticket > 0, "asking gives a ticket")
	var frames := 0
	while not _field.is_route_solved(ticket) and frames < 300:
		await get_tree().physics_frame
		frames += 1
	var route := _field.take_route(ticket)
	var round_end := false
	for p in route:
		if p.y > 40000.0:
			round_end = true
	check(round_end, "the route goes round the wall's end (%d points)" % route.size())
	check(_field.take_route(ticket).is_empty(), "a ticket gives its route once")
	var stats := _field.route_stats()
	check(float(stats.worst_ms) * 1000.0 > ask_us, "the search (%.2f ms) took longer than asking for it on the main thread (%.3f ms)" % [stats.worst_ms, ask_us / 1000.0])
	# An NPC asks, heads straight for its goal while the route is solved, then
	# follows it; no call of its route step costs it the search.
	var enemy := _enemy(Vector2(-20000, 30000))
	var goal := Vector2(20000, 30000)
	var first: Vector2 = enemy._route_next(goal, 1.0 / 60.0)
	var worst_us := 0
	var waited := 0
	while enemy._route_ticket != 0 and waited < 300:
		await get_tree().physics_frame
		started = Time.get_ticks_usec()
		enemy._route_next(goal, 1.0 / 60.0)
		worst_us = maxi(worst_us, Time.get_ticks_usec() - started)
		waited += 1
	var next: Vector2 = enemy._route_next(goal, 1.0 / 60.0)
	check(first == goal, "before the route arrives the NPC heads for its goal")
	check(enemy._route_ticket == 0 and not enemy._route.is_empty(), "the route arrived after %d physics frames" % waited)
	check(next.y > 40000.0 or enemy._route[enemy._route.size() - 1] == goal, "and the NPC follows it round the wall (%s)" % str(next.round()))
	var search_ms: float = float(_field.route_stats().worst_ms)
	check(worst_us < 2000 and worst_us / 1000.0 < search_ms, "no route step waited for the search (worst %.3f ms; the search %.2f ms)" % [worst_us / 1000.0, search_ms])
	# A cancelled route is dropped.
	var dropped := _field.request_route(Vector2(-20000, 0), Vector2(20000, 0))
	_field.cancel_route(dropped)
	await wait_frames(30)
	check(not _field.is_route_solved(dropped), "a cancelled route is never handed out")


func _test_play_area() -> void:
	# A map 24,000 px (1.2 km) a side with a 2,000 px band: the play area is
	# x and y in -10,000..10,000.
	var ok := await _map(Rect2(-12000, -12000, 24000, 24000), 2000.0)
	if not check(ok, "the route grid builds"):
		return
	var area := _field.route_area()
	check(area.position.distance_to(Vector2(-10000, -10000)) < 1.0 and area.size.distance_to(Vector2(20000, 20000)) < BuildingField.ROUTE_CELL,
			"the grid covers the play area (%s)" % str(area))
	var grid: BuildingField.RouteGrid = _field._route_grid
	check_eq(grid.size, Vector2i(80, 80), "20,000 px of play area is 80 squares a side")
	var route := _field.find_route(Vector2(-5000, 0), Vector2(11500, 3000))
	var last := route[route.size() - 1]
	check(absf(last.x) <= 10000.0 and absf(last.y) <= 10000.0, "a route to a goal in the band ends inside the play area (%s)" % str(last.round()))
	var enemy := _enemy(Vector2(0, 0))
	enemy.NavAgent.target_position = Vector2(11500, -500)
	var goal: Vector2 = enemy._goal_in_play_area()
	check(goal.x <= 10000.0 - enemy.PLAY_AREA_MARGIN + 1.0 and is_equal_approx(goal.y, -500.0),
			"an NPC's goal in the band is moved inside the play area (%s)" % str(goal.round()))
	check(enemy.NavAgent.target_position == goal, "and its navigation goal with it")
	enemy.NavAgent.target_position = Vector2(4000, 4000)
	check(enemy._goal_in_play_area() == Vector2(4000, 4000), "a goal inside stays where it is")


func _test_no_bounds() -> void:
	var ok := await _map(Rect2(), 0.0, [], [[Vector2(3000, 3000), Vector2(3500, 3000), Vector2(3500, 3500), Vector2(3000, 3500)]])
	if not check(ok, "the route grid builds"):
		return
	var area := _field.route_area()
	var content := Rect2(-9000, -9000, 12500, 12500)
	check(area.encloses(content.grow(BuildingField.ROUTE_MARGIN - 1.0)), "it reaches ROUTE_MARGIN past the buildings (%s)" % str(area))


func _test_obstacles() -> void:
	# A pipe rack across the way from the band in the north to y 4000 (the
	# only gap is to the south) and a pool to the north-west.
	var pipe := [Vector2(1900, -10500), Vector2(2100, -10500), Vector2(2100, 4000), Vector2(1900, 4000)]
	var pool := [Vector2(-3000, -3000), Vector2(-2000, -3000), Vector2(-2000, -2000), Vector2(-3000, -2000)]
	var ok := await _map(Rect2(-12000, -12000, 24000, 24000), 2000.0, [[MapObstacles.PIPE, pipe], [MapObstacles.POOL, pool]])
	if not check(ok, "the route grid builds"):
		return
	var obstacles := ObstacleField.find(_field)
	check(obstacles != null and obstacles.body_count() > 0, "the obstacles have their barrier bodies")
	check(_field.route_cost_at(Vector2(2000, 0)) == INF, "a pipe square is blocked")
	check(_field.route_cost_at(Vector2(-2500, -2500)) == INF, "a pool square is blocked")
	check(_field.route_cost_at(Vector2(2000 + BuildingField.ROUTE_OBSTACLE_CLEARANCE + 300.0, 0)) < INF, "a square clear of it is not")
	check(_field.is_in_solid(Vector2(2100 + BuildingField.ROUTE_OBSTACLE_CLEARANCE - 10.0, 0)), "the outline is grown by the obstacle clearance")
	check(not _field.is_in_solid(Vector2(2100 + BuildingField.ROUTE_OBSTACLE_CLEARANCE + 10.0, 0)), "and by no more")
	var route := _field.find_route(Vector2(0, -2000), Vector2(4000, -2000))
	var south := false
	var crosses := false
	var prev := Vector2(0, -2000)
	var blocker := Geometry2D.offset_polygon(PackedVector2Array(pipe), BuildingField.ROUTE_OBSTACLE_CLEARANCE * 0.5)[0]
	for p in route:
		if p.y > 4000.0:
			south = true
		if not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([prev, p]), blocker).is_empty():
			crosses = true
		prev = p
	check(south, "the route goes round the pipe's south end (%s)" % str(route))
	check(not crosses, "and never through it")
	# Steering: an NPC just west of the pipe sees it as a hard obstacle ahead.
	var enemy := _enemy(Vector2(1500, -2000))
	check(_field.solids_within(enemy.global_position, 900.0).size() >= 1, "steering finds the pipe's outline near the NPC")
	enemy._build_context()
	var east: float = enemy._steer_hard[0]
	var west: float = enemy._steer_hard[enemy.STEER_SLOTS >> 1]
	check(east > 0.5, "the way east, into the pipe, is hard danger (%.2f)" % east)
	check(west < 0.1, "the way west is clear (%.2f)" % west)
