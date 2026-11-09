class_name LocalPilots
extends RefCounted

## Local: the chat channel of one match. CombatScene makes one
## (local_pilots) and registers every mecha as it enters the map (join), and
## takes it off when it dies or extracts (leave). The HUD feed, the LOC app
## and NPC code read it; LocalPilots.current is the one of the latest match,
## kept after it ends so the LOC app in the hub shows the last run's log.
##
## Pilots:
##   - Each has a callsign (Mecha.callsign). NPCs without one are given one by
##     CallsignGenerator, never two the same in a match (nor a named NPC's,
##     the player's or one retired on the Memorial Wall).
##   - The roster lists the pilots who aren't Anonymous (Mecha.is_anonymous).
##   - After the intro (go_live) a pilot that joins is announced: "<name> has
##     joined Local". Whoever leaves, dead or extracted, gets the same line:
##     "<name> has left Local". Anonymous pilots get neither line, and their
##     messages show "Unknown".
##
## Messages (signal message, the log, MechLog source "LOC"). Each is an
## entry Dictionary:
##   sender    the mecha (may since have been freed)
##   callsign  the name shown: its callsign, or "Unknown"
##   kind      "joined", "left", "bark", or a broadcast kind (QUICK_CHAT,
##             "found_loot", "need_help"...)
##   text      the line
##   position  where the sender was; never shown to players
##   time      game time (s) of the match when sent
##   bark      true for speech the player heard (see Mecha.say)
##
## Reputation: the first hit between two pilots records who struck first
## (note_attack). The player killing a pilot who didn't strike the player
## first costs reputation (score_player_kill).

signal message(entry: Dictionary)
signal roster_changed
## A mecha hit another (as Mecha.register_hit reports it): NPCs witness it.
signal attack_noted(attacker, victim)

const UNKNOWN := "Unknown"
const MAX_LOG := 300
## The player's quick chat presets, in menu order. Placeholder list.
const QUICK_CHAT := [
	{"kind": "need_help", "text": "Need help!"},
	{"kind": "friendly", "text": "Friendly."},
	{"kind": "found_loot", "text": "Found loot here."},
	{"kind": "back_off", "text": "Back off."},
	{"kind": "hostile_spotted", "text": "Hostile spotted."},
]
## Reputation for the player killing a pilot who didn't strike first, and
## the share of it an Anonymous player pays. Placeholders.
const UNPROVOKED_KILL_REPUTATION := -10
const ANONYMOUS_REPUTATION_SHARE := 0.5
## The Flag's reputation: attacking within TREACHERY_WINDOW s of lowering a
## Flag raised by choice, or attacking a pilot that saw the player Flagged
## (once per pilot); killing a Flagged pilot (in place of the unprovoked
## kill's cost); sparing a pilot that raised its Flag (NPC code says when,
## note_spared). Placeholders.
const TREACHERY_REPUTATION := -15
const TREACHERY_WINDOW := 10.0
const FLAGGED_KILL_REPUTATION := -20
const SPARED_REPUTATION := 5

## The latest match's channel (null before the first match).
static var current: LocalPilots = null

## Rolls the callsigns given to NPCs that join without one.
var rng := RandomNumberGenerator.new()
## While false (before the intro ends), joins are not announced.
var live := false
## Whether the match is still running (false once its scene has gone).
var active := true
## Whether kills change the player's reputation here (not in the Arena).
var applies_reputation := true
## Match time (s), advanced by the scene.
var now := 0.0

var _pilots: Array = []  # mechas that joined and haven't left
var _log: Array[Dictionary] = []
var _used_callsigns := {}
var _first_strike := {}  # pair key -> instance id of who hit first
# The player's Flag: when it last came down, whether it was raised by
# choice, and whether that lowering has been charged; pilots already charged
# for being attacked after seeing the player Flagged.
var _player_flag_down_at := -INF
var _player_flag_voluntary := false
var _player_flag_charged := true
var _charged_witnesses := {}


## The name others see for `mecha`: its callsign, with its squad's tag before
## it ("[HLX] Viktor"), or "Unknown" if it is Anonymous or gone.
static func name_of(mecha) -> String:
	if not is_instance_valid(mecha):
		return UNKNOWN
	if mecha.get("is_anonymous") == true:
		return UNKNOWN
	var callsign = mecha.get("callsign")
	var name: String = callsign if callsign is String and callsign != "" else str(mecha.get("mecha_name"))
	var tag = mecha.get("squad_tag")
	if tag is String and tag != "":
		return "[%s] %s" % [tag, name]
	return name


## How many pilots on the roster carry squad tag `tag` (a tagged squad's
## size, which the roster gives away; an Anonymous squad shows none).
func count_tag(tag: String) -> int:
	if tag == "":
		return 0
	var count := 0
	for mecha in _pilots:
		if is_instance_valid(mecha) and not mecha.is_anonymous and mecha.get("squad_tag") == tag:
			count += 1
	return count


## The pilot on the roster whose name (as others see it) is `name`, or null.
func pilot_named(name: String):
	for mecha in _pilots:
		if is_instance_valid(mecha) and name_of(mecha) == name:
			return mecha
	return null


## "Ash: Need help!", or the line itself for joins and leaves.
static func format(entry: Dictionary) -> String:
	if entry.kind == "joined" or entry.kind == "left":
		return entry.text
	return "%s: %s" % [entry.callsign, entry.text]


func _init() -> void:
	rng.randomize()


func go_live() -> void:
	live = true


## The match is over (its scene is leaving): the roster empties and every
## listener is let go, so nothing from the match outlives it. The log stays
## for the LOC app, without its senders.
func close() -> void:
	active = false
	_pilots.clear()
	for entry in _log:
		entry.sender = null
	for signal_name in ["message", "roster_changed"]:
		for connection in get_signal_connection_list(signal_name):
			disconnect(signal_name, connection.callable)


func join(mecha) -> void:
	if not is_instance_valid(mecha) or _pilots.has(mecha):
		return
	if str(mecha.callsign) == "":
		mecha.callsign = _free_callsign()
	_used_callsigns[mecha.callsign] = true
	_pilots.append(mecha)
	if mecha.is_anonymous:
		return
	# pilot.net remembers the pilots the player has met in an expedition.
	if PlayerProgress.is_in_expedition() and not (mecha.has_method("is_player") and mecha.is_player()):
		PilotNet.note_met(str(mecha.callsign))
	roster_changed.emit()
	if live:
		_post(mecha, "joined", "%s has joined Local" % name_of(mecha))


func leave(mecha) -> void:
	if not _pilots.has(mecha):
		return
	_pilots.erase(mecha)
	if is_instance_valid(mecha) and mecha.is_anonymous:
		return
	roster_changed.emit()
	_post(mecha, "left", "%s has left Local" % name_of(mecha))


func is_in_local(mecha) -> bool:
	return _pilots.has(mecha)


## The callsigns of the pilots on the roster (not Anonymous), in join order.
func get_roster() -> Array[String]:
	var names: Array[String] = []
	for mecha in _pilots:
		if is_instance_valid(mecha) and not mecha.is_anonymous:
			names.append(name_of(mecha))
	return names


## Every message so far, oldest first.
func get_log() -> Array[Dictionary]:
	return _log


## A deliberate message to everyone on the map. `text` "" uses the preset
## text of a QUICK_CHAT kind.
func broadcast(sender, kind: String, text := "") -> Dictionary:
	if text == "":
		for preset in QUICK_CHAT:
			if preset.kind == kind:
				text = preset.text
	return _post(sender, kind, text)


## Speech the player heard (CombatScene._on_mecha_spoke).
func post_bark(speaker, text: String) -> Dictionary:
	return _post(speaker, "bark", text, true)


# ---- Reputation ----

## Records who struck first between `attacker` and `victim` (mechas only),
## tells the NPCs (attack_noted), and charges the player's treachery: an
## attack within TREACHERY_WINDOW s of lowering a Flag raised by choice, or
## on a pilot that saw the player Flagged.
func note_attack(attacker, victim) -> void:
	if not _is_mecha(attacker) or not _is_mecha(victim) or attacker == victim:
		return
	var key := _pair_key(attacker, victim)
	if not _first_strike.has(key):
		_first_strike[key] = attacker.get_instance_id()
	if attacker.has_method("is_player") and attacker.is_player():
		if _player_flag_voluntary and now - _player_flag_down_at <= TREACHERY_WINDOW:
			# Within the window, one charge for the lowering, whoever is hit.
			if not _player_flag_charged:
				_player_flag_charged = true
				_change_reputation(attacker, TREACHERY_REPUTATION, "attacked after lowering the Flag")
		elif victim.has_method("saw_flag_raised") and victim.saw_flag_raised(attacker) \
				and not _charged_witnesses.has(victim.get_instance_id()):
			_charged_witnesses[victim.get_instance_id()] = true
			_change_reputation(attacker, TREACHERY_REPUTATION, "attacked a pilot that saw you Flagged")
	attack_noted.emit(attacker, victim)


## A mecha's Flag went up (by choice or the emergency state).
func note_flag_raised(mecha, voluntary: bool) -> void:
	if mecha.has_method("is_player") and mecha.is_player():
		_player_flag_voluntary = voluntary
		_player_flag_charged = true


## A mecha's Flag came down: for the player, the treachery window starts.
func note_flag_lowered(mecha) -> void:
	if mecha.has_method("is_player") and mecha.is_player():
		_player_flag_down_at = now
		_player_flag_charged = not _player_flag_voluntary


## `sparer` left `npc` alone after it raised its Flag (NPC code decides
## when): the player gains reputation, and the pilot's hostility toward the
## player goes.
func note_spared(npc, sparer) -> void:
	if not is_instance_valid(sparer) or not sparer.has_method("is_player") or not sparer.is_player():
		return
	_change_reputation(sparer, SPARED_REPUTATION, "spared a pilot that raised its Flag")
	if npc.has_method("add_hostility"):
		npc.add_hostility(sparer, -1.0)
	if "knowledge" in npc:
		npc.knowledge.spared_by[sparer.get_instance_id()] = true


func _change_reputation(player, change: int, why: String) -> int:
	if not applies_reputation:
		return 0
	if is_instance_valid(player) and player.is_anonymous and change < 0:
		change = roundi(change * ANONYMOUS_REPUTATION_SHARE)
	PlayerProgress.add_reputation(change)
	MechLog.write("LOC", "Reputation %+d (%s)" % [change, why], MechLog.Kind.LOCAL)
	return change


## Whether `a` hit `b` before `b` hit `a`.
func struck_first(a, b) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	return _first_strike.get(_pair_key(a, b), 0) == a.get_instance_id()


## The reputation change for `player` killing `victim`:
## FLAGGED_KILL_REPUTATION for a pilot whose Flag was up, else 0 when the
## victim struck first, else UNPROVOKED_KILL_REPUTATION (a share of it while
## Anonymous). Applies it to PlayerProgress when the match applies
## reputation. Returns the change.
func score_player_kill(player, victim) -> int:
	if not applies_reputation or not _is_mecha(victim):
		return 0
	if victim.get("flag_up") == true:
		return _change_reputation(player, FLAGGED_KILL_REPUTATION, "killed a Flagged pilot")
	if struck_first(victim, player):
		return 0
	return _change_reputation(player, UNPROVOKED_KILL_REPUTATION, "unprovoked kill")


func _post(sender, kind: String, text: String, bark := false) -> Dictionary:
	var entry := {
		"sender": sender,
		"callsign": name_of(sender),
		"kind": kind,
		"text": text,
		"position": sender.global_position if is_instance_valid(sender) else Vector2.ZERO,
		"time": now,
		"bark": bark,
	}
	_log.append(entry)
	if _log.size() > MAX_LOG:
		_log.pop_front()
	MechLog.write("LOC", format(entry), MechLog.Kind.LOCAL)
	message.emit(entry)
	return entry


func _free_callsign() -> String:
	return CallsignGenerator.generate(rng, _used_callsigns)


static func _is_mecha(node) -> bool:
	return is_instance_valid(node) and node is Node and (node as Node).is_in_group("mecha")


static func _pair_key(a: Object, b: Object) -> String:
	var x := a.get_instance_id()
	var y := b.get_instance_id()
	return "%d:%d" % [mini(x, y), maxi(x, y)]
