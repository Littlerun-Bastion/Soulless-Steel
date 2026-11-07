extends TestSuite

# InfoSystemsTest: NPCs using the information systems (Phase 6 of the AI
# brief). A Local help call or loot shout becomes a lead at a position
# blurred once within 150 m of the sender, never the true spot, kept a
# minute; an NPC acts on the blurred spot (the fairness rule). Help: a
# Guardian answers a call it rolled for and goes to the lead, a Scavenger
# rarely, a Hunter never; a squadmate under fire and hurt is helped at once;
# a helper that sees the caller hit turns on the attacker. Vulture: a Hunter
# that hears gunfire waits off the fight, dark, and once it goes quiet takes
# whoever it sees there as prey; a Scavenger never. Scout: a Professional
# with a sweep ready looks before a long trip, once, not again for a while;
# a Scavenger never. Rats lie: a fake loot shout from an ambush, a fake help
# call that lures. Suspicion: an Anonymous pilot gets more hostility on first
# sight; a sweep makes the swept suspicious of everyone in sight, sends a
# Scavenger away from the spot and a Hunter's sweep back. A destroyed device
# is a lead. Car alarms: Hunters and the greedy go, Scavengers keep away,
# others ignore them. A tagged squad's size on the roster weighs on a fight.
# Hunters follow heat trails from the last-known spot. Any wreck teaches its
# killer's name.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const WARD := "WD-2"


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


class FakeWreck extends Node2D:
	var is_open := false
	var npc_searched := false
	var kill_record := {}
	func interact(_by) -> void:
		npc_searched = true


var _arena: FakeArena = null
var _spoken: Array = []


func run_tests() -> void:
	await case("a Local call is a lead at a blurred spot, kept a minute; an NPC acts on the blur", _test_leads)
	await case("help: a Guardian answers and goes, a Scavenger rarely, a Hunter never; a squadmate at once", _test_help)
	await case("vulture: a Hunter waits off a fight, dark, then preys on the survivor", _test_vulture)
	await case("scout: a Professional sweeps before a long trip, once in a while", _test_scout)
	await case("Rats lie: a fake loot shout from an ambush, a fake help call that lures", _test_rat_lies)
	await case("suspicion: an Anonymous pilot, and being swept", _test_suspicion)
	await case("a destroyed device, a car alarm and a tagged squad's size are information", _test_leads_of_the_world)
	await case("a Hunter follows a heat trail; any wreck teaches a killer's name", _test_trails_and_wrecks)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	_spoken.clear()
	Barks.reset_cooldown()
	PlayerProgress.reset()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	LocalPilots.current = _arena.local_pilots
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _design(internal := "") -> Dictionary:
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	if internal != "":
		design["internal"] = internal
	return design


# An NPC that thinks for itself, held still (paused) unless `run`, facing +x.
func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, run := false, design: Dictionary = PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var d: Dictionary = design.duplicate()
	d["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, d, "Info test %s %d" % [Personality.Type.keys()[type], _arena.mechas.size()])
	enemy.is_anonymous = false
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = not run
	enemy.spoke.connect(func(_m, text, _s, _a): _spoken.append(text))
	_arena.mechas.append(enemy)
	_arena.local_pilots.join(enemy)
	return enemy


# A plain mecha at `pos`, hot (seen at full range), held still.
func _mecha(pos: Vector2, callsign := "", anonymous := false, player_name := false) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(false)
	mecha.external_temp = 250.0
	mecha.arena = _arena
	mecha.is_anonymous = anonymous
	if player_name:
		mecha.mecha_name = "Player"
		mecha.callsign = "Drifter"
		_arena.player = mecha
	elif callsign != "":
		mecha.callsign = callsign
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	_arena.local_pilots.join(mecha)
	return mecha


func _test_leads() -> void:
	var npc := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	var caller := _mecha(Vector2(4000, 0), "Ash")
	_arena.local_pilots.broadcast(caller, "need_help")
	check_eq(npc.knowledge.local_leads.size(), 1, "the call is a lead")
	var lead: Dictionary = npc.knowledge.local_leads[0]
	check_eq(lead.kind, "need_help", "of its kind")
	check(lead.position != caller.global_position and lead.position.distance_to(caller.global_position) <= NPCKnowledge.LEAD_BLUR,
			"at a blurred spot within 150 m of the caller (%.0f px off)" % lead.position.distance_to(caller.global_position))
	var first: Vector2 = lead.position
	check_eq(npc.knowledge.help_leads()[0].position, first, "blurred once, the same spot every time it is read")
	_arena.local_pilots.broadcast(caller, "found_loot")
	check_eq(npc.knowledge.loot_leads().size(), 1, "a loot shout is a lead too")
	_arena.local_pilots.broadcast(npc, "need_help")
	check_eq(npc.knowledge.local_leads.size(), 2, "its own messages are no leads")
	_arena.local_pilots.broadcast(caller, "friendly")
	check_eq(npc.knowledge.local_leads.size(), 2, "nor chatter")
	npc.knowledge.contacts.now += NPCKnowledge.LEAD_MEMORY + 1.0
	npc.knowledge.age(0.0)
	check(npc.knowledge.local_leads.is_empty(), "leads are forgotten after a minute")
	# The fairness rule: the helper goes to the blur, not the caller.
	_arena.local_pilots.broadcast(caller, "need_help")
	lead = npc.knowledge.help_leads()[0]
	lead.answer = true
	npc.logic.force_intent(npc, "help")
	npc.logic.behaviour.do_help(0.1, npc)
	check(npc.logic.behaviour.point_of_interest == lead.position and npc.logic.behaviour.point_of_interest != caller.global_position,
			"it heads for the blurred spot, never the caller's true position")
	check(npc.logic.behaviour.helping() == caller, "and knows who it is going to help")


func _test_help() -> void:
	var caller := _mecha(Vector2(3000, 0), "Ash")
	var guardian := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	var scavenger := _enemy(Vector2(0, 600), Personality.Type.SCAVENGER)
	var hunter := _enemy(Vector2(0, -600), Personality.Type.HUNTER)
	check_eq(guardian.logic.behaviour.HELP_CHANCE[Personality.Type.GUARDIAN], 0.9, "a Guardian answers nine calls in ten")
	check_eq(scavenger.logic.behaviour.HELP_CHANCE[Personality.Type.SCAVENGER], 0.1, "a Scavenger one in ten")
	check_eq(hunter.logic.behaviour.HELP_CHANCE[Personality.Type.HUNTER], 0.0, "a Hunter never")
	_arena.local_pilots.broadcast(caller, "need_help")
	var answered := 0
	for i in 40:
		for lead in guardian.knowledge.help_leads():
			lead.answer = null
		if not guardian.logic.behaviour._help_lead_for(guardian).is_empty():
			answered += 1
	check(answered >= 25, "the Guardian's roll answers most of the time (%d of 40)" % answered)
	for lead in hunter.knowledge.help_leads():
		lead.answer = null
	check(hunter.logic.behaviour._help_lead_for(hunter).is_empty(), "the Hunter's never")
	var timid := 0
	for i in 40:
		for lead in scavenger.knowledge.help_leads():
			lead.answer = null
		if not scavenger.logic.behaviour._help_lead_for(scavenger).is_empty():
			timid += 1
	check(timid <= 12, "the Scavenger's mostly doesn't (%d of 40)" % timid)
	guardian.knowledge.help_leads()[0].answer = true
	guardian.logic.evaluate_now(guardian)
	check_eq(str(guardian.logic.get_current_state()), "help", "a Guardian with a call to answer helps")
	check(not guardian.logic.behaviour.wants_illuminator(guardian, "help"), "dark on the way: the light comes on only to engage")
	# Seeing the caller hit, it turns on the attacker.
	var attacker := _mecha(Vector2(3000, 800), "Bully")
	guardian.knowledge.see(caller, caller.global_position)
	guardian._on_attack_witnessed(attacker, caller)
	check_eq(guardian.get_relationship(attacker).hostility, guardian.HELP_HOSTILITY, "seeing the caller hit, it turns on the attacker")
	# A call from a pilot it hates goes unanswered.
	var hated := _mecha(Vector2(-3000, 0), "Enemy")
	guardian.add_hostility(hated, 0.5)
	_arena.local_pilots.broadcast(hated, "need_help")
	var from_hated: Dictionary = guardian.knowledge.help_leads()[0]
	check(from_hated.sender == hated, "the newest lead is the hated pilot's")
	check(not guardian.logic.behaviour._answers_call(guardian, from_hated), "and it isn't answered")
	# A squadmate in trouble comes first, wherever it is.
	var mate := _enemy(Vector2(2000, 2000), Personality.Type.PROFESSIONAL)
	var squad := Squad.new()
	squad.setup("HLX", false)
	squad.add(mate)
	squad.add(guardian)
	mate.under_fire_timer = 0.5
	mate.hp = mate.max_hp * 0.3
	guardian.logic.force_intent(guardian, "roam")
	guardian.logic.evaluate_now(guardian)
	check_eq(str(guardian.logic.get_current_state()), "help", "a squadmate under fire and hurt is helped")
	check(guardian.logic.behaviour.helping() == mate, "that squadmate")
	check_eq(guardian.logic.scores.get("help"), guardian.logic.behaviour.SCORE_HELP_SQUAD, "above a stranger's call")
	guardian.logic.behaviour.do_help(0.1, guardian)
	check_eq(guardian.logic.behaviour.point_of_interest, mate.global_position, "going to where it is (squad radio)")
	mate.under_fire_timer = 0.0
	guardian.logic.evaluate_now(guardian)
	check(str(guardian.logic.get_current_state()) != "help" or guardian.logic.behaviour.helping() != mate, "and done once the mate is out of trouble")


func _test_vulture() -> void:
	var hunter := _enemy(Vector2.ZERO, Personality.Type.HUNTER)
	var scavenger := _enemy(Vector2(0, 800), Personality.Type.SCAVENGER)
	var shot := {"volume_type": "loud", "type": "shooting", "position": Vector2(4000, 0), "source": null}
	hunter.heard_sound(shot)
	scavenger.heard_sound(shot)
	hunter.logic.evaluate_now(hunter)
	scavenger.logic.evaluate_now(scavenger)
	check_eq(str(hunter.logic.get_current_state()), "vulture", "a Hunter in good shape that hears gunfire vultures")
	check(str(scavenger.logic.get_current_state()) != "vulture", "a Scavenger doesn't (%s)" % str(scavenger.logic.get_current_state()))
	check(not hunter.logic.behaviour.wants_illuminator(hunter, "vulture"), "dark")
	# It can't see the fight, so it goes by its sound wedge's estimate point.
	var wedges: Array = hunter.contacts.wedges({"source": "sound"})
	check(wedges.size() == 1 and ContactStore.wedge_contains(wedges[0], Vector2(4000, 0)), "the gunfire is a sound wedge round the fight")
	if wedges.size() == 1:
		check_eq(hunter.logic.behaviour._vulture_point, ContactStore.estimate_point(wedges[0]), "toward the fight it heard, as it makes it out")
	var survivor := _mecha(Vector2(1500, 0), "Winner")
	hunter.knowledge.see(survivor, survivor.global_position)
	hunter.logic.behaviour.do_vulture(0.1, hunter)
	check_eq(hunter.get_relationship(survivor).hostility, 0.0, "while the shooting goes on, nobody is prey yet")
	for sound in hunter.knowledge.sounds:
		sound.lifetime = hunter.SOUND_LIFETIME - hunter.logic.behaviour.VULTURE_QUIET - 1.0
	hunter.logic.behaviour.do_vulture(0.1, hunter)
	check_eq(hunter.get_relationship(survivor).hostility, hunter.logic.behaviour.VULTURE_HOSTILITY, "once it is quiet, the survivor it sees is prey")
	check_eq(hunter.logic.behaviour._vulture_point, survivor.global_position, "and it closes on it")
	hunter.logic.behaviour._check_targets(hunter)
	check(is_same(hunter.valid_target, survivor), "and its target")
	hunter.logic.intent_time = 5.0
	hunter.logic.evaluate_now(hunter)
	check_eq(str(hunter.logic.get_current_state()), "engage", "so it attacks")
	# Gunfire and then nobody to see: it goes in to look, then is done with it.
	var lone := _enemy(Vector2(-6000, 6000), Personality.Type.HUNTER)
	var behaviour = lone.logic.behaviour
	var lone_shot := shot.duplicate()
	lone_shot.position = Vector2(-6000, 2500)
	lone.heard_sound(lone_shot)
	lone.logic.evaluate_now(lone)
	check_eq(str(lone.logic.get_current_state()), "vulture", "(a lone Hunter vultures a lone shot)")
	for sound in lone.knowledge.sounds:
		sound.lifetime = lone.SOUND_LIFETIME - behaviour.VULTURE_QUIET - 1.0
	behaviour.do_vulture(0.1, lone)
	var heading = behaviour.point_of_interest
	check(lone.going_to_position and heading is Vector2
			and heading.distance_to(behaviour._vulture_point) < lone.global_position.distance_to(behaviour._vulture_point) - 1000.0,
			"quiet with nobody in sight, it goes in to look (to %s)" % str(heading))
	check(not behaviour._vulture_looked and lone.logic.behaviour.score_vulture(lone) > 0.0, "still vulturing on the way")
	lone.global_position = behaviour._vulture_point + Vector2(0, behaviour.VULTURE_LOOK)
	behaviour.do_vulture(0.1, lone)
	check(behaviour._vulture_looked and behaviour.score_vulture(lone) == 0.0, "there, nobody: it's done")
	lone.logic.intent_time = 5.0
	lone.logic.evaluate_now(lone)
	check(str(lone.logic.get_current_state()) != "vulture", "and goes on (%s)" % str(lone.logic.get_current_state()))
	check_eq(behaviour.score_vulture(lone), 0.0, "the same gunfire doesn't bring it back")
	lone.contacts.advance(1.0)
	lone.heard_sound(lone_shot)
	check(behaviour.score_vulture(lone) > 0.0, "new gunfire does")
	# Running hot, it doesn't vulture.
	var hot := _enemy(Vector2(0, -800), Personality.Type.HUNTER)
	hot.heard_sound(shot)
	check(hot.logic.behaviour.score_vulture(hot) > 0.0, "a Hunter in good shape would vulture")
	hot.internal_temp = hot.overheat_temp
	hot.knowledge.refresh_state()
	check_eq(hot.logic.behaviour.score_vulture(hot), 0.0, "not one running hot")


func _test_scout() -> void:
	var pro := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	var scavenger := _enemy(Vector2(0, 800), Personality.Type.SCAVENGER)
	check(pro.fire.can_sweep(), "its sweep is ready")
	pro.logic.behaviour.point_of_interest = Vector2(5000, 0)
	scavenger.logic.behaviour.point_of_interest = Vector2(5000, 800)
	pro.logic.evaluate_now(pro)
	scavenger.logic.evaluate_now(scavenger)
	check_eq(str(pro.logic.get_current_state()), "scout", "a Professional about to travel far scouts first")
	check(str(scavenger.logic.get_current_state()) != "scout", "a Scavenger doesn't")
	check(not pro.logic.behaviour.wants_illuminator(pro, "scout"), "dark while it looks")
	pro.logic.behaviour.do_scout(0.1, pro)
	check(not pro.fire.can_sweep(), "it swept")
	check_eq(pro.logic.behaviour._scout_goal, Vector2.INF, "and is done")
	# (An intent is held a second after a switch; the test is past that.)
	pro.logic.intent_time = 5.0
	pro.logic.evaluate_now(pro)
	check(str(pro.logic.get_current_state()) != "scout", "back to its trip (%s)" % str(pro.logic.get_current_state()))
	check(pro.logic.behaviour.point_of_interest == Vector2(5000, 0) and pro.going_to_position, "which goes on where it was going")
	pro.sweep_cooldown = 0.0
	check_eq(pro.logic.behaviour.score_scout(pro), 0.0, "not again for a while")
	pro.logic.behaviour._scouted_at = -INF
	pro.logic.behaviour.point_of_interest = Vector2(500, 0)
	check_eq(pro.logic.behaviour.score_scout(pro), 0.0, "nor before a short hop")
	pro.knowledge.took_fire_from(Vector2(700, 0))
	check(pro.logic.behaviour.score_scout(pro) > 0.0, "but before a hop into ground it took fire on")


func _test_rat_lies() -> void:
	var rat := _enemy(Vector2.ZERO, Personality.Type.RAT)
	var listener := _enemy(Vector2(3000, 0), Personality.Type.SCAVENGER)
	var lines := []
	_arena.local_pilots.message.connect(func(entry): lines.append(entry))
	rat.personality.treachery = 1.0
	var lied := false
	for i in 20:
		rat.logic.behaviour._lure_until = -INF
		rat.logic.behaviour.enter_ambush(rat)
		if lines.any(func(e): return e.kind == "found_loot" and e.sender == rat):
			lied = true
			break
	check(lied, "a Rat baits its ambush with a loot shout that isn't true")
	check(not listener.knowledge.loot_leads().is_empty(), "and a Scavenger that reads it has a lead to a crate that isn't there")
	rat.logic.behaviour._lure(rat)
	check(lines.any(func(e): return e.kind == "need_help" and e.sender == rat), "a Rat's lure is a help call it doesn't need")
	rat.logic.evaluate_now(rat)
	check_eq(str(rat.logic.get_current_state()), "ambush", "then it lies in wait")
	check(listener.logic.behaviour.score_help(listener) == 0.0 or listener.knowledge.help_leads().size() == 1, "the listener has the call as a lead")
	check(AICombatLog.enabled() == false or AICombatLog.info_count("rat_lie") >= 2, "the log counts the lies")


func _test_suspicion() -> void:
	var npc := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	var named := _enemy(Vector2(800, 0), Personality.Type.PROFESSIONAL)
	var nameless := _enemy(Vector2(0, 800), Personality.Type.PROFESSIONAL)
	nameless.is_anonymous = true
	npc.knowledge.see(named, named.global_position)
	npc.knowledge.see(nameless, nameless.global_position)
	# Kin seed 0 with a jitter of a tenth either way; the Anonymous one gets
	# SUSPICION_ANONYMOUS on top.
	check(npc.get_relationship(named).hostility <= 0.1 and npc.get_relationship(nameless).hostility >= npc.SUSPICION_ANONYMOUS - 0.1,
			"a pilot with no name gets more hostility on first sight (%.2f vs %.2f)" % [npc.get_relationship(nameless).hostility, npc.get_relationship(named).hostility])
	# Swept: panic, suspicion of everyone in sight, a Scavenger keeps away, a
	# Hunter sweeps back.
	var before: float = npc.get_relationship(named).hostility
	npc.swept.emit()
	check(npc.knowledge.swept_count == 1 and npc.knowledge.swept_at == npc.knowledge.now(), "it knows when it was swept")
	check(is_equal_approx(npc.get_relationship(named).hostility, before + npc.SWEPT_SUSPICION), "and trusts everyone in sight a little less")
	var scavenger := _enemy(Vector2(0, -800), Personality.Type.SCAVENGER)
	scavenger.swept.emit()
	check(scavenger.knowledge.avoids(scavenger.global_position, 100.0), "a swept Scavenger keeps away from the spot")
	var far := 0
	for i in 10:
		scavenger.going_to_position = false
		scavenger.logic.behaviour._wander_if_idle(scavenger)
		if not scavenger.knowledge.avoids(scavenger.logic.behaviour.point_of_interest, scavenger.logic.behaviour.AVOID_RADIUS):
			far += 1
	check_eq(far, 10, "and wanders clear of it")
	var hunter := _enemy(Vector2(-800, 0), Personality.Type.HUNTER)
	check(hunter.fire.can_sweep(), "the Hunter's sweep is ready")
	hunter.swept.emit()
	check(hunter.fire.can_sweep() and hunter._sweep_back_due, "a swept Hunter doesn't sweep back inside the signal (two would never stop)")
	hunter._tick_sweep_back(0.1)
	check(not hunter.fire.can_sweep(), "it sweeps back on its next think")
	hunter.sweep_cooldown = 0.0
	hunter.swept.emit()
	hunter._tick_sweep_back(0.1)
	check(hunter.fire.can_sweep(), "and not again within its sweep-back cooldown")
	# Two Hunters sweeping each other: it ends.
	var other := _enemy(Vector2(-800, 600), Personality.Type.HUNTER)
	other.paused = false
	hunter.paused = false
	hunter._swept_back_at = -INF
	hunter.sweep_cooldown = 0.0
	other.fire.sweep(Vector2.LEFT, 360.0)
	await wait_seconds(1.0)
	check(true, "no stack overflow when Hunters sweep each other")
	hunter.paused = true
	other.paused = true


func _test_leads_of_the_world() -> void:
	# A destroyed device is a lead at its spot.
	var carrier := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL, false, _design(WARD))
	carrier.use_internal()
	await wait_frames(2)
	var wards: Array = Device.owned_by(carrier)
	check_eq(wards.size(), 1, "the ward is out")
	if wards.size() == 1:
		var at: Vector2 = wards[0].global_position
		wards[0].destroy()
		await wait_frames(1)
		var lead = carrier.get_most_recent_loud_noise()
		check(lead and lead.type == "device" and lead.position == at, "its loss is a loud lead where it stood")
		carrier.logic.intent_time = 5.0
		carrier.logic.evaluate_now(carrier)
		check_eq(str(carrier.logic.get_current_state()), "investigate", "which it investigates")
	# Car alarms by personality.
	var alarm := {"volume_type": "loud", "type": "car_alarm", "position": Vector2(2000, 0), "source": null}
	var hunter := _enemy(Vector2(0, 1000), Personality.Type.HUNTER)
	var greedy := _enemy(Vector2(0, 2000), Personality.Type.PROFESSIONAL)
	greedy.personality.greed = 0.9
	var pro := _enemy(Vector2(0, 3000), Personality.Type.PROFESSIONAL)
	var scavenger := _enemy(Vector2(0, 4000), Personality.Type.SCAVENGER)
	for m in [hunter, greedy, pro, scavenger]:
		m.heard_sound(alarm)
		check(m.get_most_recent_loud_noise() and m.get_most_recent_loud_noise().type == "car_alarm", "%s hears the alarm" % m.mecha_name)
	check(hunter.get_loud_lead() and greedy.get_loud_lead(), "a Hunter and a greedy pilot take a car alarm as a lead")
	check(not pro.get_loud_lead() and pro.logic.behaviour.score_investigate(pro) == 0.0, "a Professional of ordinary greed doesn't act on it")
	check(not scavenger.get_loud_lead() and scavenger.knowledge.avoids(Vector2(2000, 0), 100.0), "a Scavenger keeps away from it")
	# A tagged squad's size on the roster.
	var a := _mecha(Vector2(5000, 0), "One")
	var b := _mecha(Vector2(5000, 600), "Two")
	var c := _mecha(Vector2(5000, 1200), "Three")
	for m in [a, b, c]:
		m.squad_tag = "KRV"
	check_eq(_arena.local_pilots.count_tag("KRV"), 3, "the roster shows a tagged squad's size")
	check_eq(pro.known_squad_size(a), 3, "an NPC reads it")
	a.is_anonymous = true
	check_eq(pro.known_squad_size(a), 1, "not for an Anonymous pilot")
	check_eq(pro.known_squad_size(carrier), 1, "nor one with no tag")
	var lone := _mecha(Vector2(6000, 0), "Lone")
	var in_squad := _mecha(Vector2(6000, 600), "Squadded")
	in_squad.squad_tag = "KRV"
	var alone_fight: bool = pro.should_engage(lone)
	var squad_fight: bool = pro.should_engage(in_squad)
	check(alone_fight or not squad_fight, "a member of a known squad is a bigger threat than a lone pilot (alone %s, squad %s)" % [alone_fight, squad_fight])


func _test_trails_and_wrecks() -> void:
	var trails := HeatTrails.new()
	_arena.add_child(trails)
	var hunter := _enemy(Vector2(900, 0), Personality.Type.HUNTER)
	var quarry := _mecha(Vector2(1200, 0), "Quarry")
	hunter.mark_traitor(quarry)
	hunter.knowledge.see(quarry, quarry.global_position)
	hunter.logic.behaviour._check_targets(hunter)
	check(hunter.valid_target == quarry, "the quarry is its target")
	hunter.logic.force_intent(hunter, "engage")
	hunter.knowledge.contacts.advance(3.0)
	hunter.knowledge.end_sight_update()
	hunter.logic.intent_time = 5.0
	hunter.logic.evaluate_now(hunter)
	check_eq(str(hunter.logic.get_current_state()), "search", "a Hunter that lost its quarry in a fight searches")
	hunter.logic.behaviour._follow_trail(hunter, Vector2(1200, 0))
	check(hunter.logic.behaviour._trail_said and not hunter.logic.behaviour._trail_found, "with no marks about, the trail is cold")
	check_eq(hunter.logic.behaviour._trail_point, Vector2.INF, "and there is no step to take")
	trails.add_mark(Vector2(1300, 50), Vector2.DOWN, HeatTrails.FOOT_SIZE, 0.9, HeatTrails.Kind.FOOT)
	trails.add_mark(Vector2(1100, -50), Vector2.UP, HeatTrails.FOOT_SIZE, 0.3, HeatTrails.Kind.FOOT)
	hunter.logic.behaviour._follow_trail(hunter, Vector2(1200, 0))
	check_eq(hunter.logic.behaviour._trail_point, Vector2(1300, 50) + Vector2.DOWN * hunter.logic.behaviour.TRAIL_STEP,
			"the warmest mark near the spot gives the next step, along its heading")
	check(hunter.logic.behaviour._trail_found, "the trail is found")
	# Any wreck teaches its killer's name; only a squadmate's wreck a grudge.
	var killer := _mecha(Vector2(3000, 0), "Drifter")
	var wreck := FakeWreck.new()
	wreck.kill_record = {"victim": "Nobody", "killer": "Drifter"}
	_arena.add_child(wreck)
	hunter.logic.behaviour._read_kill_record(hunter, wreck)
	check(hunter.knowledge.killers.has("Drifter"), "a stranger's wreck teaches the killer's name")
	check_eq(hunter.get_relationship(killer).hostility, 0.0, "with no grudge")
