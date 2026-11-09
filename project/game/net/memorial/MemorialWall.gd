class_name MemorialWall
extends RefCounted

## The Memorial Wall's registry (memorialwall.org): pilots who didn't come
## back. PilotNet owns one (PilotNet.memorial), so it shares PilotNet's day
## and is saved in PilotNet's data under "memorial". The pages are
## game/ui/net/sites/memorial/; the data is database/memorial/.
##
## A record is a Dictionary:
##   id              a unique int, shown as "#041221"
##   callsign        the name the public knew; UNIDENTIFIED for an Anonymous
##                   pilot
##   real_callsign   the pilot's own callsign (never shown; retired)
##   squad_tag       its squad's tag, "" for none or an Anonymous pilot
##   day             the day it was lost (PilotNet.day)
##   site            where: the expedition's site, or a background region
##   build           slot -> part id, taken from the mecha at death
##   cause           "pilot", "entity" or "unknown"; cause_detail is the
##                   Entity's species for "entity"
##   last_seen_with  the public name of the pilot that killed it, or ""
##   last_words      its last line on Local, or ""
##   personality     its personality type ("hunter"...)
##   named           a named NPC (special_npc); background: a background loss
##   candles         NPC candles (they grow for CANDLE_DAYS); player_candle
##   comments        [{author, text, day, time}], rolled when the record is
##                   made; one shows from its day on. The player's message is
##                   one of them, by "{player}"
##   player_kill     the player killed it. Never shown: the story flag
##                   OWN_KILL_FLAG counts the candles the player lights for
##                   these
##
## A pilot lost in an expedition (record_loss, from CombatScene) waits as
## pending until the next day (on_new_day), so it isn't on the Wall during
## its run. Each new day also adds BACKGROUND_PER_DAY losses elsewhere for the
## day before, rolled from that day (the same day always gives the same
## losses); start() puts up BACKFILL_DAYS of them before Day 1. Every lost
## callsign is retired: the callsign generator never gives it again. At most
## MAX_RECORDS stay: the oldest generic and background records go first,
## never named records or the player's kills.
##
## The player's own losses (LIST_PLAYER_MISSING): the day after the player
## loses an expedition the side column shows MISSING, PRESUMED LOST; the next
## deployment withdraws it (and counts). The story flag HIDE_PLAYER_FLAG hides
## it. The player is never a record.

const DATA_DIR := "res://database/memorial/"
const REGIONS_PATH := DATA_DIR + "regions.json"
const CONDOLENCES_PATH := DATA_DIR + "condolences.json"
const TRIBUTES_PATH := DATA_DIR + "tributes.json"
const SITE_PATH := DATA_DIR + "site.json"
const BACKGROUND_PER_DAY := [3, 8]
const BACKFILL_DAYS := 14
const BACKGROUND_SALT := 1997
const ENTITY_SHARE := 0.3
const MAX_RECORDS := 1000
## Every loss since the Impact before the first record (a placeholder).
const REGISTRY_BASE := 41220
const UNIDENTIFIED := "Unidentified pilot"
const UNKNOWN_SITE := "Unknown"
const LIST_PLAYER_MISSING := true
const CANDLES_START := [0, 12]
const CANDLES_SQUAD := [4, 10]
const CANDLES_NAMED := [15, 40]
const CANDLE_DAYS := 7
const CANDLES_PER_DAY := [0, 3]
const CANDLES_PER_DAY_NAMED := [2, 8]
const COMMENTS_GENERIC := [0, 6]
const COMMENTS_NAMED := [6, 14]
const COMMENT_DELAY := [0, 3]
const COMMENT_REROLLS := 4
const MESSAGE_LENGTH := 100
const WEEK := 7
const OWN_KILL_FLAG := "memorial_candles_for_own_kills"
const HIDE_PLAYER_FLAG := "memorial_hide_player"
const LOST_FLAG := "lost:%s"
const PLAYER_AUTHOR := "{player}"
const TEST_NPC := "Test Dummy"
const CAUSES := ["pilot", "entity", "unknown"]
const GROUPS := ["stranger", "squadmate", "entity_loss", "rival", "anonymous"]
const RIVAL_TYPES := ["hunter", "rat"]
const LOG_SKIP := ["joined", "left"]
## The build's slots in table order: [label, slot, part type].
const BUILD_SLOTS := [["Head", "head", "head"], ["Core", "core", "core"], ["Shoulders", "shoulders", "shoulders"],
		["Chassis", "chassis", "chassis"], ["Generator", "generator", "generator"], ["Chipset", "chipset", "chipset"],
		["Thruster", "thruster", "thruster"], ["L arm", "arm_weapon_left", "arm_weapon"],
		["R arm", "arm_weapon_right", "arm_weapon"], ["L shoulder", "shoulder_weapon_left", "shoulder_weapon"],
		["R shoulder", "shoulder_weapon_right", "shoulder_weapon"], ["Internal", "internal", "internal"]]

## Records on the Wall, oldest first.
var records: Array = []
## Records lost today, up tomorrow.
var pending: Array = []
## The expedition's site (Expedition sets it as it starts).
var current_site := ""
## The player's notice: {} or {"state": "lost" / "missing" / "withdrawn",
## "site", "day", "withdrawn" (how many times)}.
var player_notice: Dictionary = {}
## Records ever put up (the registry counts REGISTRY_BASE plus these).
var total := 0
var next_id := REGISTRY_BASE + 1
var last_day := 0
## Problems found reading database/memorial/.
var load_errors: Array = []

var _retired: Dictionary = {}
var _by_id: Dictionary = {}
var _data: Dictionary = {}
var _catalogue: Dictionary = {}


# ---- data ---------------------------------------------------------------------

## The data files, read once: {"regions", "condolences", "tributes", "site"}.
func data() -> Dictionary:
	if _data.is_empty():
		load_errors.clear()
		_data = {"regions": [], "condolences": {}, "tributes": {}, "site": {}}
		var regions = _read(REGIONS_PATH)
		if regions is Dictionary and regions.get("regions") is Array:
			_data.regions = regions.regions
		var condolences = _read(CONDOLENCES_PATH)
		if condolences is Dictionary:
			_data.condolences = condolences
		var tributes = _read(TRIBUTES_PATH)
		if tributes is Dictionary:
			_data.tributes = tributes
		var site = _read(SITE_PATH)
		if site is Dictionary:
			_data.site = site
	return _data


## Reads the data files again (F9 with pilot.net's).
func reload_content() -> void:
	_data = {}
	data()


func _read(path: String):
	if not FileAccess.file_exists(path):
		load_errors.append("%s: missing" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		load_errors.append("%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## A site text from site.json ("welcome", "about", "moderator"), "" for none.
func site_text(key: String) -> String:
	return str(data().site.get(key, ""))


# ---- the day ------------------------------------------------------------------

## A new profile: an empty Wall, then BACKFILL_DAYS of background losses
## before Day 1, their candles grown to Day 1.
func start() -> void:
	reset()
	for loss_day in range(1 - BACKFILL_DAYS, 1):
		for record in _background(loss_day):
			_publish(record, false)
	for record in records:
		_grow_candles(record, int(record.day) + 1, 1)
	last_day = 1


## start() for a Wall that was never started or loaded (a profile that never
## reached PilotNet's reset or load).
func ensure_started() -> void:
	if last_day <= 0 and records.is_empty() and pending.is_empty():
		start()


func reset() -> void:
	records = []
	pending = []
	player_notice = {}
	total = 0
	next_id = REGISTRY_BASE + 1
	last_day = 0
	_retired = {}
	_by_id = {}


## PilotNet's day moved on to today: pending records go up, each day in
## between adds its background losses (for the day before), candles grow, a
## lost player's notice shows, and the oldest records past MAX_RECORDS go.
func on_new_day(today: int) -> void:
	if last_day <= 0:
		last_day = today - 1
	for this_day in range(last_day + 1, today + 1):
		for record in pending:
			_publish(record, true)
		pending = []
		for record in _background(this_day - 1):
			_publish(record, true)
		for record in records:
			if this_day - int(record.day) <= CANDLE_DAYS and this_day > int(record.day):
				_grow_candles(record, this_day, this_day)
		if player_notice.get("state") == "lost":
			player_notice.state = "missing"
	last_day = maxi(last_day, today)
	_prune()


func _publish(record: Dictionary, announce: bool) -> void:
	records.append(record)
	_by_id[int(record.id)] = record
	total += 1
	if announce:
		PilotNet.pilot_lost.emit(record)


func _prune() -> void:
	while records.size() > MAX_RECORDS:
		var index := -1
		for i in records.size():
			if not records[i].named and not records[i].player_kill:
				index = i
				break
		if index < 0:
			return
		_by_id.erase(int(records[index].id))
		records.remove_at(index)


# ---- losses -------------------------------------------------------------------

## An NPC mecha was killed in an expedition (CombatScene, before it is
## freed): its record waits as pending until the next day. killer is what
## killed it (a mecha, an Entity) or null. Returns the record.
func record_loss(mecha, killer) -> Dictionary:
	if not is_instance_valid(mecha):
		return {}
	var anonymous: bool = mecha.get("is_anonymous") == true
	var real := str(mecha.get("callsign")) if str(mecha.get("callsign")) != "" else str(mecha.get("mecha_name"))
	var record := _new_record()
	record.callsign = UNIDENTIFIED if anonymous else real
	record.real_callsign = real
	var tag = mecha.get("squad_tag")
	record.squad_tag = "" if anonymous or not tag is String else tag
	record.day = int(PilotNet.day)
	record.site = current_site if current_site != "" else UNKNOWN_SITE
	record.build = build_of(mecha)
	_set_cause(record, mecha, killer)
	record.last_words = last_words_of(mecha)
	record.personality = personality_of(mecha)
	record.named = not anonymous and is_named(real)
	record.player_kill = is_instance_valid(killer) and killer.has_method("is_player") and killer.is_player()
	var rng := _record_rng(int(record.id))
	var mates := squadmates_of(mecha)
	var rival := ""
	if record.cause == "pilot" and is_instance_valid(killer) and not record.player_kill and killer.get("is_anonymous") != true \
			and personality_of(killer) in RIVAL_TYPES:
		rival = str(killer.get("callsign"))
	record.candles = _start_candles(rng, record, not mates.is_empty() or record.squad_tag != "")
	record.comments = _roll_comments(rng, record, mates, rival)
	retire(real)
	pending.append(record)
	if record.named:
		StoryDirector.set_flag(LOST_FLAG % real, true, false)
	return record


func _set_cause(record: Dictionary, mecha, killer) -> void:
	if is_instance_valid(killer) and killer is Entity:
		record.cause = "entity"
		record.cause_detail = str(killer.species)
	elif is_instance_valid(killer) and killer is Node and (killer as Node).is_in_group("mecha"):
		record.cause = "pilot"
		var local := LocalPilots.current
		var on_roster := local != null and local.is_in_local(killer)
		if on_roster or (killer.has_method("is_player") and killer.is_player()):
			record.last_seen_with = LocalPilots.name_of(killer)
	else:
		var source = mecha.get("last_damage_source")
		var name := str(source.get("name", "")) if source is Dictionary else ""
		if name != "" and name in PilotNet.spawnable_kinds() and name != "mech":
			record.cause = "entity"
			record.cause_detail = name


## The mecha's design: slot -> part id (empty slots left out).
static func build_of(mecha) -> Dictionary:
	var build := {}
	if mecha.has_method("get_design_data"):
		var design = mecha.get_design_data()
		if design is Dictionary:
			for slot in design:
				if design[slot] is String and str(design[slot]) != "":
					build[str(slot)] = str(design[slot])
	return build


## The mecha's last line on Local (a bark or a broadcast, not its join or
## leave line), "" for none.
static func last_words_of(mecha) -> String:
	var local := LocalPilots.current
	if local == null:
		return ""
	var entries := local.get_log()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if entry.sender == mecha and not str(entry.kind) in LOG_SKIP:
			return str(entry.text)
	return ""


## A mecha's personality type in lower case ("hunter"), "" for none.
static func personality_of(mecha) -> String:
	var personality = mecha.get("personality") if is_instance_valid(mecha) else null
	if personality is Personality:
		var key = Personality.Type.find_key(personality.type)
		return str(key).to_lower() if key != null else ""
	return ""


## The callsigns of the living members of the mecha's squad (an Anonymous
## squad has none to give; never the player).
static func squadmates_of(mecha) -> Array:
	var mates := []
	var knowledge = mecha.get("knowledge")
	var squad = knowledge.get("squad") if knowledge != null else null
	if squad == null or squad.anonymous:
		return mates
	for member in squad.alive_members():
		if member == mecha or not is_instance_valid(member) or member.is_anonymous:
			continue
		if member.has_method("is_player") and member.is_player():
			continue
		if str(member.callsign) != "":
			mates.append(str(member.callsign))
	return mates


## Whether a callsign is a named NPC's (special_npc), Test Dummy aside.
static func is_named(callsign: String) -> bool:
	for npc in NPCManager.SPECIAL_NPCS:
		var name := str(npc.get("mecha_name")) if npc != null else ""
		if name != TEST_NPC and name.to_lower() == callsign.to_lower():
			return true
	return false


# Background losses for one day, rolled from the day alone.
func _background(loss_day: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = loss_day + BACKGROUND_SALT
	var made := []
	var regions: Array = data().regions
	for i in rng.randi_range(BACKGROUND_PER_DAY[0], BACKGROUND_PER_DAY[1]):
		var record := _new_record()
		record.background = true
		record.callsign = CallsignGenerator.generate(rng, _retired)
		record.real_callsign = record.callsign
		record.day = loss_day
		record.site = str(regions[rng.randi_range(0, regions.size() - 1)]) if not regions.is_empty() else UNKNOWN_SITE
		record.personality = ["scavenger", "guardian", "professional", "hunter", "rat"][rng.randi_range(0, 4)]
		if rng.randf() < ENTITY_SHARE:
			var species := PilotNet.spawnable_kinds().filter(func(k): return k != "mech")
			if not species.is_empty():
				record.cause = "entity"
				record.cause_detail = str(species[rng.randi_range(0, species.size() - 1)])
		record.build = _random_build(rng)
		record.candles = _start_candles(rng, record, false)
		record.comments = _roll_comments(rng, record, [], "")
		retire(record.callsign)
		made.append(record)
	return made


# One listed part for each slot a mecha needs.
func _random_build(rng: RandomNumberGenerator) -> Dictionary:
	var build := {}
	for slot in PlayerProgress.REQUIRED_SLOTS:
		if not _catalogue.has(slot):
			_catalogue[slot] = Store.catalogue(slot)
		var parts: Array = _catalogue[slot]
		if not parts.is_empty():
			build[slot] = str(parts[rng.randi_range(0, parts.size() - 1)])
	return build


func _new_record() -> Dictionary:
	var record := {"id": next_id, "callsign": "", "real_callsign": "", "squad_tag": "", "day": int(PilotNet.day),
			"site": UNKNOWN_SITE, "build": {}, "cause": "unknown", "cause_detail": "", "last_seen_with": "",
			"last_words": "", "personality": "", "named": false, "background": false, "candles": 0,
			"player_candle": false, "comments": [], "player_kill": false}
	next_id += 1
	return record


func _record_rng(id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("memorial:%d" % id).hash()
	return rng


func _start_candles(rng: RandomNumberGenerator, record: Dictionary, squad: bool) -> int:
	var candles := rng.randi_range(CANDLES_START[0], CANDLES_START[1])
	if squad:
		candles += rng.randi_range(CANDLES_SQUAD[0], CANDLES_SQUAD[1])
	if record.named:
		candles += rng.randi_range(CANDLES_NAMED[0], CANDLES_NAMED[1])
	return candles


# The candles a record gains from day `from` to day `to` (the record's own
# rng for each day, so the same day always adds the same).
func _grow_candles(record: Dictionary, from: int, to: int) -> void:
	for this_day in range(from, to + 1):
		if this_day - int(record.day) > CANDLE_DAYS or this_day <= int(record.day):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = ("candles:%d:%d" % [int(record.id), this_day]).hash()
		var span: Array = CANDLES_PER_DAY_NAMED if record.named else CANDLES_PER_DAY
		record.candles = int(record.candles) + rng.randi_range(span[0], span[1])


func _roll_comments(rng: RandomNumberGenerator, record: Dictionary, mates: Array, rival: String) -> Array:
	var comments := []
	var span: Array = COMMENTS_NAMED if record.named else COMMENTS_GENERIC
	var taken := _retired.duplicate()
	var used := {}
	for i in rng.randi_range(span[0], span[1]):
		var group := "stranger"
		if record.callsign == UNIDENTIFIED:
			group = "anonymous"
		elif record.cause == "entity" and rng.randf() < 0.5:
			group = "entity_loss"
		var author := CallsignGenerator.generate(rng, taken)
		taken[author.to_lower()] = true
		comments.append(_comment(rng, group, author, record, used))
	for mate in mates:
		comments.append(_comment(rng, "squadmate", str(mate), record, used))
	if rival != "":
		comments.append(_comment(rng, "rival", rival, record, used))
	comments.sort_custom(func(a, b): return a.day < b.day if a.day != b.day else a.time < b.time)
	return comments


# One comment from a group's lines; a line used on this record already
# (used: "group:index") is rolled again, a few times at most.
func _comment(rng: RandomNumberGenerator, group: String, author: String, record: Dictionary, used: Dictionary) -> Dictionary:
	var lines = data().condolences.get(group, [])
	var text := "o7"
	if lines is Array and not lines.is_empty():
		var index := rng.randi_range(0, lines.size() - 1)
		for attempt in COMMENT_REROLLS:
			if not used.has("%s:%d" % [group, index]):
				break
			index = rng.randi_range(0, lines.size() - 1)
		used["%s:%d" % [group, index]] = true
		text = str(lines[index])
	text = text.replace("{name}", str(record.callsign))
	var delay := rng.randi_range(COMMENT_DELAY[0], COMMENT_DELAY[1])
	return {"author": author, "text": text, "day": int(record.day) + delay, "time": fake_time(author + text)}


## A time of day made from text ("03:14"), the same every time.
static func fake_time(text: String) -> String:
	var h := absi(text.hash())
	@warning_ignore("integer_division")
	return "%02d:%02d" % [h % 24, (h / 24) % 60]


# ---- the player ---------------------------------------------------------------

## The player lost an expedition (PilotNet, before the day moves on).
func note_player_lost() -> void:
	if not LIST_PLAYER_MISSING:
		return
	player_notice = {"state": "lost", "site": current_site if current_site != "" else UNKNOWN_SITE,
			"day": int(PilotNet.day), "withdrawn": int(player_notice.get("withdrawn", 0))}


## The player deployed: a MISSING notice is withdrawn.
func note_deployed() -> void:
	if player_notice.get("state") in ["lost", "missing"]:
		player_notice.state = "withdrawn"
		player_notice.withdrawn = int(player_notice.get("withdrawn", 0)) + 1


## The side column's notice about the player: [the line, the count line],
## [] while there is none or the story hides it.
func player_notice_lines() -> Array:
	if StoryDirector.get_flag(HIDE_PLAYER_FLAG, false) == true:
		return []
	var state = player_notice.get("state")
	if state == "missing":
		return ["MISSING, PRESUMED LOST: %s (%s)" % [PlayerProgress.get_callsign(), str(player_notice.site)], ""]
	if state == "withdrawn":
		var count := int(player_notice.get("withdrawn", 1))
		return ["NOTICE WITHDRAWN: pilot reported alive", "Withdrawn %d time%s" % [count, "" if count == 1 else "s"]]
	return []


## Lights the player's candle on a record (one each); false if lit already.
## Lighting one for the player's own kill counts in OWN_KILL_FLAG.
func light_candle(id: int) -> bool:
	var record := get_record(id)
	if record.is_empty() or record.player_candle:
		return false
	record.player_candle = true
	if record.player_kill:
		StoryDirector.set_flag(OWN_KILL_FLAG, int(StoryDirector.get_flag(OWN_KILL_FLAG, 0)) + 1, false)
	return true


## The player's one message on a record (cut to MESSAGE_LENGTH); false when
## there is one already or the text is empty.
func post_message(id: int, text: String) -> bool:
	var record := get_record(id)
	var line := text.strip_edges().left(MESSAGE_LENGTH)
	if record.is_empty() or line == "" or has_player_message(id):
		return false
	record.comments.append({"author": PLAYER_AUTHOR, "text": line, "day": int(PilotNet.day),
			"time": fake_time(PlayerProgress.get_callsign() + line)})
	return true


func has_player_message(id: int) -> bool:
	var record := get_record(id)
	return not record.is_empty() and record.comments.any(func(c): return c.author == PLAYER_AUTHOR)


# ---- reading ------------------------------------------------------------------

func get_record(id: int) -> Dictionary:
	return _by_id.get(id, {})


## The newest records first, count at most (0 for all).
func newest(count := 0) -> Array:
	var list := records.duplicate()
	list.reverse()
	return list if count <= 0 else list.slice(0, count)


## The comments that show today (their day has come), oldest first.
func visible_comments(record: Dictionary) -> Array:
	return record.get("comments", []).filter(func(c): return int(c.day) <= int(PilotNet.day))


## The candles shown: the NPCs' and the player's.
static func candle_count(record: Dictionary) -> int:
	return int(record.get("candles", 0)) + (1 if record.get("player_candle", false) else 0)


## Records whose callsign, squad tag, site or a part name contain the text
## (any case), newest first.
func search(text: String) -> Array:
	var wanted := text.strip_edges().to_lower()
	if wanted == "":
		return []
	return newest().filter(func(r):
		if wanted in str(r.callsign).to_lower() or wanted in str(r.squad_tag).to_lower() or wanted in str(r.site).to_lower():
			return true
		for slot in r.build:
			if wanted in part_name(str(slot), str(r.build[slot])).to_lower():
				return true
		return false)


## A tag: a cause ("pilot", "entity", "unknown") or a site; records with it,
## newest first.
func tagged(tag: String) -> Array:
	var wanted := tag.to_lower()
	return newest().filter(func(r): return str(r.cause) == wanted or str(r.site).to_lower() == wanted)


## The tag cloud: {tag: count} for every cause and site on the Wall.
func tag_counts() -> Dictionary:
	var counts := {}
	for record in records:
		counts[str(record.cause)] = int(counts.get(str(record.cause), 0)) + 1
		counts[str(record.site)] = int(counts.get(str(record.site), 0)) + 1
	return counts


## Records lost within the last WEEK days, newest first.
func this_week() -> Array:
	var today := int(PilotNet.day)
	return newest().filter(func(r): return today - int(r.day) <= WEEK)


## The records with the most candles and messages, count at most.
func most_remembered(count: int) -> Array:
	var list := records.duplicate()
	list.sort_custom(func(a, b):
		var sa := candle_count(a) + visible_comments(a).size()
		var sb := candle_count(b) + visible_comments(b).size()
		return sa > sb if sa != sb else int(a.id) > int(b.id))
	return list.slice(0, count)


## Every pilot ever registered: REGISTRY_BASE and the records put up.
func registry_total() -> int:
	return REGISTRY_BASE + total


func candles_lit() -> int:
	var count := 0
	for record in records:
		count += candle_count(record)
	return count


## The newest record of a callsign (any case; not "Unidentified pilot"), {}
## for none.
func record_of(callsign: String) -> Dictionary:
	var wanted := callsign.to_lower()
	if wanted == UNIDENTIFIED.to_lower():
		return {}
	for i in range(records.size() - 1, -1, -1):
		if str(records[i].callsign).to_lower() == wanted:
			return records[i]
	return {}


## A record's tribute (named pilots): tributes.json's, else Lorem Ipsum.
func tribute_of(record: Dictionary) -> String:
	var tributes: Dictionary = data().tributes
	var text = tributes.get(str(record.callsign))
	return str(text) if text is String and text != "" else Steelapedia.lorem("tribute:" + str(record.callsign), 1)


## "Pilot engagement", "Entity: Coyote", "Unknown".
static func cause_text(record: Dictionary) -> String:
	if record.cause == "pilot":
		return "Pilot engagement"
	if record.cause == "entity":
		return "Entity: %s" % record.cause_detail if str(record.cause_detail) != "" else "Entity activity"
	return "Unknown"


## A tag's name for the cloud: a cause's words, else the site itself.
static func tag_name(tag: String) -> String:
	if tag == "pilot":
		return "Pilot engagement"
	if tag == "entity":
		return "Entity activity"
	if tag == "unknown":
		return "Unknown"
	return tag


static func part_name(slot: String, part_id: String) -> String:
	for entry in BUILD_SLOTS:
		if entry[1] == slot:
			return Store.part_name(entry[2], part_id)
	return part_id


# ---- callsigns ----------------------------------------------------------------

func retire(callsign: String) -> void:
	if callsign != "":
		_retired[callsign.to_lower()] = true


func is_retired(callsign: String) -> bool:
	return _retired.has(callsign.to_lower())


# ---- save ---------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"records": records.duplicate(true), "pending": pending.duplicate(true), "retired": _retired.keys(),
			"player_notice": player_notice.duplicate(), "total": total, "next_id": next_id, "last_day": last_day}


func set_save_data(saved: Dictionary) -> void:
	reset()
	for raw in saved.get("records", []):
		if raw is Dictionary:
			var record := _normal(raw)
			records.append(record)
			_by_id[int(record.id)] = record
	for raw in saved.get("pending", []):
		if raw is Dictionary:
			pending.append(_normal(raw))
	for name in saved.get("retired", []):
		_retired[str(name).to_lower()] = true
	var notice = saved.get("player_notice", {})
	if notice is Dictionary and not notice.is_empty():
		player_notice = notice.duplicate()
		player_notice.withdrawn = int(notice.get("withdrawn", 0))
		player_notice.day = int(notice.get("day", 0))
	total = int(saved.get("total", records.size()))
	next_id = maxi(int(saved.get("next_id", REGISTRY_BASE + 1)), REGISTRY_BASE + 1)
	last_day = int(saved.get("last_day", PilotNet.day))


# A record from a save: JSON's numbers back to ints.
func _normal(raw: Dictionary) -> Dictionary:
	var record: Dictionary = raw.duplicate(true)
	for key in ["id", "day", "candles"]:
		record[key] = int(record.get(key, 0))
	for key in ["named", "background", "player_candle", "player_kill"]:
		record[key] = record.get(key, false) == true
	var comments := []
	for comment in record.get("comments", []):
		if comment is Dictionary:
			comments.append({"author": str(comment.get("author", "")), "text": str(comment.get("text", "")),
					"day": int(comment.get("day", 0)), "time": str(comment.get("time", ""))})
	record.comments = comments
	var build := {}
	var saved_build = record.get("build", {})
	if saved_build is Dictionary:
		for slot in saved_build:
			build[str(slot)] = str(saved_build[slot])
	record.build = build
	return record


# ---- content checks -----------------------------------------------------------

## Every problem in database/memorial/ (MemorialWallTest fails on any).
func check_content() -> Array:
	reload_content()
	var errors: Array = load_errors.duplicate()
	if data().regions.is_empty():
		errors.append("%s: no regions" % REGIONS_PATH)
	for group in GROUPS:
		var lines = data().condolences.get(group)
		if not lines is Array or lines.is_empty():
			errors.append("%s: no lines for '%s'" % [CONDOLENCES_PATH, group])
	for key in ["welcome", "about", "moderator"]:
		if site_text(key) == "":
			errors.append("%s: no '%s'" % [SITE_PATH, key])
	return errors
