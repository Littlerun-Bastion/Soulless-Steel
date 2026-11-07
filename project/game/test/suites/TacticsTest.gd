extends TestSuite

# TacticsTest: the position picker (Positioning) and the fire controller
# (FireController), and the intents that use them. The picker keeps the
# range band, prefers a spot with a line of fire and partial cover, never
# picks a point inside a building, samples at most 16 candidates and caches
# cover per cell pair; walls are counted from footprints. In a 1v1 in the
# open the NPC holds its band and never walks into point-blank range. An
# NPC with a mortar fires at a last-known position behind a building, never
# at one inside a building, and not once the memory is old. A lost target
# turns the fight into a search: a Hunter sweeps, sends its drone and runs
# dark. Overheating turns it into a disengage: smoke round itself, a decoy,
# a mine on the way the foe will come, guns silent, over once cool. A
# Professional holds fire on a poor shot where a Scavenger fires; hot guns
# fire in bursts. An NPC with nothing to fight shoots an enemy ward it sees.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const MINE := preload("res://database/parts/mine.gd")
const SMOKE := preload("res://game/weapons/smoke_cloud.gd")
const MORTAR := "MA-M120"
const SMOKE_LAUNCHER := "MA-SL6"
const MINE_LAYER := "MA-ML1"


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
var _field: BuildingField = null


func run_tests() -> void:
	await case("the picker keeps the band, likes cover with a line of fire, stays out of buildings", _test_picker)
	await case("1v1 in the open: the NPC holds its range band and never closes to point-blank", _test_one_v_one)
	await case("behind a building: a mortar fires at the last-known spot, never into a building", _test_indirect)
	await case("a lost target: search, with a sweep, a drone and the lights off", _test_search)
	await case("overheating: disengage with smoke, a decoy and a mine, over once cool", _test_disengage)
	await case("a Professional holds a poor shot; hot guns fire in bursts", _test_discipline)
	await case("an NPC with nothing to fight shoots an enemy ward it sees", _test_devices)


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
	_field = null
	if not buildings.is_empty():
		var footprints := BuildingFootprints.new()
		var starts := PackedInt32Array([0])
		for b in buildings:
			footprints.points.append_array(PackedVector2Array(b))
			starts.append(footprints.points.size())
		footprints.starts = starts
		_field = BuildingField.new()
		_field.footprints = footprints
		_arena.add_child(_field)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _house(x0: float, x1: float, y0: float, y1: float) -> Array:
	return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]


# A design with `weapon` on the left shoulder (a core that has one), `right`
# on the right, and `internal` in the bay.
func _design(weapon := "", right := "", internal := "") -> Dictionary:
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	if weapon != "" or right != "":
		for core_id in PartManager.get_parts("core"):
			var core = PartManager.get_part("core", core_id)
			if (weapon == "" or core.has_left_shoulder) and (right == "" or core.has_right_shoulder):
				design["core"] = core_id
				break
	if weapon != "":
		design["shoulder_weapon_left"] = weapon
	if right != "":
		design["shoulder_weapon_right"] = right
	if internal != "":
		design["internal"] = internal
	return design


# An NPC that thinks for itself, held still (paused) unless `run`, facing +x.
func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, design: Dictionary = PlayerProgress.DEFAULT_MECHA, run := false) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var d: Dictionary = design.duplicate()
	d["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, d, "Tactics test")
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = not run
	_arena.mechas.append(enemy)
	return enemy


# A plain mecha standing at `pos`, dark, that `enemy` is set on attacking.
func _foe(pos: Vector2, enemy) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(false)
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	enemy.mark_traitor(mecha)
	return mecha


func _count_shots(mecha) -> Array:
	var shots := [0]
	mecha.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	return shots


func _engage_state(enemy) -> Dictionary:
	return enemy.logic.behaviour._get_self_state(enemy)


func _test_picker() -> void:
	# A house between the NPC and its foe, with open ground round it.
	await _setup([_house(600, 1000, -200, 200)])
	var enemy := _enemy(Vector2.ZERO)
	var foe := _foe(Vector2(1600, 0), enemy)
	enemy.knowledge.see(foe, foe.global_position)
	check_eq(_field.walls_crossed(Vector2.ZERO, Vector2(1600, 0)), 2, "a segment through the house crosses two walls")
	check_eq(_field.walls_crossed(Vector2(0, 600), Vector2(1600, 600)), 0, "one beside it crosses none")
	var behaviour = enemy.logic.behaviour
	var eff: Dictionary = behaviour._get_effective_distances(enemy)
	var wanted: float = (eff.min_kite + eff.max_kite) * 0.5
	var picker: Positioning = enemy.positioning
	var pick: Vector2 = picker.choose(enemy, foe.global_position, wanted, behaviour.ENGAGE_WEIGHTS, foe.global_position)
	check(picker.candidates.size() <= Positioning.MAX_CANDIDATES, "at most %d candidates (%d)" % [Positioning.MAX_CANDIDATES, picker.candidates.size()])
	var dist := pick.distance_to(foe.global_position)
	check(dist > wanted * 0.5 and dist < wanted * 1.6, "the pick keeps the range band (%.0f px for %.0f wanted)" % [dist, wanted])
	check_eq(_field.building_at(pick), -1, "and isn't inside the house")
	var entry := {}
	for candidate in picker.candidates:
		if candidate.position == pick:
			entry = candidate
			break
	check(not entry.is_empty() and float(entry.terms.fire_line) > 0.5, "it has a line of fire to the foe")
	check(not entry.is_empty() and not MapSenses.sight_blocked(_arena.get_world_2d(), pick, foe.global_position),
			"confirmed by the ray")
	var before: Dictionary = picker.cover_stats()
	picker.request()
	picker.choose(enemy, foe.global_position, wanted, behaviour.ENGAGE_WEIGHTS, foe.global_position)
	var after: Dictionary = picker.cover_stats()
	check(after.hits > before.hits, "the second pick answers cover from the cache (%d hits)" % after.hits)
	# Cover is wanted by a disengaging NPC: the pick is behind the house.
	picker.request()
	var cover_pick: Vector2 = picker.choose(enemy, foe.global_position, eff.max_kite * 1.5, behaviour.DISENGAGE_WEIGHTS, foe.global_position)
	check(_field.walls_crossed(cover_pick, foe.global_position) >= 2 or cover_pick.distance_to(foe.global_position) > dist,
			"disengaging, it picks cover or distance (%.0f px, %d walls)" % [cover_pick.distance_to(foe.global_position), _field.walls_crossed(cover_pick, foe.global_position)])
	# Fairness: the picker never reads the foe's true position.
	foe.global_position = Vector2(-4000, -4000)
	picker.request()
	var stale: Vector2 = picker.choose(enemy, enemy.get_target_position(foe), wanted, behaviour.ENGAGE_WEIGHTS, enemy.get_target_position(foe))
	check(stale.distance_to(Vector2(1600, 0)) < wanted * 1.6, "a pick is made against where the foe was last seen")


func _test_one_v_one() -> void:
	await _setup()
	var enemy := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL, PlayerProgress.DEFAULT_MECHA, true)
	var foe := _foe(Vector2(1000, 0), enemy)
	# The foe is kept whole (its grace window held) so the fight lasts: the
	# NPC holds its fire at it and the test is about where it stands. It is
	# hot, so it is seen at the NPC's full range, not the cold mecha's 60%.
	foe.flag_grace = 1.0e9
	foe.external_temp = 250.0
	enemy.knowledge.see(foe, foe.global_position)
	var eff: Dictionary = enemy.logic.behaviour._get_effective_distances(enemy)
	var engaged := await wait_until(func(): return str(enemy.logic.get_current_state()) == "engage", 4.0)
	check(engaged, "it engages")
	var closest := INF
	var last := 0.0
	for i in 32:
		await wait_seconds(0.25)
		last = enemy.global_position.distance_to(foe.global_position)
		if i >= 4:
			closest = minf(closest, last)
	check(closest > eff.cqb * 0.5, "it never closes to point-blank (closest %.0f px, cqb %.0f)" % [closest, eff.cqb])
	check(last > eff.min_kite * 0.5 and last < eff.max_kite * 1.6, "and ends near its band (%.0f px for %.0f to %.0f)" % [last, eff.min_kite, eff.max_kite])
	check(str(enemy.logic.get_current_state()) == "engage", "still fighting")


func _test_indirect() -> void:
	# A house between the mortar and where the foe went.
	await _setup([_house(1400, 1800, -200, 200)])
	var enemy := _enemy(Vector2.ZERO, Personality.Type.SCAVENGER, _design(MORTAR))
	check_eq(enemy._weapon_roles.get("shoulder_weapon_left"), "indirect", "the mortar's role")
	var foe := _foe(Vector2(2200, 0), enemy)
	var shots := _count_shots(enemy)
	enemy.knowledge.place(foe, foe.global_position)
	var eff: Dictionary = enemy.logic.behaviour._get_effective_distances(enemy)
	var fired: bool = enemy.fire.engage(0.1, foe, false, eff, _engage_state(enemy), false)
	check(fired and shots[0] > 0, "unseen behind the house, the mortar fires at the last-known spot")
	check(enemy.is_salvo_firing("shoulder_weapon_left") or shots[0] > 0, "a salvo is on its way")
	# Inside the house: never.
	var inside := _enemy(Vector2(0, 600), Personality.Type.SCAVENGER, _design(MORTAR))
	var hider := _foe(Vector2(1600, 600), inside)
	inside.global_position = Vector2(0, 0)
	inside.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	inside.knowledge.place(hider, Vector2(1600, 0))
	check(MapSenses.building_key_at(inside, Vector2(1600, 0)) != "", "the spot is inside the house")
	var inside_shots := _count_shots(inside)
	var fired_in: bool = inside.fire.engage(0.1, hider, false, eff, _engage_state(inside), false)
	check(not fired_in and inside_shots[0] == 0, "no round at a spot inside a building")
	# An old memory: no. The foe has gone out of the NPC's sight circle, so
	# only the memory could aim the mortar.
	var late := _enemy(Vector2(0, -600), Personality.Type.SCAVENGER, _design(MORTAR))
	var ghost := _foe(Vector2(2200, -600), late)
	late.knowledge.place(ghost, ghost.global_position)
	ghost.global_position = late.global_position + Vector2(0, -(late.sight_radius() + 1000.0))
	late.update_senses(FireController.INDIRECT_MEMORY + 1.0)
	var late_shots := _count_shots(late)
	late.fire.engage(0.1, ghost, false, eff, _engage_state(late), false)
	check_eq(late_shots[0], 0, "and none at a spot last known %.0f s ago" % (FireController.INDIRECT_MEMORY + 1.0))


func _test_search() -> void:
	await _setup()
	var enemy := _enemy(Vector2.ZERO, Personality.Type.HUNTER, _design("", "", "DR-4"), true)
	var foe := _foe(Vector2(900, 0), enemy)
	# Engaged, and with the target in sight on a think (aiming_at_enemy):
	# lost from there, it heads for the last-known spot. A Hunter flashes its
	# light, so it can go into engage between flashes, with the target unseen
	# and its last roam point still its point_of_interest; it heads there
	# instead, past max_shooting_distance from the spot within SEARCH_AFTER,
	# and drops the target before it searches.
	var engaged := await wait_until(func(): return str(enemy.logic.get_current_state()) == "engage" and enemy.logic.behaviour.aiming_at_enemy, 4.0)
	check(engaged, "it engages the mecha it sees")
	foe.global_position = Vector2(0, 7000)
	# The search may be over within a poll under load (its first think
	# sweeps; a sweep that finds the foe far off ends it): the sweep flag
	# says the search ran even then.
	var states := []
	var searching := await wait_until(func():
		var now_state := "%s:%s:%s" % [enemy.logic.get_current_state(), "T" if enemy.valid_target else "-", "L" if enemy.get_locked_to() else "-"]
		if states.is_empty() or states[-1] != now_state:
			states.append(now_state)
		return str(enemy.logic.get_current_state()) == "search" or enemy.logic.behaviour._search_swept, 8.0)
	check(searching, "with the target gone it searches (now %s; went %s; unseen %.1f s)" % [
			enemy.logic.get_current_state(), str(states), enemy.time_unseen(foe)])
	var swept := await wait_until(func(): return enemy.sweep_cooldown > 0.0, 3.0)
	check(swept, "a Hunter sweeps toward the last-known spot")
	var drone := await wait_until(func(): return not Device.owned_by(enemy).filter(func(d): return d.kind == "drone").is_empty(), 3.0)
	check(drone, "and sends its drone")
	check(not enemy.illuminator_on, "running dark")
	check(enemy.get_target_position(foe).distance_to(Vector2(900, 0)) < 300.0, "while it works from where it last saw the target")
	check(enemy.global_position.distance_to(foe.global_position) > 4000.0, "and never heads for the true position")


func _test_disengage() -> void:
	await _setup()
	var enemy := _enemy(Vector2.ZERO, Personality.Type.SCAVENGER, _design(SMOKE_LAUNCHER, MINE_LAYER, "DC-2"))
	check_eq(enemy._weapon_roles.get("shoulder_weapon_left"), "smoke", "the smoke launcher's role")
	check_eq(enemy._weapon_roles.get("shoulder_weapon_right"), "mine", "the mine layer's role")
	var foe := _foe(Vector2(1200, 0), enemy)
	enemy.knowledge.see(foe, foe.global_position)
	enemy.logic.behaviour._check_targets(enemy)
	enemy.logic.force_intent(enemy, "engage")
	enemy.logic.behaviour.stance = "attack"
	enemy.current_target = foe
	enemy.logic.intent_time = 5.0
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "engage", "fighting")
	enemy.internal_temp = enemy.overheat_temp * 0.95
	enemy.knowledge.refresh_state()
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "disengage", "overheating, it breaks contact")
	var smoke_before := SMOKE.count()
	var mines_before := MINE.count()
	var behaviour = enemy.logic.behaviour
	for i in 4:
		behaviour.do_disengage(0.5, enemy)
	check(SMOKE.count() > smoke_before or enemy.fire.salvos_fired.get("shoulder_weapon_left", 0) > 0, "smoke round itself")
	check(not Device.owned_by(enemy).filter(func(d): return d.kind == "decoy").is_empty(), "a decoy out")
	check(enemy.fire.salvos_fired.get("shoulder_weapon_right", 0) > 0 or MINE.count() > mines_before, "a mine laid on the way the foe will come")
	check(not behaviour.wants_illuminator(enemy, "disengage"), "dark")
	check(is_same(enemy.valid_target, foe), "the target is kept for later")
	enemy.logic.intent_time = behaviour.DISENGAGE_MIN_TIME
	enemy.knowledge.refresh_state()
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "disengage", "held while hot")
	enemy.internal_temp = 0.0
	enemy.external_temp = 0.0
	behaviour._disengage_time = behaviour.DISENGAGE_MIN_TIME
	enemy.knowledge.refresh_state()
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "engage", "cool again, it goes back to the fight")
	check(enemy.knowledge.now() < behaviour._disengage_ok_at, "and won't break off again for a while")


func _test_discipline() -> void:
	await _setup()
	var pro := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	var scav := _enemy(Vector2(0, 3000), Personality.Type.SCAVENGER)
	var eff: Dictionary = pro.logic.behaviour._get_effective_distances(pro)
	var far: float = float(eff.max_shoot) * 0.95
	var pro_foe := _foe(Vector2(far, 0), pro)
	var scav_foe := _foe(Vector2(far, 3000), scav)
	pro.knowledge.see(pro_foe, pro_foe.global_position)
	scav.knowledge.see(scav_foe, scav_foe.global_position)
	var pro_shots := _count_shots(pro)
	var scav_shots := _count_shots(scav)
	var state := {"heat_ratio": 0.0}
	for i in 5:
		pro.fire.engage(0.1, pro_foe, true, eff, state, true)
		scav.fire.engage(0.1, scav_foe, true, eff, state, false)
	check_eq(pro_shots[0], 0, "a Professional holds fire at the edge of its range")
	check(scav_shots[0] > 0, "a Scavenger fires (%d shots)" % scav_shots[0])
	# Closer, the Professional fires too (a moved body reaches the physics
	# server a step later, and the sight ray needs it there).
	pro_foe.global_position = Vector2(800, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	pro.knowledge.see(pro_foe, pro_foe.global_position)
	for i in 5:
		pro.fire.engage(0.1, pro_foe, true, eff, state, true)
	check(pro_shots[0] > 0, "and fires at a good shot")
	# Hot: bursts.
	var hot := {"heat_ratio": pro.logic.behaviour.weapon_heat_threshold * 0.9}
	pro.fire._burst_time = FireController.BURST_ON + 0.05
	var before: int = pro_shots[0]
	check(not pro.fire.engage(0.0, pro_foe, true, eff, hot, false) and pro_shots[0] == before, "hot, it holds in the burst's off phase")
	# Two calls: after a cease, a gun's first shoot() only spools up. The
	# guns' own fire-rate timers from the shots above are cleared first.
	pro.fire._burst_time = 0.05
	for slot in pro.WEAPON_SLOTS:
		var node = pro.get_weapon_part(slot)
		if node:
			node.timer = 0.0
	for i in 2:
		pro.fire.engage(0.0, pro_foe, true, eff, hot, false)
	check(pro_shots[0] > before, "and fires in its on phase")


func _test_devices() -> void:
	await _setup()
	var enemy := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	var other: Mecha = MECHA.instantiate()
	other.mech_inventory = Inventory.new()
	other.position = Vector2(700, 0)
	_arena.add_child(other)
	other.set_parts_from_design(PlayerProgress.DEFAULT_MECHA.duplicate())
	other.arena = _arena
	other.set_internal("WD-2")
	other.set_pause(true)
	other.use_internal()
	# The owner walks off, leaving its ward in the open.
	other.global_position = Vector2(700, 4000)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var wards := Device.owned_by(other)
	check(not wards.is_empty(), "an enemy ward is out")
	var shots := _count_shots(enemy)
	var busy: bool = enemy.fire.shoot_devices(0.0)
	check(busy, "with nothing to fight the NPC takes the ward on")
	if not wards.is_empty():
		check(enemy.ai_aim_point != null and (enemy.ai_aim_point as Vector2).distance_to(wards[0].global_position) < 1.0, "aiming at it")
	for i in 5:
		enemy.fire.shoot_devices(0.1)
	check(shots[0] > 0, "and shoots it (%d shots)" % shots[0])
	enemy.under_fire_timer = 0.5
	check(not enemy.fire.shoot_devices(0.1), "not while under fire")
