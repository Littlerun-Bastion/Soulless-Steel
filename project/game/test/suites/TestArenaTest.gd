extends TestSuite

# TestArenaTest: the test arena (game/arena/TestArena.tscn, opened by Arena
# Mode) starts with one NPC of each generic design plus an extra tank, spaced
# apart and clear of vehicles, has its buildings, vehicles and route grid,
# puts nothing at stake, and replaces an NPC that dies.

const TEST_ARENA := preload("res://game/arena/TestArena.tscn")

var _scene = null


func _init() -> void:
	slow = true


func run_tests() -> void:
	await case("the test arena starts with its NPCs and no stakes", _test_start)
	await case("a dead NPC is replaced", _test_respawn)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	await wait_frames(2)


func _enemies() -> Array:
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


func _start() -> void:
	PlayerProgress.reset()
	TransitionManager.captured.clear()
	_scene = TEST_ARENA.instantiate()
	add_child(_scene)
	await wait_until(func(): return _enemies().size() > 0, 20.0)


func _test_start() -> void:
	await _start()
	var expected: int = NPCManager.NPCS.size() + _arena_script().EXTRA_TANKS
	check_eq(_enemies().size(), expected, "one NPC per generic design plus the extra tank")
	check(_enemies().any(func(e): return e.movement_type == "tank"), "a tank is among them")
	check(not PlayerProgress.is_in_expedition(), "nothing is at stake")
	var vehicles := VehicleField.find(_scene)
	check(vehicles != null and vehicles.vehicle_count() > 100, "the arena has its vehicles (%d)" % (vehicles.vehicle_count() if vehicles else 0))
	var buildings := BuildingField.find(_scene)
	check(buildings != null and buildings.footprints != null and buildings.footprints.count() >= 10, "and its buildings")
	var routed := await wait_until(func(): return buildings.routes_ready(), 5.0)
	check(routed, "and a route grid")
	var enemies := _enemies()
	for e in enemies:
		check(vehicles.is_clear(e.global_position, 100.0), "%s didn't spawn inside a vehicle" % e.mecha_name)
	var closest := INF
	for a in enemies.size():
		for b in range(a + 1, enemies.size()):
			closest = minf(closest, enemies[a].global_position.distance_to(enemies[b].global_position))
	check(closest >= 400.0, "NPCs spawn apart (closest pair %.0f px)" % closest)


func _test_respawn() -> void:
	await _start()
	var before := _enemies().size()
	var victim = _enemies()[0]
	var victim_id: int = victim.get_instance_id()
	victim.die({"name": "Test"}, "test")
	var replaced := await wait_until(func():
		return _enemies().size() == before and not _enemies().any(func(e): return e.get_instance_id() == victim_id), 15.0)
	check(replaced, "a new NPC takes its place")


func _arena_script():
	return load("res://game/arena/TestArena.gd")
