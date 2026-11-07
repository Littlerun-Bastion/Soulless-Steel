extends TestSuite

# CombatLogTest: the player's combat log (CombatRecorder). What happens to the
# frame is written to the LOG's COMBAT tab (MechLog, source CBT) as it
# happens, the moments that teach something only, and the last minute of it
# is kept for the frame loss report.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const BANNED_WORDS := ["died", "dead", "death", "killed"]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null
var _weapon_id := ""
var _weapon := ""


func run_tests() -> void:
	_weapon_id = PartManager.get_parts("arm_weapon").keys()[0]
	_weapon = KillRecord.weapon_label(_weapon_id)
	await case("an attacker's first hit gets a line, its next ones don't for 30 s", _test_new_attackers)
	await case("every hit is remembered: who, where from, lit, shielding", _test_hit_memory)
	await case("attackers by name: pilots, creatures, swarms, Unknown; own blasts aren't hits", _test_names)
	await case("take_damage hits count, and the attacker is known when it is announced", _test_take_damage)
	await case("destroyed components say what they did", _test_destroyed)
	await case("heat damage is marked, isn't a hit, and says so", _test_heat)
	await case("a part that comes off is one line", _test_part_lost)
	await case("the cockpit breach", _test_cockpit)
	await case("the Flag: by choice, emergency, with the core shell", _test_flag)
	await case("overheating gets a line, at most every 20 s", _test_overheating)
	await case("only the last minute is kept", _test_memory)
	await case("frame lost: who, with what, from where, how", _test_lost_line)
	await case("frame lost by heat, while exposed, to nobody, to a swarm", _test_lost_causes)
	await case("each lesson applies when it should", _test_lessons_apply)
	await case("a lesson from the frame's state: head, weight, shield", _test_lessons_state)
	await case("the least shown lesson is picked, and counted", _test_rotation)
	await case("lesson texts: every lesson and species, keys and names filled in", _test_texts)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	MechOS.close_all()
	MechLog.clear()
	PlayerProgress.lessons_seen = {}
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	await get_tree().physics_frame


func _mecha(pos: Vector2, callsign := "", chassis := "") -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	if chassis != "":
		design["chassis"] = chassis
	mecha.set_parts_from_design(design)
	mecha.set_pause(true)
	mecha.global_rotation = 0.0
	if callsign != "":
		mecha.callsign = callsign
	_arena.mechas.append(mecha)
	return mecha


# The player's mecha with its recorder, at the origin facing up (-y).
func _recorded(chassis := "") -> Array:
	var me := _mecha(Vector2.ZERO, "", chassis)
	return [me, CombatRecorder.attach(me)]


func _source(body) -> Dictionary:
	return {"body": body, "name": body.mecha_name if is_instance_valid(body) else ""}


# A hit on `target` by `source`, as a round or a bite lands: the attacker is
# recorded, then the component damaged. No pips by default: a hit that
# changes nothing but is still a hit.
func _hit(target: Mecha, source, weapon := "", part := "core", component := "radiator", pips := 0) -> void:
	target.last_damage_source = source
	target.last_damage_weapon = weapon
	target.damage_component(part, component, pips, Vector2.DOWN)


func _lines() -> Array:
	var texts := []
	for line in MechLog.lines:
		if line.source == CombatRecorder.SOURCE:
			texts.append(line.text)
	return texts


func _is_critical(text: String) -> bool:
	for line in MechLog.lines:
		if line.source == CombatRecorder.SOURCE and line.text == text:
			return line.critical
	return false


func _test_new_attackers() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -600), "Vex")
	var ash := _mecha(Vector2(0, 600), "Ash")
	_hit(me, _source(vex), _weapon_id)
	check_eq(_lines(), ["Hit by Vex (%s) · core" % _weapon], "a new attacker: who, with what, where it landed")
	check(not _is_critical("Hit by Vex (%s) · core" % _weapon), "an ordinary line")
	_hit(me, _source(vex), _weapon_id)
	_hit(me, _source(vex), _weapon_id, "head", "optics")
	check_eq(_lines().size(), 1, "its next hits get no line")
	_hit(me, _source(ash), "", "head", "optics")
	check_eq(_lines().back(), "Hit by Ash · head", "another attacker gets its own (no weapon known: none shown)")
	rec.now += CombatRecorder.NEW_ATTACKER_GAP - 1.0
	_hit(me, _source(vex), _weapon_id)
	check_eq(_lines().size(), 2, "29 s after its last hit, still none")
	rec.now += CombatRecorder.NEW_ATTACKER_GAP
	_hit(me, _source(vex), _weapon_id)
	check_eq(_lines().back(), "Hit by Vex (%s) · core" % _weapon, "after 30 s without one, a line again")


func _test_hit_memory() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -600), "Vex")
	var ash := _mecha(Vector2(0, 600), "Ash")
	var cole := _mecha(Vector2(600, 0), "Cole")
	_hit(me, _source(vex), _weapon_id)
	_hit(me, _source(vex), _weapon_id)
	me.set_illuminator(false)
	me.is_shielding = true
	_hit(me, _source(ash), "", "head", "optics")
	me.is_shielding = false
	_hit(me, {"body": cole, "name": cole.mecha_name, "from": Vector2(0, -900)})
	check_eq(rec.hits.size(), 4, "every hit, lines or not")
	if rec.hits.size() != 4:
		return
	var first: Dictionary = rec.hits[0]
	check(first.name == "Vex" and first.weapon == _weapon and first.part == "core", "who, with what, which part")
	check(first.key == rec.hits[1].key and first.key != rec.hits[2].key, "the same attacker is told apart from another")
	check_eq(first.facing, "front", "hit from the front")
	check_eq(rec.hits[2].facing, "rear", "and from behind")
	check_eq(rec.hits[3].facing, "front", "a round's side comes from where it was fired (from), not the shooter")
	check(first.lit and not rec.hits[2].lit, "whether the illuminator was on")
	check(rec.hits[2].shielding and not first.shielding, "whether the shield was up")
	check(not first.overheating, "whether it was overheating")
	check_eq(rec.recent_hits(1.0).size(), 4, "recent hits")


func _test_names() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(400, 0)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	_hit(me, {"body": stalker, "name": stalker.mecha_name}, stalker.mecha_name)
	check_eq(_lines().back() if not _lines().is_empty() else "", "Hit by Stalker · core", "a creature by its species, its attack isn't a weapon")
	_hit(me, {"body": null, "name": "Tick Swarm"})
	check_eq(_lines().back(), "Hit by Tick Swarm · core", "a swarm with no body by its name")
	var anon := _mecha(Vector2(0, -400), "Hidden")
	anon.is_anonymous = true
	_hit(me, _source(anon))
	check_eq(_lines().back(), "Hit by Unknown · core", "an Anonymous pilot is Unknown")
	var gone := _mecha(Vector2(0, -500), "Gone")
	var source := _source(gone)
	_arena.mechas.erase(gone)
	gone.free()
	_hit(me, source)
	check_eq(_lines().back(), "Hit by Unknown · core", "a round from a shooter that is gone: Unknown")
	var before := rec.hits.size()
	var count := _lines().size()
	_hit(me, _source(me))
	check(rec.hits.size() == before and _lines().size() == count, "its own blast isn't a hit")
	check_eq(CombatRecorder.weapon_name("not a part"), "", "an id that isn't a weapon part names none")


func _test_take_damage() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var ash := _mecha(Vector2(0, -600), "Ash")
	var vex := _mecha(Vector2(0, -700), "Vex")
	me.last_damage_source = _source(vex)
	var heard := []
	me.took_damage.connect(func(_m, _status): heard.append(me.last_damage_source))
	me.take_damage(1, 1.0, 1.0, 0, 0, false, false, _source(ash), _weapon_id)
	check(heard.size() == 1 and heard[0].get("body") == ash, "when took_damage is announced, the attacker is already the new one")
	check_eq(_lines(), ["Hit by Ash (%s)" % _weapon], "a hit with no component: no part")
	me.emit_signal("took_damage", me, true)
	check_eq(rec.hits.size(), 1, "status damage (fire, corrosion) isn't a hit")


func _test_destroyed() -> void:
	# A tank chassis: its tracks are a mobility component (the default has none).
	var tank := ""
	for id in PartManager.get_parts("chassis"):
		if PartManager.get_part("chassis", id).movement_type == "tank":
			tank = id
			break
	check(tank != "", "(there is a tank chassis)")
	var made := _recorded(tank)
	var me: Mecha = made[0]
	var vex := _mecha(Vector2(0, -600), "Vex")
	_hit(me, _source(vex), "", "core", "radiator", 2)
	check_eq(_lines(), ["Hit by Vex · core", "Core radiator destroyed · heat dispersion halved"], "what it did, after the hit")
	_hit(me, _source(vex), "", "head", "optics", 9)
	check_eq(_lines().back(), "Head optics destroyed · sensors reduced", "optics")
	_hit(me, _source(vex), "", "head", "backup_optics", 9)
	check_eq(_lines().back(), "Head backup optics destroyed · nearly blind", "backup optics with the optics gone")
	_hit(me, _source(vex), "", "core", Mecha.SHIELD_PROJECTOR, 9)
	check_eq(_lines().back(), "Core shield projector destroyed · shield weakened", "a shield projector")
	var mobility := ""
	for component in me.components.chassis:
		if "mobility" in me.components.chassis[component].tags:
			mobility = component
			break
	check(mobility != "", "(the chassis has a mobility component)")
	if mobility != "":
		_hit(me, _source(vex), "", "chassis", mobility, 9)
		check_eq(_lines().back(), CombatRecorder.component_label("chassis", mobility) + " destroyed · mobility reduced", "mobility")
	check(me.components.left_shoulder.has("weapon_feed"), "(the left shoulder feeds its arm weapon)")
	_hit(me, _source(vex), "", "left_shoulder", "weapon_feed", 9)
	check_eq(_lines().back(), "Left shoulder weapon feed destroyed · left arm weapon offline", "a weapon feed")
	_hit(me, _source(vex), "", "left_shoulder", "shoulder_shell", 9)
	check(me.is_part_lost("left_shoulder") or _lines().back() == "Left shoulder shell destroyed", "a shell: no 'shoulder shoulder'")
	check_eq(CombatRecorder.component_label("core", "core_shell"), "Core shell", "a core's shell")


func _test_heat() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var causes := []
	me.component_damaged.connect(func(_p, _c, _hp, _max): causes.append(me.damage_cause))
	me.overheat_damage_tick()
	check(causes.size() == 1 and causes[0] == "heat", "an overheat tick damages a component as heat")
	check_eq(me.damage_cause, "", "and leaves no cause behind")
	check(rec.hits.is_empty() and rec.heat_damage.size() == 1, "remembered as heat damage, not a hit")
	# A fresh mecha: the tick above picks a component at random.
	MechLog.clear()
	var cooked := _recorded()[0] as Mecha
	cooked.damage_cause = "heat"
	cooked.damage_component("head", "optics", 9)
	cooked.damage_cause = ""
	check_eq(_lines().back() if not _lines().is_empty() else "", "Head optics destroyed by heat · sensors reduced", "a component heat destroyed says so")
	check(not _lines().any(func(text): return text.begins_with("Hit by")), "no hit lines for heat")


func _test_part_lost() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	check(me.lose_part("arm_weapon_left"), "(the left arm weapon comes off)")
	check_eq(_lines(), ["Left arm weapon lost"], "one line: not its feed's too")
	check(me.lose_part("head"), "(the head comes off)")
	check_eq(_lines(), ["Left arm weapon lost", "Head lost"], "nor the head's components")
	check(me.lose_part("right_shoulder"), "(the right shoulder comes off)")
	check_eq(_lines().back(), "Right shoulder lost", "a shoulder, with its weapons")
	check_eq(_lines().size(), 3, "one line each")


func _test_cockpit() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var vex := _mecha(Vector2(0, -600), "Vex")
	_hit(me, _source(vex), _weapon_id, "core", "cockpit", 9)
	check(me.is_dead, "(a cockpit hit ends the frame)")
	check_eq(_lines().back() if not _lines().is_empty() else "", "Cockpit breached", "the breach")
	check(_is_critical("Cockpit breached"), "as a critical line")
	for text in _lines():
		for word in BANNED_WORDS:
			check(not str(text).to_lower().contains(word), "'%s' doesn't say '%s'" % [text, word])


func _test_flag() -> void:
	var me := _recorded()[0] as Mecha
	me.raise_flag(true)
	check_eq(_lines(), ["Flag raised"], "a Flag by choice")
	check(not _is_critical("Flag raised"), "an ordinary line")

	MechLog.clear()
	var shell := _recorded()[0] as Mecha
	var vex := _mecha(Vector2(0, -600), "Vex")
	_hit(shell, _source(vex), "", "core", "core_shell", 99)
	check_eq(_lines(), ["Hit by Vex · core", "Core shell broken · emergency Flag raised"], "the core shell and the Flag it raises: one line")
	check(_is_critical("Core shell broken · emergency Flag raised"), "critical")

	MechLog.clear()
	var hull := _recorded()[0] as Mecha
	hull.take_damage(hull.hp + 1, 1.0, 1.0, 0, 0, false, false, _source(vex), _weapon_id)
	check(hull.is_exposed, "(the hull gives out)")
	check_eq(_lines().back() if not _lines().is_empty() else "", "Emergency Flag raised", "the emergency Flag on its own")


func _test_overheating() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	me.set_status("overheating", 1.0)
	rec._physics_process(0.0)
	check_eq(_lines(), ["Overheating"], "it starts")
	rec._physics_process(0.0)
	check_eq(_lines().size(), 1, "not again while it goes on")
	me.set_status("overheating", 0.0)
	rec._physics_process(0.0)
	me.set_status("overheating", 1.0)
	rec._physics_process(0.0)
	check_eq(_lines().size(), 1, "nor when it starts again soon after")
	me.set_status("overheating", 0.0)
	rec._physics_process(CombatRecorder.OVERHEAT_GAP)
	me.set_status("overheating", 1.0)
	rec._physics_process(0.0)
	check_eq(_lines().size(), 2, "but again 20 s after the last line")


func _test_memory() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -600), "Vex")
	var ash := _mecha(Vector2(0, 600), "Ash")
	_hit(me, _source(vex))
	me.damage_cause = "heat"
	me.damage_component("core", "radiator", 0)
	me.damage_cause = ""
	rec.now += CombatRecorder.MEMORY + 1.0
	_hit(me, _source(ash))
	check(rec.hits.size() == 1 and rec.hits[0].name == "Ash", "a hit over a minute old is forgotten")
	check(rec.heat_damage.is_empty(), "heat damage too")
	rec.now += 5.0
	check(rec.recent_hits(10.0).size() == 1 and rec.recent_hits(4.0).is_empty(), "recent hits by age")


# ---- The frame loss report (FrameLossReport) ----

func _stalker(pos: Vector2) -> Entity:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = pos
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	return stalker


func _lesson_lines() -> Array:
	var texts := []
	for line in MechLog.lines:
		if line.source == FrameLossReport.SOURCE:
			texts.append(line.text)
	return texts


func _applicable(mecha: Mecha, recorder: CombatRecorder) -> Array:
	return FrameLossReport.applicable(FrameLossReport.gather(mecha, recorder))


func _test_lost_line() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -1000), "Vex")
	_hit(me, _source(vex), _weapon_id, "core", "cockpit", 9)
	check(me.is_dead, "(the cockpit is breached)")
	var report := FrameLossReport.write(me, rec)
	var expected := "Frame lost to Vex · %s · from 50 m N · cockpit breached" % _weapon
	check_eq(report.lost, expected, "who, with what, from where, how")
	check(_lines().has(expected) and _is_critical(expected), "in the combat log, as a critical line")
	check_eq(report.lesson, "unseen", "Vex never showed in its contacts: the unseen lesson (before lit)")
	var lessons := _lesson_lines()
	check(lessons.size() == 1 and lessons[0] == report.text, "one lesson line, after it")
	check(report.text.begins_with("Vex wasn't on your sensors") and report.text.contains("(%s)" % MechUI.key_name("sweep")),
			"naming the attacker and the sweep key")
	check(MechLog.lines.back().critical, "a lesson shown for the first time stands out")
	for line in MechLog.lines:
		for word in BANNED_WORDS:
			check(not str(line.text).to_lower().contains(word), "'%s' doesn't say '%s'" % [line.text, word])


func _test_lost_causes() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -1000), "Vex")
	_hit(me, _source(vex), _weapon_id)
	me.damage_cause = "heat"
	me.damage_component("core", "cockpit", 9)
	me.damage_cause = ""
	check(me.is_dead, "(heat breaches the cockpit)")
	check(_lines().has("Cockpit breached by heat"), "the breach says heat did it")
	var facts := FrameLossReport.gather(me, rec)
	check_eq(FrameLossReport.lost_line(facts), "Frame lost · cockpit breached by heat", "heat did it: nobody is named")
	check_eq(FrameLossReport.applicable(facts), ["heat"], "the heat lesson")

	var exposed := _recorded()
	var hull: Mecha = exposed[0]
	var ash := _mecha(Vector2(1000, 0), "Ash")
	hull.take_damage(hull.hp + 1, 1.0, 1.0, 0, 0, false, false, _source(ash), _weapon_id)
	check(hull.is_exposed, "(the hull gives out)")
	facts = FrameLossReport.gather(hull, exposed[1])
	check_eq(FrameLossReport.lost_line(facts), "Frame lost to Ash · %s · from 50 m E · finished while exposed" % _weapon,
			"finished while exposed")
	check(facts.flag_up and "flag_ignored" in FrameLossReport.applicable(facts), "a mecha finishing a Flagged frame ignored the Flag")

	var plain := _recorded()
	var lone: Mecha = plain[0]
	lone.last_damage_source = {"name": "Player"}
	facts = FrameLossReport.gather(lone, plain[1])
	check_eq(FrameLossReport.lost_line(facts), "Frame lost", "no attacker at all: just that")
	check(FrameLossReport.applicable(facts).is_empty(), "and nothing to learn from it")
	var anon := _mecha(Vector2(0, 1000), "Hidden")
	anon.is_anonymous = true
	lone.last_damage_source = _source(anon)
	facts = FrameLossReport.gather(lone, plain[1])
	check_eq(FrameLossReport.lost_line(facts), "Frame lost to Unknown · from 50 m S", "an Anonymous pilot: Unknown, and from where")
	check(FrameLossReport.lesson_text("unseen", facts).begins_with("An unknown pilot wasn't"), "a lesson calls it an unknown pilot")
	lone.last_damage_source = {"body": null, "name": "Tick Swarm"}
	facts = FrameLossReport.gather(lone, plain[1])
	check(FrameLossReport.lost_line(facts) == "Frame lost to Tick Swarm" and facts.species == "Tick Swarm", "a swarm by its name, as a creature")
	check_eq(FrameLossReport.applicable(facts), ["creature"], "with the creature lesson")


func _test_lessons_apply() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -1000), "Vex")
	var ash := _mecha(Vector2(0, 1000), "Ash")
	_hit(me, _source(vex))
	check_eq(_applicable(me, rec), ["unseen", "lit"], "never in its contacts, and lit at Vex's first hit")
	me.contacts.report(vex, "mech", vex.global_position, "sight", 5.0)
	check_eq(_applicable(me, rec), ["lit"], "in its contacts: not unseen")

	var dark := _recorded()
	var unlit: Mecha = dark[0]
	unlit.contacts.report(vex, "mech", vex.global_position, "sight", 5.0)
	unlit.set_illuminator(false)
	_hit(unlit, _source(vex))
	unlit.set_illuminator(true)
	_hit(unlit, _source(vex))
	check(_applicable(unlit, dark[1]).is_empty(), "lit only if it was on at that attacker's first hit")

	_hit(me, _source(ash))
	var facts := FrameLossReport.gather(me, rec)
	check(facts.attackers == 2 and "outnumbered" in FrameLossReport.applicable(facts), "two attackers within 15 s: outnumbered")
	var text := FrameLossReport.lesson_text("outnumbered", facts)
	check(text.contains("2") and not text.contains("{"), "saying how many")
	rec.now += FrameLossReport.OUTNUMBERED_WINDOW + 1.0
	check(not "outnumbered" in _applicable(me, rec), "not once one of them is 15 s back")

	me.damage_cause = "heat"
	me.damage_component("core", "radiator", 0)
	me.damage_cause = ""
	check_eq(_applicable(me, rec).front(), "heat", "heat damage in the last 30 s: heat, first")
	rec.now += FrameLossReport.HEAT_WINDOW + 1.0
	check(not "heat" in _applicable(me, rec), "not after 30 s")

	var flagged := _recorded()
	var white: Mecha = flagged[0]
	white.raise_flag(true)
	white.last_damage_source = _source(vex)
	check("flag_ignored" in _applicable(white, flagged[1]), "the Flag up and a mecha finished it")
	var stalker := _stalker(Vector2(400, 0))
	white.last_damage_source = {"body": stalker, "name": stalker.mecha_name}
	facts = FrameLossReport.gather(white, flagged[1])
	check(facts.species == "Stalker" and FrameLossReport.applicable(facts) == ["creature"], "a creature: its lesson, not the Flag's")
	check_eq(FrameLossReport.lesson_text("creature", facts), FrameLossReport.creature_texts().get("Stalker", "?"), "the Stalker's own line")


func _test_lessons_state() -> void:
	var made := _recorded()
	var me: Mecha = made[0]
	var rec: CombatRecorder = made[1]
	var vex := _mecha(Vector2(0, -1000), "Vex")
	me.contacts.report(vex, "mech", vex.global_position, "sight", 5.0)
	me.set_illuminator(false)
	_hit(me, _source(vex))
	check(_applicable(me, rec).is_empty(), "seen, dark, one attacker: nothing to learn")
	var report := FrameLossReport.write(me, rec)
	check(report.lesson == "" and _lesson_lines().is_empty() and _lines().back().begins_with("Frame lost"), "the frame lost line, and no lesson line")
	check(me.lose_part("head"), "(the head comes off)")
	check_eq(_applicable(me, rec), ["no_head"], "without its head")
	me.is_shielding = true
	_hit(me, {"body": vex, "name": vex.mecha_name, "from": Vector2(0, 1000)})
	me.is_shielding = false
	check("shield_flanked" in _applicable(me, rec), "shielding, hit from behind")
	var facts := FrameLossReport.gather(me, rec)
	check(not facts.overweight, "(not over capacity)")
	facts.overweight = true
	check("overweight" in FrameLossReport.applicable(facts), "over capacity")


func _test_rotation() -> void:
	check_eq(FrameLossReport.pick(["unseen", "lit"], {}), "unseen", "none shown yet: by priority")
	check_eq(FrameLossReport.pick(["unseen", "lit"], {"unseen": 1}), "lit", "the least shown")
	check_eq(FrameLossReport.pick(["unseen", "lit"], {"unseen": 2, "lit": 2}), "unseen", "a tie: by priority")
	check_eq(FrameLossReport.pick([], {}), "", "none")
	# Three losses alike.
	var critical := []
	for i in 3:
		var made := _recorded()
		var vex := _mecha(Vector2(0, -1000), "Vex")
		_hit(made[0], _source(vex), _weapon_id, "core", "cockpit", 9)
		FrameLossReport.write(made[0], made[1])
		critical.append(MechLog.lines.back().critical)
	var lessons := _lesson_lines()
	check(lessons.size() == 3 and lessons[0].contains("sensors") and lessons[1].contains("illuminator") and lessons[2].contains("sensors"),
			"one loss after another alike: unseen, then lit, then unseen again")
	check_eq(critical, [true, true, false], "new ones stand out, a repeat doesn't")
	check(PlayerProgress.lesson_count("unseen") == 2 and PlayerProgress.lesson_count("lit") == 1, "each counted")
	var data := PlayerProgress.get_save_data()
	check_eq(data.get("lessons_seen"), {"unseen": 2, "lit": 1}, "saved")
	PlayerProgress.lessons_seen = {}
	PlayerProgress.set_save_data(data)
	check_eq(PlayerProgress.lessons_seen, {"unseen": 2, "lit": 1}, "and loaded")
	PlayerProgress.set_save_data({"lessons_seen": {"lit": 3.0, "junk": "a", "none": 0}})
	check_eq(PlayerProgress.lessons_seen, {"lit": 3}, "a bad entry in a save is dropped")
	PlayerProgress.set_save_data({})
	check(PlayerProgress.lessons_seen.is_empty(), "an older save: none shown yet")


func _test_texts() -> void:
	var facts := {"killer": "Vex", "attackers": 3, "species": "Coyote"}
	for id in FrameLossReport.ORDER:
		var text := FrameLossReport.lesson_text(id, facts)
		check(text != "" and not text.contains("{"), "'%s' has a line, with everything filled in" % id)
		for word in BANNED_WORDS:
			check(not text.to_lower().contains(word), "'%s' doesn't say '%s'" % [id, word])
	check(FrameLossReport.lesson_text("unseen", facts).contains("(%s)" % MechUI.key_name("sweep")), "keys by what they are bound to")
	var creatures := FrameLossReport.creature_texts()
	check(creatures.has("default"), "a line for a creature without its own")
	var species := _species_in("res://game/entities")
	check(species.size() >= 5, "(found the game's species: %s)" % ", ".join(species))
	for kind in species:
		check(creatures.has(kind), "%s has its own line" % kind)
	for kind in creatures:
		for word in BANNED_WORDS:
			check(not str(creatures[kind]).to_lower().contains(word), "%s's line doesn't say '%s'" % [kind, word])


# The species the creatures' scenes and scripts give themselves.
func _species_in(path: String) -> Array:
	var found := []
	var pattern := RegEx.create_from_string("^species = \"([^\"]+)\"")
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		for kind in _species_in(path.path_join(sub)):
			if not kind in found:
				found.append(kind)
	for file in dir.get_files():
		if not (file.ends_with(".tscn") or file.ends_with(".gd")):
			continue
		for line in FileAccess.get_file_as_string(path.path_join(file)).split("\n"):
			var hit := pattern.search(line.strip_edges())
			if hit != null and not hit.get_string(1) in found:
				found.append(hit.get_string(1))
	return found
