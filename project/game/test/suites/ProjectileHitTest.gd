extends TestSuite

# ProjectileHitTest: how a round (SimpleProjectile) finds what it hits. One
# movement ray per step meets walls, vehicles, mechas and Entities in order
# (SimpleProjectile._fly); the shooter is never in its way. Every round that
# reaches a mecha gets that mecha's armour check (Mecha.armor_check), however
# close to the mecha it starts its step and whether it flies into the mecha
# or the mecha walks onto it; a wall behind a mecha doesn't take the hit
# first; walls on the way cost AP; a parry sends the round back as the
# parrying mecha's; a bounced round doesn't hit again; a round that meets
# nothing is removed after max_flight_distance; others still sense rounds
# (an NPC's NearbyProjectile). And the polygon maths a rocket's contact hit
# uses (ProjectileManager). Real rounds at game speed, a fresh target mecha
# for every shot (a mecha that lost a part stops rounds without a check).
# A mecha's armour check leaves its _hit_facing set, which is how a case
# tells a checked hit from one that wasn't.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ROUNDS := {
	"MA-L127": "res://database/parts/projectiles/MA-L127_projectile.tscn",
	"OM1810": "res://database/parts/projectiles/OM1810_projectile.tscn",
	"Default": "res://database/parts/projectiles/DefaultSimpleProjectile.tscn",
	"Galatine-EM": "res://database/parts/projectiles/Galatine-EM_projectile.tscn",
}
const DEFAULT_ROUND := "res://database/parts/projectiles/DefaultSimpleProjectile.tscn"
const ROCKET := "res://database/parts/projectiles/RP6_rocket.tscn"
const SHOTS := 12
const LANE := 3000.0


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _lane := 0


func _init() -> void:
	time_scale = 1.0
	case_timeout = 180


func run_tests() -> void:
	await case("every round that reaches a mecha gets its armour check", _test_every_hit)
	await case("a round starting its step just short of a mecha hits it", _test_close)
	await case("the shooter is never hit by its own round", _test_shooter)
	await case("a mecha that walks onto a round takes the hit", _test_walk_onto)
	await case("a mecha with its back to a wall is hit before the wall", _test_wall_behind)
	await case("each wall on the way costs the round 1 AP", _test_wall_ap)
	await case("a parry sends the round back as the parrying mecha's", _test_parry)
	await case("a bounced round doesn't hit the same mecha again", _test_bounce)
	await case("a round that meets nothing is removed", _test_max_distance)
	await case("rounds can still be sensed by an Area", _test_sensed)
	await case("polygon crossing points close each outline properly", _test_polygon_maths)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	await get_tree().physics_frame


func _mecha(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA.duplicate())
	_arena.mechas.append(mecha)
	return mecha


# A fresh target on a lane of its own, settled in the physics space.
func _target(x := 0.0) -> Mecha:
	_lane += 1
	var mecha := _mecha(Vector2(x, _lane * LANE))
	await get_tree().physics_frame
	await get_tree().physics_frame
	return mecha


func _fire(path: String, shooter, pos: Vector2, dir: Vector2) -> Node:
	var p = load(path).instantiate()
	p.setup(shooter, {"pos": pos, "dir": dir, "seeker_target": null}, "test")
	_arena.add_child(p)
	return p


func _drop(mecha: Mecha) -> void:
	_arena.mechas.erase(mecha)
	mecha.queue_free()


func _checked(mecha: Mecha) -> bool:
	return not mecha._hit_facing.is_empty()


# Where a line from the left along the target's lane first meets its outline.
func _front(target: Mecha, y_offset := 0.0) -> Vector2:
	var y := target.global_position.y + y_offset
	var query := PhysicsRayQueryParameters2D.create(Vector2(target.global_position.x - 2000.0, y), Vector2(target.global_position.x + 2000.0, y))
	var hits := []
	var skip: Array[RID] = []
	for i in 8:
		query.exclude = skip
		var hit := _arena.get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		if hit.collider == target and target.get_part_name_from_shape(hit.shape) != "shield":
			return hit.position
		skip.append(hit.rid)
	return target.global_position


# The rightmost point of the target's outline.
func _back_x(target: Mecha) -> float:
	var right := -INF
	for c in target.get_children():
		if c is CollisionPolygon2D and not c.disabled and c.name != "ShieldCollision":
			for q in c.polygon:
				right = maxf(right, (c.global_transform * q).x)
	return right


func _wait_gone(p: Node, frames := 40) -> void:
	var t := 0
	while is_instance_valid(p) and t < frames:
		await get_tree().physics_frame
		t += 1


func _test_every_hit() -> void:
	var shooter := _mecha(Vector2(0, -90000))
	for label in ROUNDS:
		var checked := 0
		for i in SHOTS:
			var target := await _target()
			var y := target.global_position.y + randf_range(-20.0, 20.0)
			var p := _fire(ROUNDS[label], shooter, Vector2(-1000.0 - randf() * 400.0, y), Vector2.RIGHT)
			await _wait_gone(p)
			if _checked(target):
				checked += 1
			_drop(target)
		check_eq(checked, SHOTS, "%s: every round that reached the mecha got its armour check" % label)


func _test_close() -> void:
	var shooter := _mecha(Vector2(0, -90000))
	for gap in [1.0, 5.0, 10.0, 14.0]:
		var target := await _target()
		var front := _front(target)
		var p := _fire(DEFAULT_ROUND, shooter, front - Vector2(gap, 0), Vector2.RIGHT)
		await _wait_gone(p)
		check(_checked(target), "a round %.0f px short of the mecha hits it" % gap)
		_drop(target)


func _test_shooter() -> void:
	var shooter := await _target()
	var target := _mecha(shooter.global_position + Vector2(600, 0))
	await wait_frames(2)
	var p := _fire(DEFAULT_ROUND, shooter, shooter.global_position, Vector2.RIGHT)
	await _wait_gone(p)
	check(not _checked(shooter), "a round fired from inside its shooter doesn't hit it")
	check(_checked(target), "and flies on to the mecha in front")


func _test_walk_onto() -> void:
	var shooter := _mecha(Vector2(0, -90000))
	var target := await _target()
	var round_at := _front(target) - Vector2(60, 0)
	var p := _fire(DEFAULT_ROUND, shooter, round_at, Vector2.RIGHT)
	p.speed = 0.0
	await wait_frames(3)
	check(is_instance_valid(p) and not _checked(target), "a still round short of the mecha waits there")
	target.global_position.x -= 120.0
	await _wait_gone(p, 5)
	check(_checked(target), "the mecha walking onto it takes the hit")
	check(not is_instance_valid(p) or p.deflection_cooldown > 0.0, "and the round ended there or bounced off")


func _wall_strip() -> void:
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 1000000), Vector2(0, 1000000)])
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await wait_frames(3)


func _test_wall_behind() -> void:
	await _wall_strip()
	var shooter := _mecha(Vector2(0, -90000))
	var checked := 0
	for i in SHOTS:
		var target := await _target(-200.0)
		target.global_position.x -= _back_x(target) + 20.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		var p := _fire(DEFAULT_ROUND, shooter, Vector2(-1500.0 - randf() * 400.0, target.global_position.y + randf_range(-20.0, 20.0)), Vector2.RIGHT)
		# Faster than the mecha is deep: the wall is in the same step as the
		# mecha's front, the round stops at the first wall (AP 1).
		p.speed = 25000.0
		await _wait_gone(p)
		if _checked(target):
			checked += 1
		_drop(target)
	check_eq(checked, SHOTS, "every fast round hit the mecha, not the wall behind it")


func _test_wall_ap() -> void:
	await _wall_strip()
	var shooter := _mecha(Vector2(0, -90000))
	var target := await _target(900.0)
	var p := _fire(DEFAULT_ROUND, shooter, Vector2(-500.0, target.global_position.y), Vector2.RIGHT)
	p.armor_pen = 3
	var pen := []
	p.bullet_impact.connect(func(pr, _e, _c, body):
		if body == target:
			pen.append(pr.armor_pen))
	await _wait_gone(p)
	check(_checked(target), "the round crossed the building and hit the mecha")
	check(not pen.is_empty() and pen[0] == 1, "with 1 AP left of 3 after two walls (got %s)" % str(pen))


func _test_parry() -> void:
	var target := await _target()
	# The chassis can't parry: take it out of the way.
	for node in ["ChassisSingleCollision", "ChassisLeftCollision", "ChassisRightCollision"]:
		target.get_node(node).disabled = true
	var shooter := _mecha(target.global_position + Vector2(-1500, 0))
	await wait_frames(2)
	target.is_parrying = true
	target.shield_parry_timer = 10.0
	var p := _fire(DEFAULT_ROUND, shooter, target.global_position + Vector2(-900, 0), Vector2.RIGHT)
	var parried := false
	var t := 0
	while is_instance_valid(p) and t < 60:
		await get_tree().physics_frame
		if is_instance_valid(p) and p.original_mecha_info.body == target:
			parried = true
		t += 1
	check(parried, "the round was sent back as the parrying mecha's")
	check(not _checked(target), "the parrying mecha took no hit")
	check(_checked(shooter), "and the first shooter did")


func _test_bounce() -> void:
	var shooter := _mecha(Vector2(0, -90000))
	var bounced := 0
	for i in SHOTS:
		var target := await _target()
		var p := _fire(DEFAULT_ROUND, shooter, Vector2(-1000.0, target.global_position.y + randf_range(-20.0, 20.0)), Vector2.RIGHT)
		p.armor_pen = -10
		var hits := [0]
		p.bullet_impact.connect(func(_pr, _e, clear, body):
			if body == target and not clear:
				hits[0] += 1)
		await _wait_gone(p, 60)
		if hits[0] > 0:
			bounced += 1
		check(hits[0] <= 1, "a bounced round met the mecha once (%d)" % hits[0])
		_drop(target)
	check(bounced > 0, "some rounds bounced (%d of %d)" % [bounced, SHOTS])


func _test_max_distance() -> void:
	var shooter := _mecha(Vector2(0, -90000))
	var simple = load(DEFAULT_ROUND).instantiate()
	var complex = load(ROCKET).instantiate()
	check_eq(simple.max_flight_distance, 20000.0, "a round flies 20000 px at most")
	check_eq(complex.max_flight_distance, 20000.0, "so does a rocket")
	simple.free()
	complex.free()
	var p := _fire(DEFAULT_ROUND, shooter, Vector2(0, 50000), Vector2.RIGHT)
	p.max_flight_distance = 2000.0
	var started := Time.get_ticks_msec()
	await _wait_gone(p, 120)
	check(not is_instance_valid(p), "a round that met nothing is gone after its distance")
	check(Time.get_ticks_msec() - started < 1500, "soon after it flew it")


func _test_sensed() -> void:
	var shooter := _mecha(Vector2(0, -90000))
	var sensor := Area2D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 750.0
	shape.shape = circle
	sensor.add_child(shape)
	sensor.position = Vector2(0, 60000)
	_arena.add_child(sensor)
	var sensed := []
	sensor.area_entered.connect(func(area): sensed.append(area))
	await wait_frames(2)
	var p := _fire(DEFAULT_ROUND, shooter, Vector2(-2000, 60000), Vector2.RIGHT)
	await wait_frames(30)
	check(sensed.has(p), "an Area watching for rounds senses one flying through it")
	if is_instance_valid(p):
		p.queue_free()


func _test_polygon_maths() -> void:
	var square := PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)])
	var a := Transform2D(0.0, Vector2(5000, 5000))
	var b := Transform2D(0.0, Vector2(5015, 5005))
	var points: Array = ProjectileManager.get_intersection_points(square, a, square, b)
	check_eq(points.size(), 2, "two squares overlapping at a corner cross at two points")
	var expected := [Vector2(5010, 4995), Vector2(5005, 5010)]
	for e in expected:
		var found := false
		for point in points:
			if (point as Vector2).distance_to(e) < 0.01:
				found = true
		check(found, "they cross at %s" % str(e))
	# The square's closing edge (its last point back to its first) counts.
	var c := Transform2D(0.0, Vector2(4985, 5005))
	var closing: Array = ProjectileManager.get_intersection_points(square, a, square, c)
	check_eq(closing.size(), 2, "squares overlapping on the closing edge's side cross twice")
	var circle_points: Array = ProjectileManager.get_intersection_circle_polygon(Vector2.ZERO, 12.0, Transform2D(0.0, Vector2(5000, 5000)), square, a)
	check_eq(circle_points.size(), 4, "a circle a bit wider than a square meets each side (first crossing along it)")
