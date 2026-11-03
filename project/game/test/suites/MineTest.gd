extends TestSuite

# MineTest: mine layers and mines (mine.gd). The three layers' data; a
# contact mine settling on its point and going off only when a mecha drives
# over it; a burst of sensor mines landing in the circle and one going off
# when a mecha comes near; a magnetic mine crawling to a mecha and going off;
# a direct-fire mine bouncing off a wall; mines lasting until triggered with
# no limit on their number; mines_near() for NPC code; a settled mine
# costing no process or physics; and a mine landing on a roof bursting there.
# Real mines at game speed.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const MINE := preload("res://database/parts/mine.gd")
const CONTACT := "MA-ML1"
const BURST := "MA-ML4"
const MAGNETIC := "TORI-MM1"
const SLOT := "shoulder_weapon_left"

# A building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("mine layer data", _test_data)
	await case("a contact mine goes off only when driven over", _test_contact)
	await case("a burst of sensor mines lands in the circle; one goes off when a mecha comes near", _test_sensor)
	await case("a magnetic mine crawls to a mecha and goes off", _test_magnetic)
	await case("a direct-fire mine bounces off a wall", _test_bounce)
	await case("mines last until triggered, no limit on their number; mines_near reports them", _test_many)
	await case("a mine landing on a roof bursts there", _test_roof)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
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


# A mecha at `pos` facing `facing`, with `weapon` fitted if given; its rounds
# are put in the arena. Armour is set low so a blast always costs pips.
func _mecha(pos: Vector2, facing: Vector2, weapon := "") -> Mecha:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	if weapon != "":
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
	for part in mecha.armor:
		for side in mecha.armor[part]:
			mecha.armor[part][side].level = 1
	_arena.mechas.append(mecha)
	mecha.create_projectile.connect(_on_create_projectile)
	return mecha


func _on_create_projectile(mecha, args: Dictionary, weapon) -> void:
	var data = ProjectileManager.create(mecha, args, weapon)
	_arena.add_child(data.node)


func _pips(mecha: Mecha) -> int:
	var total := 0
	for part in mecha.armor:
		for side in mecha.armor[part]:
			total += int(mecha.armor[part][side].pips)
	return total


func _armed_near(pos: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mine in MINE.mines_near(pos, radius):
		if mine.armed:
			out.append(mine)
	return out


func _test_data() -> void:
	check_eq(MINE.count(), 0, "no mines left over")
	var expect := {CONTACT: ["point", "direct", "contact"], BURST: ["circle", "indirect", "sensor"],
			MAGNETIC: ["point", "direct", "magnetic"]}
	for id in expect:
		var weapon = PartManager.get_part("shoulder_weapon", id)
		if not check(weapon != null, "%s exists" % id):
			continue
		var info: Dictionary = weapon.get_aoe_info()
		check_eq(info.designator, expect[id][0], "%s: %s designator" % [id, expect[id][0]])
		check_eq(info.fire_type, expect[id][1], "%s: %s fire" % [id, expect[id][1]])
		var probe: Node = weapon.projectile.instantiate()
		check_eq(probe.get("mine_type"), expect[id][2], "%s lays %s mines" % [id, expect[id][2]])
		probe.free()
		var heat: float = weapon.muzzle_heat * weapon.barrage_count
		check(heat >= 650.0 and heat <= 1300.0, "%s: one to two dashes of heat (%.0f kJ)" % [id, heat])
	check(PartManager.get_part("shoulder_weapon", BURST).barrage_count > 1, "the burst layer fires several mines")


func _test_contact() -> void:
	var layer := _mecha(Vector2(-4000, 4000), Vector2.UP, CONTACT)
	var point := layer.global_position + Vector2(0, -800)
	check_eq(layer.fire_at_point(SLOT, point), "", "the mine layer fires")
	var armed := await wait_until(func(): return _armed_near(point, 300.0).size() == 1, 5.0)
	if not check(armed, "a mine settled and armed"):
		return
	var mine: Dictionary = _armed_near(point, 300.0)[0]
	check(mine.position.distance_to(point) < 5.0, "on its point")
	check_eq(mine.type, "contact", "a contact mine")
	var node = mine.node
	check(not node.is_physics_processing() and not node.monitoring, "a settled mine runs no process or physics")
	var walker := _mecha(point + Vector2(200, 0), Vector2.UP)
	var before := _pips(walker)
	await wait_seconds(0.4)
	check_eq(MINE.count(), 1, "a mecha 10 m away doesn't set it off")
	walker.global_position = point + Vector2(30, 0)
	var boom := await wait_until(func(): return MINE.count() == 0, 2.0)
	check(boom, "driving over it sets it off")
	await wait_frames(2)
	check(_pips(walker) < before, "and the blast hurts the mecha")


func _test_sensor() -> void:
	var layer := _mecha(Vector2(-4000, 4000), Vector2.UP, BURST)
	var weapon = layer.build[SLOT]
	var point := layer.global_position + Vector2(0, -1200)
	check_eq(layer.fire_at_point(SLOT, point), "", "the burst layer fires")
	var landed := await wait_until(func(): return _armed_near(point, 600.0).size() == weapon.barrage_count, 6.0)
	if not check(landed, "every mine landed and armed"):
		return
	for mine in _armed_near(point, 600.0):
		check(mine.position.distance_to(point) <= weapon.scatter_radius + 0.01, "a mine in the circle")
		check_eq(mine.type, "sensor", "a sensor mine")
	var target: Dictionary = _armed_near(point, 600.0)[0]
	var walker := _mecha(target.position + Vector2(target.trigger_radius - 40.0, 0), Vector2.UP)
	var before := _pips(walker)
	var boom := await wait_until(func(): return MINE.count() < weapon.barrage_count, 2.0)
	check(boom, "a mecha coming near sets one off")
	await wait_frames(3)
	check(_pips(walker) < before, "and the blast hurts it")


func _test_magnetic() -> void:
	var layer := _mecha(Vector2(-4000, 4000), Vector2.UP, MAGNETIC)
	var point := layer.global_position + Vector2(0, -900)
	check_eq(layer.fire_at_point(SLOT, point), "", "the magnetic mine layer fires")
	var armed := await wait_until(func(): return _armed_near(point, 300.0).size() == 1, 5.0)
	if not check(armed, "a mine settled and armed"):
		return
	var mine: Dictionary = _armed_near(point, 300.0)[0]
	var start: Vector2 = mine.position
	var walker := _mecha(start + Vector2(mine.attract_radius - 80.0, 0), Vector2.UP)
	var before := _pips(walker)
	await wait_frames(10)
	var moving: Array[Dictionary] = MINE.mines_near(start, 1000.0)
	if not moving.is_empty():
		check(moving[0].position.distance_to(walker.global_position) < start.distance_to(walker.global_position) - 20.0,
				"it crawls towards the mecha")
	var boom := await wait_until(func(): return MINE.count() == 0, 3.0)
	check(boom, "and goes off when it reaches it")
	await wait_frames(3)
	check(_pips(walker) < before, "hurting it")


func _test_bounce() -> void:
	var layer := _mecha(Vector2(-700, 200), Vector2.RIGHT, CONTACT)
	var point := Vector2(400, 200)
	check_eq(layer.fire_at_point(SLOT, point), "", "the mine layer fires at a point past a wall")
	var settled := await wait_until(func(): return MINE.count() == 1, 5.0)
	if not check(settled, "the mine settled"):
		return
	var mine: Dictionary = MINE.mines_near(Vector2(-300, 200), 2000.0)[0]
	check(mine.position.x < 0.0, "it bounced back off the wall (x %.0f)" % mine.position.x)
	check_eq(MapSenses.building_key_at(_arena, mine.position), "", "outside the building")


func _test_many() -> void:
	var count := 3
	var layers: Array[Mecha] = []
	for i in count:
		layers.append(_mecha(Vector2(-4000 + i * 600, 4000), Vector2.UP, CONTACT))
	for layer in layers:
		check_eq(layer.fire_at_point(SLOT, layer.global_position + Vector2(0, -800)), "", "a layer fires")
	var settled := await wait_until(func(): return _armed_near(Vector2(-3400, 3200), 2000.0).size() == count, 5.0)
	check(settled, "every mine settled")
	await wait_seconds(2.0)
	check_eq(MINE.count(), count, "they are all still there")
	var near: Array[Dictionary] = layers[0].mines_near(layers[0].global_position + Vector2(0, -800), 100.0)
	if check_eq(near.size(), 1, "mines_near finds the one near a point"):
		check_eq(near[0].type, "contact", "with its type")
		check(near[0].owner == layers[0], "its owner")
		check(near[0].trigger_radius > 0.0, "its trigger radius")
		check(near[0].position.distance_to(layers[0].global_position + Vector2(0, -800)) < 5.0, "and its position")


func _test_roof() -> void:
	var layer := _mecha(Vector2(-1200, 200), Vector2.RIGHT, BURST)
	var weapon = layer.build[SLOT]
	var point := Vector2(200, 200)
	var scatter: float = weapon.scatter_radius
	weapon.scatter_radius = 0.0
	var reason := layer.fire_at_point(SLOT, point)
	await wait_seconds(1.0)
	weapon.scatter_radius = scatter
	check_eq(reason, "", "the burst layer fires every mine onto the building")
	await wait_seconds(2.0)
	check_eq(MINE.count(), 0, "none settled: they burst on the roof")
