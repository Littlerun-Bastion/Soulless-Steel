extends TestSuite

# AoEDesignatorTest: shoulder weapons with a designator (weapon.gd,
# Mecha.fire_at_point, Player). The MA-GL44's designator data; the
# designator clamped to the weapon's range and, with look limits, to its
# gimbal round the mecha's facing; every reason a slot can't fire at a point;
# a salvo's rounds, ammo, heat, cooldown and reload; the plain shoot() call
# NPCs use going through the same rules; a direct-fire designator stopping
# at a wall; the player's hold / release / reload-to-cancel input; and an
# indirect weapon greyed out indoors.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const SLOT := "shoulder_weapon_left"

# A building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null


func run_tests() -> void:
	await case("the MA-GL44 is an indirect circle designator weapon", _test_data)
	await case("the designator is clamped to range and look angle", _test_clamp)
	await case("every reason a slot can't fire at a point", _test_reasons)
	await case("a salvo: rounds in the circle, ammo, heat, cooldown, reload", _test_salvo)
	await case("plain shoot() fires a designator salvo by the same rules", _test_plain_shoot)
	await case("a direct-fire designator stops at the first wall", _test_clip)
	await case("hold shows the designator, release fires, reload cancels", _test_player_input)
	await case("an indirect weapon is greyed out indoors", _test_indoors_hud)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	Profile.set_option("designator_look_limits", true)
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


func _design() -> Dictionary:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "MA-GL44"
	for core_id in PartManager.get_parts("core"):
		if PartManager.get_part("core", core_id).has_left_shoulder:
			design["core"] = core_id
			break
	return design


# A mecha with the GL44 on its left shoulder, facing up (-y).
func _mecha(pos: Vector2, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(_design())
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


func _test_data() -> void:
	var weapon = PartManager.get_part("shoulder_weapon", "MA-GL44")
	var info: Dictionary = weapon.get_aoe_info()
	check_eq(info.fire_type, "indirect", "indirect fire")
	check_eq(info.designator, "circle", "circle designator")
	check(info.min_range > 0.0 and info.max_range > info.min_range, "a minimum and a maximum range")
	check(info.scatter_radius > 0.0, "scatter")
	check(info.barrage_count > 1, "a barrage")
	check(info.blast_radius > 0.0, "the blast radius read from the projectile")
	check(not weapon.auto_fire, "no auto fire")


func _test_clamp() -> void:
	var mecha := _mecha(Vector2(-3000, 3000))
	var weapon = mecha.build[SLOT]
	var o := mecha.global_position
	var far := mecha.designator_point(SLOT, o + Vector2(0, -9000))
	check(absf(far.distance_to(o) - weapon.max_range) < 1.0, "beyond max range: pulled in to it")
	var near := mecha.designator_point(SLOT, o + Vector2(0, -50))
	check(absf(near.distance_to(o) - weapon.min_range) < 1.0, "inside min range: pushed out to it")
	var side := o + Vector2(1500, 0)
	var limited := mecha.designator_point(SLOT, side, true)
	var angle := rad_to_deg(absf(Vector2.UP.angle_to(limited - o)))
	check(absf(angle - weapon.gimbal) < 0.1, "with look limits, held at the gimbal (%.1f deg)" % angle)
	var free := mecha.designator_point(SLOT, side, false)
	check(free.distance_to(side) < 1.0, "without, it goes where the cursor is")
	check_eq(mecha.can_fire_at_point(SLOT, limited), "", "the limited point can be fired at")
	check_eq(mecha.can_fire_at_point(SLOT, free), "not_facing", "the free one waits for the mecha to turn")
	mecha.global_rotation = PI / 2.0
	var turned := mecha.designator_point(SLOT, side, true)
	check(turned.distance_to(side) < 1.0, "the designator turns with the mecha")


func _test_reasons() -> void:
	var mecha := _mecha(Vector2(-3000, 3000))
	var node = mecha.get_weapon_part(SLOT)
	var ahead := mecha.global_position + Vector2(0, -1000)
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "", "free to fire straight ahead in range")
	check_eq(mecha.can_fire_at_point(SLOT, mecha.global_position + Vector2(0, -100)), "too_close", "too close")
	check_eq(mecha.can_fire_at_point(SLOT, mecha.global_position + Vector2(0, -5000)), "too_far", "too far")
	check_eq(mecha.can_fire_at_point(SLOT, mecha.global_position + Vector2(1000, 0)), "not_facing", "off to the side")
	check_eq(mecha.can_fire_at_point("shoulder_weapon_right", ahead), "no_weapon", "an empty slot")

	mecha.is_inside_building = true
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "indoors", "indirect fire from inside a building")
	mecha.is_inside_building = false

	node.timer = 1.0
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "reloading", "cooling down")
	node.timer = 0.0

	var clip = node.clip_ammo
	var total = node.total_ammo
	node.clip_ammo = 0
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "reloading", "empty clip, ammo left: reloading")
	node.total_ammo = 0
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "no_ammo", "no ammo at all")
	node.clip_ammo = clip
	node.total_ammo = total

	mecha.internal_temp = mecha.overheat_temp
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "too_hot", "overheated")
	mecha.internal_temp = 0.0

	mecha.disabled_systems.left_shoulder_weapon = true
	check_eq(mecha.can_fire_at_point(SLOT, ahead), "disabled", "its feed destroyed")
	check(mecha.fire_at_point(SLOT, ahead) == "disabled", "fire_at_point gives the same reason")
	mecha.disabled_systems.left_shoulder_weapon = false


func _test_salvo() -> void:
	var mecha := _mecha(Vector2(-3000, 3000))
	var weapon = mecha.build[SLOT]
	var node = mecha.get_weapon_part(SLOT)
	var shots := []
	mecha.create_projectile.connect(func(_m, args, _w): shots.append(args))
	var point := mecha.global_position + Vector2(0, -1200)
	var clip_before: int = node.clip_ammo
	var total_before: int = node.total_ammo
	var heat_before: float = mecha.pending_heat_kj
	check_eq(mecha.fire_at_point(SLOT, point), "", "it fires")
	check_eq(shots.size(), 1, "the first round goes out at once")
	check(absf(mecha.pending_heat_kj - heat_before - weapon.muzzle_heat * weapon.barrage_count) < 0.01,
			"the salvo's heat is added at once")
	check_eq(node.clip_ammo, clip_before - 1, "one clip round per salvo")
	check_eq(mecha.can_fire_at_point(SLOT, point), "busy", "busy while the salvo goes out")
	await wait_until(func(): return shots.size() >= weapon.barrage_count, 3.0)
	check_eq(shots.size(), weapon.barrage_count, "a round per barrage_count")
	for args in shots:
		check(args.get("indirect") == true, "indirect round")
		var target: Vector2 = args.get("target_pos")
		check(target.distance_to(point) <= weapon.scatter_radius + 0.01, "lands within the scatter circle")
	await wait_frames(2)
	check(node.is_reloading(), "the empty clip reloads: the cooldown")
	check_eq(mecha.can_fire_at_point(SLOT, point), "reloading", "can't fire while reloading")
	var reloaded := await wait_until(func(): return not node.is_reloading(), weapon.reload_speed + 2.0)
	check(reloaded, "the reload finishes")
	check_eq(node.clip_ammo, clip_before, "clip refilled")
	check_eq(node.total_ammo, total_before - 1, "from the reserve")


func _test_plain_shoot() -> void:
	var mecha := _mecha(Vector2(-3000, 3000))
	var weapon = mecha.build[SLOT]
	var shots := []
	mecha.create_projectile.connect(func(_m, args, _w): shots.append(args))
	mecha.shoot(SLOT)
	if not check_eq(shots.size(), 1, "shoot() fired a salvo"):
		return
	var target: Vector2 = shots[0].target_pos
	var expected := mecha.global_position + Vector2(0, -weapon.ai_engage_range)
	check(target.distance_to(expected) <= weapon.scatter_radius + 0.01, "aimed straight ahead at its AI engage range")
	await wait_until(func(): return not mecha.is_salvo_firing(SLOT), 3.0)
	mecha.is_inside_building = true
	check_eq(mecha.can_fire_at_point(SLOT, expected), "indoors", "indoors now")
	var count := shots.size()
	mecha.get_weapon_part(SLOT).timer = 0.0
	mecha.shoot(SLOT)
	check_eq(shots.size(), count, "shoot() can't fire indirect from indoors either")


func _test_clip() -> void:
	var mecha := _mecha(Vector2(-600, 200))
	mecha.global_rotation = PI / 2.0
	var other := _mecha(Vector2(-300, 200))
	other.global_rotation = 0.0
	var end := mecha.designator_clip(SLOT, Vector2(800, 200))
	check(end.x < 0.0 and end.x > -20.0, "stops short of the wall at x 0 (got %.0f), not at the mecha on the way" % end.x)
	var open := mecha.designator_clip(SLOT, Vector2(-600, -800))
	check(open.distance_to(Vector2(-600, -800)) < 1.0, "a clear line reaches the point")


func _test_player_input() -> void:
	var player = _mecha(Vector2(-3000, 3000), PLAYER)
	player.mecha_name = "Player"
	player.global_rotation = 0.0
	var shots := []
	player.create_projectile.connect(func(_m, args, _w): shots.append(args))
	player._input(_action("shoulder_weapon_left_shoot", true))
	check(player.is_designating(SLOT), "holding: designating")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check_eq(shots.size(), 0, "nothing fires while held")
	check_eq(player.designator.marks.size(), 1, "the designator is drawn")
	player._input(_action("reload_mode", true))
	check(not player.is_designating(SLOT), "reload cancels it")
	check_eq(player.cur_mode, Mecha.MODES.NEUTRAL, "and doesn't enter reload mode")
	player._input(_action("shoulder_weapon_left_shoot", false))
	check_eq(shots.size(), 0, "releasing after a cancel fires nothing")
	await get_tree().physics_frame
	check_eq(player.designator.marks.size(), 0, "the designator is gone")

	player._input(_action("shoulder_weapon_left_shoot", true))
	player._input(_action("shoulder_weapon_left_shoot", false))
	check(not shots.is_empty(), "releasing fires")
	if not shots.is_empty():
		var target: Vector2 = shots[0].target_pos
		var weapon = player.build[SLOT]
		var dist := target.distance_to(player.global_position)
		check(dist >= weapon.min_range - weapon.scatter_radius - 1.0 and dist <= weapon.max_range + weapon.scatter_radius + 1.0,
				"at a point within range (%.0f px)" % dist)


func _test_indoors_hud() -> void:
	var player = _mecha(Vector2(-3000, 3000), PLAYER)
	player.mecha_name = "Player"
	var hud := HudWeapons.new()
	add_child(hud)
	hud.setup(player)
	await wait_frames(1)
	check(not hud.get_row_text(SLOT).contains("INDOORS"), "outside: not greyed out")
	player.is_inside_building = true
	await wait_frames(1)
	check(hud.get_row_text(SLOT).contains("INDOORS"), "inside a building: INDOORS")
	var shots := []
	player.create_projectile.connect(func(_m, args, _w): shots.append(args))
	player._input(_action("shoulder_weapon_left_shoot", true))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var marks: Array = player.designator.marks
	check(marks.size() == 1 and marks[0].dashed, "the designator is dashed")
	player._input(_action("shoulder_weapon_left_shoot", false))
	check(shots.is_empty(), "releasing fires nothing")
	hud.queue_free()


func _action(action: String, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event
