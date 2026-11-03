extends TestSuite

# CannonTest: the shoulder cannon (NS-C120) and its indirect variant, the
# howitzer (NS-H150). Their data; the cannon's line always reaching its full
# range, only its direction following the aim, for the player and for NPCs;
# its shell, a normal gun shot, flying along the line into a mecha; the
# howitzer's rounds landing in a square box lined up with the line of fire;
# and a howitzer shell flying over a building into its box. Real projectiles
# at game speed.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const CANNON := "NS-C120"
const HOWITZER := "NS-H150"
const SLOT := "shoulder_weapon_left"
const MIN_SALVO_HEAT := 650.0
const MAX_SALVO_HEAT := 1300.0
const BOX_SAMPLES := 60

# A building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _shots: Array[Dictionary] = []
var _impacts: Array[Vector2] = []


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("cannon and howitzer data", _test_data)
	await case("the cannon's line always reaches its full range", _test_line)
	await case("the cannon shell flies along the line into a mecha", _test_shell)
	await case("howitzer rounds land in a box lined up with the line", _test_box)
	await case("a howitzer shell flies over a building into its box", _test_howitzer_flight)


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
	_shots.append({"target": args.get("target_pos"), "pos": args.pos, "dir": args.dir})
	if not real:
		return
	var data = ProjectileManager.create(mecha, args, weapon)
	data.node.bullet_impact.connect(_on_impact)
	_arena.add_child(data.node)


func _on_impact(projectile, _effect, clear: bool, _body) -> void:
	if clear:
		_impacts.append(projectile.global_position)


func _pips(mecha: Mecha) -> int:
	var total := 0
	for part in mecha.armor:
		for facing in mecha.armor[part]:
			total += int(mecha.armor[part][facing].pips)
	return total


func _test_data() -> void:
	var cannon = PartManager.get_part("shoulder_weapon", CANNON)
	var howitzer = PartManager.get_part("shoulder_weapon", HOWITZER)
	if not check(cannon != null and howitzer != null, "both exist"):
		return
	var c: Dictionary = cannon.get_aoe_info()
	check_eq(c.designator, "line", "cannon: line designator")
	check_eq(c.fire_type, "direct", "cannon: direct fire")
	check_eq(c.barrage_count, 1, "cannon: one shot")
	check_eq(c.scatter_radius, 0.0, "cannon: no scatter, a skillshot")
	var h: Dictionary = howitzer.get_aoe_info()
	check_eq(h.designator, "line_box", "howitzer: line ending in a box")
	check_eq(h.fire_type, "indirect", "howitzer: indirect fire")
	check(h.scatter_radius > 0.0, "howitzer: a landing box")
	check(h.min_range > 0.0, "howitzer: a minimum range")
	check(h.blast_radius > 0.0, "howitzer: shells explode")
	for weapon in [cannon, howitzer]:
		var heat: float = weapon.muzzle_heat * weapon.barrage_count
		check(heat >= MIN_SALVO_HEAT and heat <= MAX_SALVO_HEAT, "%s: a shot costs one to two dashes of heat (%.0f kJ)" % [weapon.part_name, heat])
		check(not weapon.auto_fire, "%s: no auto fire" % weapon.part_name)


func _test_line() -> void:
	var mecha := _mecha(CANNON, Vector2(-5000, 5000), Vector2.UP)
	var weapon = mecha.build[SLOT]
	var o := mecha.global_position
	var near := mecha.designator_point(SLOT, o + Vector2(20, -300))
	check(absf(near.distance_to(o) - weapon.max_range) < 1.0, "a near aim still draws the full line")
	check(absf(Vector2.UP.angle_to(near - o) - Vector2.UP.angle_to(Vector2(20, -300))) < 0.001, "in the aimed direction")
	var side := mecha.designator_point(SLOT, o + Vector2(3000, 0))
	check(absf(rad_to_deg(absf(Vector2.UP.angle_to(side - o))) - weapon.gimbal) < 0.1, "held to the gimbal with look limits")
	# An NPC fires at its target's position: the shot still runs the full line.
	var target := o + Vector2(50, -1000)
	check_eq(mecha.fire_at_point(SLOT, target), "", "fires at a target closer than full range")
	if check_eq(_shots.size(), 1, "one shot"):
		var landing: Vector2 = _shots[0].target
		check(absf(landing.distance_to(o) - weapon.max_range) < 1.0, "its line runs to full range")
		check(absf(Vector2(50, -1000).angle_to(landing - o)) < 0.001, "through the target")


func _test_shell() -> void:
	var mecha := _mecha(CANNON, Vector2(-3000, 2000), Vector2.RIGHT, true)
	var target := _mecha(CANNON, Vector2(-2000, 2000), Vector2.UP)
	await get_tree().physics_frame
	var before := _pips(target)
	check_eq(mecha.fire_at_point(SLOT, target.global_position), "", "the cannon fires at a mecha")
	await wait_until(func(): return _pips(target) < before, 2.0)
	check(_pips(target) < before, "the shell hit it")
	if not _shots.is_empty():
		check(_shots[0].dir.dot(Vector2.RIGHT) > 0.999, "straight along the line")


func _test_box() -> void:
	var mecha := _mecha(HOWITZER, Vector2(-5000, 5000), Vector2.UP)
	var weapon = mecha.build[SLOT]
	var r: float = weapon.scatter_radius
	var point := mecha.global_position + Vector2(200, -2000)
	var along := mecha.global_position.direction_to(point)
	for _i in BOX_SAMPLES:
		mecha._fire_designator_round(SLOT, point)
	var in_box := 0
	var past_circle := 0
	for shot in _shots:
		var offset: Vector2 = shot.target - point
		var a := offset.dot(along)
		var b := offset.dot(along.orthogonal())
		if absf(a) <= r + 0.01 and absf(b) <= r + 0.01:
			in_box += 1
		if offset.length() > r:
			past_circle += 1
	check_eq(in_box, _shots.size(), "every round lands in the box")
	check(past_circle > 0, "the box's corners are used too: a square, not a circle (%d of %d)" % [past_circle, _shots.size()])


func _test_howitzer_flight() -> void:
	var mecha := _mecha(HOWITZER, Vector2(-1500, 200), Vector2.RIGHT, true)
	var point := Vector2(800, 200)
	check_eq(mecha.fire_at_point(SLOT, point), "", "the howitzer fires over the building")
	var done := await wait_until(func(): return not _impacts.is_empty(), 6.0)
	if check(done, "the shell went off") and not _shots.is_empty():
		var landing: Vector2 = _shots[0].target
		check(_impacts[0].distance_to(landing) < 1.0, "on its landing point")
		check(landing.distance_to(point) <= mecha.build[SLOT].scatter_radius * sqrt(2.0) + 0.01, "in the box")
