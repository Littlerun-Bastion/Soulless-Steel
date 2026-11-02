extends TestSuite

# MapWallsTest: building walls and foliage from the generated maps (game/map/).
# Two square buildings from a BuildingField: walls block sight between
# outside and inside, but two points in one building see each other; a shot
# loses 1 AP per wall and stops at the wall that uses up its AP, for both the
# wall maths and a real bullet; an impact-fused grenade goes off at the
# first wall whatever its AP; an Entity can't spot a mecha through a wall
# but can in the same building; and a tree over a mecha hides it from
# further away.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")

# Building A spans x 0..400, building B x 1000..1400; both y 0..400.
const A := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]
const B := [Vector2(1000, 0), Vector2(1400, 0), Vector2(1400, 400), Vector2(1000, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


# Stands in for a foliage layer: a tree crown of `radius` at `centre`.
class FakeFoliage extends Node2D:
	var centre := Vector2.ZERO
	var radius := 150.0
	func concealment_at(pos: Vector2) -> String:
		return "tree" if pos.distance_to(centre) <= radius else ""


var _arena: FakeArena = null


func run_tests() -> void:
	await case("walls block sight, except inside one building", _test_sight)
	await case("each wall costs a shot 1 AP", _test_ap_maths)
	await case("a real bullet stops at the wall that uses up its AP", _test_real_bullet)
	await case("an impact-fused grenade goes off at the first wall", _test_grenade)
	await case("an Entity can't see a mecha through a wall", _test_entity_sight)
	await case("a tree over a mecha hides it from further away", _test_tree)
	await case("walls far apart are merged per cell and still each count", _test_wall_cells)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(A + B)
	footprints.starts = PackedInt32Array([0, 4, 8])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _world() -> World2D:
	return _arena.get_world_2d()


func _test_sight() -> void:
	var w := _world()
	check(MapSenses.walls_between(w, Vector2(-200, 200), Vector2(200, 200)), "outside to inside A is blocked")
	check(MapSenses.walls_between(w, Vector2(-200, 200), Vector2(700, 200)), "past A from side to side is blocked")
	check(not MapSenses.walls_between(w, Vector2(50, 50), Vector2(350, 350)), "two points inside A see each other")
	check(MapSenses.walls_between(w, Vector2(200, 200), Vector2(1200, 200)), "inside A to inside B is blocked")
	check(not MapSenses.walls_between(w, Vector2(-200, 600), Vector2(1600, 600)), "a clear line past both is open")


func _test_ap_maths() -> void:
	var w := _world()
	var from := Vector2(-200, 200)
	var to := Vector2(1600, 200)
	check_eq(MapSenses.wall_hits(w, from, to).size(), 4, "four walls on the way through A and B")
	var r1 := MapSenses.trace_shot(w, from, to, 1)
	check(r1.stop != null and absf(r1.stop.x - 0.0) < 2.0, "AP 1 stops at A's first wall")
	var r2 := MapSenses.trace_shot(w, from, to, 2)
	check(r2.stop != null and absf(r2.stop.x - 400.0) < 2.0, "AP 2 stops at A's far wall")
	var r5 := MapSenses.trace_shot(w, from, to, 5)
	check(r5.stop == null and r5.ap == 1, "AP 5 goes through all four walls with 1 left")
	var inside := MapSenses.trace_shot(w, Vector2(200, 200), Vector2(700, 200), 1)
	check(inside.stop != null and absf(inside.stop.x - 400.0) < 2.0, "a shot from inside A meets A's wall")


func _test_real_bullet() -> void:
	var shooter := _mecha(Vector2(-1500, 1500))
	shooter.battery = 1000000.0
	var shots := []
	shooter.create_projectile.connect(func(_m, args, weapon): shots.append([args, weapon]))
	var fired := await wait_until(func():
		shooter.shoot("arm_weapon_left")
		return not shots.is_empty(), 3.0)
	if not check(fired, "the arm weapon fires"):
		return
	for case_ap in [[1, 0.0], [2, 400.0], [5, 0.0]]:
		var args: Dictionary = shots[0][0].duplicate()
		args["pos"] = Vector2(-300, 200)
		args["dir"] = Vector2.RIGHT
		var bullet = ProjectileManager.create(shooter, args, shots[0][1]).node
		bullet.armor_pen = case_ap[0]
		# Where it ends: the impact point if it stops, else how far it flew.
		var end := [null]
		bullet.bullet_impact.connect(func(p, _e, _c, _b): end[0] = p.global_position)
		var ref: WeakRef = weakref(bullet)
		_arena.add_child(bullet)
		await wait_until(func():
			var b = ref.get_ref()
			if end[0] != null or b == null:
				return true
			var pos: Vector2 = (b as Node2D).global_position
			if pos.x > 1800.0:
				end[0] = pos
				return true
			return false, 5.0)
		if ref.get_ref():
			ref.get_ref().queue_free()
		var x: float = end[0].x if end[0] != null else -9999.0
		var expected: float = case_ap[1]
		if case_ap[0] >= 4:
			check(x > 1400.0, "AP %d goes through both buildings (got x %.0f)" % [case_ap[0], x])
		else:
			check(absf(x - expected) < 20.0, "AP %d stops at x %d (got %.0f)" % [case_ap[0], expected, x])


func _test_grenade() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "MA-GL44"
	for core_id in PartManager.get_parts("core"):
		if PartManager.get_part("core", core_id).has_left_shoulder:
			design["core"] = core_id
			break
	var shooter := _mecha(Vector2(-1500, 1500), design)
	shooter.battery = 1000000.0
	var shots := []
	shooter.create_projectile.connect(func(_m, args, weapon): shots.append([args, weapon]))
	var fired := await wait_until(func():
		shooter.shoot("shoulder_weapon_left")
		return not shots.is_empty(), 3.0)
	if not check(fired, "the grenade launcher fires"):
		return
	var args: Dictionary = shots[0][0].duplicate()
	args["pos"] = Vector2(-150, 200)
	args["dir"] = Vector2.RIGHT
	var grenade = ProjectileManager.create(shooter, args, shots[0][1]).node
	if not check(grenade.fuse_is_contact_enabled, "the GL44 grenade has an impact fuse"):
		grenade.queue_free()
		return
	grenade.armor_pen = 5
	var ref: WeakRef = weakref(grenade)
	_arena.add_child(grenade)
	var went_off := await wait_until(func():
		var g: Object = ref.get_ref()
		return g == null or g.payload_expended, 4.0)
	var g: Object = ref.get_ref()
	check(went_off, "it went off")
	if g != null:
		check((g as Node2D).global_position.x < 10.0, "at the first wall, not past it")
		g.queue_free()


func _test_entity_sight() -> void:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(200, 200)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	var mecha := _mecha(Vector2(-600, 200))
	await get_tree().physics_frame
	check(stalker.find_prey() == null, "a mecha outside the building is unseen")
	mecha.global_position = Vector2(300, 300)
	await get_tree().physics_frame
	check(stalker.find_prey() == mecha, "a mecha in the same building is seen")


func _test_tree() -> void:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(-2000, 1500)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	var d := stalker.sight_range * 0.8
	var mecha := _mecha(Vector2(-2000 + d, 1500))
	await get_tree().physics_frame
	check(stalker.find_prey() == mecha, "seen in the open at 80% of sight range")
	var tree := FakeFoliage.new()
	tree.centre = mecha.global_position
	tree.add_to_group("foliage_layer")
	_arena.add_child(tree)
	# Concealment is looked up once per physics frame.
	await get_tree().physics_frame
	check_eq(MapSenses.detection_mult(mecha), MapSenses.TREE_CONCEALMENT, "the tree conceals the mecha")
	check(stalker.find_prey() == null, "hidden under a tree at the same distance")
	tree.remove_from_group("foliage_layer")


func _mecha(pos: Vector2, design := PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	_arena.mechas.append(mecha)
	return mecha


func _test_wall_cells() -> void:
	for n in _arena.get_children():
		if n is BuildingField:
			n.free()
	# A third building 12,000 px away, in another wall cell.
	var c := [Vector2(12000, 0), Vector2(12400, 0), Vector2(12400, 400), Vector2(12000, 400)]
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(A + B + c)
	footprints.starts = PackedInt32Array([0, 4, 8, 12])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await get_tree().physics_frame
	check_eq(field.wall_body_count(), 2, "two cells, two wall bodies for three buildings")
	var hits := MapSenses.wall_hits(_world(), Vector2(11800, 200), Vector2(12600, 200))
	check_eq(hits.size(), 2, "the far building's two walls")
	var r := MapSenses.trace_shot(_world(), Vector2(-200, 300), Vector2(12600, 300), 6)
	check(r.stop != null and absf(r.stop.x - 12400.0) < 2.0, "AP 6 stops at the sixth wall, in the far cell")
