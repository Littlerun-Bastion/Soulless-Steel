extends TestSuite

# NpcSenseRateTest: a near NPC (LOD tier 0) thinks every frame but senses
# (update_senses) on every Enemy.NEAR_SENSE_INTERVAL-th frame, over the time
# since its senses last ran, so its memory ages as before; a further NPC
# senses on every thinking frame, and a new NPC on its first think. Real
# physics frames; the NPC's behaviour is held (wait_for_map_sync) so only
# its senses run. The senses also drop cached wall rays too old to be used
# again (Enemy._prune_sight_cache), every SIGHT_CACHE_PRUNE_FRAMES frames.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const FRAMES := 40


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
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("a near NPC senses every other frame, its memory ageing as before", _test_near)
	await case("a far NPC senses on every thinking frame", _test_far)
	await case("cached wall rays too old to use are dropped", _test_sight_cache_pruned)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	await get_tree().physics_frame


func _player(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_physics_process(false)
	_arena.player = mecha
	_arena.mechas.append(mecha)
	return mecha


func _npc(pos: Vector2) -> Mecha:
	var enemy: Mecha = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Sense rate test")
	enemy.set_scripted(false)
	enemy.auto_illuminator = false
	enemy.wait_for_map_sync = 1.0e9
	_arena.mechas.append(enemy)
	return enemy


func _test_near() -> void:
	_player(Vector2(500, 500))
	var npc := _npc(Vector2(900, 500))
	check(npc.is_sensing_frame(), "a new NPC senses on its first think, whatever the frame")
	await wait_frames(3)
	check(npc._has_sensed, "and it has")
	check_eq(npc.lod_tier(), 0, "near the player: tier 0")
	var sensing := 0
	for i in 10:
		if npc.is_sensing_frame():
			sensing += 1
		await get_tree().physics_frame
	check_eq(sensing, 10 / npc.NEAR_SENSE_INTERVAL, "a sensing frame every %d" % npc.NEAR_SENSE_INTERVAL)
	var start: float = npc.contacts.now
	var elapsed := 0.0
	var updates := 0
	var last: float = start
	for i in FRAMES:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if npc.contacts.now != last:
			updates += 1
			last = npc.contacts.now
	check(absi(updates - FRAMES / npc.NEAR_SENSE_INTERVAL) <= 1, "its senses ran on every other frame (%d of %d)" % [updates, FRAMES])
	var aged: float = npc.contacts.now - start
	check(absf(aged - elapsed) <= get_physics_process_delta_time() * npc.NEAR_SENSE_INTERVAL + 0.001,
			"its memory aged as long as the frames took (%.3f s of %.3f s)" % [aged, elapsed])


func _test_far() -> void:
	# Off screen and past THINK_FULL_DISTANCE from the player: tier 1 or 2.
	_player(Vector2(60000, 0))
	var npc := _npc(Vector2(53000, 0))
	await wait_frames(3)
	check(npc.lod_tier() > 0, "far from the player: a far tier (%d)" % npc.lod_tier())
	var all_sensing := true
	for i in 10:
		all_sensing = all_sensing and npc.is_sensing_frame()
		await get_tree().physics_frame
	check(all_sensing, "every frame it thinks on is a sensing frame")


func _test_sight_cache_pruned() -> void:
	_player(Vector2(500, 500))
	var npc := _npc(Vector2(900, 500))
	await wait_frames(3)
	var frame := Engine.get_physics_frames()
	var at := Vector2.ZERO
	# One ray cast long ago (a body gone since), one just now.
	npc._sight_cache[111] = [frame - npc.SIGHT_RECHECK_FRAMES - 50, false, at, at]
	npc._sight_cache[222] = [frame, true, at, at]
	npc._sight_cache_pruned = frame - npc.SIGHT_CACHE_PRUNE_FRAMES
	npc.update_senses(0.1)
	check(not npc._sight_cache.has(111), "a ray too old to use is dropped")
	check(npc._sight_cache.has(222) and npc._sight_cache[222][1] == true, "a fresh one is kept as it was")
	check_eq(npc._sight_cache_pruned, Engine.get_physics_frames(), "and the next prune is SIGHT_CACHE_PRUNE_FRAMES away")
	npc._sight_cache[333] = [frame - npc.SIGHT_RECHECK_FRAMES - 50, false, at, at]
	npc.update_senses(0.1)
	check(npc._sight_cache.has(333), "between prunes nothing is dropped")
