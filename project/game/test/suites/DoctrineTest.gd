extends TestSuite

# DoctrineTest: how NPCs meet what is out there (BaseBehaviour's IDENTIFY and
# illuminator rules, Enemy's lock and light discipline).
#   - Each type's response to an UNKNOWN IR track, a shot wedge and a lock
#     wedge (doctrine_response), and the identify intent running it.
#   - The skill breakpoints: tools from 0.3, light discipline from 0.5, a
#     lock search on a shot wedge and a lock back from 0.7; the reaction
#     delay by skill.
#   - Lights: off in calm intents, steady under 0.5, flashing from 0.5, the
#     anchor lit, the flanker and the Rat dark, execute lit.
#   - Nervous: above NERVOUS_PANIC it fires or leaves by courage.
#   - Identify ends on visual, when the track is lost, and on timeout.
#   - The lock warning: a bark, and panic once locked.
#   - The fairness rule: an NPC with no track on a mech never starts a lock
#     search on it, never aims at it and never goes toward it.
#
# NPCs are paused and stepped by hand unless a case runs them.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const TYPES := [Personality.Type.SCAVENGER, Personality.Type.RAT, Personality.Type.GUARDIAN,
		Personality.Type.PROFESSIONAL, Personality.Type.HUNTER]


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return mechas.filter(func(m): return is_instance_valid(m)).map(func(m): return m.get_lock_area())
	func get_safe_position() -> Vector2:
		return Vector2(-9000, -9000)
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-2000, 2000), randf_range(-2000, 2000))


var _arena: FakeArena = null
var _spoken := []


func run_tests() -> void:
	await case("each type meets an UNKNOWN track, a shot wedge and a lock wedge its own way", _test_responses)
	await case("identify runs the response: sweep, lock search, leave, light", _test_identify_runs)
	await case("the skill breakpoints allow and refuse their tools; the reaction delay", _test_breakpoints)
	await case("lights: off when calm, steady under 0.5, flashing from 0.5, the anchor, the Rat", _test_lights)
	await case("nervous: above the panic line it fires or leaves by courage", _test_nervous)
	await case("identify ends on visual, on loss and on timeout; the ladder", _test_identify_ends)
	await case("a lock warning: a bark, panic once locked, and a reaction", _test_lock_warning)
	await case("the fairness rule: no track, no lock search, no aim, no approach", _test_fairness)
	await case("the barks have lines for every type", _test_barks)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	_spoken.clear()
	await get_tree().physics_frame


func _mecha(pos: Vector2, lit := false) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_physics_process(false)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(lit)
	mecha.external_temp = 0.0
	_arena.mechas.append(mecha)
	return mecha


func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, skill := 0.6, design: Dictionary = PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var enemy: Mecha = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var d: Dictionary = design.duplicate()
	d["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, d, "Doctrine %s" % Personality.Type.keys()[type])
	enemy.personality.skill = skill
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.auto_illuminator = true
	enemy.set_illuminator(false)
	enemy.global_rotation = 0.0
	enemy.wait_for_map_sync = 0.0
	enemy.spoke.connect(func(_m, text, _s, _a): _spoken.append(text))
	_arena.mechas.append(enemy)
	return enemy


func _sense(enemy) -> void:
	await get_tree().physics_frame
	enemy.contacts.advance(0.05)
	enemy.update_senses(0.05)


# Ages an NPC's store past its reaction delay.
func _wait_out(enemy) -> void:
	enemy.contacts.advance(enemy.reaction_delay() + 0.1)


func _decide(enemy) -> String:
	enemy.knowledge.refresh_state()
	enemy.logic.intent_time = 10.0
	enemy.logic.evaluate_now(enemy)
	return str(enemy.logic.get_current_state())


func _ir_reason(enemy, body) -> Dictionary:
	var contact: Dictionary = enemy.knowledge.sensed_heat(body, body.global_position)
	return {"kind": "ir", "point": body.global_position, "key": "test", "contact": contact, "body": body}


func _wedge_reason(enemy, source: String, from: Vector2) -> Dictionary:
	var wedge: Dictionary = enemy.contacts.report_wedge(null, source, enemy.global_position, from)
	return {"kind": source, "point": ContactStore.estimate_point(wedge), "key": "test", "wedge": wedge}


func _test_responses() -> void:
	var o := Vector2(-3000, -3000)
	var expected := {
		Personality.Type.SCAVENGER: ["leave", "leave", "leave"],
		Personality.Type.RAT: ["flank", "flank", "break_line"],
		Personality.Type.GUARDIAN: ["scan", "scan", "lock"],
		Personality.Type.PROFESSIONAL: ["scan", "scan", "lock"],
		Personality.Type.HUNTER: ["lock", "lock", "lock"],
	}
	for type in TYPES:
		var npc := _enemy(o, type, 0.8)
		var hidden := _mecha(o + Vector2(0, -1500))
		var name: String = Personality.Type.keys()[type]
		var behaviour = npc.logic.behaviour
		var got := [behaviour.doctrine_response(npc, _ir_reason(npc, hidden)),
				behaviour.doctrine_response(npc, _wedge_reason(npc, "shot", hidden.global_position)),
				behaviour.doctrine_response(npc, _wedge_reason(npc, "lock", hidden.global_position))]
		check_eq(got, expected[type], "a %s (skill 0.8): UNKNOWN, shot, lock" % name)
		npc.queue_free()
		hidden.queue_free()
		_arena.mechas.clear()
		await get_tree().physics_frame
	# A Hunter with its drone, no sweep: lock (and the drone keeps the track
	# live); a Professional with nothing to scan with locks.
	var pro := _enemy(o, Personality.Type.PROFESSIONAL, 0.8)
	pro.sweep_cooldown = 100.0
	check_eq(pro.logic.behaviour.doctrine_response(pro, _wedge_reason(pro, "sound", o + Vector2(0, -1500))), "lock",
			"a Professional with no sweep or drone ready goes straight to a lock search")
	var guardian := _enemy(o + Vector2(3000, 0), Personality.Type.GUARDIAN, 0.8)
	guardian.sweep_cooldown = 100.0
	check_eq(guardian.logic.behaviour.doctrine_response(guardian, _wedge_reason(guardian, "sound", o)), "light",
			"a Guardian with nothing to scan with lights it up to make sure")


func _test_identify_runs() -> void:
	var o := Vector2(-3000, -3000)
	var hidden := _mecha(o + Vector2(0, -2000))
	# A Professional: an alarm by the hidden mech; it sweeps that way, the
	# sweep reports a mech, and it goes on to a lock search on it.
	var pro := _enemy(o, Personality.Type.PROFESSIONAL, 0.8)
	pro.contacts.report(null, "car", hidden.global_position + Vector2(200, 0), "alarm", 30.0)
	_wait_out(pro)
	check_eq(_decide(pro), "identify", "an alarm with nothing seen: identify")
	var behaviour = pro.logic.behaviour
	check_eq(behaviour.identifying().response, "scan", "a Professional scans first")
	behaviour.do_identify(0.1, pro)
	check(pro.sweep_cooldown > 0.0 and pro.fire.last_sweep.get("counts", {}).has("mech"), "it swept, and the sweep reports a mech")
	check_eq(behaviour.identifying().response, "lock", "then it goes on to a lock")
	behaviour.do_identify(0.1, pro)
	check(is_same(pro.lock_search_target, hidden), "a lock search on the mech by the alarm")
	pro.update_enemy_locking(0.1, pro.lock_search_target)
	check(not pro.get_locking_to() and pro._lock_search > 0.0, "searching first (no live track), nothing showing")
	check(hidden.lock_warning().is_empty(), "the hidden mech isn't warned during the search")
	pro.update_enemy_locking(pro._lock_search + 0.01, pro.lock_search_target)
	check(pro.get_locking_to() != null and pro.get_locking_to() and not hidden.lock_warning().is_empty(), "then locks, and the mech is warned")

	# A Scavenger: it leaves, and keeps away.
	var scav := _enemy(o + Vector2(4000, 0), Personality.Type.SCAVENGER, 0.4)
	var spot := scav.global_position + Vector2(0, -1500)
	scav.contacts.report(null, "car", spot, "alarm", 30.0)
	_wait_out(scav)
	check_eq(_decide(scav), "identify", "a Scavenger identifies too")
	check_eq(scav.logic.behaviour.identifying().response, "leave", "by leaving")
	scav.logic.behaviour.do_identify(0.1, scav)
	check(scav.knowledge.avoids(spot, 100.0), "it keeps away from the spot")
	var goal = scav.logic.behaviour.point_of_interest
	check(goal is Vector2 and goal.distance_to(spot) > scav.global_position.distance_to(spot), "and heads away from it")

	# A Guardian with nothing to scan with: its light toward it.
	var guardian := _enemy(o + Vector2(-4000, 0), Personality.Type.GUARDIAN, 0.5)
	guardian.sweep_cooldown = 100.0
	guardian.contacts.report(null, "car", guardian.global_position + Vector2(0, -1500), "alarm", 30.0)
	_wait_out(guardian)
	check_eq(_decide(guardian), "identify", "a Guardian identifies")
	guardian._illuminator_hold = 0.0
	guardian._update_illuminator(0.1)
	check(guardian.illuminator_on, "with its light")


func _test_breakpoints() -> void:
	var o := Vector2(-3000, -3000)
	var hidden := _mecha(o + Vector2(0, -2000))
	var pro := _enemy(o, Personality.Type.PROFESSIONAL, 0.2)
	var reason := _wedge_reason(pro, "sound", hidden.global_position)
	check_eq(pro.logic.behaviour.doctrine_response(pro, reason), "watch", "under 0.3: it only turns and watches")
	pro.personality.skill = 0.3
	check_eq(pro.logic.behaviour.doctrine_response(pro, reason), "scan", "at 0.3 it sweeps or sends its drone")
	check(is_equal_approx(pro.reaction_delay(), lerpf(1.5, 0.3, 0.3)), "the reaction delay is lerp(1.5, 0.3, skill)")
	pro.personality.skill = 1.0
	check(is_equal_approx(pro.reaction_delay(), 0.3), "0.3 s at skill 1")
	pro.personality.skill = 0.0
	check(is_equal_approx(pro.reaction_delay(), 1.5), "1.5 s at skill 0")

	# The reaction delay: a new track isn't acted on until it has passed.
	pro.personality.skill = 0.5
	pro.contacts.clear()
	pro.contacts.report(null, "car", hidden.global_position, "alarm", 30.0)
	check(pro.logic.behaviour.identify_reason(pro).is_empty(), "a track newer than the delay is no reason yet")
	_wait_out(pro)
	check(not pro.logic.behaviour.identify_reason(pro).is_empty(), "past it, it is")

	# 0.7: a lock search the moment a shot wedge comes, from beyond visual.
	var hunter := _enemy(o + Vector2(4000, 0), Personality.Type.HUNTER, 0.8)
	var shooter := _mecha(hunter.global_position + Vector2(0, -2200))
	hunter._took_round(shooter, shooter.global_position)
	check(is_same(hunter.lock_search_target, shooter), "skill 0.8: a lock search along the shot wedge at once")
	var green := _enemy(o + Vector2(-4000, 0), Personality.Type.PROFESSIONAL, 0.6)
	var shooter2 := _mecha(green.global_position + Vector2(0, -2200))
	green._took_round(shooter2, shooter2.global_position)
	check(green.lock_search_target == null, "skill 0.6: not")
	var rat := _enemy(o + Vector2(0, 4000), Personality.Type.RAT, 0.9)
	var shooter3 := _mecha(rat.global_position + Vector2(0, -2200))
	rat._took_round(shooter3, shooter3.global_position)
	check(rat.lock_search_target == null, "a Rat never: a lock would give it away")
	# 0.7: a lock back on a lock wedge; under it, smoke or break line.
	var reason_lock := _wedge_reason(green, "lock", shooter2.global_position)
	check(green.logic.behaviour.doctrine_response(green, reason_lock) in ["smoke", "break_line"], "skill 0.6 locked: smoke or break line")
	green.personality.skill = 0.7
	check_eq(green.logic.behaviour.doctrine_response(green, reason_lock), "lock", "skill 0.7: a lock search back")


func _test_lights() -> void:
	var o := Vector2(-3000, -3000)
	var npc := _enemy(o, Personality.Type.PROFESSIONAL, 0.3)
	var behaviour = npc.logic.behaviour
	for intent in ["roam", "loot", "investigate", "follow", "help", "protect", "search", "scout", "ambush", "vulture", "extract"]:
		check_eq(behaviour.illuminator_mode(npc, intent), "off", "%s: off" % intent)
	check_eq(behaviour.illuminator_mode(npc, "engage"), "off", "engage with no known target: off")
	var foe := _mecha(o + Vector2(0, -1500))
	npc.mark_traitor(foe)
	npc.knowledge.see(foe, foe.global_position)
	npc.valid_target = foe
	check_eq(behaviour.illuminator_mode(npc, "engage"), "on", "engaging a tracked target under 0.5: steady")
	npc.personality.skill = 0.6
	check_eq(behaviour.illuminator_mode(npc, "engage"), "flash", "from 0.5: flashing")
	check_eq(behaviour.illuminator_mode(npc, "execute"), "on", "execute: lit")

	# The flash cycle: on to get visual, off after a burst, dark a while, on
	# again; off at FLASH_MAX with no visual.
	npc.logic.g.set_state("engage")
	npc._update_illuminator(0.1)
	check(npc.illuminator_on, "a flash: on")
	npc.fire.last_shot_time = npc.knowledge.now()
	npc._update_illuminator(0.1)
	check(npc.illuminator_on, "lit while the burst goes on")
	npc.fire.last_shot_time = npc.knowledge.now() - 1.0
	npc._update_illuminator(0.1)
	check(not npc.illuminator_on, "off once the burst ends")
	npc._update_illuminator(npc.FLASH_REST * 0.5)
	check(not npc.illuminator_on, "dark a while")
	npc._update_illuminator(npc.FLASH_REST)
	npc._update_illuminator(0.05)
	check(npc.illuminator_on, "then on again for the next")
	npc.valid_target = false
	npc.knowledge.forget(foe)
	var unseen := _mecha(o + Vector2(0, -2800))
	npc.mark_traitor(unseen)
	npc.knowledge.place(unseen, unseen.global_position)
	npc.valid_target = unseen
	npc._flash_reset()
	for i in 25:
		npc._update_illuminator(0.1)
	check(not npc.illuminator_on, "with no visual, off at FLASH_MAX")

	# The anchor lit, the flanker dark; a Rat dark but to execute.
	var squad := Squad.new()
	squad.setup("TST", false)
	var anchor := _enemy(o + Vector2(3000, 0), Personality.Type.PROFESSIONAL, 0.2)
	var flanker := _enemy(o + Vector2(3600, 0), Personality.Type.PROFESSIONAL, 0.2)
	squad.add(anchor)
	squad.add(flanker)
	squad.assign_roles()
	var a_role: String = anchor.knowledge.role()
	var f_role: String = flanker.knowledge.role()
	var lit_one = anchor if a_role == Squad.ROLE_ANCHOR else flanker
	var dark_one = flanker if a_role == Squad.ROLE_ANCHOR else anchor
	check(a_role == Squad.ROLE_ANCHOR or f_role == Squad.ROLE_ANCHOR, "(one anchors)")
	check_eq(lit_one.logic.behaviour.illuminator_mode(lit_one, "engage"), "on", "the anchor is lit while engaging")
	if dark_one.knowledge.role() == Squad.ROLE_FLANKER:
		check_eq(dark_one.logic.behaviour.illuminator_mode(dark_one, "engage"), "off", "the flanker dark")
	var rat := _enemy(o + Vector2(0, 3000), Personality.Type.RAT, 0.2)
	rat.mark_traitor(foe)
	rat.knowledge.see(foe, foe.global_position)
	rat.valid_target = foe
	check_eq(rat.logic.behaviour.illuminator_mode(rat, "engage"), "off", "a Rat never lights up to fight")
	check_eq(rat.logic.behaviour.illuminator_mode(rat, "execute"), "on", "but an execution must be seen")


func _test_nervous() -> void:
	var o := Vector2(-3000, -3000)
	var hidden := _mecha(o + Vector2(0, -1500))
	var brave := _enemy(o, Personality.Type.GUARDIAN, 0.6)
	var timid := _enemy(o + Vector2(4000, 0), Personality.Type.PROFESSIONAL, 0.6)
	timid.personality.courage = 0.2
	brave.knowledge.panic = brave.logic.behaviour.NERVOUS_PANIC + 0.05
	timid.knowledge.panic = timid.logic.behaviour.NERVOUS_PANIC + 0.05
	var reason := _wedge_reason(brave, "sound", hidden.global_position)
	check_eq(brave.logic.behaviour.doctrine_response(brave, reason), "fire", "nervous with courage 0.8: it fires at the track")
	check_eq(timid.logic.behaviour.doctrine_response(timid, _wedge_reason(timid, "sound", hidden.global_position)), "leave",
			"nervous with courage 0.2: it leaves")
	brave.knowledge.panic = 0.2
	check(brave.logic.behaviour.doctrine_response(brave, reason) != "fire", "calm again, its doctrine")


func _test_identify_ends() -> void:
	var o := Vector2(-3000, -3000)
	var npc := _enemy(o, Personality.Type.PROFESSIONAL, 0.2)
	var hidden := _mecha(o + Vector2(0, -2000))
	npc.contacts.report(null, "car", hidden.global_position, "alarm", 2.0)
	_wait_out(npc)
	check_eq(_decide(npc), "identify", "an alarm: identify")
	check(npc.logic.scores.identify > npc.logic.scores.get("investigate", 0.0) and npc.logic.scores.identify > npc.logic.scores.get("roam", 0.0),
			"above roam and investigate")
	npc.contacts.advance(3.0)
	check(_decide(npc) != "identify", "the alarm gone, it ends")
	npc.contacts.report(null, "car", hidden.global_position + Vector2(10, 0), "alarm", 100.0)
	_wait_out(npc)
	check_eq(_decide(npc), "identify", "another alarm: identify")
	check_eq(npc.logic.behaviour.identifying().get("response"), "watch", "(under 0.3 it only watches)")
	npc.logic.behaviour.do_identify(npc.logic.behaviour.IDENTIFY_WATCH_TIME - 0.5, npc)
	check_eq(_decide(npc), "identify", "it watches a while")
	npc.logic.behaviour.do_identify(0.6, npc)
	check(_decide(npc) != "identify", "and after IDENTIFY_WATCH_TIME with nothing to show for it, goes on")
	check(npc.logic.behaviour.identify_reason(npc).is_empty(), "and doesn't take the same track up again")
	npc.contacts.report(null, "car", hidden.global_position + Vector2(20, 0), "alarm", 100.0)
	_wait_out(npc)
	check_eq(_decide(npc), "identify", "a third alarm: identify")
	npc.logic.behaviour._identify_response = "scan"
	npc.logic.behaviour._identify_scanned = true
	npc.logic.behaviour.do_identify(npc.logic.behaviour.IDENTIFY_WATCH_TIME + 0.5, npc)
	check_eq(_decide(npc), "identify", "one waiting on a drone isn't hurried")
	npc.logic.behaviour.do_identify(npc.logic.behaviour.IDENTIFY_TIME, npc)
	check(_decide(npc) != "identify", "after IDENTIFY_TIME it gives up")

	# Visual ends it: a mech it sees inside the wedge.
	var shooter := _mecha(o + Vector2(0, -350))
	npc.contacts.report_wedge(null, "sound", npc.global_position, shooter.global_position)
	_wait_out(npc)
	check_eq(_decide(npc), "identify", "a sound wedge: identify")
	npc.knowledge.see(shooter, shooter.global_position)
	check(_decide(npc) != "identify", "a mech seen inside the wedge: its cause is visual, identify ends")

	# Under engage when a target is in sight.
	var foe := _mecha(o + Vector2(1200, 0))
	npc.mark_traitor(foe)
	npc.knowledge.see(foe, foe.global_position)
	npc.contacts.report(null, "car", o + Vector2(-2000, 0), "alarm", 100.0)
	_wait_out(npc)
	npc.knowledge.see(foe, foe.global_position)
	npc.logic.behaviour._check_targets(npc)
	check_eq(_decide(npc), "engage", "a target in sight: engage, over identify")


func _test_lock_warning() -> void:
	var o := Vector2(-3000, -3000)
	var npc := _enemy(o, Personality.Type.PROFESSIONAL, 0.5)
	var locker := _mecha(o + Vector2(0, -2000))
	locker._warn_target(npc, 0.2)
	npc._watch_lock_warning()
	check(npc._warned_since == float(npc.lock_warning().wedge.since), "a lock beginning on it is noted (its lock_warning bark)")
	var panic_before: float = npc.knowledge.panic
	locker._warn_target(npc, 1.0)
	npc._watch_lock_warning()
	check(npc.knowledge.panic > panic_before, "once locked, its panic rises")
	var after: float = npc.knowledge.panic
	npc._watch_lock_warning()
	check_eq(npc.knowledge.panic, after, "once per lock")
	_wait_out(npc)
	locker._warn_target(npc, 1.0)
	check_eq(_decide(npc), "identify", "a lock on it puts it in identify")
	check(npc.logic.scores.identify >= npc.logic.behaviour.SCORE_IDENTIFY_LOCKED - 0.001, "above a fight")
	check(npc.logic.behaviour.identifying().response in ["smoke", "break_line"], "skill 0.5: it breaks line")


func _test_fairness() -> void:
	var o := Vector2(-3000, -3000)
	var npc := _enemy(o, Personality.Type.HUNTER, 1.0)
	var hidden := _mecha(o + Vector2(0, -1800))
	npc.mark_traitor(hidden)
	check(not npc.lock_reason_for(hidden), "no track on the hidden mech: no reason to look for a lock")
	npc.update_enemy_locking(5.0, hidden)
	check(not npc.get_locking_to() and npc._lock_search < 0.0, "so no lock search on it")
	var elsewhere := npc.global_position + Vector2(3000, 0)
	var reason := {"kind": "alarm", "point": elsewhere, "key": "x", "contact": {}}
	check(npc.logic.behaviour.lock_candidate(npc, reason) == null, "a track elsewhere finds nothing to lock")
	# Run it a while: the arena's random points are all well away from the
	# hidden mech, so only knowledge of it could take the NPC there.
	npc.paused = false
	npc.set_physics_process(true)
	var aimed_at := false
	var headed_for := false
	for i in 90:
		await get_tree().physics_frame
		if npc.ai_aim_point is Vector2 and npc.ai_aim_point.distance_to(hidden.global_position) < 300.0:
			aimed_at = true
		if npc.NavAgent.target_position.distance_to(hidden.global_position) < 300.0:
			headed_for = true
	npc.paused = true
	check(not npc.knowledge.knows(hidden), "(it never picked the mech up)")
	check(not aimed_at, "it never aims at it")
	check(npc.lock_search_target == null and not npc.get_locked_to() and not npc.get_locking_to(), "never locks it")
	check(not headed_for, "and never goes toward it")


func _test_barks() -> void:
	for event in ["lock_warning", "identifying", "locked_on", "contact_unknown"]:
		check(Barks.chance_for(event) > 0.0, "%s has a chance" % event)
		for type in ["any", "scavenger", "guardian", "professional", "hunter", "rat"]:
			check(Barks.has_lines(event, type), "%s has %s lines" % [event, type])
