extends TestSuite

# FlagTest: the Flag, panic and mines (Phase 3 of the AI brief). A Flag is
# raised at once and lowered with a visible wind-up; it locks the weapons but
# not the smoke launcher or the internal bay; the emergency state is a Flag
# too, and lowering it keeps the capsule exposed; the HUD says which; the
# pilot whose damage pressed a mecha into its Flag is named with the signal.
# NPCs respect a Flag by personality, and a low reputation makes some ignore
# the player's. Lowering a Flag raised by choice and attacking makes a
# traitor of the player and costs reputation; lowering an emergency Flag
# doesn't. Witnesses of a shot at a Flagged mech turn hostile, Guardians
# most. Killing a Flagged pilot costs more; sparing one pays. A losing,
# panicked Scavenger surrenders: Flag up, a plea in Local, the flight; a Rat
# may lower it again behind its sparer's back. A Rat executes a Flagged mech
# after a bark and the grace window's length; a Rat stalks a distracted
# target with its Flag up and lowers it close behind; a Guardian goes to a
# Flagged mech that isn't hostile. Panic rises with hits and fire, falls when
# calm, scales with courage and spoils the aim. A calm NPC sees a mine and
# steers clear; a panicked one may miss it. The stage step sets an actor's
# Flag.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER_SCRIPT := preload("res://game/mecha/player/Player.gd")
const MINE := preload("res://database/parts/mine.gd")
const SMOKE_LAUNCHER := "MA-SL6"
const MINE_LAYER := "MA-ML1"


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	var local_pilots := LocalPilots.new()
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
var _spoken: Array = []


func run_tests() -> void:
	await case("a Flag goes up at once and comes down with a wind-up; weapons lock, smoke and the bay don't", _test_flag)
	await case("the emergency Flag is a Flag; lowering it keeps the capsule exposed; the HUD; the key", _test_emergency_and_hud)
	await case("the pilot that pressed a mecha into its Flag is named", _test_pressure)
	await case("NPCs respect a Flag by personality; a low reputation makes some ignore the player's", _test_respect)
	await case("lowering a Flag raised by choice and attacking is treachery; an emergency Flag isn't", _test_treachery)
	await case("a witness of a shot at a Flagged mech turns hostile, a Guardian most", _test_witness)
	await case("killing a Flagged pilot costs reputation; sparing one pays", _test_kill_and_spare)
	await case("a losing, panicked Scavenger surrenders and is spared; a Rat may fake it", _test_surrender)
	await case("a Rat executes a Flagged mech: a bark, then the grace window's length before it fires", _test_execute)
	await case("a Rat stalks a distracted target with its Flag up and lowers it behind its back", _test_stalk)
	await case("a Guardian goes to a Flagged mech that isn't hostile", _test_protect)
	await case("panic rises with hits and fire, falls when calm, scales with courage, spoils the aim", _test_panic)
	await case("a calm NPC sees a mine and steers clear; a panicked one may miss it", _test_mines)
	await case("the stage step sets an actor's Flag", _test_stage_step)


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
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


# A design with `weapon` on the left shoulder (a core with one) and
# `internal` in the bay.
func _design(weapon := "", internal := "") -> Dictionary:
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	if weapon != "":
		design["shoulder_weapon_left"] = weapon
		for core_id in PartManager.get_parts("core"):
			if PartManager.get_part("core", core_id).has_left_shoulder:
				design["core"] = core_id
				break
	if internal != "":
		design["internal"] = internal
	return design


# A plain mecha at `pos`, facing +x, held still, wired to Local as a scene
# would; `player_name` makes it the player as the game tells (is_player).
func _mecha(pos: Vector2, design: Dictionary = PlayerProgress.DEFAULT_MECHA, player_name := false) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.arena = _arena
	mecha.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	if player_name:
		mecha.mecha_name = "Player"
		mecha.callsign = "Drifter"
	mecha.set_pause(true)
	_wire(mecha)
	_arena.mechas.append(mecha)
	return mecha


# An NPC that thinks for itself, held still unless `run`, facing +x.
func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, design: Dictionary = PlayerProgress.DEFAULT_MECHA, run := false) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var d: Dictionary = design.duplicate()
	d["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, d, "Flag test %s" % Personality.Type.keys()[type])
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = not run
	_wire(enemy)
	enemy.spoke.connect(func(_m, text, _s, _a): _spoken.append(text))
	_arena.mechas.append(enemy)
	return enemy


# The Flag's signals go to Local, as CombatScene connects them.
func _wire(mecha) -> void:
	var local: LocalPilots = _arena.local_pilots
	mecha.flag_raised.connect(func(m, voluntary, _by): local.note_flag_raised(m, voluntary))
	mecha.flag_lowered.connect(func(m): local.note_flag_lowered(m))


func _count_shots(mecha) -> Array:
	var shots := [0]
	mecha.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	return shots


func _source(attacker) -> Dictionary:
	return {"body": attacker, "name": attacker.mecha_name}


# A hit from attacker as the victim hears of it (Mecha.register_hit), worth
# `amount` pressure.
func _hit(victim, attacker, amount := 5.0) -> void:
	victim.register_hit(_source(attacker), amount)


# Scores every intent as if the minimum time were over, and gives the winner.
func _decide(enemy) -> String:
	enemy.knowledge.refresh_state()
	enemy.logic.intent_time = 10.0
	enemy.logic.evaluate_now(enemy)
	return str(enemy.logic.get_current_state())


# Every line's bark lands for sure.
func _rig_barks() -> void:
	for event in Barks.data().chances:
		Barks.data().chances[event] = 1.0


func _test_flag() -> void:
	var mecha := _mecha(Vector2.ZERO, _design(SMOKE_LAUNCHER, "DC-2"))
	mecha.set_pause(false)
	var raised := []
	var lowered := [0]
	var started := [0]
	mecha.flag_raised.connect(func(_m, voluntary, _by): raised.append(voluntary))
	mecha.flag_lowering_started.connect(func(_m): started[0] += 1)
	mecha.flag_lowered.connect(func(_m): lowered[0] += 1)
	check(not mecha.is_flagged(), "the Flag starts down")
	mecha.raise_flag()
	check(mecha.is_flagged() and mecha.flag_voluntary and not mecha.is_exposed, "raised by choice, at once, with the capsule intact")
	check_eq(raised, [true], "the signal says so")
	check(is_instance_valid(mecha._flag_marker) and mecha._flag_marker.voluntary, "the marker shows a raised Flag")
	var shots := _count_shots(mecha)
	mecha.shoot("arm_weapon_left")
	mecha.shoot("arm_weapon_left")
	check_eq(shots[0], 0, "the guns are locked")
	check_eq(mecha.can_fire_at_point("shoulder_weapon_left", mecha.global_position), "", "the smoke launcher isn't")
	check_eq(mecha.can_use_internal(), "", "nor the internal bay (a decoy)")
	mecha.lower_flag()
	check(mecha.is_lowering_flag() and mecha.is_flagged(), "lowering it takes a wind-up, during which it is still up")
	check_eq(started[0], 1, "the wind-up is announced")
	check_eq(mecha.can_fire_at_point("arm_weapon_left", Vector2(500, 0)), "flagged", "the guns stay locked meanwhile")
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	check(not mecha.is_flagged() and not mecha.is_lowering_flag(), "then it is down")
	check_eq(lowered[0], 1, "the signal says so")
	check(not is_instance_valid(mecha._flag_marker), "and the marker is gone")
	mecha.raise_flag()
	mecha.lower_flag()
	mecha.raise_flag()
	check(mecha.is_flagged() and not mecha.is_lowering_flag(), "raising it during the wind-up puts it back up")
	# The key.
	PLAYER_SCRIPT.ensure_flag_key_action()
	check(InputMap.has_action(PLAYER_SCRIPT.FLAG_ACTION), "the Flag key action exists")


func _test_emergency_and_hud() -> void:
	var mecha := _mecha(Vector2.ZERO)
	mecha.set_pause(false)
	var alerts := HudAlerts.new()
	add_child(alerts)
	alerts.setup(mecha)
	alerts._process(0.0)
	check_eq(alerts.get_current(), "", "nothing to say with the Flag down")
	mecha.raise_flag()
	alerts._process(0.0)
	check_eq(alerts.get_current(), "! FLAG RAISED · WEAPONS LOCKED", "the HUD says a Flag raised by choice")
	mecha.lower_flag()
	alerts._process(0.0)
	check_eq(alerts.get_current(), "! LOWERING FLAG", "and the wind-up")
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	mecha.enter_flagged_state()
	check(mecha.is_flagged() and not mecha.flag_voluntary and mecha.is_exposed, "the emergency state raises the Flag, not by choice")
	alerts._process(0.0)
	check_eq(alerts.get_current(), "! FLAGGED · CAPSULE EXPOSED · WEAPONS LOCKED", "the HUD says the emergency Flag")
	mecha.flag_grace = 0.0
	mecha.lower_flag()
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	check(not mecha.is_flagged() and mecha.is_exposed, "lowering it leaves the capsule exposed")
	alerts._process(0.0)
	check_eq(alerts.get_current(), "! CAPSULE EXPOSED", "and the HUD says so")
	mecha.raise_flag(false)
	check(mecha.is_flagged() and not mecha.flag_voluntary, "raising it again while exposed is the emergency Flag")
	alerts.queue_free()


func _test_pressure() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var a := _mecha(Vector2(1000, 0))
	var b := _mecha(Vector2(-1000, 0))
	mecha.contacts.advance(1.0)
	_hit(mecha, a, 2.0)
	_hit(mecha, b, 6.0)
	_hit(mecha, a, 2.0)
	check(is_same(mecha.pressured_by(), b), "the pilot that did the most damage lately")
	var got := []
	mecha.flag_raised.connect(func(_m, voluntary, by): got.append([voluntary, by]))
	mecha.enter_flagged_state()
	check(got.size() == 1 and got[0][0] == false and is_same(got[0][1], b), "the Flag's signal names it")
	mecha.contacts.advance(Mecha.PRESSURE_WINDOW + 1.0)
	check(mecha.pressured_by() == null, "old damage is forgotten")


func _test_respect() -> void:
	var target := _mecha(Vector2(800, 0))
	target.raise_flag()
	var expect := {Personality.Type.SCAVENGER: false, Personality.Type.GUARDIAN: false,
			Personality.Type.PROFESSIONAL: false, Personality.Type.HUNTER: false, Personality.Type.RAT: true}
	var y := 0.0
	for type in expect:
		var npc := _enemy(Vector2(0, y), type)
		y += 600.0
		check_eq(npc.should_attack(target), expect[type], "%s attacks a Flagged mech: %s" % [Personality.Type.keys()[type], expect[type]])
	# The reputation roll.
	var player := _mecha(Vector2(3000, 0), PlayerProgress.DEFAULT_MECHA, true)
	player.raise_flag()
	var ignoring := 0
	for i in 10:
		var npc := _enemy(Vector2(3000, 600 + 500 * i), Personality.Type.PROFESSIONAL)
		if npc.knowledge.ignores_player_flag:
			ignoring += 1
	check_eq(ignoring, 0, "with a clean reputation nobody ignores the player's Flag")
	PlayerProgress.add_reputation(-100, false)
	ignoring = 0
	var ignorer = null
	for i in 10:
		var npc := _enemy(Vector2(-3000, 600 + 500 * i), Personality.Type.PROFESSIONAL)
		if npc.knowledge.ignores_player_flag:
			ignoring += 1
			ignorer = npc
	check(ignoring > 0, "with a reputation of -100 some do (%d of 10)" % ignoring)
	if ignorer != null:
		ignorer.add_hostility(player, 1.0)
		check(ignorer.should_attack(player), "and one that does attacks the Flagged player")
	var rat := _enemy(Vector2(-3000, -600), Personality.Type.RAT)
	check(rat.knowledge.ignores_player_flag, "a Rat always does")


func _test_treachery() -> void:
	var local: LocalPilots = _arena.local_pilots
	var player := _mecha(Vector2(800, 0), PlayerProgress.DEFAULT_MECHA, true)
	player.set_pause(false)
	var npc := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	player.raise_flag()
	npc.update_senses(0.1)
	check(npc.saw_flag_raised(player), "the NPC saw the player raise the Flag")
	player.lower_flag()
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	npc.update_senses(0.1)
	check(npc.knowledge.flag_lowered_recently(player, 10.0), "and saw it come down")
	var before := PlayerProgress.get_reputation()
	_hit(npc, player)
	check(npc.get_relationship(player).is_traitor, "shot right after, it marks the player a traitor")
	check_eq(PlayerProgress.get_reputation(), before + LocalPilots.TREACHERY_REPUTATION, "and the reputation drops")
	_hit(npc, player)
	check_eq(PlayerProgress.get_reputation(), before + LocalPilots.TREACHERY_REPUTATION, "once per lowering")
	# A pilot that saw the player Flagged, attacked later.
	var witness := _enemy(Vector2(0, 800), Personality.Type.SCAVENGER)
	player.raise_flag()
	witness.update_senses(0.1)
	player.lower_flag()
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	local.now += LocalPilots.TREACHERY_WINDOW + 5.0
	before = PlayerProgress.get_reputation()
	_hit(witness, player)
	check_eq(PlayerProgress.get_reputation(), before + LocalPilots.TREACHERY_REPUTATION, "attacking a pilot that saw you Flagged costs the same, past the window")
	# An emergency Flag lowered to fight back: no treachery.
	var downed := _mecha(Vector2(-800, 0), PlayerProgress.DEFAULT_MECHA, true)
	downed.set_pause(false)
	var other := _enemy(Vector2(-800, 1200), Personality.Type.PROFESSIONAL)
	downed.enter_flagged_state()
	other.update_senses(0.1)
	downed.flag_grace = 0.0
	downed.lower_flag()
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	other.update_senses(0.1)
	before = PlayerProgress.get_reputation()
	_hit(other, downed)
	check(not other.get_relationship(downed).is_traitor, "no traitor's mark for fighting back from the emergency Flag")
	check_eq(PlayerProgress.get_reputation(), before, "and no cost")


func _test_witness() -> void:
	# Within a cold mecha's sight range (60% of 2,000 px).
	var attacker := _mecha(Vector2(900, 0))
	var victim := _mecha(Vector2(900, 500))
	victim.raise_flag()
	var guardian := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	var pro := _enemy(Vector2(0, 500), Personality.Type.PROFESSIONAL)
	var blind := _enemy(Vector2(0, -6000), Personality.Type.GUARDIAN)
	for npc in [guardian, pro, blind]:
		npc.update_senses(0.1)
	check(guardian.is_seeing(attacker) and guardian.is_seeing(victim), "the Guardian sees both")
	check(not blind.is_seeing(attacker) and not blind.is_seeing(victim), "a far NPC sees neither")
	_hit(victim, attacker)
	check(guardian.get_relationship(attacker).hostility >= guardian.WITNESS_HOSTILITY_GUARDIAN, "the Guardian turns hostile to the shooter")
	check(pro.get_relationship(attacker).hostility >= pro.WITNESS_HOSTILITY and pro.get_relationship(attacker).hostility < guardian.get_relationship(attacker).hostility, "the Professional less so")
	check_eq(blind.get_relationship(attacker).hostility, 0.0, "the one that saw nothing is unmoved")


func _test_kill_and_spare() -> void:
	var local: LocalPilots = _arena.local_pilots
	var player := _mecha(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA, true)
	var victim := _mecha(Vector2(800, 0))
	victim.raise_flag()
	check_eq(local.score_player_kill(player, victim), LocalPilots.FLAGGED_KILL_REPUTATION, "killing a Flagged pilot")
	check_eq(PlayerProgress.get_reputation(), LocalPilots.FLAGGED_KILL_REPUTATION, "costs reputation")
	var npc := _enemy(Vector2(0, 800), Personality.Type.SCAVENGER)
	npc.add_hostility(player, 0.75)
	local.note_spared(npc, player)
	check_eq(PlayerProgress.get_reputation(), LocalPilots.FLAGGED_KILL_REPUTATION + LocalPilots.SPARED_REPUTATION, "sparing one pays")
	check_eq(npc.get_relationship(player).hostility, 0.0, "and its hostility toward the player goes")
	check(npc.knowledge.spared_by.has(player.get_instance_id()), "it remembers who spared it")


func _test_surrender() -> void:
	var local: LocalPilots = _arena.local_pilots
	var got := []
	local.message.connect(func(entry): got.append(entry))
	var player := _mecha(Vector2(1000, 0), PlayerProgress.DEFAULT_MECHA, true)
	_arena.player = player
	var scav := _enemy(Vector2.ZERO, Personality.Type.SCAVENGER)
	local.join(scav)
	_rig_barks()
	scav.knowledge.see(player, player.global_position)
	scav.mark_traitor(player)
	scav.logic.behaviour._check_targets(scav)
	scav.logic.force_intent(scav, "engage")
	scav.logic.behaviour.stance = "attack"
	scav.current_target = player
	scav.logic.behaviour.aggression = -1.0
	_hit(scav, player)
	scav.knowledge.panic = 0.8
	check_eq(_decide(scav), "raise_flag", "losing and panicked, a Scavenger surrenders")
	check(scav.is_flagged() and scav.flag_voluntary, "its Flag is up, by choice")
	check(not got.filter(func(e): return e.kind == "surrender").is_empty(), "it pleads in Local")
	check(_spoken.size() > 0, "and out loud")
	check(not scav.logic.behaviour.wants_illuminator(scav, "raise_flag"), "and leaves dark")
	var behaviour = scav.logic.behaviour
	var before := PlayerProgress.get_reputation()
	# The hit before the surrender put it under fire for half a second; the
	# NPC is paused here, so that runs out by hand.
	scav.under_fire_timer = 0.0
	for i in 12:
		behaviour.do_raise_flag(1.0, scav)
	check_eq(PlayerProgress.get_reputation(), before + LocalPilots.SPARED_REPUTATION, "left alone for %.0f s, it was spared" % behaviour.SPARE_TIME)
	check_eq(scav.get_relationship(player).hostility, 0.0, "and holds nothing against the player")
	# Hurt by its sparer, it isn't.
	var other := _enemy(Vector2(0, 3000), Personality.Type.SCAVENGER)
	other.knowledge.see(player, player.global_position)
	_hit(other, player)
	other.logic.force_intent(other, "raise_flag")
	before = PlayerProgress.get_reputation()
	other.under_fire_timer = 0.5
	other.most_recent_attacker = player
	for i in 12:
		other.logic.behaviour.do_raise_flag(1.0, other)
	check_eq(PlayerProgress.get_reputation(), before, "shot at by its sparer, no reward")
	# A Rat fakes it: the sparer close and looking away, the Flag comes down.
	var rat := _enemy(Vector2(0, -3000), Personality.Type.RAT)
	var mark := _mecha(Vector2(500, -3000), PlayerProgress.DEFAULT_MECHA, true)
	rat.knowledge.see(mark, mark.global_position)
	_hit(rat, mark)
	rat.logic.force_intent(rat, "raise_flag")
	check(rat.is_flagged(), "the Rat's Flag is up")
	mark.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	rat.logic.behaviour.do_raise_flag(0.5, rat)
	check(rat.is_lowering_flag(), "its sparer close and facing away, it lowers the Flag again")
	check(is_same(rat.valid_target, mark), "with its sparer as its target")


func _test_execute() -> void:
	var player := _mecha(Vector2(0, 1000), PlayerProgress.DEFAULT_MECHA, true)
	_arena.player = player
	_rig_barks()
	var rat := _enemy(Vector2.ZERO, Personality.Type.RAT)
	var victim := _mecha(Vector2(700, 0))
	victim.raise_flag()
	rat.knowledge.see(victim, victim.global_position)
	rat.logic.behaviour._check_targets(rat)
	check(is_same(rat.valid_target, victim), "a Rat takes a Flagged mech as its target")
	check_eq(_decide(rat), "execute", "and executes it rather than fighting it")
	check(rat.logic.behaviour.wants_illuminator(rat, "execute"), "lit")
	var shots := _count_shots(rat)
	var behaviour = rat.logic.behaviour
	behaviour.do_execute(0.5, rat)
	check(_spoken.size() > 0, "it says so first")
	for i in 6:
		behaviour.do_execute(0.5, rat)
	check_eq(shots[0], 0, "no shot for the grace window's length (%.1f s)" % Mecha.FLAG_GRACE_TIME)
	for i in 4:
		behaviour.do_execute(0.5, rat)
	check(shots[0] > 0, "then it fires (%d shots)" % shots[0])
	# A Professional with no grudge doesn't execute.
	var pro := _enemy(Vector2(0, -1500), Personality.Type.PROFESSIONAL)
	pro.knowledge.see(victim, victim.global_position)
	pro.logic.behaviour._check_targets(pro)
	check(not pro.valid_target, "a Professional won't even target it")


func _test_stalk() -> void:
	var rat := _enemy(Vector2(-500, 0), Personality.Type.RAT)
	var mark := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL)
	var third := _mecha(Vector2(1200, 0))
	mark.knowledge.see(third, third.global_position)
	mark.mark_traitor(third)
	mark.logic.behaviour._check_targets(mark)
	check(is_same(mark.valid_target, third), "the mark is busy with someone else")
	rat.knowledge.see(mark, mark.global_position)
	rat.add_hostility(mark, 1.0)
	rat.logic.behaviour._check_targets(rat)
	check(is_same(rat.valid_target, mark), "the Rat has it as its target")
	check_eq(_decide(rat), "stalk", "and stalks it")
	rat.logic.behaviour.do_stalk(0.1, rat)
	check(rat.is_flagged() and rat.flag_voluntary, "with its Flag up")
	check(not rat.logic.behaviour.wants_illuminator(rat, "stalk"), "dark")
	# Right behind it, close: the Flag comes down.
	rat.global_position = Vector2(-400, 0)
	await get_tree().physics_frame
	rat.logic.behaviour.do_stalk(0.1, rat)
	check(rat.is_lowering_flag(), "close behind a distracted mark it lowers the Flag")
	rat.paused = false
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.3)
	rat.paused = true
	check(not rat.is_flagged(), "down")
	rat.knowledge.see(mark, mark.global_position)
	rat.logic.behaviour._check_targets(rat)
	check_eq(_decide(rat), "engage", "and it strikes")


func _test_protect() -> void:
	var guardian := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	var downed := _mecha(Vector2(1500, 0))
	downed.raise_flag()
	guardian.knowledge.see(downed, downed.global_position)
	check_eq(_decide(guardian), "protect", "a Guardian goes to a Flagged mech that isn't hostile")
	guardian.logic.behaviour.do_protect(0.1, guardian)
	check(guardian.NavAgent.target_position.distance_to(downed.global_position) <= guardian.logic.behaviour.PROTECT_RANGE * 1.5,
			"heading to stand by it (%.0f px off)" % guardian.NavAgent.target_position.distance_to(downed.global_position))
	check(not guardian.logic.behaviour.wants_illuminator(guardian, "protect"), "dark: the light comes on only to engage")
	guardian.add_hostility(downed, 1.0)
	check_eq(_decide(guardian), "roam", "not one it hates")
	var scav := _enemy(Vector2(0, 3000), Personality.Type.SCAVENGER)
	scav.knowledge.see(downed, downed.global_position)
	check(_decide(scav) != "protect", "a Scavenger doesn't")


func _test_panic() -> void:
	var brave := _enemy(Vector2.ZERO, Personality.Type.HUNTER)
	var timid := _enemy(Vector2(0, 600), Personality.Type.SCAVENGER)
	brave.knowledge.raise_panic(brave.knowledge.PANIC_HIT)
	timid.knowledge.raise_panic(timid.knowledge.PANIC_HIT)
	check(timid.knowledge.panic > brave.knowledge.panic and brave.knowledge.panic > 0.0, "a hit frightens the timid more")
	timid.knowledge.panic = 0.5
	timid.knowledge.tick_panic(1.0, true, 1, false)
	check(timid.knowledge.panic > 0.5, "under fire it rises")
	var p: float = timid.knowledge.panic
	timid.knowledge.tick_panic(1.0, false, 3, false)
	check(timid.knowledge.panic > p, "outnumbered it rises")
	p = timid.knowledge.panic
	timid.knowledge.tick_panic(1.0, false, 0, false)
	check(timid.knowledge.panic < p, "left alone it falls")
	timid.knowledge.panic = 0.0
	timid.knowledge.tick_panic(0.1, false, 0, true)
	check(timid.knowledge.panic > 0.0, "overheating adds once")
	p = timid.knowledge.panic
	timid.knowledge.tick_panic(0.1, false, 0, true)
	check(timid.knowledge.panic <= p, "not while it stays hot")
	# The aim.
	var foe := _mecha(Vector2(1500, 0))
	var calm_lead := 0.0
	brave.knowledge.panic = 0.0
	brave.knowledge.see(foe, foe.global_position, Vector2(0, 300))
	calm_lead = brave.compute_lead_point(foe).distance_to(foe.global_position)
	brave.knowledge.panic = 1.0
	var panicked_lead: float = brave.compute_lead_point(foe).distance_to(foe.global_position)
	check(calm_lead > 0.0 and panicked_lead < calm_lead * 0.6, "panic spoils the lead (%.0f px to %.0f)" % [calm_lead, panicked_lead])
	brave.update_senses(0.1)
	check(brave.extra_bloom > 0.0, "and widens the bloom")
	# Barks and scores.
	brave.knowledge.panic = 0.8
	check(Barks.has_lines("taking_fire_panicked", "any"), "panicked lines exist")
	timid.knowledge.panic = 0.9
	timid.knowledge.panic = 0.0
	check(not timid.logic.behaviour._should_flee(timid), "whole and calm it doesn't flee")


func _test_mines() -> void:
	var layer := _mecha(Vector2(-900, 2000), _design(MINE_LAYER))
	layer.create_projectile.connect(func(m, args, w):
		var data = ProjectileManager.create(m, args, w)
		_arena.add_child(data.node))
	check_eq(layer.fire_at_point("shoulder_weapon_left", Vector2(-500, 2000)), "", "a mine goes out")
	var settled := await wait_until(func(): return not MINE.mines_near(Vector2(-500, 2000), 150.0).is_empty(), 5.0)
	check(settled, "and settles")
	var mine_pos: Vector2 = MINE.mines_near(Vector2(-500, 2000), 150.0)[0].position
	var calm := _enemy(mine_pos + Vector2(-400, 0), Personality.Type.PROFESSIONAL)
	calm.knowledge.panic = 0.0
	calm.knowledge.mine_luck = 0.5
	var seen: Array = calm.knowledge.spot_mines(false)
	check_eq(seen.size(), 1, "a calm NPC sees the mine")
	check(calm.knowledge.known_mine_near(mine_pos, 50.0), "and knows where it is")
	calm.set_interest(Vector2.RIGHT, 0.0)
	calm._build_context()
	var ahead := 0
	for i in calm.STEER_SLOTS:
		if calm._steer_hard[i] > 0.0 and absf(angle_difference(0.0, calm._slot_angles[i])) < 0.5:
			ahead += 1
	check(ahead > 0, "the way onto it is blocked for steering")
	check(calm.knowledge.spot_mines(false).is_empty(), "it isn't rolled for again")
	var panicked := _enemy(mine_pos + Vector2(0, -400), Personality.Type.PROFESSIONAL)
	panicked.knowledge.panic = 1.0
	panicked.knowledge.mine_luck = 0.5
	check(panicked.knowledge.spot_mines(false).is_empty(), "a panicked NPC misses it (roll 0.5 against a 0.7 chance)")
	check(panicked.knowledge.missed_mines.size() == 1 and panicked.knowledge.known_mines.is_empty(), "for good")
	var hurried := _enemy(mine_pos + Vector2(400, 0), Personality.Type.PROFESSIONAL)
	hurried.knowledge.panic = 0.0
	hurried.knowledge.mine_luck = 0.25
	check(hurried.knowledge.spot_mines(true).is_empty(), "a sprinting one with a 0.25 roll misses it (0.3 chance)")
	var far := _enemy(mine_pos + Vector2(0, 900), Personality.Type.PROFESSIONAL)
	far.knowledge.mine_luck = 0.5
	check(far.knowledge.spot_mines(false).is_empty() and far.knowledge.missed_mines.is_empty(), "one too far away doesn't see it and isn't rolled")
	# The picker keeps away from a known mine.
	var terms_at_mine: float = 0.0
	calm.knowledge.see(layer, layer.global_position)
	calm.positioning.request()
	calm.positioning.choose(calm, layer.global_position, 1000.0, calm.logic.behaviour.ENGAGE_WEIGHTS, layer.global_position)
	for candidate in calm.positioning.candidates:
		if candidate.position.distance_to(mine_pos) < Positioning.MINE_CLEARANCE:
			terms_at_mine = maxf(terms_at_mine, float(candidate.terms.mines))
	check(calm.positioning.pick_position().distance_to(mine_pos) > Positioning.MINE_CLEARANCE, "the picker's choice keeps clear of it")


func _test_stage_step() -> void:
	var actor := _mecha(Vector2.ZERO)
	actor.mecha_name = "Flagger"
	var director := StageDirector.new()
	director._actors["Flagger"] = actor
	var step := StageActorFlag.new()
	step.actor = "Flagger"
	step.raised = true
	await step.run(director)
	check(actor.is_flagged() and actor.flag_voluntary, "raised by choice")
	var down := StageActorFlag.new()
	down.actor = "Flagger"
	down.raised = false
	down.instant = true
	await down.run(director)
	check(not actor.is_flagged(), "lowered at once")
	var emergency := StageActorFlag.new()
	emergency.actor = "Flagger"
	emergency.raised = true
	emergency.emergency = true
	await emergency.run(director)
	check(actor.is_flagged() and actor.is_exposed and not actor.flag_voluntary, "the emergency Flag, as the tutorial starts")
	director.free()
