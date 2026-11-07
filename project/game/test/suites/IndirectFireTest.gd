extends TestSuite

# IndirectFireTest: indirect rounds and blasts (complex_projectile,
# MapSenses.building_key_at). An indirect shell flies over a building and a
# truck that stops every shot and lands on its point, where a direct shell
# stops in the truck; a shell that comes down on a building bursts on the
# roof and hurts no one inside; one landing in the open hurts a mecha next
# to it; a direct shell with a landing point goes off there; and building
# walls block blasts both ways, for generated and hand-made buildings, while
# a blast still hurts the mecha that fired it.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const FIRE_ENGINE := preload("res://assets/images/map/props/vehicle_fire_engine.png")
const TRUCK_SIZE := Vector2(190, 74)

# A generated building spanning x 0..400, y 0..400; a hand-made one spanning
# x 2000..2400, y 0..400; a truck at TRUCK.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]
const HAND_MADE := [Vector2(2000, 0), Vector2(2400, 0), Vector2(2400, 400), Vector2(2000, 400)]
const TRUCK := Vector2(800, 200)
const SHOOTER_POS := Vector2(-4000, 4000)
# Mechas are placed this far from a blast: well inside its reach, but not
# so close that the blast starts inside the mecha's own shapes. They all
# face the same way, so the same parts are in reach every run.
const NEAR := 170.0


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _shooter: Mecha = null
var _template := {}
var _weapon_id = null


func run_tests() -> void:
	await case("an indirect shell flies over a building and a truck and lands on its point", _test_over)
	await case("a shell coming down on a building bursts on the roof and hurts no one", _test_roof)
	await case("a shell landing in the open hurts a mecha next to it", _test_open)
	await case("a shell landing right on a mecha hurts it", _test_direct_on)
	await case("a direct shell with a landing point goes off there", _test_direct_landing)
	await case("generated building walls block blasts both ways", _test_walls_generated)
	await case("hand-made building walls block blasts both ways", _test_walls_hand_made)
	await case("a blast hurts the mecha that fired it", _test_firer)


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

	var hand_made := Node2D.new()
	var area := Area2D.new()
	area.monitorable = false
	area.add_to_group("building_area")
	var poly := CollisionPolygon2D.new()
	poly.polygon = PackedVector2Array(HAND_MADE)
	area.add_child(poly)
	hand_made.add_child(area)
	_arena.add_child(hand_made)

	var spawn_set := PropSpawnSet.new()
	spawn_set.kinds = PackedStringArray(["truck"])
	spawn_set.kind.append(0)
	spawn_set.position.append(TRUCK)
	spawn_set.rotation.append(0.0)
	spawn_set.size.append(TRUCK_SIZE)
	spawn_set.variant.append(0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawn_set
	_arena.add_child(spawner)
	var layer := PropSpriteLayer.new()
	layer.name = "Vehicles"
	layer.kinds = PackedStringArray(["truck"])
	layer.textures = {"truck": [FIRE_ENGINE]}
	layer.spans = {"truck": PackedFloat32Array([1.0])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
	var vehicles := VehicleField.new()
	vehicles.spawner_path = NodePath("../PropSpawner")
	vehicles.layer_path = NodePath("../Vehicles")
	vehicles.kinds = PackedStringArray(["truck"])
	vehicles.masses = {"truck": PackedFloat32Array([14000.0])}
	vehicles.shot_blocks = {"truck": PackedFloat32Array([1.0])}
	vehicles.stream = false
	_arena.add_child(vehicles)

	_shooter = _mecha(SHOOTER_POS, _gl44_design())
	await get_tree().physics_frame
	await get_tree().physics_frame
	vehicles._block[0] = 1.0
	# A real GL44 shot, as the template for the rounds below.
	var shots := []
	_shooter.create_projectile.connect(func(_m, args, weapon): shots.append([args, weapon]))
	_shooter.shoot("shoulder_weapon_left")
	_template = shots[0][0].duplicate() if not shots.is_empty() else {}
	_weapon_id = shots[0][1] if not shots.is_empty() else null


func _gl44_design() -> Dictionary:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "MA-GL44"
	for core_id in PartManager.get_parts("core"):
		if PartManager.get_part("core", core_id).has_left_shoulder:
			design["core"] = core_id
			break
	return design


func _mecha(pos: Vector2, design := PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


# A GL44 shell from `pos`, aimed at `target` (null: none, flying right).
# AP 6, so every blast hit penetrates and shows as lost armour pips.
func _round(pos: Vector2, target, indirect: bool):
	var args: Dictionary = _template.duplicate()
	args["pos"] = pos
	args.erase("target_pos")
	args.erase("indirect")
	var dir := Vector2.RIGHT
	if target != null:
		args["target_pos"] = target
		args["indirect"] = indirect
		dir = pos.direction_to(target)
	args["dir"] = dir
	args["align_dir"] = dir
	var shell = ProjectileManager.create(_shooter, args, _weapon_id).node
	shell.armor_pen = 6
	return shell


# Fires `shell` and waits until it goes off. Returns {"pos", "roof"}, empty if it never did.
func _fly(shell, timeout := 5.0) -> Dictionary:
	var end := {}
	shell.bullet_impact.connect(func(p, _e, _c, _b):
		if not end.has("pos"):
			end["pos"] = p.global_position
			end["roof"] = p.roof_burst)
	var ref: WeakRef = weakref(shell)
	_arena.add_child(shell)
	await wait_until(func(): return end.has("pos") or ref.get_ref() == null, timeout)
	if ref.get_ref():
		ref.get_ref().queue_free()
	return end


# A shell that only explodes, at `pos`: no flight, no contact or proximity
# fuse. Waits for its blast area to find what is in reach.
func _blast_at(pos: Vector2) -> void:
	var shell = _round(pos, null, false)
	shell.monitoring = false
	shell.get_node("Fuse").monitoring = false
	_arena.add_child(shell)
	shell.set_physics_process(false)
	for _i in 3:
		await get_tree().physics_frame
	shell.explosion()


func _pips(mecha: Mecha) -> int:
	var total := 0
	for part in mecha.armor:
		for facing in mecha.armor[part]:
			total += int(mecha.armor[part][facing].pips)
	return total


func _test_over() -> void:
	if not check(not _template.is_empty(), "the GL44 fires"):
		return
	check(_template.get("indirect") == true, "the GL44 fires indirect")
	var target := Vector2(1200, 200)
	var end: Dictionary = await _fly(_round(Vector2(-300, 200), target, true))
	check(end.has("pos"), "it went off")
	if end.has("pos"):
		check((end.pos as Vector2).distance_to(target) < 1.0, "on its point, past the building and the truck (at %s)" % str(end.pos))
	var direct: Dictionary = await _fly(_round(Vector2(550, 200), target, false))
	check(direct.has("pos") and (direct.pos as Vector2).x < TRUCK.x + 20.0, "a direct shell on the same line stops in the truck")


func _test_roof() -> void:
	var target := Vector2(200, 330)
	var inside := _mecha(Vector2(200, 330 - NEAR + 80))
	var outside := _mecha(Vector2(-20, 330))
	await get_tree().physics_frame
	var before_in := _pips(inside)
	var before_out := _pips(outside)
	var shell = _round(Vector2(-900, 330), target, true)
	shell.muzzle_speed = 400
	var end: Dictionary = await _fly(shell, 8.0)
	check(end.get("roof", false), "a roof burst")
	check_eq(_pips(inside), before_in, "the mecha inside is unhurt")
	check_eq(_pips(outside), before_out, "the mecha outside the wall is unhurt")


func _test_open() -> void:
	var target := Vector2(-1200, 1200)
	var mecha := _mecha(target + Vector2(NEAR, 0))
	await get_tree().physics_frame
	var before := _pips(mecha)
	var shell = _round(Vector2(-2000, 1200), target, true)
	shell.muzzle_speed = 400
	var end: Dictionary = await _fly(shell, 8.0)
	check(end.has("pos") and not end.get("roof", true), "an open-ground burst")
	check(_pips(mecha) < before, "the mecha next to it is hurt")


func _test_direct_on() -> void:
	var target := Vector2(-1200, 1800)
	var mecha := _mecha(target)
	await get_tree().physics_frame
	var before := _pips(mecha)
	var shell = _round(Vector2(-2000, 1800), target, true)
	shell.muzzle_speed = 400
	var end: Dictionary = await _fly(shell, 8.0)
	check(end.has("pos"), "it went off on the mecha")
	check(_pips(mecha) < before, "the mecha it landed on is hurt")


func _test_direct_landing() -> void:
	var target := Vector2(-400, 1500)
	var end: Dictionary = await _fly(_round(Vector2(-1400, 1500), target, false))
	check(end.has("pos"), "it went off")
	if end.has("pos"):
		check((end.pos as Vector2).distance_to(target) < 150.0, "at its landing point (at %s)" % str(end.pos))


func _test_walls_generated() -> void:
	await _check_blast(Vector2(-150, 200), Vector2(-150 + NEAR, 200), false, "outside, mecha inside: blocked")
	await _check_blast(Vector2(340, 200), Vector2(340 + NEAR, 200), false, "inside, mecha outside: blocked")
	await _check_blast(Vector2(-300, 600), Vector2(-300 + NEAR, 600), true, "both outside: hurt")
	await _check_blast(Vector2(80, 200), Vector2(80 + NEAR, 200), true, "both inside: hurt")


func _test_walls_hand_made() -> void:
	await _check_blast(Vector2(1850, 200), Vector2(1850 + NEAR, 200), false, "outside, mecha inside: blocked")
	await _check_blast(Vector2(2340, 200), Vector2(2340 + NEAR, 200), false, "inside, mecha outside: blocked")
	await _check_blast(Vector2(2080, 200), Vector2(2080 + NEAR, 200), true, "both inside: hurt")


func _check_blast(blast: Vector2, at: Vector2, hurt: bool, message: String) -> void:
	var mecha := _mecha(at)
	await get_tree().physics_frame
	var before := _pips(mecha)
	await _blast_at(blast)
	check((_pips(mecha) < before) == hurt, message)
	_arena.mechas.erase(mecha)
	mecha.queue_free()
	await get_tree().physics_frame


func _test_firer() -> void:
	var before := _pips(_shooter)
	await _blast_at(SHOOTER_POS + Vector2(NEAR, 0))
	check(_pips(_shooter) < before, "the firer is hurt by its own blast")
