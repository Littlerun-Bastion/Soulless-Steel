extends TestSuite

# NPCPerceptionTest: what NPC mechas know about their targets (Enemy.gd,
# senses and target choice) and how their combat behaviour uses it
# (BaseBehaviour.gd). An NPC only picks a target it can see, or one shooting
# at it; out of sight it works from where the target was last seen and
# forgets it after a while; a roaming NPC that spots a target goes to engage
# it; it fires blind through walls only when its rounds can get through them;
# it enters combat at its build's range; and a build's preferred range comes
# from its direct-fire weapons. Its head's IR sensor: a hot mecha behind a
# wall is tracked by its heat (where it is, live, not seen) but not picked as
# a target; a target it was fighting stays tracked exactly behind cover, and
# turns into a frozen memory once it cools; one hot enough to identify is
# seen through the wall; with its head gone it senses nothing.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
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


func run_tests() -> void:
	await case("an NPC only picks a target it can see", _test_sight)
	await case("out of sight, an NPC works from the last-known position and forgets in time", _test_memory)
	await case("being shot gives the shooter away", _test_shot_reveals)
	await case("a roaming NPC that spots a target goes to engage it", _test_roam_engages)
	await case("blind fire goes only through walls the round can get through", _test_blind_fire)
	await case("an NPC enters combat at its build's range", _test_combat_entry)
	await case("a build's range comes from its direct-fire weapons", _test_build_range)
	await case("IR: a hot mecha behind a wall is tracked, not seen, not picked", _test_ir_unknown)
	await case("IR: a target behind cover stays tracked exactly while hot", _test_ir_keeps_target)
	await case("IR: hot enough to identify is seen; no head, no IR", _test_ir_identify)
	await case("a mecha with its light on within a screen is known, past sight and walls", _test_light_known)
	await case("a Fisher with its harpoon in the NPC is seen, wherever it is", _test_tethered_seen)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)


# A flat map with an open navmesh and the given building footprints.
func _setup(buildings: Array = []) -> void:
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	if not buildings.is_empty():
		var footprints := BuildingFootprints.new()
		var starts := PackedInt32Array([0])
		for b in buildings:
			footprints.points.append_array(PackedVector2Array(b))
			starts.append(footprints.points.size())
		footprints.starts = starts
		var field := BuildingField.new()
		field.footprints = footprints
		_arena.add_child(field)
	await get_tree().physics_frame
	await get_tree().physics_frame


# An NPC that thinks for itself, held still (paused) unless `run`.
func _enemy(pos: Vector2, design: Dictionary = PlayerProgress.DEFAULT_MECHA, run := false) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, design, "Perception test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(false)
	enemy.paused = not run
	_arena.mechas.append(enemy)
	return enemy


# A plain mecha standing at `pos`, that the NPC is set on attacking. Dark (its
# illuminator off), so only plain sight finds it.
func _foe(pos: Vector2, enemy) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(false)
	_arena.mechas.append(mecha)
	enemy.mark_traitor(mecha)
	return mecha


# Turns the NPC to face `pos`: it sees a dark mecha only in its cone, so a
# sight check that is about walls or memory has it looking that way.
func _face(enemy, pos: Vector2) -> void:
	enemy.global_rotation = Vector2.UP.angle_to(pos - enemy.global_position)


func _house(x0: float, x1: float, y0: float, y1: float) -> Array:
	return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]


func _test_sight() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var foe := _foe(Vector2(800, 0), enemy)
	_face(enemy, foe.global_position)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	enemy.check_for_targets(1800.0, 2000.0)
	check(not enemy.is_seeing(foe), "it doesn't see a mecha behind a building")
	check(not enemy.valid_target, "so it doesn't pick it as a target")
	foe.global_position = Vector2(0, 800)
	_face(enemy, foe.global_position)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	enemy.check_for_targets(1800.0, 2000.0)
	check(enemy.is_seeing(foe), "it sees the mecha in the open")
	check(enemy.valid_target == foe, "and picks it as a target")


func _test_memory() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var foe := _foe(Vector2(800, -800), enemy)
	_face(enemy, foe.global_position)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	enemy.check_for_targets(1800.0, 2000.0)
	check(enemy.valid_target == foe, "it picks the mecha it sees")
	foe.global_position = Vector2(800, 0)
	_face(enemy, foe.global_position)
	await get_tree().physics_frame
	enemy.update_senses(0.5)
	check(not enemy.is_seeing(foe), "the mecha went behind the building")
	check(enemy.get_target_position(foe).distance_to(Vector2(800, -800)) < 1.0,
		"it believes the mecha is where it last saw it")
	enemy.check_for_targets(1800.0, 2000.0)
	check(enemy.valid_target == foe, "it keeps the target out of sight for a while")
	enemy.update_senses(_memory_time() + 1.0)
	enemy.check_for_targets(1800.0, 2000.0)
	check(not enemy.valid_target, "it gives up on a target it hasn't seen or heard for long")


func _memory_time() -> float:
	return preload("res://game/mecha/Enemy.gd").TARGET_MEMORY_TIME


func _test_shot_reveals() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var foe := _foe(Vector2(800, 0), enemy)
	enemy.update_senses(0.1)
	check(not enemy.is_seeing(foe), "it can't see the shooter behind the building")
	enemy.on_attacked_by(foe)
	enemy.check_for_targets(1800.0, 2000.0)
	check(enemy.valid_target == foe, "it takes the shooter as its target")
	check(enemy.get_target_position(foe).distance_to(foe.global_position) < 1.0,
		"and knows where the shot came from")


func _test_roam_engages() -> void:
	await _setup()
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA, true)
	var foe := _foe(Vector2(0, -900), enemy)
	foe.set_pause(true)
	check(enemy.logic.get_current_state() == "roam", "it starts out roaming")
	var left_roam := await wait_until(func(): return enemy.logic.get_current_state() != "roam", 6.0)
	check(left_roam, "it stops roaming once it spots the mecha (now %s)" % enemy.logic.get_current_state())
	check(enemy.valid_target == foe, "and has it as its target")


func _test_blind_fire() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var foe := _foe(Vector2(800, -800), enemy)
	_face(enemy, foe.global_position)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "it sees the mecha first")
	check(enemy._weapon_ap["arm_weapon_left"] == 2, "the MA-L127's round has 2 AP")
	# The mecha ducks into the building: one wall between them.
	foe.global_position = Vector2(500, 0)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	enemy.knowledge.place(foe, foe.global_position)
	enemy.global_rotation = PI / 2.0
	check(enemy.blind_fire(foe), "it fires blind through one wall with 2 AP rounds")
	# Behind the building: two walls, too many for 2 AP.
	enemy.knowledge.place(foe, Vector2(800, 0))
	check(not enemy.blind_fire(foe), "it doesn't fire through two walls")
	enemy.knowledge.place(foe, Vector2(500, 0))
	enemy.global_rotation = 0.0
	check(not enemy.blind_fire(foe), "it doesn't fire before it faces the spot")
	enemy.global_rotation = PI / 2.0
	enemy.update_senses(10.0)
	check(not enemy.blind_fire(foe), "it stops firing blind once the information is old")


func _test_combat_entry() -> void:
	await _setup()
	var enemy := _enemy(Vector2.ZERO)
	var foe := _foe(Vector2(1650, 0), enemy)
	# Spotted (a cold mecha this far away would only be seen once it heats up).
	enemy.knowledge.see(foe, foe.global_position)
	enemy.check_for_targets(1800.0, 2000.0)
	check(is_same(enemy.valid_target, foe), "it has the mecha as its target")
	var behaviour = enemy.logic.behaviour
	check(behaviour.score_engage(enemy) >= behaviour.SCORE_ENGAGE_IN_RANGE,
		"it enters combat at its kite range (1650 px), not only at close quarters")
	foe.global_position = Vector2(2600, 0)
	enemy.knowledge.see(foe, foe.global_position)
	check(is_equal_approx(behaviour.score_engage(enemy), behaviour.SCORE_ENGAGE_CLOSING),
		"from far beyond it, it only closes in")


func _test_build_range() -> void:
	await _setup()
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design.arm_weapon_left = "Kruis_CL157.0"
	design.arm_weapon_right = "Kruis_CL157.0"
	design.shoulder_weapon_left = "TORI-ML"
	var enemy := _enemy(Vector2.ZERO, design)
	check(is_equal_approx(enemy.preferred_combat_range, 2800.0),
		"two cannons and a missile launcher prefer the cannons' range (%.0f)" % enemy.preferred_combat_range)
	check(enemy.combat_style == "balanced", "a 2800 px build fights as balanced")
	var eff: Dictionary = enemy.logic.behaviour._get_effective_distances(enemy)
	check(eff.max_kite > 1700.0 and eff.max_kite < 2500.0,
		"its kite range scales with its weapons (%.0f px)" % eff.max_kite)
	var plain := _enemy(Vector2(0, 500))
	var base: Dictionary = plain.logic.behaviour._get_effective_distances(plain)
	check(base.min_kite == 1500 and base.max_kite == 1700, "the default build keeps the tuned 1500-1700 px band")


# ---- Lights and tethers ----

func _test_light_known() -> void:
	await _setup([_house(400, 600, -1200, 1200)])
	var enemy := _enemy(Vector2.ZERO)
	var half := Illumination.SCREEN_HALF
	var foe := _foe(Vector2(half.x * 0.9, half.y * 0.6), enemy)
	foe.set_illuminator(true)
	check(MapSenses.walls_between(enemy.get_world_2d(), enemy.global_position, foe.global_position),
			"behind the building")
	await _sense(enemy)
	var contact: Dictionary = enemy.knowledge.best(foe)
	check(not contact.is_empty() and contact.live and contact.kind == "mech", "its light gives it away, as a mecha (%s)" % str(contact.get("source")))
	check(enemy.get_target_position(foe) == foe.global_position, "exactly where it is")
	enemy.check_for_targets(5000.0, 6000.0)
	check(is_same(enemy.valid_target, foe), "and it can be taken on")
	foe.set_illuminator(false)
	await _sense(enemy)
	check(not enemy.knowledge.best(foe).live, "light off: only a memory")
	var far := _foe(Vector2(enemy.sight_radius() * 1.1, 0), enemy)
	far.set_illuminator(true)
	await _sense(enemy)
	check(not enemy.knowledge.knows(far), "a light past its sight circle isn't noticed")


func _test_tethered_seen() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var fisher: Fisher = load("res://game/entities/fisher/Fisher.tscn").instantiate()
	fisher.position = Vector2(900, 0)
	_arena.add_child(fisher)
	fisher.setup(_arena)
	fisher.set_pause(true)
	var reach_sq: float = pow(enemy.sight_radius(), 2.0)
	enemy._look_at(fisher, reach_sq, 1.0)
	enemy.knowledge.end_sight_update()
	check(not enemy.is_seeing(fisher), "a Fisher behind the building isn't seen")
	fisher.harpoon = Fisher.Harpoon.LATCHED
	fisher._latched_to = enemy
	fisher.global_position = Vector2(9000, 0)
	await get_tree().physics_frame
	enemy.contacts.advance(0.1)
	enemy._look_at(fisher, reach_sq, 1.0)
	enemy.knowledge.end_sight_update()
	check(enemy.is_seeing(fisher), "with its harpoon in the NPC, it's seen, however far and whatever's between")
	fisher.queue_free()


# ---- IR ----

# Holds a foe at `celsius` (absolute): its physics off, so it doesn't cool.
func _heat(foe: Mecha, celsius: float) -> void:
	foe.set_physics_process(false)
	foe.external_temp = celsius - Mecha.AMBIENT_TEMP


func _sense(enemy) -> void:
	await get_tree().physics_frame
	enemy.update_senses(0.1)


func _test_ir_unknown() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var head = enemy.build.head
	var foe := _foe(Vector2(800, 0), enemy)
	_heat(foe, head.ir_sensitivity - 10.0)
	await _sense(enemy)
	check(not enemy.knowledge.knows(foe), "cooler than its sensitivity behind a wall: unknown")
	_heat(foe, head.ir_sensitivity + 10.0)
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "hot enough to sense: still not seen")
	var contact: Dictionary = enemy.knowledge.best(foe)
	check(contact.get("source") == IRSensing.SOURCE and contact.get("kind") == IRSensing.KIND and contact.get("live") == true,
			"but tracked by its heat, as an unknown")
	check(enemy.get_target_position(foe) == foe.global_position, "exactly where it is")
	enemy.check_for_targets(1800.0, 2000.0)
	check(not enemy.valid_target, "an unknown heat track isn't picked as a target")
	foe.global_position = Vector2(820, 120)
	await _sense(enemy)
	check(enemy.get_target_position(foe) == foe.global_position, "and the track follows it live")


func _test_ir_keeps_target() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var head = enemy.build.head
	var foe := _foe(Vector2(0, 800), enemy)
	_heat(foe, head.ir_sensitivity + 10.0)
	_face(enemy, foe.global_position)
	await _sense(enemy)
	enemy.check_for_targets(1800.0, 2000.0)
	if not check(enemy.valid_target == foe, "it picks the mecha it sees in the open"):
		return
	foe.global_position = Vector2(800, 0)
	_face(enemy, foe.global_position)
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "behind the building, it's out of sight")
	check(enemy.get_target_position(foe) == foe.global_position and enemy.time_unseen(foe) < 0.2,
			"but its heat keeps it tracked exactly")
	enemy.check_for_targets(1800.0, 2000.0)
	check(enemy.valid_target == foe, "so it keeps the target")
	_heat(foe, Mecha.AMBIENT_TEMP)
	await _sense(enemy)
	var frozen: Vector2 = enemy.get_target_position(foe)
	foe.global_position = Vector2(820, 200)
	await _sense(enemy)
	check(enemy.get_target_position(foe) == frozen and not enemy.knowledge.best(foe).live,
			"cooled off, it works from where it last had it")


func _test_ir_identify() -> void:
	await _setup([_house(400, 600, -300, 300)])
	var enemy := _enemy(Vector2.ZERO)
	var head = enemy.build.head
	var foe := _foe(Vector2(800, 0), enemy)
	_heat(foe, head.ir_identification + 10.0)
	await _sense(enemy)
	check(enemy.is_seeing(foe), "hot enough to identify: seen through the wall")
	enemy.check_for_targets(1800.0, 2000.0)
	check(enemy.valid_target == foe, "and picked as a target")
	var blind := _enemy(Vector2(0, -600))
	var blind_foe := _foe(Vector2(800, -100), blind)
	_heat(blind_foe, head.ir_identification + 10.0)
	blind.lose_part("head")
	await _sense(blind)
	check(not blind.knowledge.knows(blind_foe), "with its head gone, an NPC senses no heat")
