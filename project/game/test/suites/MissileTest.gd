extends TestSuite

# MissileTest: the cluster missile launcher (TORI-ML) and the VLS launcher
# (TORI-V4). Their data; with a target locked, firing at it whatever the
# designator, the gimbal or the minimum range, up to max range; an unlocked
# cluster missile's submunitions dropping onto points inside its circle,
# also when a wall stops the missile on the way; a locked cluster missile
# that meets a wall breaking up there with nothing released; a locked VLS missile flying
# over a building onto a target that moved; and unlocked VLS missiles
# landing in their circle. Real projectiles at game speed.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const CLUSTER := "TORI-ML"
const VLS := "TORI-V4"
const SLOT := "shoulder_weapon_left"
const SUBMUNITION := "res://database/parts/projectiles/TORI-ML_subprojectile.tscn"

# A building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null
# Every round fired, by mechas and by rounds: {"scene", "target", "indirect",
# "seeker"}.
var _shots: Array[Dictionary] = []
var _impacts: Array[Vector2] = []


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("cluster missile and VLS data", _test_data)
	await case("locked on: fires at the target, any facing, up to max range", _test_locked_rules)
	await case("unlocked: cluster submunitions land inside the circle", _test_cluster_open)
	await case("unlocked: a wall stops the missile, submunitions still reach the circle", _test_cluster_wall)
	await case("locked: a wall stops the missile, which breaks up and releases nothing", _test_locked_wall)
	await case("locked VLS missiles fly over a building onto a moving target", _test_vls_locked)
	await case("unlocked VLS missiles land in the circle", _test_vls_unlocked)


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


func _lock(mecha: Mecha, target: Mecha) -> void:
	mecha.locked_to = target
	mecha.lock_timer = 0.0


func _on_create_projectile(mecha, args: Dictionary, weapon, real: bool) -> void:
	var scene: PackedScene = args.projectile
	_shots.append({"scene": scene.resource_path, "target": args.get("target_pos"),
			"indirect": args.get("indirect", false), "seeker": args.get("seeker_target")})
	if not real:
		return
	var data = ProjectileManager.create(mecha, args, weapon)
	data.node.bullet_impact.connect(_on_impact)
	if data.node.has_signal("create_projectile"):
		data.node.create_projectile.connect(_on_create_projectile.bind(true))
	_arena.add_child(data.node)


func _on_impact(projectile, _effect, clear: bool, _body) -> void:
	if clear:
		_impacts.append(projectile.global_position)


func _subs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for shot in _shots:
		if shot.scene == SUBMUNITION:
			out.append(shot)
	return out


func _pips(mecha: Mecha) -> int:
	var total := 0
	for part in mecha.armor:
		for facing in mecha.armor[part]:
			total += int(mecha.armor[part][facing].pips)
	return total


func _test_data() -> void:
	var cluster = PartManager.get_part("shoulder_weapon", CLUSTER)
	var vls = PartManager.get_part("shoulder_weapon", VLS)
	if not check(cluster != null and vls != null, "both exist"):
		return
	var c: Dictionary = cluster.get_aoe_info()
	check_eq(c.designator, "circle", "cluster: circle designator")
	check_eq(c.fire_type, "direct", "cluster: direct fire")
	check(c.requires_lock, "cluster: a lock-on weapon")
	check(c.submunitions > 0, "cluster: submunitions")
	check(not cluster.auto_fire, "cluster: no auto fire")
	var v: Dictionary = vls.get_aoe_info()
	check_eq(v.designator, "circle", "VLS: circle designator")
	check_eq(v.fire_type, "indirect", "VLS: indirect fire")
	check(v.requires_lock, "VLS: a lock-on weapon")
	check(v.blast_radius > 0.0, "VLS: missiles explode")
	for weapon in [cluster, vls]:
		var heat: float = weapon.muzzle_heat * weapon.barrage_count
		check(heat >= 650.0 and heat <= 1300.0, "%s: one to two dashes of heat (%.0f kJ)" % [weapon.part_name, heat])


func _test_locked_rules() -> void:
	var mecha := _mecha(CLUSTER, Vector2(-5000, 5000), Vector2.UP)
	var weapon = mecha.build[SLOT]
	var behind := _mecha(CLUSTER, mecha.global_position + Vector2(0, 1500), Vector2.UP)
	var aside := mecha.global_position + Vector2(1500, 0)
	check_eq(mecha.can_fire_at_point(SLOT, aside), "not_facing", "unlocked: the gimbal holds")
	_lock(mecha, behind)
	check_eq(mecha.can_fire_at_point(SLOT, aside), "", "locked: fires whatever the designator says")
	check_eq(mecha.fire_at_point(SLOT, aside), "", "fires at the lock behind it")
	if check_eq(_shots.size(), 1, "one missile"):
		check(_shots[0].seeker == behind, "seeking the locked target")
		check(_shots[0].target == null, "a direct missile has no landing point when locked")
	var near := _mecha(CLUSTER, mecha.global_position + Vector2(200, 0), Vector2.UP)
	_lock(mecha, near)
	var node = mecha.get_weapon_part(SLOT)
	node.timer = 0.0
	node.reloading = false
	node.clip_ammo = 1
	check_eq(mecha.can_fire_at_point(SLOT, aside), "", "locked: no minimum range")
	var far := _mecha(CLUSTER, mecha.global_position + Vector2(0, -(weapon.max_range + 500.0)), Vector2.UP)
	_lock(mecha, far)
	check_eq(mecha.can_fire_at_point(SLOT, aside), "too_far", "locked: out of max range")


func _test_cluster_open() -> void:
	var mecha := _mecha(CLUSTER, Vector2(-3000, 3000), Vector2.UP, true)
	var weapon = mecha.build[SLOT]
	var point := mecha.global_position + Vector2.UP * 1500.0
	check_eq(mecha.fire_at_point(SLOT, point), "", "the cluster missile fires unlocked")
	await _check_cluster(weapon, point)


func _test_cluster_wall() -> void:
	var mecha := _mecha(CLUSTER, Vector2(-700, 200), Vector2.RIGHT, true)
	var weapon = mecha.build[SLOT]
	var point := Vector2(900, 200)
	check_eq(mecha.fire_at_point(SLOT, point), "", "the cluster missile fires at a point past a building")
	await _check_cluster(weapon, point)


func _test_locked_wall() -> void:
	var mecha := _mecha(CLUSTER, Vector2(-400, 200), Vector2.RIGHT, true)
	var target := _mecha(CLUSTER, Vector2(1100, 200), Vector2.UP)
	await get_tree().physics_frame
	_lock(mecha, target)
	check_eq(mecha.fire_at_point(SLOT, target.global_position), "", "the cluster missile fires at the lock past the building")
	var ended := await wait_until(func(): return not _impacts.is_empty(), 3.0)
	check(ended, "the missile ends")
	if ended:
		check(absf(_impacts[0].x) < 40.0, "at the building's wall (x %.0f)" % _impacts[0].x)
	await wait_seconds(2.5)
	check(_subs().is_empty(), "with no submunitions (%d)" % _subs().size())
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 0, "and nothing left in the air or stuck on the wall")


func _check_cluster(weapon, point: Vector2) -> void:
	var count: int = weapon.get_aoe_info().submunitions
	await wait_until(func(): return _subs().size() >= count, 6.0)
	var subs := _subs()
	check_eq(subs.size(), count, "every submunition released")
	for sub in subs:
		var target: Vector2 = sub.target if sub.target != null else Vector2.INF
		check(sub.indirect and target.distance_to(point) <= weapon.scatter_radius + 0.01,
				"a submunition drops onto a point inside the circle")
	var landed := await wait_until(func():
		for sub in subs:
			if not _impacts.any(func(p): return p.distance_to(sub.target) < 1.0):
				return false
		return true, 6.0)
	check(landed, "and goes off there")


func _test_vls_locked() -> void:
	var mecha := _mecha(VLS, Vector2(-1800, 200), Vector2.RIGHT, true)
	var target := _mecha(VLS, Vector2(1100, 200), Vector2.UP)
	await get_tree().physics_frame
	var before := _pips(target)
	_lock(mecha, target)
	check_eq(mecha.fire_at_point(SLOT, Vector2.ZERO), "", "the VLS fires at the lock past the building")
	if not _shots.is_empty():
		check(_shots[0].indirect and _shots[0].seeker == target, "an indirect missile seeking the target")
	await wait_frames(10)
	target.global_position = Vector2(1100, 800)
	var hit := await wait_until(func(): return _impacts.any(func(p): return p.distance_to(target.global_position) < 40.0), 6.0)
	check(hit, "a missile came down on the target where it moved to")
	await wait_frames(2)
	check(_pips(target) < before, "and hurt it")


func _test_vls_unlocked() -> void:
	var mecha := _mecha(VLS, Vector2(-5000, 5000), Vector2.UP)
	var weapon = mecha.build[SLOT]
	var point := mecha.global_position + Vector2.UP * 2000.0
	check_eq(mecha.fire_at_point(SLOT, point), "", "the VLS fires unlocked")
	await wait_until(func(): return _shots.size() >= weapon.barrage_count, 3.0)
	check_eq(_shots.size(), weapon.barrage_count, "the whole salvo")
	for shot in _shots:
		var target: Vector2 = shot.target
		check(shot.indirect and target.distance_to(point) <= weapon.scatter_radius + 0.01, "each missile lands in the circle")
