class_name Barks
extends RefCounted

## NPC barks: short lines an NPC says (Mecha.say) when something happens to
## it (Enemy.bark). The lines are in database/npcs/barks.json, which can be
## edited as text:
##   chances     event -> how likely it is to bark (0 to 1)
##   events      event -> personality type ("hunter"...) or "any" -> lines
##   named       NPC name (mecha_name) -> event -> lines, used first
##   broadcasts  broadcast kind -> lines NPCs send to Local
## A line may use {target}: the target's callsign, or "someone".
##
## A bark is only worth anything if the player hears it: Enemy.bark checks
## EARSHOT first and does nothing more for an NPC out of it. Then come the
## cooldowns: one per NPC (NPC_COOLDOWN, kept on the NPC) and one across all
## NPCs (GLOBAL_COOLDOWN, kept here), both in real time.

const PATH := "res://database/npcs/barks.json"
## How far (px) a bark carries: 75 m. Placeholder.
const EARSHOT := 1500.0
## Seconds before the same NPC may bark again, and before any NPC may.
## Placeholders.
const NPC_COOLDOWN := 8.0
const GLOBAL_COOLDOWN := 1.5
const SOMEONE := "someone"

static var _data := {}
static var _global_ready_ms := 0


## The bark file, loaded once.
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Barks: %s isn't valid JSON" % PATH)
	return _data


## Every event that has lines.
static func events() -> Array:
	return data().get("events", {}).keys()


static func chance_for(event: String) -> float:
	return float(data().get("chances", {}).get(event, 0.0))


## A line for `event`: the named NPC's own lines first, then its
## personality type's, then "any". "" when there are none.
static func line_for(event: String, personality_type: String, npc_name := "", target = null) -> String:
	var lines: Array = data().get("named", {}).get(npc_name, {}).get(event, [])
	if lines.is_empty():
		var by_type: Dictionary = data().get("events", {}).get(event, {})
		lines = by_type.get(personality_type, by_type.get("any", []))
	if lines.is_empty():
		return ""
	return fill(str(lines.pick_random()), target)


## A line for an NPC broadcast kind ("found_loot", "need_help"); "" if none.
static func broadcast_line(kind: String) -> String:
	var lines: Array = data().get("broadcasts", {}).get(kind, [])
	return str(lines.pick_random()) if not lines.is_empty() else ""


## Puts the target's name in for {target}: its callsign, or "someone" for an
## Anonymous pilot, a creature or nobody.
static func fill(line: String, target = null) -> String:
	if not line.contains("{target}"):
		return line
	var who := SOMEONE
	if is_instance_valid(target) and target is Node and (target as Node).is_in_group("mecha") \
			and target.get("is_anonymous") != true:
		who = LocalPilots.name_of(target)
	return line.replace("{target}", who)


## The lowercase personality type name ("hunter"), "any" without one.
static func type_name(personality: Personality) -> String:
	if personality == null:
		return "any"
	return str(Personality.Type.keys()[personality.type]).to_lower()


static func global_ready() -> bool:
	return Time.get_ticks_msec() >= _global_ready_ms


static func use_global() -> void:
	_global_ready_ms = Time.get_ticks_msec() + int(GLOBAL_COOLDOWN * 1000.0)


## Clears the shared cooldown (tests).
static func reset_cooldown() -> void:
	_global_ready_ms = 0
