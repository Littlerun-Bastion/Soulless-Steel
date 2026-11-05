extends TestSuite

# NPCIntentTest: how an NPC picks what to do (EnemyLogic intent scoring,
# BaseBehaviour's score_ methods and NPCKnowledge). Each intent wins in the
# situation its old state was entered in; the current intent gets a
# commitment bonus and is held for a minimum time, and a tie keeps it; an
# NPC that enters the emergency Flag flees from any intent (a Rat doesn't),
# dark, and keeps fleeing while nobody shoots it until it is far from every
# threat and left alone, then leaves; an NPC acts only on what it knows: a
# lost target is searched for at its last-known position, never at its true
# one, and a body it never perceived is nowhere; and the think-time probe and
# the intent log record what happens.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const LOGIC := preload("res://game/mecha/enemy_logic/EnemyLogic.gd")


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


# Stands in for a loot container (group "loot_container").
class FakeContainer extends Node2D:
	var is_open := false
	var npc_searched := false
	var searched_by = null
	func interact(by) -> void:
		npc_searched = true
		searched_by = by


var _arena: FakeArena = null


func run_tests() -> void:
	await case("each intent wins where its old state was entered", _test_ladder)
	await case("the current intent is held: commitment, minimum time and ties", _test_commitment)
	await case("the emergency Flag makes an NPC flee from any intent, dark; a Rat doesn't", _test_flee_from_any_intent)
	await case("a flight goes on while nobody shoots, ends far away and left alone, then it leaves", _test_flight)
	await case("a lost target is searched for at its last-known position, never its true one", _test_lost_target_fairness)
	await case("the think-time probe and the intent log record", _test_probe)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


# An NPC that thinks for itself, held still (paused) unless `run`.
func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, run := false) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, design, "Intent test")
	enemy.global_rotation = 0.0
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


func _exit(pos: Vector2) -> Node2D:
	var exit := Node2D.new()
	exit.position = pos
	exit.add_to_group("exit_point")
	_arena.add_child(exit)
	return exit


func _container(pos: Vector2) -> FakeContainer:
	var container := FakeContainer.new()
	container.position = pos
	container.add_to_group("loot_container")
	_arena.add_child(container)
	return container


# Scores every intent as if the minimum time were over, and gives the winner.
func _decide(enemy) -> String:
	enemy.logic.intent_time = LOGIC.MIN_INTENT_TIME
	enemy.logic.evaluate_now(enemy)
	return str(enemy.logic.get_current_state())


func _sound(enemy, volume: String, pos: Vector2) -> void:
	enemy.heard_sound({"volume_type": volume, "type": "test", "position": pos, "source": null})


func _test_ladder() -> void:
	var enemy := _enemy(Vector2.ZERO)
	var behaviour = enemy.logic.behaviour
	check_eq(_decide(enemy), "roam", "with nothing going on it roams")
	check(enemy.logic.uses_intents() and enemy.logic.intents.size() == 17, "the default behaviour has the seventeen intents")

	# A loud noise: investigate; once used up it stays wary a while, then roams.
	_sound(enemy, "loud", Vector2(3000, 0))
	check_eq(_decide(enemy), "investigate", "a loud noise is investigated")
	enemy.senses.sounds.clear()
	check_eq(_decide(enemy), "investigate", "with the noise used up it stays wary")
	behaviour._wary_time = 0.0
	check_eq(_decide(enemy), "roam", "and then roams again")

	# A quiet noise while investigating: ambush.
	_sound(enemy, "loud", Vector2(3000, 0))
	check_eq(_decide(enemy), "investigate", "a loud noise again")
	_sound(enemy, "quiet", Vector2(1500, 0))
	check_eq(_decide(enemy), "ambush", "a quiet noise on top: it lies in wait")
	enemy.senses.sounds.clear()
	check_eq(_decide(enemy), "roam", "with every sound gone the ambush is over")

	# Under fire: investigate where the shot came from, above a noise.
	_sound(enemy, "quiet", Vector2(1500, 0))
	enemy.under_fire_timer = 0.5
	check_eq(_decide(enemy), "investigate", "under fire it investigates the attack")
	check(is_equal_approx(enemy.logic.scores.investigate, behaviour.SCORE_INVESTIGATE_FIRE), "at the under-fire score")
	enemy.under_fire_timer = 0.0
	enemy.senses.sounds.clear()
	behaviour._wary_time = 0.0

	# A target in range: engage, over everything above. (Targets are picked
	# by the running intent's target check, not by the scores.)
	var foe := _foe(Vector2(1650, 0), enemy)
	enemy.knowledge.see(foe, foe.global_position)
	behaviour._check_targets(enemy)
	enemy.under_fire_timer = 0.5
	_sound(enemy, "loud", Vector2(-3000, 0))
	check_eq(_decide(enemy), "engage", "a target in sight: engage")
	check(is_equal_approx(enemy.logic.scores.engage, behaviour.SCORE_ENGAGE_IN_RANGE), "at the in-range score at 1650 px")
	check(is_same(enemy.valid_target, foe) and behaviour.stance == "closing", "closing in on it first")
	enemy.under_fire_timer = 0.0
	enemy.senses.sounds.clear()

	# Losing the target ends the engagement.
	enemy.valid_target = false
	enemy.current_target = false
	check_eq(_decide(enemy), "roam", "with no target it roams")
	check_eq(behaviour.stance, "closing", "the stance is reset on the way out")

	# Loot: a container in reach while roaming (the scene scan is refreshed
	# every SCAN_INTERVAL s of the NPC's time).
	var container := _container(Vector2(500, 0))
	enemy.update_senses(behaviour.SCAN_INTERVAL + 0.1)
	check_eq(_decide(enemy), "loot", "a container in reach: loot")
	check(is_same(behaviour.target_container, container), "the container is claimed")
	container.npc_searched = true
	check_eq(_decide(enemy), "roam", "once searched, nothing to loot")

	# Extract: the shift-over decision, with an exit on the map.
	behaviour._wants_to_extract = true
	check_eq(_decide(enemy), "roam", "wanting to leave with no exit changes nothing")
	_exit(Vector2(0, 8000))
	await wait_seconds(behaviour.SCAN_INTERVAL + 0.1)
	enemy.update_senses(behaviour.SCAN_INTERVAL + 0.1)
	check_eq(_decide(enemy), "extract", "with an exit it leaves")
	check_eq(_decide(enemy), "extract", "and keeps leaving")
	check(is_equal_approx(enemy.logic.scores.extract, behaviour.SCORE_EXTRACT_COMMITTED), "committed to it")

	# The emergency Flag beats everything.
	enemy.is_exposed = true
	check_eq(_decide(enemy), "flee", "Flagged while leaving: it runs for its life")
	enemy.is_exposed = false


func _test_commitment() -> void:
	var enemy := _enemy(Vector2.ZERO)
	var behaviour = enemy.logic.behaviour
	var container := _container(Vector2(500, 0))
	check_eq(_decide(enemy), "loot", "looting")
	# Under fire right after the switch: the under-fire score is above
	# loot's, but not by the override margin, so loot is held for the
	# minimum time.
	enemy.under_fire_timer = 0.5
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "loot", "held for the minimum time")
	enemy.logic.intent_time = LOGIC.MIN_INTENT_TIME
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "investigate", "then it reacts to the fire")
	enemy.under_fire_timer = 0.0
	# A far higher score overrides the minimum time at once.
	var foe := _foe(Vector2(1000, 0), enemy)
	enemy.knowledge.see(foe, foe.global_position)
	behaviour._check_targets(enemy)
	enemy.logic.evaluate_now(enemy)
	check_eq(str(enemy.logic.get_current_state()), "engage", "a target overrides the hold at once")
	check(enemy.logic.intent_time < 0.5, "the switch just happened")
	# A tie keeps the current intent.
	enemy.valid_target = false
	enemy.current_target = false
	behaviour._wary_time = 0.0
	container.npc_searched = true
	check_eq(_decide(enemy), "roam", "back to roaming")
	for i in 3:
		check_eq(_decide(enemy), "roam", "roaming stays roaming")
	check_eq(enemy.logic.last_scores.size(), LOGIC.TOP_SCORES, "the top scores are kept for the overlay")
	check(enemy.logic.last_scores[0][0] == "roam", "roam on top")


func _test_flee_from_any_intent() -> void:
	var container := _container(Vector2(500, 0))
	for intent in ["roam", "investigate", "loot", "ambush", "engage", "extract"]:
		var enemy := _enemy(Vector2(0, 0))
		_sound(enemy, "quiet", Vector2(1500, 0))
		enemy.logic.force_intent(enemy, intent)
		enemy.logic.behaviour.target_container = container
		enemy.enter_flagged_state()
		check_eq(_decide(enemy), "flee", "Flagged while in %s: it flees" % intent)
		check(not enemy.logic.behaviour.wants_illuminator(enemy, "flee"), "and runs dark")
		enemy.queue_free()
		_arena.mechas.erase(enemy)
	# A Rat in the emergency state keeps its own counsel (its weapons are
	# still locked, so it can't engage either).
	var rat := _enemy(Vector2(0, 0), Personality.Type.RAT)
	var foe := _foe(Vector2(1000, 0), rat)
	# Facing the Rat: not a target to stalk, one to fight.
	foe.global_rotation = Vector2.UP.angle_to(Vector2.LEFT)
	rat.knowledge.see(foe, foe.global_position)
	rat.logic.behaviour._check_targets(rat)
	check_eq(_decide(rat), "engage", "a Rat with a target engages")
	rat.enter_flagged_state()
	var picked := _decide(rat)
	check(picked != "flee" and picked != "engage", "Flagged, a Rat neither flees for its life nor fights with locked weapons (now %s)" % picked)


func _test_flight() -> void:
	var enemy := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL, true)
	var behaviour = enemy.logic.behaviour
	var attacker := _foe(Vector2(0, -1200), enemy)
	_exit(Vector2(0, 8000))
	enemy.on_attacked_by(attacker)
	enemy.enter_flagged_state()
	var fled := await wait_until(func(): return str(enemy.logic.get_current_state()) == "flee", 2.0)
	check(fled, "it flees")
	await wait_seconds(10.0)
	check_eq(str(enemy.logic.get_current_state()), "flee", "still fleeing 10 s later with nobody shooting")
	check(not enemy.illuminator_on, "its illuminator is off")
	check(enemy.global_position.y > 1500.0, "it ran away from the attacker, toward the exit (y %.0f)" % enemy.global_position.y)
	check(not enemy.valid_target and not enemy.current_target, "it never stops to fight")
	var threats: Array = behaviour._flee_threats(enemy)
	check(not threats.is_empty(), "it knows what it is running from")
	# Far from every threat and left alone for FLEE_SAFE_TIME: the flight is
	# over and, Flagged, it leaves.
	var left := await wait_until(func(): return str(enemy.logic.get_current_state()) == "extract", 45.0)
	check(left, "once safe it heads for the exit (now %s at %.0f px from the attacker)" % [
			enemy.logic.get_current_state(), enemy.global_position.distance_to(attacker.global_position)])
	if left:
		check(enemy.global_position.distance_to(attacker.global_position) > behaviour.FLEE_SAFE_DISTANCE * 0.9,
				"after reaching the safe distance")
		check(not behaviour.wants_illuminator(enemy, "extract"), "and leaves dark")


func _test_lost_target_fairness() -> void:
	var enemy := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL, true)
	var behaviour = enemy.logic.behaviour
	var foe := _foe(Vector2(0, -900), enemy)
	var engaged := await wait_until(func(): return str(enemy.logic.get_current_state()) == "engage", 4.0)
	check(engaged, "it engages the mecha it sees (ahead of it)")
	var stranger := _foe(Vector2(-6000, -6000), enemy)
	check(enemy.get_target_position(stranger).is_equal_approx(enemy.global_position),
			"a body it never perceived is nowhere (its own position), not at its true position")
	check(not enemy.knowledge.knows(stranger), "it doesn't know it")
	# The target vanishes out of sight range.
	var last_seen := foe.global_position
	foe.global_position = Vector2(0, 6000)
	await wait_seconds(0.5)
	check(not enemy.is_seeing(foe), "the target is out of sight")
	check(enemy.get_target_position(foe).distance_to(last_seen) < 300.0, "it believes the target is where it last saw it")
	var strayed := false
	var true_pos := foe.global_position
	for i in 12:
		await wait_seconds(0.25)
		if enemy.global_position.distance_to(true_pos) < 3000.0:
			strayed = true
		if behaviour.point_of_interest is Vector2 and (behaviour.point_of_interest as Vector2).distance_to(true_pos) < 2000.0:
			strayed = true
	check(not strayed, "for the next 3 s it searches near the last-known spot and never heads for the true position")
	check(enemy.global_position.distance_to(true_pos) > 3000.0, "it is nowhere near the target's real position")


func _test_probe() -> void:
	var saved_log = Debug.debug_settings.get("ai_log")
	Debug.debug_settings["ai_log"] = true
	AICombatLog.reset()
	var enemy := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL, true)
	await wait_frames(10)
	# With no player on the map every NPC is "near" (Enemy.lod_tier).
	var stats := AICombatLog.think_stats("think_near")
	check(not stats.is_empty() and stats.n > 0, "thinking frames were timed")
	if not stats.is_empty():
		check(stats.median >= 0.0 and stats.max >= stats.median, "with a median and a worst time")
	enemy.logic.force_intent(enemy, "investigate")
	enemy.logic.force_intent(enemy, "roam")
	check(AICombatLog.switches_per_minute() >= 2, "intent switches are counted")
	var report := AICombatLog.report()
	check(report.contains("think_near") and report.contains("intent switches"), "and reported")
	AICombatLog.reset()
	Debug.debug_settings["ai_log"] = saved_log
