extends TestSuite

# BarksTest: NPC barks and speech (Barks.gd, Enemy.bark, Mecha.say). The
# line file loads and has lines for every event; a named NPC's lines come
# first, then its personality type's, then "any"; {target} becomes a
# callsign, or "someone" for an Anonymous pilot or a creature; an NPC only
# barks with the player in earshot, then waits out its own cooldown and the
# shared one; an event's chance of 0 never barks; each event comes from the
# right change in what the NPC is doing (Enemy._watch_barks), and so do the
# loot shout and the once-a-fight help call; and StageActorSay makes an
# actor speak, heard whatever the distance.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const EVENTS := ["spotted", "lost_target", "searching", "taking_fire", "reloading", "overheating",
		"retreating", "target_down", "looting", "extracting", "idle"]
const TESTER := "Bark Tester"


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
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null
var _spoken: Array = []  # [mecha, text, seconds, always_heard]


func run_tests() -> void:
	await case("the line file has lines and a chance for every event", _test_file)
	await case("named lines first, then the type's, then 'any'; {target}", _test_lines)
	await case("an NPC barks only with the player in earshot", _test_earshot)
	await case("an NPC's own cooldown and the shared one", _test_cooldowns)
	await case("an event with no chance never barks", _test_chance)
	await case("each event comes from the right change", _test_watcher)
	await case("loot shout and help call go to Local", _test_broadcasts)
	await case("StageActorSay makes an actor speak, always heard", _test_stage_step)
	await before_each()
	Barks._data = {}


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	_spoken.clear()
	Barks._data = {}
	Barks.reset_cooldown()
	await wait_frames(2)


func _setup() -> void:
	_arena = FakeArena.new()
	add_child(_arena)
	_arena.player = _mecha(Vector2.ZERO)
	_arena.player.mecha_name = "Player"
	_arena.player.callsign = "Drifter"
	await get_tree().physics_frame


func _mecha(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	return mecha


# An NPC held still (thinking only when the test says), whose speech is
# recorded in _spoken.
func _enemy(pos: Vector2, npc_name := "Bark test") -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, npc_name)
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.global_rotation = 0.0
	_arena.mechas.append(enemy)
	enemy.spoke.connect(_on_spoke)
	return enemy


func _on_spoke(mecha, text: String, seconds: float, always_heard: bool) -> void:
	_spoken.append([mecha, text, seconds, always_heard])


func _last_text() -> String:
	return _spoken[_spoken.size() - 1][1] if not _spoken.is_empty() else ""


# Every event barks for sure, with the line "<event>" for the tester NPC.
func _rig_lines() -> void:
	var data := Barks.data()
	var named := {}
	for event in EVENTS:
		named[event] = [event]
		data.chances[event] = 1.0
	data.named[TESTER] = named


func _ready_to_bark(enemy) -> void:
	enemy._bark_ready_ms = 0
	Barks.reset_cooldown()


func _test_file() -> void:
	var data := Barks.data()
	check(not data.is_empty(), "barks.json loads")
	for event in EVENTS:
		var any: Array = data.events.get(event, {}).get("any", [])
		check(any.size() >= 3 and any.size() <= 5, "%s has 3 to 5 'any' lines (%d)" % [event, any.size()])
		var chance := Barks.chance_for(event)
		check(chance >= 0.3 and chance <= 1.0, "%s has a chance between 30%% and 100%% (%.2f)" % [event, chance])
	check(not data.broadcasts.get("found_loot", []).is_empty() and not data.broadcasts.get("need_help", []).is_empty(),
			"NPC broadcast lines for loot shouts and help calls")


func _test_lines() -> void:
	await _setup()
	var data := Barks.data()
	data.events["spotted"] = {"any": ["Any line."], "hunter": ["Hunter sees {target}."]}
	data.named["Named"] = {"spotted": ["Named line."]}
	check_eq(Barks.line_for("spotted", "professional"), "Any line.", "a type without lines uses 'any'")
	check_eq(Barks.line_for("spotted", "hunter"), "Hunter sees someone.", "a type's own lines; no target is 'someone'")
	check_eq(Barks.line_for("spotted", "hunter", "Named"), "Named line.", "a named NPC's lines come first")
	check_eq(Barks.line_for("nothing", "hunter"), "", "an unknown event has no line")
	var target := _mecha(Vector2(100, 0))
	target.callsign = "Rook"
	check_eq(Barks.fill("Got {target}.", target), "Got Rook.", "{target} is the callsign")
	target.is_anonymous = true
	check_eq(Barks.fill("Got {target}.", target), "Got someone.", "an Anonymous target is 'someone'")
	var stalker: Entity = STALKER.instantiate()
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	check_eq(Barks.fill("Got {target}.", stalker), "Got someone.", "so is a creature")
	var hunter := Personality.new()
	hunter.type = Personality.Type.HUNTER
	check_eq(Barks.type_name(hunter), "hunter", "personality type names match the file's keys")


func _test_earshot() -> void:
	await _setup()
	_rig_lines()
	var near := _enemy(Vector2(Barks.EARSHOT - 100.0, 0), TESTER)
	var far := _enemy(Vector2(Barks.EARSHOT + 100.0, 0), TESTER)
	check(not far.bark("idle"), "out of earshot it doesn't bark")
	check(_spoken.is_empty(), "nothing is said")
	check(near.bark("idle"), "within earshot it does")
	check(_spoken.size() == 1 and _spoken[0][0] == near and _last_text() == "idle", "it says the line")


func _test_cooldowns() -> void:
	await _setup()
	_rig_lines()
	var a := _enemy(Vector2(200, 0), TESTER)
	var b := _enemy(Vector2(-200, 0), TESTER)
	check(a.bark("idle"), "first bark")
	check(not b.bark("idle"), "another NPC waits out the shared cooldown")
	Barks.reset_cooldown()
	check(not a.bark("idle"), "the same NPC waits out its own cooldown")
	check(b.bark("idle"), "another barks once the shared one is over")


func _test_chance() -> void:
	await _setup()
	_rig_lines()
	Barks.data().chances["idle"] = 0.0
	var a := _enemy(Vector2(200, 0), TESTER)
	var spoke := false
	for i in 20:
		_ready_to_bark(a)
		spoke = spoke or a.bark("idle")
	check(not spoke, "a chance of 0 never barks")


func _test_watcher() -> void:
	await _setup()
	_rig_lines()
	var npc := _enemy(Vector2(0, -600), TESTER)
	var foe := _mecha(Vector2(0, -1000))
	foe.callsign = "Rook"
	var g = npc.logic.g

	# Spotted: the fight starts (the engage intent's attack stance) with the
	# target in sight.
	npc.update_senses(0.1)
	npc.current_target = foe
	g.set_state("engage")
	npc.logic.behaviour.stance = "attack"
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "spotted", "spotted")
	check(npc.is_in_fight(), "a fight starts")

	# Taking fire: the first hit of the fight only.
	_ready_to_bark(npc)
	npc.took_damage.emit(npc, false)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "taking_fire", "taking_fire")
	_ready_to_bark(npc)
	var before := _spoken.size()
	npc.took_damage.emit(npc, false)
	npc._watch_barks(0.1)
	check_eq(_spoken.size(), before, "not again in the same fight")

	# Lost target, then searching SEARCH_BARK_DELAY s later.
	foe.global_position = Vector2(0, -50000)
	npc.update_senses(0.1)
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "lost_target", "lost_target")
	_ready_to_bark(npc)
	npc._watch_barks(npc.SEARCH_BARK_DELAY)
	check_eq(_last_text(), "searching", "searching")

	# Retreating: takes the defend stance.
	npc.logic.behaviour.stance = "defend"
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "retreating", "retreating")

	# Overheating: the status comes on.
	npc.set_status("overheating", 1.0)
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "overheating", "overheating")

	# Reloading in a fight.
	npc.get_node("ArmWeaponLeft").reloading_signal.emit(1.0)
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "reloading", "reloading")

	# Target down.
	foe.is_dead = true
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "target_down", "target_down")

	# Looting: reached a container.
	npc.current_target = false
	g.set_state("loot")
	npc.logic.behaviour.times_looted += 1
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "looting", "looting")

	# Extracting: heads for an exit.
	g.set_state("extract")
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	check_eq(_last_text(), "extracting", "extracting")
	check(not npc.is_in_fight(), "the fight is over in a calm state")

	# Idle: while roaming, at IDLE_BARK_RATE per second.
	g.set_state("roam")
	_ready_to_bark(npc)
	npc._watch_barks(0.1)
	_ready_to_bark(npc)
	npc._watch_barks(1.0 / npc.IDLE_BARK_RATE + 1.0)
	check_eq(_last_text(), "idle", "idle")


func _test_broadcasts() -> void:
	await _setup()
	var local: LocalPilots = _arena.local_pilots
	var got := []
	local.message.connect(func(entry): got.append(entry))
	var npc := _enemy(Vector2(0, -600), "Shouter")
	local.join(npc)
	var g = npc.logic.g

	# Loot shout: chance personality.greed x LOOT_SHOUT_GREED; greed far
	# above 1 makes the roll certain.
	npc.personality.greed = 100.0
	g.set_state("loot")
	npc.logic.behaviour.times_looted += 1
	npc._watch_barks(0.1)
	check(got.size() == 1 and got[0].kind == "found_loot" and got[0].sender == npc, "a loot shout to Local")
	if got.size() == 1:
		check(Barks.data().broadcasts.found_loot.has(got[0].text), "with one of the file's loot lines")
	npc.personality.greed = 0.0
	npc.logic.behaviour.times_looted += 1
	npc._watch_barks(0.1)
	check_eq(got.size(), 1, "no greed, no shout")

	# Help call: in a fight, under fire, below half its structure; once a fight.
	g.set_state("engage")
	npc._watch_barks(0.1)
	npc.under_fire_timer = 0.5
	npc._watch_barks(0.1)
	check(not got.any(func(e): return e.kind == "need_help"), "no help call under fire while whole")
	wear_down(npc)
	npc.under_fire_timer = 0.5
	npc._watch_barks(0.1)
	var calls := got.filter(func(e): return e.kind == "need_help")
	check_eq(calls.size(), 1, "a help call")
	npc._watch_barks(0.1)
	calls = got.filter(func(e): return e.kind == "need_help")
	check_eq(calls.size(), 1, "only once a fight")
	npc.under_fire_timer = 0.0
	g.set_state("roam")
	npc._watch_barks(0.1)
	g.set_state("engage")
	npc.under_fire_timer = 0.5
	npc._watch_barks(0.1)
	npc._watch_barks(0.1)
	calls = got.filter(func(e): return e.kind == "need_help")
	check_eq(calls.size(), 2, "and again in the next fight")


func _test_stage_step() -> void:
	await _setup()
	var actor := _mecha(Vector2(50000, 0))
	actor.mecha_name = "Herald"
	actor.spoke.connect(_on_spoke)
	var director := StageDirector.new()
	director.shows_bars = false
	director.takes_control = false
	director.takes_camera = false
	director.freezes_world = false
	var step := StageActorSay.new()
	step.actor = "Herald"
	step.text = "Hear me."
	step.seconds = 0.5
	director.add_child(step)
	_arena.add_child(director)
	var finished := [false]
	director.finished.connect(func(): finished[0] = true)
	director.play()
	check(_spoken.size() == 1 and _spoken[0][1] == "Hear me." and _spoken[0][3], "the actor says the line, always heard")
	if _spoken.size() == 1:
		check_eq(_spoken[0][2], 0.5, "for the step's time")
	var done := await wait_until(func(): return finished[0], 3.0)
	check(done, "the step ends when the line's time is up")
