extends TestSuite

# ArtilleryTest: the mortar (MA-M120), MLRS (TORI-AR8) and rocket launcher
# (MA-RP6). Their data; minimum and maximum range for fire_at_point and for
# the plain shoot() NPCs use; a barrage spread over time, over the barrels
# and over the scatter circle; mortar shells flying over a building onto
# their points; flat rockets stopping at a wall, at a mecha in the way, or
# going off on their points in the open. Real projectiles at game speed.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const MORTAR := "MA-M120"
const MLRS := "TORI-AR8"
const ROCKETS := "MA-RP6"
const SLOT := "shoulder_weapon_left"
## One to two dashes (650 kJ each) per salvo: the brief's starting heat.
const MIN_SALVO_HEAT := 650.0
const MAX_SALVO_HEAT := 1300.0

# A building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
# Every round fired in a case: {"target": Vector2, "pos": muzzle, "frame"}.
var _shots: Array[Dictionary] = []
# Where each real round went off.
var _impacts: Array[Vector2] = []


func _init() -> void:
	# Rounds fly at their real speed, so where they stop is as in play.
	time_scale = 1.0


func run_tests() -> void:
	await case("mortar, MLRS and rocket launcher data", _test_data)
	await case("minimum and maximum range", _test_ranges)
	await case("a barrage spreads over time, barrels and the circle", _test_barrage)
	await case("mortar shells fly over a building onto their points", _test_mortar)
	await case("rockets fly flat and stop at a wall", _test_rockets_wall)
	await case("rockets stop at a mecha in the way", _test_rockets_mecha)
	await case("rockets in the open go off on their points", _test_rockets_open)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_shots.clear()
	_impacts.clear()
	_arena = FakeArena.new()
	add_child(_arena)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await get_tree().physics_frame
	await get_tree().physics_frame


# A mecha with `weapon` on its left shoulder at `pos`, facing `facing`.
# With `real`, its rounds are put in the arena and their impacts recorded.
func _mecha(weapon: String, pos: Vector2, facing: Vector2, real := false) -> Mecha:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = weapon
	for core_id in PartManager.get_parts("core"):
		if PartManager.get_part("core", core_id).has_left_shoulder:
			design["core"] = core_id
			break
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.global_rotation = Vector2.UP.angle_to(facing)
	_arena.mechas.append(mecha)
	mecha.create_projectile.connect(_on_create_projectile.bind(real))
	return mecha


func _on_create_projectile(mecha, args: Dictionary, weapon, real: bool) -> void:
	_shots.append({"target": args.get("target_pos"), "pos": args.pos, "frame": Engine.get_physics_frames()})
	if not real:
		return
	var data = ProjectileManager.create(mecha, args, weapon)
	data.node.bullet_impact.connect(_on_impact)
	_arena.add_child(data.node)


func _on_impact(projectile, _effect, clear: bool, _body) -> void:
	if clear:
		_impacts.append(projectile.global_position)


func _test_data() -> void:
	for id in [MORTAR, MLRS, ROCKETS]:
		var weapon = PartManager.get_part("shoulder_weapon", id)
		if not check(weapon != null, "%s exists" % id):
			continue
		var info: Dictionary = weapon.get_aoe_info()
		check_eq(info.designator, "circle", "%s: circle designator" % id)
		check(info.barrage_count > 1, "%s: fires a barrage" % id)
		check(info.scatter_radius > 0.0, "%s: scatters" % id)
		check(info.blast_radius > 0.0, "%s: rounds explode" % id)
		check(weapon.ai_engage_range >= info.min_range and weapon.ai_engage_range <= info.max_range,
				"%s: AI engage range within its range" % id)
		var heat: float = weapon.muzzle_heat * weapon.barrage_count
		check(heat >= MIN_SALVO_HEAT and heat <= MAX_SALVO_HEAT, "%s: a salvo costs one to two dashes of heat (%.0f kJ)" % [id, heat])
		check(not weapon.auto_fire, "%s: no auto fire" % id)
	check_eq(PartManager.get_part("shoulder_weapon", MORTAR).get_aoe_info().fire_type, "indirect", "the mortar fires indirect")
	check_eq(PartManager.get_part("shoulder_weapon", MLRS).get_aoe_info().fire_type, "indirect", "the MLRS fires indirect")
	check_eq(PartManager.get_part("shoulder_weapon", ROCKETS).get_aoe_info().fire_type, "direct", "the rocket launcher fires direct")
	check(PartManager.get_part("shoulder_weapon", MORTAR).min_range >= 1000.0, "the mortar has a real minimum range")
	check(PartManager.get_part("shoulder_weapon", MLRS).min_range >= 1000.0, "the MLRS has a real minimum range")


func _test_ranges() -> void:
	var mecha := _mecha(MORTAR, Vector2(-5000, 5000), Vector2.UP)
	var weapon = mecha.build[SLOT]
	var o := mecha.global_position
	check_eq(mecha.fire_at_point(SLOT, o + Vector2.UP * (weapon.min_range - 100.0)), "too_close", "inside the minimum range")
	check_eq(mecha.fire_at_point(SLOT, o + Vector2.UP * (weapon.max_range + 100.0)), "too_far", "past the maximum range")
	check(_shots.is_empty(), "neither fired")
	# NPCs fire through shoot() at their target; one too close isn't shelled.
	var engage = weapon.ai_engage_range
	weapon.ai_engage_range = int(weapon.min_range - 200.0)
	mecha.shoot(SLOT)
	weapon.ai_engage_range = engage
	check(_shots.is_empty(), "shoot() doesn't fire at a target inside the minimum range")
	mecha.shoot(SLOT)
	check(not _shots.is_empty(), "shoot() fires at one in range")


func _test_barrage() -> void:
	var mecha := _mecha(MLRS, Vector2(-5000, 5000), Vector2.UP)
	var weapon = mecha.build[SLOT]
	var point := mecha.global_position + Vector2.UP * 2500.0
	check_eq(mecha.fire_at_point(SLOT, point), "", "the MLRS fires")
	await wait_until(func(): return _shots.size() >= weapon.barrage_count, 5.0)
	check_eq(_shots.size(), weapon.barrage_count, "the whole barrage")
	var frames := {}
	var barrels := {}
	var widest := 0.0
	for shot in _shots:
		frames[shot.frame] = true
		barrels[shot.pos.round()] = true
		var target: Vector2 = shot.target
		check(target.distance_to(point) <= weapon.scatter_radius + 0.01, "each rocket lands in the circle")
		for other in _shots:
			widest = maxf(widest, target.distance_to(other.target))
	check(frames.size() >= weapon.barrage_count - 1, "rockets go out one after another (%d frames)" % frames.size())
	check(barrels.size() > 1, "from more than one barrel")
	check(widest > weapon.scatter_radius * 0.5, "spread over the circle (%.0f px apart at most)" % widest)


func _test_mortar() -> void:
	var mecha := _mecha(MORTAR, Vector2(-1400, 200), Vector2.RIGHT, true)
	var weapon = mecha.build[SLOT]
	var point := Vector2(800, 200)
	check_eq(mecha.fire_at_point(SLOT, point), "", "the mortar fires over the building")
	var done := await wait_until(func(): return _impacts.size() >= weapon.barrage_count, 8.0)
	check(done, "every shell went off")
	for i in mini(_impacts.size(), _shots.size()):
		var target: Vector2 = _shots[i].target
		check(_impacts.has(target), "a shell landed on its point %s" % str(target))


func _test_rockets_wall() -> void:
	var mecha := _mecha(ROCKETS, Vector2(-900, 200), Vector2.RIGHT, true)
	var weapon = mecha.build[SLOT]
	check_eq(mecha.fire_at_point(SLOT, Vector2(700, 200)), "", "the rocket pod fires at a point past the wall")
	var done := await wait_until(func(): return _impacts.size() >= weapon.barrage_count, 5.0)
	check(done, "every rocket went off")
	for pos in _impacts:
		check(pos.x < 2.0 and pos.x > -40.0, "at the wall (x %.0f)" % pos.x)


func _test_rockets_mecha() -> void:
	var mecha := _mecha(ROCKETS, Vector2(-2000, 2000), Vector2.RIGHT, true)
	var weapon = mecha.build[SLOT]
	var target := _mecha(ROCKETS, Vector2(-1300, 2000), Vector2.UP)
	var point := Vector2(-600, 2000)
	check_eq(mecha.fire_at_point(SLOT, point), "", "the rocket pod fires past a mecha")
	var done := await wait_until(func(): return _impacts.size() >= weapon.barrage_count, 5.0)
	check(done, "every rocket went off")
	var at_mecha := 0
	for pos in _impacts:
		if pos.distance_to(target.global_position) < 200.0:
			at_mecha += 1
	check(at_mecha * 2 >= _impacts.size(), "most go off at the mecha in the way (%d of %d)" % [at_mecha, _impacts.size()])


func _test_rockets_open() -> void:
	var mecha := _mecha(ROCKETS, Vector2(-2000, 3000), Vector2.UP, true)
	var weapon = mecha.build[SLOT]
	var point := mecha.global_position + Vector2.UP * 1200.0
	check_eq(mecha.fire_at_point(SLOT, point), "", "the rocket pod fires")
	var done := await wait_until(func(): return _impacts.size() >= weapon.barrage_count, 5.0)
	check(done, "every rocket went off")
	for pos in _impacts:
		check(pos.distance_to(point) <= weapon.scatter_radius + 1.0, "in the circle (%.0f px from its centre)" % pos.distance_to(point))
