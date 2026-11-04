extends TestSuite

# PersonalityTest: the personality table of the AI brief (3.6) and the
# voice (3.12), Phase 7. A Hunter never loots and is provoked by a Flagged
# mech that crowds it or stares it down, until it will finish it; a Guardian
# protects a hurt or Flagged squadmate before a stranger and all but never
# yields while a squadmate stands; a Professional extracts on schedule, a
# Scavenger on its greed's roll; a Scavenger keeps away from where it was
# swept and a Rat lies (covered elsewhere, checked here by the constants).
# The voice: every bark event of the brief has lines for every personality
# type and "any", a chance, and the panicked variants have chances; a
# panicked NPC uses the panicked line.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
## The events of the brief's section 3.12, plus the ones the game had.
const EVENTS := ["contact", "flanking", "covering", "moving_up", "falling_back", "man_down", "regroup",
		"investigating", "heard_alarm", "swept", "device_destroyed", "mine_spotted", "scouting", "vulturing",
		"flag_raised", "flag_lowered", "execute", "surrender_plea", "spared", "traitor", "buddy_offer",
		"buddy_accept", "order_ack", "betrayal", "lost_trail", "found_trail",
		"spotted", "lost_target", "searching", "taking_fire", "reloading", "overheating", "retreating",
		"target_down", "looting", "extracting", "idle"]
const TYPES := ["scavenger", "guardian", "professional", "hunter", "rat"]


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	var local_pilots := LocalPilots.new()
	var squads: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2(-5000, -5000)
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-6000, 6000), randf_range(-6000, 6000))


class FakeContainer extends Node2D:
	var is_open := false
	var npc_searched := false
	func interact(_by) -> void:
		npc_searched = true


var _arena: FakeArena = null
var _spoken: Array = []


func run_tests() -> void:
	await case("a Hunter never loots, and a Flagged mech that crowds or stares it down provokes it", _test_hunter)
	await case("a Guardian protects a hurt squadmate first, and all but never yields while one stands", _test_guardian)
	await case("a Professional extracts on schedule; others on their greed's roll", _test_schedule)
	await case("the voice: every event has lines for every type, a chance, and panicked variants", _test_voice)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	_spoken.clear()
	Barks.reset_cooldown()
	Barks._data = {}
	PlayerProgress.reset()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	LocalPilots.current = _arena.local_pilots
	await get_tree().physics_frame


func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, design, "Personality test %s %d" % [Personality.Type.keys()[type], _arena.mechas.size()])
	enemy.is_anonymous = false
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = true
	enemy.spoke.connect(func(_m, text, _s, _a): _spoken.append(text))
	_arena.mechas.append(enemy)
	_arena.local_pilots.join(enemy)
	return enemy


func _mecha(pos: Vector2, callsign := "") -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(false)
	mecha.external_temp = 250.0
	mecha.arena = _arena
	mecha.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	if callsign != "":
		mecha.callsign = callsign
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	_arena.local_pilots.join(mecha)
	return mecha


func _test_hunter() -> void:
	var hunter := _enemy(Vector2.ZERO, Personality.Type.HUNTER)
	var scavenger := _enemy(Vector2(0, 3000), Personality.Type.SCAVENGER)
	var crate := FakeContainer.new()
	crate.position = Vector2(300, 0)
	crate.add_to_group("loot_container")
	_arena.add_child(crate)
	var crate2 := FakeContainer.new()
	crate2.position = Vector2(300, 3000)
	crate2.add_to_group("loot_container")
	_arena.add_child(crate2)
	check_eq(hunter.logic.behaviour.score_loot(hunter), 0.0, "a Hunter never loots, crate or no crate")
	check(scavenger.logic.behaviour.score_loot(scavenger) > 0.0, "a Scavenger would")
	# Provocation: a Flagged mech close by, or facing it from further off.
	var flagged := _mecha(Vector2(600, 0), "Pest")
	flagged.raise_flag(true)
	flagged.global_rotation = Vector2.UP.angle_to(Vector2.LEFT)
	hunter.knowledge.see(flagged, flagged.global_position)
	check(not hunter.should_attack(flagged), "a Hunter respects a Flag at first")
	for i in 10:
		hunter._tick_provocation(0.5)
	check(hunter.get_relationship(flagged).hostility >= 0.3, "a Flagged mech that stays close wears its patience (%.2f)" % hunter.get_relationship(flagged).hostility)
	check(hunter.should_attack(flagged), "until it will finish it")
	var starer := _mecha(Vector2(1200, 0), "Starer")
	starer.raise_flag(true)
	starer.global_rotation = Vector2.UP.angle_to(Vector2.LEFT)
	var polite := _mecha(Vector2(0, 1200), "Polite")
	polite.raise_flag(true)
	polite.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	hunter.knowledge.see(starer, starer.global_position)
	hunter.knowledge.see(polite, polite.global_position)
	for i in 10:
		hunter._tick_provocation(0.5)
	check(hunter.get_relationship(starer).hostility >= 0.3, "one that keeps facing it from further off too (%.2f)" % hunter.get_relationship(starer).hostility)
	check(hunter.get_relationship(polite).hostility < 0.3, "not one that looks away (%.2f)" % hunter.get_relationship(polite).hostility)
	var pro := _enemy(Vector2(-600, 0), Personality.Type.PROFESSIONAL)
	pro.knowledge.see(flagged, flagged.global_position)
	for i in 10:
		pro._tick_provocation(0.5)
	check(pro.get_relationship(flagged).hostility < 0.3, "a Professional isn't provoked that way")


func _test_guardian() -> void:
	var guardian := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	var mate := _enemy(Vector2(2000, 0), Personality.Type.PROFESSIONAL)
	var stranger := _mecha(Vector2(500, 0), "Stranger")
	var squad := Squad.new()
	squad.setup("HLX", false)
	squad.add(mate)
	squad.add(guardian)
	stranger.raise_flag(true)
	guardian.knowledge.see(stranger, stranger.global_position)
	check(guardian.logic.behaviour._find_protege(guardian) == stranger, "with no mate in trouble, a Flagged stranger is protected")
	mate.raise_flag(true)
	check(guardian.logic.behaviour._find_protege(guardian) == mate, "a Flagged squadmate comes first, wherever it is")
	mate.lower_flag()
	mate._finish_lowering()
	for part_name in mate.armor:
		for facing in mate.armor[part_name]:
			mate.armor[part_name][facing].pips = 0
	for part_name in mate.components:
		for comp_name in mate.components[part_name]:
			mate.components[part_name][comp_name].hp = 0
	check(NPCKnowledge._structural_health(mate) <= guardian.logic.behaviour.PROTECT_DAMAGE, "the mate is badly hurt")
	check(guardian.logic.behaviour._find_protege(guardian) == mate, "a hurt squadmate too")
	# Yielding: only at the very end while a squadmate stands.
	guardian.logic.force_intent(guardian, "engage")
	guardian.logic.behaviour.aggression = -1.0
	guardian.knowledge.panic = 0.9
	check_eq(guardian.logic.behaviour.score_raise_flag(guardian), 0.0, "at panic 0.9 with a squadmate alive, no surrender")
	guardian.knowledge.panic = 0.99
	check(guardian.logic.behaviour.score_raise_flag(guardian) > 0.0, "only all but broken")
	squad.remove(mate)
	guardian.knowledge.panic = 0.9
	check(guardian.logic.behaviour.score_raise_flag(guardian) > 0.0, "alone, it yields at its own threshold")


func _test_schedule() -> void:
	var pro := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	var scavenger := _enemy(Vector2(0, 600), Personality.Type.SCAVENGER)
	pro.paused = false
	scavenger.paused = false
	pro.logic.behaviour._start_tick_msec = Time.get_ticks_msec() - int(pro.logic.behaviour.PRO_EXTRACT_TIME * 1000.0) + 2000
	pro.logic.behaviour.do_roam(0.1, pro)
	check(not pro.logic.behaviour._wants_to_extract, "a Professional stays until its time is up")
	pro.logic.behaviour._start_tick_msec = Time.get_ticks_msec() - int(pro.logic.behaviour.PRO_EXTRACT_TIME * 1000.0) - 1000
	pro.logic.behaviour.do_roam(0.1, pro)
	check(pro.logic.behaviour._wants_to_extract, "then leaves, on schedule, whatever its greed")
	scavenger.logic.behaviour._start_tick_msec = Time.get_ticks_msec() - 400000
	var left := false
	for i in 400:
		scavenger.logic.behaviour.do_roam(0.1, scavenger)
		if scavenger.logic.behaviour._wants_to_extract:
			left = true
			break
	check(left, "a Scavenger past its time leaves on its greed's roll")
	pro.paused = true
	scavenger.paused = true


func _test_voice() -> void:
	var data := Barks.data()
	check(not data.is_empty(), "barks.json loads")
	for event in EVENTS:
		var lines: Dictionary = data.events.get(event, {})
		check(not lines.get("any", []).is_empty(), "%s has 'any' lines" % event)
		for type in TYPES:
			check(not lines.get(type, []).is_empty(), "%s has %s lines" % [event, type])
		check(Barks.chance_for(event) > 0.0, "%s has a chance" % event)
		if data.events.has(event + "_panicked"):
			check(Barks.chance_for(event + "_panicked") > 0.0, "%s_panicked has a chance" % event)
			check(not data.events[event + "_panicked"].get("any", []).is_empty(), "%s_panicked has 'any' lines" % event)
	var panicked := 0
	for event in data.events:
		if str(event).ends_with("_panicked"):
			panicked += 1
	check(panicked >= 15, "a good share of the events have panicked variants (%d)" % panicked)
	for type in TYPES:
		check(Barks.has_lines("spotted", type), "%s has its own voice" % type)
	# A panicked NPC uses the panicked line.
	var npc := _enemy(Vector2(300, 0), Personality.Type.SCAVENGER)
	_arena.player = _mecha(Vector2.ZERO, "Drifter")
	_arena.player.mecha_name = "Player"
	npc.knowledge.panic = 0.9
	data.chances["taking_fire_panicked"] = 1.0
	npc._bark_ready_ms = 0
	Barks.reset_cooldown()
	check(npc.bark("taking_fire"), "a panicked NPC barks")
	var said: String = _spoken[_spoken.size() - 1] if not _spoken.is_empty() else ""
	var panicked_lines: Array = data.events["taking_fire_panicked"].get("scavenger", []) + data.events["taking_fire_panicked"].get("any", [])
	check(panicked_lines.has(said), "the panicked line (%s)" % said)
