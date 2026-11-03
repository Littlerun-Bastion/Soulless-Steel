extends TestSuite

# LaserTest: the sweep laser (TORI-LZ1, a "rect" designator, laser_beam.gd).
# Its data; the rectangle always reaching full range; the beam hitting every
# mecha in it exactly once, for one fixed amount (armour pips and heat), and
# nothing beside it, behind it or the firer; the lit front sweeping from
# near to far; and the beam stopping at a wall, so mechas inside and past
# the building are untouched. Real beams at game speed.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const LASER := "TORI-LZ1"
const SLOT := "shoulder_weapon_left"

# A building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _beams: Array = []


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("laser data", _test_data)
	await case("the laser's rectangle always reaches full range", _test_rect)
	await case("the beam hits each mecha in it once, for a fixed amount", _test_hits)
	await case("the beam sweeps from near to far", _test_sweep)
	await case("the beam stops at a wall", _test_wall)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_beams.clear()
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


# A mecha at `pos` facing `facing`; with the laser fitted it is a shooter
# whose beams are put in the arena. Armour is set low so every hit
# penetrates and costs exactly the beam's damage pips.
func _mecha(pos: Vector2, facing: Vector2, laser := false) -> Mecha:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	if laser:
		design["shoulder_weapon_left"] = LASER
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
	if laser:
		mecha.create_projectile.connect(_on_create_projectile)
	return mecha


func _on_create_projectile(mecha, args: Dictionary, weapon) -> void:
	var data = ProjectileManager.create(mecha, args, weapon)
	_beams.append(data.node)
	_arena.add_child(data.node)


func _pips(mecha: Mecha) -> int:
	var total := 0
	for part in mecha.armor:
		for side in mecha.armor[part]:
			total += int(mecha.armor[part][side].pips)
	return total


func _beam_done() -> bool:
	return not _beams.is_empty() and _beams.all(func(b): return not is_instance_valid(b))


func _test_data() -> void:
	var laser = PartManager.get_part("shoulder_weapon", LASER)
	if not check(laser != null, "the laser exists"):
		return
	var info: Dictionary = laser.get_aoe_info()
	check_eq(info.designator, "rect", "a rectangle designator")
	check_eq(info.fire_type, "direct", "direct fire")
	check(info.width > 0.0, "a beam width")
	check_eq(info.barrage_count, 1, "one beam per shot")
	var heat: float = laser.muzzle_heat * laser.barrage_count
	check(heat >= 650.0 and heat <= 1300.0, "one to two dashes of heat (%.0f kJ)" % heat)
	check(not laser.auto_fire, "no auto fire")


func _test_rect() -> void:
	var mecha := _mecha(Vector2(-5000, 5000), Vector2.UP, true)
	var weapon = mecha.build[SLOT]
	var o := mecha.global_position
	var near := mecha.designator_point(SLOT, o + Vector2(10, -200))
	check(absf(near.distance_to(o) - weapon.max_range) < 1.0, "a near aim still draws the full beam")


func _test_hits() -> void:
	var shooter := _mecha(Vector2(-3000, 3000), Vector2.UP, true)
	var o := shooter.global_position
	var near := _mecha(o + Vector2(0, -600), Vector2.RIGHT)
	var far := _mecha(o + Vector2(0, -1400), Vector2.RIGHT)
	var beside := _mecha(o + Vector2(450, -1000), Vector2.RIGHT)
	var behind := _mecha(o + Vector2(0, 700), Vector2.RIGHT)
	await get_tree().physics_frame
	var probe: Node = shooter.build[SLOT].projectile.instantiate()
	var damage: int = probe.base_damage
	probe.free()
	var before := {}
	for m in [shooter, near, far, beside, behind]:
		before[m] = _pips(m)
	var heat_before: float = near.pending_heat_kj
	check_eq(shooter.fire_at_point(SLOT, o + Vector2(0, -1000)), "", "the laser fires")
	check(await wait_until(_beam_done, 3.0), "the beam swept and went out")
	check_eq(before[near] - _pips(near), damage, "the near mecha lost %d pips, once" % damage)
	check_eq(before[far] - _pips(far), damage, "the far mecha too: the beam goes through")
	check_eq(_pips(beside), before[beside], "a mecha beside the beam is untouched")
	check_eq(_pips(behind), before[behind], "a mecha behind the firer is untouched")
	check_eq(_pips(shooter), before[shooter], "the firer is untouched")
	check(near.pending_heat_kj > heat_before or near.internal_temp > 0.0, "the beam heats what it hits")


func _test_sweep() -> void:
	var shooter := _mecha(Vector2(-3000, 3000), Vector2.UP, true)
	var o := shooter.global_position
	var near := _mecha(o + Vector2(0, -500), Vector2.RIGHT)
	var far := _mecha(o + Vector2(0, -2000), Vector2.RIGHT)
	await get_tree().physics_frame
	var near_pips := _pips(near)
	var far_pips := _pips(far)
	var frames := {}
	check_eq(shooter.fire_at_point(SLOT, o + Vector2(0, -1000)), "", "the laser fires")
	for frame in 120:
		await get_tree().physics_frame
		if not frames.has("near") and _pips(near) < near_pips:
			frames["near"] = frame
		if not frames.has("far") and _pips(far) < far_pips:
			frames["far"] = frame
		if frames.size() == 2:
			break
	if check(frames.size() == 2, "both were hit"):
		check(frames.far - frames.near >= 10, "the far one %d frames after the near one" % (frames.far - frames.near))


func _test_wall() -> void:
	var shooter := _mecha(Vector2(-900, 200), Vector2.RIGHT, true)
	var before_wall := _mecha(Vector2(-400, 200), Vector2.UP)
	var inside := _mecha(Vector2(200, 200), Vector2.UP)
	var past := _mecha(Vector2(800, 200), Vector2.UP)
	await get_tree().physics_frame
	var before := {}
	for m in [before_wall, inside, past]:
		before[m] = _pips(m)
	check_eq(shooter.fire_at_point(SLOT, Vector2(1000, 200)), "", "the laser fires at the building")
	await wait_frames(2)
	if not _beams.is_empty() and is_instance_valid(_beams[0]):
		var end_x: float = _beams[0].global_position.x + _beams[0].get_length()
		check(absf(end_x) < 5.0, "the beam ends at the wall (x %.0f)" % end_x)
	await wait_until(_beam_done, 3.0)
	check(_pips(before_wall) < before[before_wall], "the mecha before the wall is hit")
	check_eq(_pips(inside), before[inside], "the mecha inside the building is not")
	check_eq(_pips(past), before[past], "nor the one past it")
