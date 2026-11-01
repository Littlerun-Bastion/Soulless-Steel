extends TestSuite

# MapVehiclesTest: map vehicles from a VehicleField (game/map/props/).
# A mecha walking into a car shoves it, and the car slides on a few metres
# after the mecha stops; a fire engine barely moves and holds the mecha back;
# a stopped car settles back into a static body and its sprite where it
# stopped; a shoved car shunts the next one; a building wall stops a shoved
# car; a vehicle stops a shot with its shot_block chance and otherwise lets
# it through with its AP; a real bullet stops in a car that always blocks;
# and vehicles don't block an Entity's sight.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")
const FIRE_ENGINE := preload("res://assets/images/map/props/vehicle_fire_engine.png")

const WALK := 480.0
const CAR_SIZE := Vector2(80, 40)
const TRUCK_SIZE := Vector2(190, 74)
const DT := 1.0 / 60.0


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _field: VehicleField = null


func _init() -> void:
	# How far things slide depends on the physics step, so run at game speed.
	time_scale = 1.0
var _layer: PropSpriteLayer = null


func run_tests() -> void:
	await case("a mecha shoves a car, which slides on a few metres", _test_shove_car)
	await case("a fire engine barely moves and holds the mecha back", _test_fire_engine)
	await case("a shoved car shunts the next one", _test_shunt)
	await case("a building wall stops a shoved car", _test_wall)
	await case("a vehicle stops shots by its shot_block chance", _test_shot_chance)
	await case("a real bullet stops in a car that always blocks", _test_real_bullet)
	await case("vehicles don't block sight", _test_sight)


func before_each() -> void:
	await _clear()


func _clear() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)


# A map with vehicles: each item is [kind, position, rotation].
func _setup(vehicles: Array, buildings: Array = []) -> void:
	_arena = FakeArena.new()
	add_child(_arena)
	var set := PropSpawnSet.new()
	set.kinds = PackedStringArray(["vehicle", "truck"])
	for v in vehicles:
		set.kind.append(0 if v[0] == "vehicle" else 1)
		set.position.append(v[1])
		set.rotation.append(v[2])
		set.size.append(CAR_SIZE if v[0] == "vehicle" else TRUCK_SIZE)
		set.variant.append(0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = set
	_arena.add_child(spawner)
	if not buildings.is_empty():
		var footprints := BuildingFootprints.new()
		var starts := PackedInt32Array([0])
		for b in buildings:
			footprints.points.append_array(PackedVector2Array(b))
			starts.append(footprints.points.size())
		footprints.starts = starts
		var field := BuildingField.new()
		field.footprints = footprints
		_arena.add_child(field)
	_layer = PropSpriteLayer.new()
	_layer.name = "Vehicles"
	_layer.kinds = PackedStringArray(["vehicle", "truck"])
	_layer.textures = {"vehicle": [HATCHBACK], "truck": [FIRE_ENGINE]}
	_layer.spans = {"vehicle": PackedFloat32Array([1.0]), "truck": PackedFloat32Array([1.0])}
	_layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(_layer)
	_field = VehicleField.new()
	_field.spawner_path = NodePath("../PropSpawner")
	_field.layer_path = NodePath("../Vehicles")
	_field.kinds = PackedStringArray(["vehicle", "truck"])
	_field.masses = {"vehicle": PackedFloat32Array([950.0]), "truck": PackedFloat32Array([14000.0])}
	_field.shot_blocks = {"vehicle": PackedFloat32Array([0.5]), "truck": PackedFloat32Array([0.85])}
	_arena.add_child(_field)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mecha(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	# Mechas spawn turned at random; face them along the push so each case
	# meets the vehicle the same way every run.
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


# Walks the mecha at `vel` for `seconds`. Returns how far it went.
func _walk(mecha: Mecha, vel: Vector2, seconds: float) -> float:
	var start := mecha.global_position
	var frames := int(seconds / DT)
	for _i in frames:
		await get_tree().physics_frame
		mecha.move(vel)
	return mecha.global_position.distance_to(start)


func _wait_settled(timeout := 6.0) -> bool:
	return await wait_until(func(): return _field.awake_count() == 0, timeout)


# Runs a shove into vehicle 0 from 400 px to its left. Returns [mecha
# distance, vehicle distance while pushed, vehicle distance after].
func _shove(kind: String, push_seconds: float) -> Array:
	await _setup([[kind, Vector2(400, 0), PI / 2.0]])
	var mecha := _mecha(Vector2(0, 0))
	await get_tree().physics_frame
	var start := _field.vehicle_transform(0).origin
	var walked := await _walk(mecha, Vector2(WALK, 0), push_seconds)
	var pushed := _field.vehicle_transform(0).origin.distance_to(start)
	# Step back so the vehicle can settle.
	mecha.global_position = Vector2(-1500, 0)
	await _wait_settled()
	var final := _field.vehicle_transform(0).origin.distance_to(start)
	return [walked, pushed, final]


func _test_shove_car() -> void:
	var r := await _shove("vehicle", 1.5)
	check(r[1] > 150.0, "the car moves while pushed (moved %.0f px)" % r[1])
	check(r[0] > WALK * 1.5 * 0.6, "the mecha keeps most of its speed (walked %.0f px)" % r[0])
	var slide: float = r[2] - r[1]
	check(slide > 15.0 and slide < 300.0, "it slides on 1-15 m after the push (slid %.0f px)" % slide)
	check(_field.awake_count() == 0 and not _field.is_awake(0), "it settles")
	var placed := _field.vehicle_transform(0).origin
	check(placed.x > 550.0, "it settled further along (x %.0f)" % placed.x)
	var sprite_pos: Vector2 = _layer._by_spawn[0][0][2]
	check(sprite_pos.distance_to(_layer.to_local(placed)) < 1.0, "its sprite is back on the layer there")
	_field._block[0] = 1.0
	var hit := MapSenses.trace_shot(_arena.get_world_2d(), placed + Vector2(0, -300), placed + Vector2(0, 300), 3)
	check(hit.by == "vehicle", "shots meet it in its new place")


func _test_fire_engine() -> void:
	var car := await _shove("vehicle", 2.5)
	await _clear()
	var truck := await _shove("truck", 2.5)
	check(truck[1] < car[1] * 0.35, "the fire engine moves far less (%.0f px against %.0f)" % [truck[1], car[1]])
	check(truck[0] < car[0] * 0.6, "the mecha is held back (walked %.0f px against %.0f)" % [truck[0], car[0]])
	check(truck[1] > 20.0, "but it does move (%.0f px)" % truck[1])


func _test_shunt() -> void:
	await _setup([["vehicle", Vector2(400, 0), PI / 2.0], ["vehicle", Vector2(560, 0), PI / 2.0]])
	var mecha := _mecha(Vector2(0, 0))
	await get_tree().physics_frame
	await _walk(mecha, Vector2(WALK, 0), 1.0)
	mecha.global_position = Vector2(-1500, 0)
	await _wait_settled()
	var second := _field.vehicle_transform(1).origin
	check(second.x > 580.0, "the second car was shunted (x %.0f)" % second.x)


func _test_wall() -> void:
	var building := [Vector2(700, -300), Vector2(1100, -300), Vector2(1100, 300), Vector2(700, 300)]
	await _setup([["vehicle", Vector2(400, 0), PI / 2.0]], [building])
	var mecha := _mecha(Vector2(0, 0))
	await get_tree().physics_frame
	await _walk(mecha, Vector2(WALK, 0), 2.0)
	mecha.global_position = Vector2(-1500, 0)
	await _wait_settled()
	var car := _field.vehicle_transform(0).origin
	check(car.x < 700.0, "the car stops outside the wall (x %.0f)" % car.x)
	check(car.x > 550.0, "after moving up to it (x %.0f)" % car.x)


func _test_shot_chance() -> void:
	await _setup([["vehicle", Vector2(0, 0), 0.0]])
	var w := _arena.get_world_2d()
	var from := Vector2(0, -300)
	var to := Vector2(0, 300)
	_field._block[0] = 1.0
	var r := MapSenses.trace_shot(w, from, to, 3)
	check(r.by == "vehicle" and absf(r.stop.y + 20.0) < 2.0, "shot_block 1 stops it at the car's side")
	_field._block[0] = 0.0
	r = MapSenses.trace_shot(w, from, to, 3)
	check(r.stop == null and r.ap == 3, "shot_block 0 lets it through with its AP")
	_field._block[0] = 0.5
	var stopped := 0
	for _i in 1000:
		if MapSenses.trace_shot(w, from, to, 3).stop != null:
			stopped += 1
	check(stopped > 430 and stopped < 570, "shot_block 0.5 stops about half (%d of 1000)" % stopped)
	r = MapSenses.trace_shot(w, Vector2(0, -10), to, 3)
	check(r.stop == null, "a shot that starts inside a car is not stopped by it")


func _test_real_bullet() -> void:
	await _setup([["vehicle", Vector2(400, 200), PI / 2.0]])
	_field._block[0] = 1.0
	var shooter := _mecha(Vector2(-1500, 1500))
	shooter.battery = 1000000.0
	var shots := []
	shooter.create_projectile.connect(func(_m, args, weapon): shots.append([args, weapon]))
	var fired := await wait_until(func():
		shooter.shoot("arm_weapon_left")
		return not shots.is_empty(), 3.0)
	if not check(fired, "the arm weapon fires"):
		return
	var args: Dictionary = shots[0][0].duplicate()
	args["pos"] = Vector2(-300, 200)
	args["dir"] = Vector2.RIGHT
	var bullet = ProjectileManager.create(shooter, args, shots[0][1]).node
	var end := [null]
	bullet.bullet_impact.connect(func(p, _e, _c, _b): end[0] = p.global_position)
	var ref: WeakRef = weakref(bullet)
	_arena.add_child(bullet)
	await wait_until(func():
		var b = ref.get_ref()
		if end[0] != null or b == null:
			return true
		if (b as Node2D).global_position.x > 1500.0:
			end[0] = (b as Node2D).global_position
			return true
		return false, 5.0)
	if ref.get_ref():
		ref.get_ref().queue_free()
	var x: float = end[0].x if end[0] != null else -9999.0
	check(absf(x - 380.0) < 20.0, "it stops at the car's side (got x %.0f)" % x)


func _test_sight() -> void:
	await _setup([["truck", Vector2(0, 0), PI / 2.0]])
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(-400, 0)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	var mecha := _mecha(Vector2(500, 0))
	await get_tree().physics_frame
	check(stalker.can_see(mecha), "an Entity sees a mecha past a fire engine")
