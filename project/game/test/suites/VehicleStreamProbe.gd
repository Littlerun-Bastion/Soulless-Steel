extends TestSuite

# VehicleStreamProbe: what parked vehicles cost with many of them. It builds
# a VehicleField of about 15,000 vehicles over Helwan's play area (12,000
# cars and 700 trucks spread out, plus CAR_PARKS car parks of 300 cars in
# 100 x 60 m each) and prints:
#   - _update_streaming's time (mean and worst ms) with the player and 12
#     NPCs moving, all in full simulation and with a third of the NPCs in the
#     distant tier, and how many boxes are made;
#   - the per-frame cost under FrameProfiler's "vehicles" key over real
#     physics frames;
#   - an NPC in the middle of a car park: vehicles_near and
#     steering_obstacles_into (the lookups NPC steering makes), and a whole
#     steering rebuild (Enemy._build_context) there and on open ground;
#   - the route grid: the main-thread part of its build (which reads every
#     vehicle), the build's time, and the extra route cost of a car park's
#     squares.
# The numbers are headless. It never fails on a timing. A probe, not a
# test: it runs only when named (--suite=VehicleStreamProbe).

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const ENEMY_SCRIPT := preload("res://game/mecha/Enemy.gd")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")
const FIRE_ENGINE := preload("res://assets/images/map/props/vehicle_fire_engine.png")
const SEED := 20261124
const CARS := 12000
const TRUCKS := 700
const CAR_PARKS := 10
const PARK_CARS := 300
const PARK_SIZE := Vector2(2000, 1200)
const CAR_SIZE := Vector2(88, 36)
const TRUCK_SIZE := Vector2(170, 50)
const PLAY_HALF := 48000.0
const NPCS := 12


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
		return Vector2(-5000, -5000)


class Waker extends Node2D:
	var distant := false
	var velocity := Vector2.ZERO
	func _init() -> void:
		add_to_group("mecha")
	func is_distant() -> bool:
		return distant


var _arena: FakeArena = null
var _field: VehicleField = null
var _parks: Array[Vector2] = []
var _wakers: Array[Waker] = []


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 300


func run_tests() -> void:
	if not asked_for():
		return
	await _build()
	await case("streaming boxes round the player and 12 NPCs", _test_streaming)
	await case("an NPC in a car park: steering lookups and rebuilds", _test_steering)
	await case("the route grid's vehicle weights", _test_route_grid)
	if is_instance_valid(_arena):
		_arena.queue_free()


func asked_for() -> bool:
	if get_tree().current_scene == self:
		return true
	for filter in TestSession.get_options()["suites"]:
		if str(filter).to_lower() in get_suite_name().to_lower():
			return true
	print("  (a probe: run it with --suite=%s)" % get_suite_name())
	return false


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_arena = FakeArena.new()
	add_child(_arena)
	var bounds := MapBounds.new()
	bounds.map_rect = Rect2(-54000, -54000, 108000, 108000)
	bounds.border = 4000.0
	_arena.add_child(bounds)
	var spawn_set := PropSpawnSet.new()
	spawn_set.kinds = PackedStringArray(["vehicle", "truck"])
	var add := func(kind: int, pos: Vector2, rot: float) -> void:
		spawn_set.kind.append(kind)
		spawn_set.position.append(pos)
		spawn_set.rotation.append(rot)
		spawn_set.size.append(CAR_SIZE if kind == 0 else TRUCK_SIZE)
		spawn_set.variant.append(0)
	for _i in CARS:
		add.call(0, Vector2(rng.randf_range(-PLAY_HALF, PLAY_HALF), rng.randf_range(-PLAY_HALF, PLAY_HALF)),
				rng.randf_range(0, TAU))
	for _i in TRUCKS:
		add.call(1, Vector2(rng.randf_range(-PLAY_HALF, PLAY_HALF), rng.randf_range(-PLAY_HALF, PLAY_HALF)),
				rng.randf_range(0, TAU))
	# Car parks: rows of bays 2.5 m wide, a row every 7.5 m (bays and half an
	# aisle), 40 bays a row, 300 cars a park.
	for p in CAR_PARKS:
		var corner := Vector2(rng.randf_range(-40000, 38000), rng.randf_range(-40000, 38000))
		_parks.append(corner + PARK_SIZE * 0.5)
		for k in PARK_CARS:
			@warning_ignore("integer_division")
			var row := k / 40
			var bay := k % 40
			add.call(0, corner + Vector2(25 + bay * 50, 75 + row * 150), PI / 2.0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawn_set
	_arena.add_child(spawner)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array([Vector2(-200, -200), Vector2(200, -200), Vector2(200, 200), Vector2(-200, 200)])
	footprints.starts = PackedInt32Array([0, 4])
	var buildings := BuildingField.new()
	buildings.footprints = footprints
	var layer := PropSpriteLayer.new()
	layer.name = "Vehicles"
	layer.kinds = PackedStringArray(["vehicle", "truck"])
	layer.textures = {"vehicle": [HATCHBACK], "truck": [FIRE_ENGINE]}
	layer.spans = {"vehicle": PackedFloat32Array([1.0]), "truck": PackedFloat32Array([1.0])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
	_field = VehicleField.new()
	_field.spawner_path = NodePath("../PropSpawner")
	_field.layer_path = NodePath("../Vehicles")
	_field.kinds = PackedStringArray(["vehicle", "truck"])
	_field.masses = {"vehicle": PackedFloat32Array([1200.0]), "truck": PackedFloat32Array([14000.0])}
	_field.shot_blocks = {"vehicle": PackedFloat32Array([0.5]), "truck": PackedFloat32Array([0.85])}
	_field.stream = true
	var started := Time.get_ticks_usec()
	_arena.add_child(_field)
	await wait_until(func(): return _field.is_built(), 30.0)
	print("    built %d vehicles in %.0f ms (VehicleField._build, deferred)" % [_field.vehicle_count(),
			(Time.get_ticks_usec() - started) / 1000.0])
	_arena.add_child(buildings)
	for i in NPCS + 1:
		var w := Waker.new()
		w.position = Vector2(rng.randf_range(-20000, 20000), rng.randf_range(-20000, 20000))
		w.velocity = Vector2.from_angle(rng.randf_range(0, TAU)) * 400.0
		_arena.add_child(w)
		_wakers.append(w)
	_wakers[0].position = _parks[0]
	_wakers[1].position = _parks[1] + Vector2(800, 0)


func _move_wakers(seconds: float) -> void:
	for w in _wakers:
		w.position += w.velocity * seconds
		w.position = w.position.clamp(Vector2(-PLAY_HALF, -PLAY_HALF), Vector2(PLAY_HALF, PLAY_HALF))


func _time_streaming(label: String) -> void:
	var times := PackedFloat32Array()
	var mechas := get_tree().get_nodes_in_group("mecha")
	for key in _field._active_cells.keys():
		_field._active_cells.erase(key)
		for j in _field._cells.get(key, PackedInt32Array()):
			_field._free_static(j)
	var t0 := Time.get_ticks_usec()
	_field._update_streaming(mechas)
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var boxes := _field.static_body_count()
	print("    %s: first call with no boxes yet %.3f ms (%d boxes made)" % [label, first_ms, boxes])
	for _i in 200:
		_move_wakers(1.0 / 6.0)
		var t := Time.get_ticks_usec()
		_field._update_streaming(mechas)
		times.append((Time.get_ticks_usec() - t) / 1000.0)
		boxes = maxi(boxes, _field.static_body_count())
	var sorted := times.duplicate()
	sorted.sort()
	var mean := 0.0
	for t in times:
		mean += t
	mean /= times.size()
	print("    %s: then, wakers moving 67 px a call: mean %.3f ms, median %.3f, 95th %.3f, worst %.3f; up to %d boxes" % [label,
			mean, sorted[int(sorted.size() * 0.5)], sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1], boxes])
	check(boxes > 0, "%s: boxes are made round the wakers" % label)


func _test_streaming() -> void:
	await _time_streaming("13 wakers in full simulation")
	for i in range(1, NPCS + 1, 3):
		_wakers[i].distant = true
	await _time_streaming("4 of the NPCs distant")
	for w in _wakers:
		w.distant = false
	FrameProfiler.enabled = true
	FrameProfiler.reset()
	var frames := 600
	for _i in frames:
		await get_tree().physics_frame
		_move_wakers(1.0 / 60.0)
	FrameProfiler.enabled = false
	for row in FrameProfiler.report():
		if row.key == "vehicles":
			print("    per physics frame (%d frames): vehicles mean %.4f ms, worst %.3f ms" % [frames, row.mean_ms,
					row.worst_ms])
			check(row.mean_ms >= 0.0, "the per-frame cost was measured")
	print("    boxes now: %d of %d vehicles" % [_field.static_body_count(), _field.vehicle_count()])
	FrameProfiler.reset()


func _enemy(pos: Vector2) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Probe NPC")
	enemy.global_rotation = 0.0
	enemy.set_scripted(true)
	_arena.mechas.append(enemy)
	return enemy


func _time(fn: Callable, runs: int) -> float:
	var t := Time.get_ticks_usec()
	for _i in runs:
		fn.call()
	return (Time.get_ticks_usec() - t) / 1000.0 / runs


func _test_steering() -> void:
	var lot := _parks[2]
	var npc := _enemy(lot)
	await wait_frames(3)
	var buf := PackedFloat32Array()
	var reach := 650.0 + 130.0
	var near_ms := _time(func(): _field.vehicles_near(lot, 650.0), 1000)
	var near_count := _field.vehicles_near(lot, 650.0).size()
	var steer_ms := _time(func(): _field.steering_obstacles_into(lot, reach, buf), 1000)
	var steer_count := int(buf.size() / float(VehicleField.STEER_STRIDE))
	print("    car park centre: vehicles_near(650 px) %d cars in %.4f ms; steering_obstacles_into(%.0f px) %d in %.4f ms"
			% [near_count, near_ms, reach, steer_count, steer_ms])
	npc.set_interest(Vector2.RIGHT, 0.0)
	var in_lot_ms := _time(func(): npc._build_context(), 200)
	var open := Vector2(-46000, 46000)
	npc.global_position = open
	await wait_frames(1)
	var open_ms := _time(func(): npc._build_context(), 200)
	var edge := lot + Vector2(PARK_SIZE.x * 0.5 + 300, 0)
	npc.global_position = edge
	await wait_frames(1)
	var edge_ms := _time(func(): npc._build_context(), 200)
	print("    one steering rebuild (Enemy._build_context): in the car park %.3f ms, at its edge %.3f ms, on open ground %.3f ms"
			% [in_lot_ms, edge_ms, open_ms])
	print("    (rebuilt every %d physics frames near the player, %d far)" % [ENEMY_SCRIPT.STEER_NEAR_INTERVAL, ENEMY_SCRIPT.STEER_FAR_INTERVAL])
	check(steer_count > 100, "the car park is dense round the NPC (%d cars)" % steer_count)
	npc.queue_free()
	_arena.mechas.erase(npc)
	await wait_frames(2)


func _test_route_grid() -> void:
	var buildings := BuildingField.find(_arena)
	if not check(buildings != null, "a BuildingField"):
		return
	await wait_until(func(): return buildings.routes_ready(), 60.0)
	buildings._route_grid = null
	buildings._route_task = -1
	var t := Time.get_ticks_usec()
	buildings._start_route_build()
	var main_ms := (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var ready := await wait_until(func(): return buildings.routes_ready(), 60.0)
	var build_ms := (Time.get_ticks_usec() - t) / 1000.0
	check(ready, "the grid builds")
	var area := buildings.route_area()
	print("    route grid %s: main-thread part (reads all %d vehicles) %.1f ms; build on the worker %.0f ms" % [
			str(area.size / BuildingField.ROUTE_CELL), _field.vehicle_count(), main_ms, build_ms])
	var lot := _parks[3]
	var costs := PackedFloat32Array()
	for dy in range(-2, 3):
		var row := PackedStringArray()
		for dx in range(-3, 4):
			var at := lot + Vector2(dx, dy) * BuildingField.ROUTE_CELL
			var cost := buildings.route_cost_at(at)
			costs.append(cost)
			var cell := buildings.route_cell(at)
			var cars := 0
			for v in _field.vehicles_near(at, 400.0):
				if buildings.route_cell(_field.vehicle_transform(v).origin) == cell:
					cars += 1
			row.append("%.1f/%d" % [cost, cars])
		print("      cost/cars: ", " ".join(row))
	costs.sort()
	var capped := 0
	for c in costs:
		if c >= 1.0 + BuildingField.ROUTE_VEHICLE_MAX - 0.01:
			capped += 1
	print("    car park squares: route cost %.1f .. %.1f, %d of %d at the cap (open ground 1.0, cap 1 + %.1f)" % [costs[0],
			costs[costs.size() - 1], capped, costs.size(), BuildingField.ROUTE_VEHICLE_MAX])
	print("    open ground: %.1f" % buildings.route_cost_at(Vector2(-46000, 46000)))
