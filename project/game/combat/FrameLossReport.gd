class_name FrameLossReport
extends RefCounted

## The frame loss report: when the player's frame is lost, the combat log
## (LOG › COMBAT) gets one line on how, then one lesson. Expedition calls write
## from _on_player_destroyed, before the mecha is freed:
##   CBT ! Frame lost to Vex · Autocannon · from 84 m NE · cockpit breached
##   ANL ! Vex wasn't on your sensors. A sweep (B) shows what is around...
## The fiction (ExtractionSummary): the pilot doesn't know it died, so nothing
## here says so.
##
## The lessons, in priority order (ORDER), and when each applies:
##   heat            a heat tick damaged a component in the last HEAT_WINDOW
##                   s, or heat breached the cockpit
##   flag_ignored    the Flag was up and a mecha finished the frame
##   creature        a creature or a swarm finished it (one line per species)
##   unseen          the mecha that finished it wasn't in the frame's contacts
##   lit             the illuminator was on at that attacker's first hit the
##                   recorder remembers
##   outnumbered     2 or more attackers in the last OUTNUMBERED_WINDOW s
##   no_head         the head had come off
##   overweight      over weight capacity
##   shield_flanked  hit from the side or rear with the shield up, in the
##                   last FLANK_WINDOW s
## Of those that apply, the one shown least so far (PlayerProgress.
## lessons_seen) is picked, ties going to priority, so one loss after another
## teaches different things. A lesson shown for the first time is a critical
## (bright) line. If none applies there is no lesson line.
##
## The wording is in TEXTS_PATH, so it can change without code. Placeholders:
## {killer}, {count} (attackers), {key:action} (the key bound to an action).

const SOURCE := "ANL"
const TEXTS_PATH := "res://database/lessons/frame_loss.json"
const ORDER := ["heat", "flag_ignored", "creature", "unseen", "lit", "outnumbered",
		"no_head", "overweight", "shield_flanked"]
const HEAT_WINDOW := 30.0
const OUTNUMBERED_WINDOW := 15.0
const FLANK_WINDOW := 30.0
## How {killer} reads for a pilot nobody can name (Anonymous, or gone).
const UNKNOWN_KILLER := "an unknown pilot"

static var _texts := {}


## Writes the report for `mecha`, just lost, to the combat log and counts its
## lesson as shown. Returns {"lost": the frame lost line, "lesson": the lesson
## id or "", "text": its line or ""}.
static func write(mecha: Mecha, recorder: CombatRecorder) -> Dictionary:
	var facts := gather(mecha, recorder)
	var lost := lost_line(facts)
	MechLog.write(CombatRecorder.SOURCE, lost, MechLog.Kind.COMBAT, true)
	var id := pick(applicable(facts), PlayerProgress.lessons_seen)
	var text := lesson_text(id, facts) if id != "" else ""
	if text == "":
		return {"lost": lost, "lesson": "", "text": ""}
	MechLog.write(SOURCE, text, MechLog.Kind.COMBAT, PlayerProgress.lesson_count(id) == 0)
	PlayerProgress.note_lesson(id)
	return {"lost": lost, "lesson": id, "text": text}


## What the report goes on, read off the frame as it is lost and the
## recorder's memory (null: no memory, the frame alone).
static func gather(mecha: Mecha, recorder: CombatRecorder) -> Dictionary:
	var source = mecha.last_damage_source
	var body = null
	if source is Dictionary:
		body = source.get("body")
	elif source is Node:
		body = source
	var breach: String = recorder.breach if recorder != null else ""
	var by_heat := breach == "heat"
	# Heat finished it: nobody did, whoever hit last.
	var valid: bool = not by_heat and is_instance_valid(body) and body != mecha
	var species := ""
	if valid and body is Entity:
		species = str(body.species)
	elif not by_heat and source is Dictionary and typeof(body) == TYPE_NIL \
			and creature_texts().has(str(source.get("name", ""))):
		species = str(source.name)  # a swarm with no body: the Tick Swarm
	var key: String = str(body.get_instance_id()) if valid else ""
	var hits: Array = recorder.hits if recorder != null else []
	var lit := false
	for hit in hits:
		if hit.key == key:
			lit = hit.lit
			break
	var attackers := {}
	var flanked := false
	var heat := by_heat
	if recorder != null:
		for hit in recorder.recent_hits(OUTNUMBERED_WINDOW):
			attackers[hit.key] = true
		for hit in recorder.recent_hits(FLANK_WINDOW):
			if hit.shielding and hit.facing in ["side", "rear"]:
				flanked = true
		for time in recorder.heat_damage:
			if recorder.now - time <= HEAT_WINDOW:
				heat = true
	var cause := ""
	if by_heat:
		cause = "cockpit breached by heat"
	elif breach == "hit":
		cause = "cockpit breached"
	elif mecha.is_exposed:
		cause = "finished while exposed"
	return {
		"killer": "" if by_heat else CombatRecorder.attacker_name(source),
		"is_mecha": valid and body.is_in_group("mecha"),
		"species": species,
		"weapon": "" if by_heat else CombatRecorder.weapon_name(mecha.last_damage_weapon),
		"from": KillRecord.bearing(mecha.global_position, body.global_position).replace(" M", " m")
				if valid and body is Node2D else "",
		"cause": cause,
		"flag_up": mecha.flag_up == true,
		"seen": valid and not mecha.contacts.best_for(body).is_empty(),
		"lit": valid and lit,
		"attackers": attackers.size(),
		"heat": heat,
		"no_head": mecha.is_part_lost("head"),
		"overweight": mecha.is_overweight() == true,
		"flanked": flanked,
	}


## "Frame lost to Vex · Autocannon · from 84 m NE · cockpit breached": who
## (left out when nobody can be named or heat did it), with what, from where,
## and how.
static func lost_line(facts: Dictionary) -> String:
	var head := "Frame lost"
	var killer: String = facts.killer
	if killer != "" and (killer != KillRecord.UNKNOWN or facts.from != ""):
		head += " to " + killer
	var parts := [head]
	for field in ["weapon", "from", "cause"]:
		if facts[field] != "":
			parts.append(("from " if field == "from" else "") + facts[field])
	return " · ".join(parts)


## The lessons that apply, in priority order.
static func applicable(facts: Dictionary) -> Array:
	var applies := {
		"heat": facts.heat,
		"flag_ignored": facts.flag_up and facts.is_mecha,
		"creature": facts.species != "",
		"unseen": facts.is_mecha and not facts.seen,
		"lit": facts.lit,
		"outnumbered": facts.attackers >= 2,
		"no_head": facts.no_head,
		"overweight": facts.overweight,
		"shield_flanked": facts.flanked,
	}
	return ORDER.filter(func(id): return applies[id])


## Of `ids` (in priority order), the one `seen` counts least; ties go to the
## first.
static func pick(ids: Array, seen: Dictionary) -> String:
	var best := ""
	for id in ids:
		if best == "" or int(seen.get(id, 0)) < int(seen.get(best, 0)):
			best = id
	return best


## Lesson `id`'s line for these facts, or "" if the texts have none.
static func lesson_text(id: String, facts: Dictionary) -> String:
	var raw = texts().get(id, "")
	if id == "creature":
		var creatures := creature_texts()
		raw = creatures.get(facts.species, creatures.get("default", ""))
	if not raw is String or raw == "":
		return ""
	var killer: String = facts.killer
	if killer == KillRecord.UNKNOWN or killer == "":
		killer = UNKNOWN_KILLER
	var text: String = raw.replace("{killer}", killer).replace("{count}", str(facts.attackers))
	var pattern := RegEx.create_from_string("\\{key:([a-z_0-9]+)\\}")
	for found in pattern.search_all(text):
		text = text.replace(found.get_string(), MechUI.key_name(found.get_string(1)))
	return text.left(1).to_upper() + text.substr(1)


## The texts file, loaded once.
static func texts() -> Dictionary:
	if _texts.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(TEXTS_PATH))
		if parsed is Dictionary:
			_texts = parsed
		else:
			push_error("FrameLossReport: %s isn't valid JSON" % TEXTS_PATH)
	return _texts


## Species -> line, and "default".
static func creature_texts() -> Dictionary:
	var creatures = texts().get("creature", {})
	return creatures if creatures is Dictionary else {}
