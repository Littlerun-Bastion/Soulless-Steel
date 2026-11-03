extends TestSuite

# SmokeTest: smoke clouds (smoke_cloud.gd), the smoke launcher (MA-SL6) and
# smoke blocking sight. A cloud thickens, blocks sight into, out of and
# through it (MapSenses.in_smoke, smoke_between, sight_blocked) and clears
# when it ends; the player's view hides mechas in and behind smoke without
# the cloud casting a shadow; an NPC
# and an Entity can't see through it; tapping the launcher screens the mecha
# itself, holding it sends the canisters to the designator; a canister
# leaves a cloud where it lands.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const CLOUD := preload("res://game/weapons/SmokeCloud.tscn")
const SMOKE := preload("res://game/weapons/smoke_cloud.gd")
const LAUNCHER := "MA-SL6"
const SLOT := "shoulder_weapon_left"


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2(-5000, -5000)
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-3000, 3000), randf_range(-3000, 3000))


var _arena: FakeArena = null
var _shots: Array[Dictionary] = []


func run_tests() -> void:
	await case("launcher data", _test_data)
	await case("a cloud thickens, blocks sight into, out of and through it, then clears", _test_cloud)
	await case("the player's view hides mechas in and behind smoke", _test_view)
	await case("an NPC can't see through smoke", _test_npc)
	await case("an Entity can't see through smoke", _test_entity)
	await case("tap screens the mecha itself; hold sends canisters to the designator", _test_tap_hold)
	await case("a canister leaves a cloud where it lands", _test_canister)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_shots.clear()
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _design(with_launcher: bool) -> Dictionary:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	if with_launcher:
		design["shoulder_weapon_left"] = LAUNCHER
		for core_id in PartManager.get_parts("core"):
			if PartManager.get_part("core", core_id).has_left_shoulder:
				design["core"] = core_id
				break
	return design


func _mecha(pos: Vector2, scene: PackedScene = MECHA, with_launcher := false) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(_design(with_launcher))
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


# A cloud at `pos` lasting `lifetime` s, already thick unless `fresh`.
func _cloud(pos: Vector2, lifetime := 15.0, fresh := false) -> Node2D:
	var cloud: Node2D = CLOUD.instantiate()
	cloud.position = pos
	cloud.lifetime = lifetime
	cloud.grow_time = minf(cloud.grow_time, lifetime * 0.25)
	cloud.fade_time = minf(cloud.fade_time, lifetime * 0.25)
	_arena.add_child(cloud)
	if not fresh:
		var ref: WeakRef = weakref(cloud)
		await wait_until(func(): return ref.get_ref() == null or ref.get_ref().is_thick(), 3.0)
	return cloud


func _test_data() -> void:
	var weapon = PartManager.get_part("shoulder_weapon", LAUNCHER)
	if not check(weapon != null, "the smoke launcher exists"):
		return
	var info: Dictionary = weapon.get_aoe_info()
	check_eq(info.designator, "circle", "circle designator")
	check_eq(info.fire_type, "indirect", "indirect fire")
	check(weapon.tap_self, "tapping screens the mecha itself")
	check_eq(info.min_range, 0.0, "no minimum range")
	check(info.barrage_count > 1, "several canisters")
	var heat: float = weapon.muzzle_heat * weapon.barrage_count
	check(heat >= 650.0 and heat <= 1300.0, "one to two dashes of heat (%.0f kJ)" % heat)


func _test_cloud() -> void:
	var centre := Vector2(0, 3000)
	var cloud := await _cloud(centre, 15.0, true)
	check(not MapSenses.in_smoke(centre), "a fresh cloud isn't thick yet")
	await wait_until(func(): return cloud.is_thick(), 3.0)
	var r: float = cloud.current_radius()
	var w := _arena.get_world_2d()
	check(MapSenses.in_smoke(centre), "its centre is in smoke")
	check(not MapSenses.in_smoke(centre + Vector2(r + 50.0, 0)), "past its edge isn't")
	check(MapSenses.smoke_between(centre + Vector2(-1000, 0), centre + Vector2(1000, 0)), "a line through it is blocked")
	check(MapSenses.smoke_between(centre, centre + Vector2(1000, 0)), "so is a line out of it")
	check(not MapSenses.smoke_between(centre + Vector2(-1000, r + 50.0), centre + Vector2(1000, r + 50.0)), "a line past it isn't")
	check(MapSenses.sight_blocked(w, centre + Vector2(-1000, 0), centre + Vector2(1000, 0)), "sight_blocked counts smoke")
	check(not MapSenses.sight_blocked(w, centre + Vector2(-1000, r + 50.0), centre + Vector2(1000, r + 50.0)), "and is clear past it")
	var short := await _cloud(Vector2(3000, 3000), 1.5)
	check(MapSenses.in_smoke(Vector2(3000, 3000)), "a short cloud blocks while it lasts")
	var ref: WeakRef = weakref(short)
	await wait_until(func(): return ref.get_ref() == null, 3.0)
	check(not MapSenses.in_smoke(Vector2(3000, 3000)), "a cloud that ended blocks nothing")


# The player is held still facing the smoke (no physics), its view stepped
# by hand.
func _test_view() -> void:
	var player = _mecha(Vector2(-1000, 0), PLAYER)
	player.mecha_name = "Player"
	player.set_physics_process(false)
	player.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	var behind := _mecha(Vector2(800, 0))
	var inside := _mecha(Vector2(0, 0))
	var close := _mecha(Vector2(-1000, 350))
	var cloud := await _cloud(Vector2(0, 0), 4.0)
	check(cloud.find_children("*", "LightOccluder2D", true, false).is_empty(), "a thick cloud casts no shadow")
	for i in 12:
		player._update_view(0.1)
	check(player.is_hidden_from_view(behind) and behind.modulate.a < 0.05, "a mecha behind the smoke is hidden")
	check(player.is_hidden_from_view(inside) and inside.modulate.a < 0.05, "a mecha in the smoke is hidden")
	check(not player.is_hidden_from_view(close) and close.modulate.a > 0.95, "one close by with a clear line is seen")
	await wait_until(func(): return SMOKE.count() == 0, 6.0)
	for i in 12:
		player._update_view(0.1)
	check(not player.is_hidden_from_view(behind) and behind.modulate.a > 0.95, "seen again once the smoke clears")


func _test_npc() -> void:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = Vector2(-350, 0)
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Smoke test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(false)
	enemy.paused = true
	_arena.mechas.append(enemy)
	var foe := _mecha(Vector2(350, 0))
	enemy.mark_traitor(foe)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "it sees the mecha in the open")
	await _cloud(Vector2(0, 0))
	enemy.update_senses(0.1)
	check(not enemy.is_seeing(foe), "not through smoke")
	check(MapSenses.sight_blocked(_arena.get_world_2d(), enemy.global_position, foe.global_position),
			"the shared sight check counts the smoke")


func _test_entity() -> void:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(-600, 0)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	var prey := _mecha(Vector2(600, 0))
	await get_tree().physics_frame
	check(stalker.can_see(prey), "it sees the mecha in the open")
	await _cloud(Vector2(0, 0))
	check(not stalker.can_see(prey), "not through smoke")


func _test_tap_hold() -> void:
	var player = _mecha(Vector2(-3000, 3000), PLAYER, true)
	player.mecha_name = "Player"
	player.global_rotation = 0.0
	var weapon = player.build[SLOT]
	player.create_projectile.connect(func(_m, args, _w): _shots.append(args))
	player._input(_action("shoulder_weapon_left_shoot", true))
	player._input(_action("shoulder_weapon_left_shoot", false))
	await wait_until(func(): return _shots.size() >= weapon.barrage_count, 3.0)
	check_eq(_shots.size(), weapon.barrage_count, "a tap fires the whole salvo")
	for args in _shots:
		var target: Vector2 = args.target_pos
		check(target.distance_to(player.global_position) <= weapon.scatter_radius + 0.01, "a canister lands round the mecha")
	_shots.clear()
	var node = player.get_weapon_part(SLOT)
	await wait_until(func(): return not node.is_reloading(), weapon.reload_speed + 2.0)
	player._input(_action("shoulder_weapon_left_shoot", true))
	await wait_seconds(player.TAP_TIME * 2.0)
	var aim: Vector2 = player.get_designator_aim(SLOT)
	player._input(_action("shoulder_weapon_left_shoot", false))
	await wait_until(func(): return _shots.size() >= weapon.barrage_count, 3.0)
	check_eq(_shots.size(), weapon.barrage_count, "a hold fires the whole salvo")
	for args in _shots:
		var target: Vector2 = args.target_pos
		check(target.distance_to(aim) <= weapon.scatter_radius + 5.0, "a canister lands round the designator")


func _test_canister() -> void:
	var launcher := _mecha(Vector2(-3000, 3000), MECHA, true)
	launcher.create_projectile.connect(func(m, args, w):
		var data = ProjectileManager.create(m, args, w)
		_arena.add_child(data.node))
	var point := launcher.global_position + Vector2(0, -1000)
	check_eq(launcher.fire_at_point(SLOT, point), "", "the launcher fires")
	var smoked := await wait_until(func(): return SMOKE.count() >= 3, 5.0)
	check(smoked, "every canister left a cloud")
	await wait_seconds(2.0)
	check(MapSenses.in_smoke(point) or MapSenses.smoke_between(point + Vector2(-400, 0), point + Vector2(400, 0)),
			"smoke covers the target point")


func _action(action: String, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event
