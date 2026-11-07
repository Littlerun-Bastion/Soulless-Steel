extends TestSuite

# MemorialWallTest: the Memorial Wall (memorialwall.org: MemorialWall,
# MemorialWallPage, MemorialCandle, database/memorial/) and the NET's links to
# it. Pages load instantly (NetWindow.load_time_scale 0).
#   - the data files are valid; a tribute for every named NPC
#   - CombatScene: an NPC killed in an expedition makes a pending record, one
#     that extracts doesn't, an Arena kill doesn't; it goes up the next day
#     (pilot_lost)
#   - the cause and its detail for an Entity, an NPC and the player as the
#     killer, and for none; last_seen_with names the player, or Unknown when
#     the player is Anonymous
#   - last words: the pilot's last line on Local
#   - an Anonymous pilot is "Unidentified pilot", its callsign still retired;
#     lost callsigns are never generated again
#   - background losses: 3-8 a day, the same day the same records, the
#     backfill on a new profile
#   - comments arrive over three days, show when their day comes and survive
#     save and load; the player's one message is saved
#   - candles: one from the player per record, the own-kill flag counts only
#     the player's kills, NPC candles grow for a week
#   - a named loss sets lost:<callsign> and shows its tribute
#   - the player's MISSING notice: after a loss, withdrawn (and counted) on
#     deploying, hidden by memorial_hide_player; never a record
#   - the calendar: date_text for Day 1, Day 32 and a later month
#   - MAX_RECORDS keeps named and player-kill records
#   - every Wall page opens; the record page's candle, button and message
#     form; the tag cloud; the candle stops while hidden
#   - In memoriam on pilot.net's front page (both looks), the lost line on a
#     profile, a met pilot's page and a Steelapedia pilot article

const MECHA := preload("res://game/mecha/Mecha.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const COMBAT_SCENE := preload("res://game/combat/CombatScene.gd")
const NAMED := "Lady Volk"
const SITE := "Helwan"
const NEW_LOOK_FLAG := "pilotnet_new_look"
const SAMPLE_PILOT := "[SAMPLE] Sample pilot"


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
		return Vector2.ZERO
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null
var _local_before: LocalPilots = null


func run_tests() -> void:
	_local_before = LocalPilots.current
	await case("the data files", _test_data)
	await case("a loss in an expedition is pending, then goes up the next day", _test_combat_hook)
	await case("cause, detail and last seen with", _test_causes)
	await case("last words are the pilot's last line on Local", _test_last_words)
	await case("an Anonymous pilot is Unidentified; lost callsigns never come back", _test_retired)
	await case("background losses and the backfill", _test_background)
	await case("comments and the player's message", _test_comments)
	await case("candles", _test_candles)
	await case("a named pilot's loss", _test_named)
	await case("the player's MISSING notice", _test_player_notice)
	await case("the calendar", _test_dates)
	await case("MAX_RECORDS keeps named and player-kill records", _test_prune)
	await case("every Wall page opens", _test_pages)
	await case("the record page", _test_record_page)
	await case("links from pilot.net and Steelapedia", _test_links)
	await before_each()
	LocalPilots.current = _local_before
	NetWindow.load_time_scale = 1.0


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	StoryDirector.reset(false)
	PlayerProgress.reset()
	PilotNet.rng.seed = 4242
	PilotNet.reset(false)
	PilotNet.look_override = ""
	PilotNet.memorial.reload_content()
	CallsignGenerator.reload_data()
	MechOS.close_all()
	MechOS.set_app_available("net", false)
	NetWindow.load_time_scale = 0.0
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	LocalPilots.current = _arena.local_pilots


func _wall() -> MemorialWall:
	return PilotNet.memorial


func _mecha(callsign: String, local := true) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_pause(true)
	mecha.callsign = callsign
	_arena.mechas.append(mecha)
	if local:
		_arena.local_pilots.join(mecha)
	return mecha


func _player(callsign := "Drifter") -> Mecha:
	var mecha := _mecha(callsign)
	mecha.mecha_name = "Player"
	PlayerProgress.set_callsign(callsign, false)
	_arena.player = mecha
	return mecha


func _personality(mecha: Mecha, type: Personality.Type) -> void:
	var personality := Personality.new()
	personality.type = type
	mecha.personality = personality


func _net(url: String) -> NetWindow:
	MechOS.set_app_available("net", true)
	var window: NetWindow = MechOS.open_net(url)
	check(window != null, "NET opens")
	return window


# A CombatScene with the children it looks for (as FlagFixTest builds one),
# recording losses or not.
func _combat_scene(records: bool):
	var scene = COMBAT_SCENE.new()
	scene.records_losses = records
	for child_name in ["Mechas", "Projectiles", "Trails", "Flashes", "Smoke", "Explosions", "ScrapParts",
			"HeatmapEffects", "PlayerHUD", "PauseMenu", "GameOver", "ArenaCamera", "DebugNavigation"]:
		var child := Node2D.new()
		child.name = child_name
		scene.add_child(child)
	var intro := Node2D.new()
	intro.name = "Intro"
	scene.add_child(intro)
	var intro_animation := Node2D.new()
	intro_animation.name = "IntroAnimation"
	intro.add_child(intro_animation)
	_arena.add_child(scene)
	return scene


func _scene_mecha(scene, callsign: String) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = Vector2(200, 0)
	scene.Mechas.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.callsign = callsign
	scene.all_mechas.append(mecha)
	scene._connect_mecha_signals(mecha)
	scene.local_pilots.join(mecha)
	return mecha


# ---- data ---------------------------------------------------------------------

func _test_data() -> void:
	var problems := _wall().check_content()
	check(problems.is_empty(), "database/memorial/ is valid (%s)" % "; ".join(problems))
	var regions: Array = _wall().data().regions
	check(regions.size() == 8 and regions[0] == "[REGION A]" and regions[7] == "[REGION H]", "eight placeholder regions")
	for group in MemorialWall.GROUPS:
		var lines: Array = _wall().data().condolences.get(group, [])
		check(lines.size() >= 8, "about ten '%s' lines (%d)" % [group, lines.size()])
	var tributes: Dictionary = _wall().data().tributes
	for npc in NPCManager.SPECIAL_NPCS:
		var npc_name := str(npc.get("mecha_name")) if npc != null else ""
		if npc_name != "" and npc_name != MemorialWall.TEST_NPC:
			check(tributes.get(npc_name) is String and str(tributes[npc_name]) != "", "a tribute for %s" % npc_name)
	check(not tributes.has(MemorialWall.TEST_NPC), "none for Test Dummy")
	for key in ["welcome", "about", "moderator"]:
		check(_wall().site_text(key) != "", "site.json has '%s'" % key)


# ---- recording a loss -----------------------------------------------------------

func _test_combat_hook() -> void:
	_wall().current_site = SITE
	var expedition = _combat_scene(true)
	await wait_frames(2)
	var victim := _scene_mecha(expedition, "Hookline")
	victim.die({"name": "Test"}, "test")
	var recorded := await wait_until(func(): return _wall().pending.size() == 1, 6.0)
	check(recorded, "an NPC killed in an expedition makes a pending record")
	var record: Dictionary = _wall().pending[0] if recorded else {}
	check(record.get("callsign") == "Hookline" and record.get("site") == SITE, "with its callsign and the site")
	check(_wall().record_of("Hookline").is_empty(), "not on the Wall during the run")
	var leaver := _scene_mecha(expedition, "Leaver")
	expedition._on_mecha_died(leaver)
	await wait_frames(2)
	check_eq(_wall().pending.size(), 1, "an NPC that extracts makes none")
	var arena = _combat_scene(false)
	await wait_frames(2)
	var sparring: WeakRef = weakref(_scene_mecha(arena, "Sparring"))
	sparring.get_ref().die({"name": "Test"}, "test")
	await wait_until(func(): return sparring.get_ref() == null, 6.0)
	check_eq(_wall().pending.size(), 1, "an Arena kill makes none")
	var announced := []
	PilotNet.pilot_lost.connect(func(entry): announced.append(entry.callsign))
	PilotNet.advance_day()
	check(_wall().pending.is_empty() and not _wall().record_of("Hookline").is_empty(), "it goes up the next day")
	check("Hookline" in announced, "and PilotNet says so (pilot_lost)")
	expedition.queue_free()
	arena.queue_free()
	await wait_frames(2)


func _test_causes() -> void:
	var player := _player()
	var npc := _mecha("Kestrel")
	var stranger := _mecha("Stranger", false)
	var stalker: Entity = STALKER.instantiate()
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)

	var by_entity := _wall().record_loss(_mecha("Victim1"), stalker)
	check(by_entity.cause == "entity" and by_entity.cause_detail == stalker.species, "an Entity: entity, its species")
	check_eq(by_entity.last_seen_with, "", "an Entity is no pilot to be seen with")
	var by_npc := _wall().record_loss(_mecha("Victim2"), npc)
	check(by_npc.cause == "pilot" and by_npc.cause_detail == "", "an NPC: pilot")
	check_eq(by_npc.last_seen_with, "Kestrel", "last seen with the NPC")
	check(not by_npc.player_kill, "not the player's kill")
	var by_stranger := _wall().record_loss(_mecha("Victim3"), stranger)
	check_eq(by_stranger.last_seen_with, "", "a killer not on the Local roster isn't named")
	var by_player := _wall().record_loss(_mecha("Victim4"), player)
	check(by_player.cause == "pilot" and by_player.player_kill, "the player: pilot, the player's kill")
	check_eq(by_player.last_seen_with, "Drifter", "last seen with the player, by callsign")
	player.is_anonymous = true
	var by_hidden := _wall().record_loss(_mecha("Victim5"), player)
	check_eq(by_hidden.last_seen_with, LocalPilots.UNKNOWN, "an Anonymous player is Unknown")
	var by_nothing := _wall().record_loss(_mecha("Victim6"), null)
	check(by_nothing.cause == "unknown" and by_nothing.cause_detail == "" and by_nothing.last_seen_with == "", "no killer: unknown")
	var ticked := _mecha("Victim7")
	ticked.last_damage_source = {"body": null, "name": "Tick Swarm"}
	var by_ticks := _wall().record_loss(ticked, null)
	if "Tick Swarm" in PilotNet.spawnable_kinds():
		check(by_ticks.cause == "entity" and by_ticks.cause_detail == "Tick Swarm", "a tick swarm (no body) is an Entity too")
	check_eq(MemorialWallPage.cause_line(by_npc), "Pilot engagement. Last seen with: KESTREL", "the cause line for a pilot")
	check_eq(MemorialWallPage.cause_line(by_entity), "Entity activity (%s)" % stalker.species, "for an Entity")
	check_eq(MemorialWallPage.cause_line(by_nothing), "Unknown", "for nothing")
	check(by_npc.build.has("core") and str(by_npc.build.core) == str(PlayerProgress.DEFAULT_MECHA.core), "the build at death")


func _test_last_words() -> void:
	var local: LocalPilots = _arena.local_pilots
	var victim := _mecha("Talker")
	var other := _mecha("Other")
	local.post_bark(victim, "Contact left!")
	local.broadcast(victim, "need_help", "Need help over here!")
	local.post_bark(other, "Not me.")
	local.leave(victim)
	var record := _wall().record_loss(victim, null)
	check_eq(record.last_words, "Need help over here!", "the last bark or broadcast, not the leave line")
	var quiet := _wall().record_loss(_mecha("Quiet"), null)
	check_eq(quiet.last_words, "", "none for a pilot that never spoke")


func _test_retired() -> void:
	var ghost := _mecha("Ghosty")
	ghost.is_anonymous = true
	ghost.squad_tag = "GHO"
	var record := _wall().record_loss(ghost, null)
	check_eq(record.callsign, MemorialWall.UNIDENTIFIED, "an Anonymous pilot is Unidentified pilot")
	check(record.real_callsign == "Ghosty" and record.squad_tag == "", "its own callsign kept (hidden), no squad tag")
	check(_wall().is_retired("ghosty"), "its callsign is retired")
	_wall().record_loss(_mecha("Lark"), null)
	CallsignGenerator.use_data({"weights": {"word": 1}, "words": ["Ghosty", "Lark", "Wren"], "blocklist": []})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 100:
		seen[CallsignGenerator.generate(rng, {})] = true
	check(not seen.has("Ghosty") and not seen.has("Lark") and seen.has("Wren"), "lost callsigns never come back (%s)" % str(seen.keys()))
	CallsignGenerator.reload_data()
	var data = JSON.parse_string(JSON.stringify(PilotNet.get_save_data()))
	PilotNet.set_save_data(data)
	check(_wall().is_retired("Ghosty") and _wall().is_retired("Lark"), "and they stay retired after a load")


func _test_background() -> void:
	var counts := []
	for loss_day in range(1, 41):
		counts.append(_wall()._background(loss_day).size())
	check(counts.all(func(c): return c >= MemorialWall.BACKGROUND_PER_DAY[0] and c <= MemorialWall.BACKGROUND_PER_DAY[1]),
			"3-8 a day (%s)" % str(counts))
	_wall().reset()
	var first: Array = _wall()._background(9).map(func(r): return [r.callsign, r.site, r.cause, r.cause_detail, r.build])
	_wall().reset()
	var again: Array = _wall()._background(9).map(func(r): return [r.callsign, r.site, r.cause, r.cause_detail, r.build])
	check_eq(again, first, "the same day gives the same losses")
	_wall().start()
	var records: Array = _wall().records
	check(records.size() >= MemorialWall.BACKFILL_DAYS * 3 and records.size() <= MemorialWall.BACKFILL_DAYS * 8,
			"a new profile has %d days of losses (%d)" % [MemorialWall.BACKFILL_DAYS, records.size()])
	check(records.all(func(r): return r.background and int(r.day) >= 1 - MemorialWall.BACKFILL_DAYS and int(r.day) <= 0),
			"all before Day 1")
	var regions: Array = _wall().data().regions
	check(records.all(func(r): return r.site in regions), "each in a region from regions.json")
	check(records.all(func(r): return r.cause in ["unknown", "entity"]), "lost to unknown causes or Entities")
	check(records.any(func(r): return r.cause == "entity") and records.any(func(r): return r.cause == "unknown"), "some of each")
	var species := PilotNet.spawnable_kinds()
	check(records.filter(func(r): return r.cause == "entity").all(func(r): return r.cause_detail in species),
			"Entities that exist in the game")
	var slots_ok := true
	for record in records:
		for slot in PlayerProgress.REQUIRED_SLOTS:
			if not Store.catalogue(slot).is_empty():
				slots_ok = slots_ok and Store.is_listed(slot, str(record.build.get(slot, "")))
	check(slots_ok, "a listed part in every required slot the store sells")
	check(_wall().last_day == 1 and _wall().pending.is_empty(), "the Wall is on Day 1")
	var before := records.size()
	PilotNet.advance_day()
	var added := _wall().records.size() - before
	check(added >= 3 and added <= 8 and _wall().newest(1)[0].day == 1, "each new day adds the day before's losses (%d)" % added)


func _test_comments() -> void:
	var record := _wall().record_loss(_mecha("Mourned"), null)
	PilotNet.advance_day()
	var all_days_ok := true
	for entry in _wall().records:
		for comment in entry.comments:
			all_days_ok = all_days_ok and int(comment.day) >= int(entry.day) \
					and int(comment.day) <= int(entry.day) + MemorialWall.COMMENT_DELAY[1]
	check(all_days_ok, "every comment comes within three days of the loss")
	var late: Array = _wall().records.filter(func(r): return r.comments.any(func(c): return int(c.day) > int(PilotNet.day)))
	if not late.is_empty():
		var waiting: Dictionary = late[0]
		var shown := _wall().visible_comments(waiting).size()
		check(shown < waiting.comments.size(), "a comment whose day hasn't come doesn't show")
		for i in MemorialWall.COMMENT_DELAY[1]:
			PilotNet.advance_day()
		check_eq(_wall().visible_comments(waiting).size(), waiting.comments.size(), "and shows when it has")
	check(_wall().post_message(int(record.id), "  Rest easy.  "), "the player posts a message")
	check(not _wall().post_message(int(record.id), "Again"), "only one")
	check(_wall().has_player_message(int(record.id)), "it's there")
	var other: Dictionary = _wall().newest(1)[0]
	check(_wall().post_message(int(other.id), "x".repeat(150)), "a long one is cut")
	var mine: Array = _wall().get_record(int(other.id)).comments.filter(func(c): return c.author == MemorialWall.PLAYER_AUTHOR)
	check(mine.size() == 1 and str(mine[0].text).length() == MemorialWall.MESSAGE_LENGTH, "to 100 characters")
	var before: Array = _wall().get_record(int(record.id)).comments.duplicate(true)
	var data = JSON.parse_string(JSON.stringify(PilotNet.get_save_data()))
	PilotNet.set_save_data(data)
	check_eq(_wall().get_record(int(record.id)).comments, before, "comments are the same after save and load")
	check(_wall().has_player_message(int(record.id)), "the player's message is saved")


func _test_candles() -> void:
	var player := _player()
	var victim := _wall().record_loss(_mecha("Shot"), player)
	var other := _wall().record_loss(_mecha("Elsewhere"), null)
	PilotNet.advance_day()
	var start := MemorialWall.candle_count(other)
	check(_wall().light_candle(int(other.id)), "the player lights a candle")
	check(not _wall().light_candle(int(other.id)), "one per record")
	check_eq(MemorialWall.candle_count(other), start + 1, "it adds one")
	check_eq(StoryDirector.get_flag(MemorialWall.OWN_KILL_FLAG, 0), 0, "not the player's kill: the flag doesn't move")
	_wall().light_candle(int(victim.id))
	check_eq(StoryDirector.get_flag(MemorialWall.OWN_KILL_FLAG, 0), 1, "the player's own kill: the flag counts it")
	var data = JSON.parse_string(JSON.stringify(PilotNet.get_save_data()))
	PilotNet.set_save_data(data)
	check(_wall().get_record(int(other.id)).player_candle, "the candle is saved")
	var named := _mecha(NAMED)
	var grows := _wall().record_loss(named, null)
	var counts := [int(grows.candles)]
	for i in MemorialWall.CANDLE_DAYS + 3:
		PilotNet.advance_day()
		counts.append(int(_wall().get_record(int(grows.id)).candles))
	check(counts[MemorialWall.CANDLE_DAYS] > counts[0], "NPC candles grow for a week (%s)" % str(counts))
	check_eq(counts[counts.size() - 1], counts[MemorialWall.CANDLE_DAYS + 1], "then stop")


func _test_named() -> void:
	var volk := _mecha(NAMED)
	var record := _wall().record_loss(volk, null)
	check(record.named, "a named NPC's record is named")
	check_eq(StoryDirector.get_flag("lost:%s" % NAMED, false), true, "lost:%s is set" % NAMED)
	check(int(record.candles) >= MemorialWall.CANDLES_NAMED[0], "it starts with more candles")
	check(record.comments.size() >= MemorialWall.COMMENTS_NAMED[0], "and more messages")
	check_eq(_wall().tribute_of(record), str(_wall().data().tributes[NAMED]), "its tribute from tributes.json")
	var nameless := record.duplicate()
	nameless.callsign = "Nobody Named"
	check(_wall().tribute_of(nameless) != "", "Lorem Ipsum when there's none")
	var plain := _wall().record_loss(_mecha("Plain"), null)
	check(not plain.named and not StoryDirector.has_flag("lost:Plain"), "a generic pilot sets no flag")


func _test_player_notice() -> void:
	_wall().current_site = SITE
	PlayerProgress.set_callsign("Drifter", false)
	check(_wall().player_notice_lines().is_empty(), "no notice before a loss")
	PlayerProgress.expedition_lost.emit({})
	check_eq(_wall().player_notice_lines(), ["MISSING, PRESUMED LOST: Drifter (%s)" % SITE, ""], "the day after a loss")
	check(_wall().record_of("Drifter").is_empty() and _wall().pending.is_empty(), "the player is never a record")
	var window := _net("memorialwall.org/")
	check("MISSING, PRESUMED LOST: Drifter (%s)" % SITE in window.page.get_text(), "the side column shows it")
	PlayerProgress.expedition_started.emit()
	check_eq(_wall().player_notice_lines(), ["NOTICE WITHDRAWN: pilot reported alive", "Withdrawn 1 time"], "withdrawn on deploying")
	PlayerProgress.expedition_lost.emit({})
	check_eq(_wall().player_notice_lines()[0], "MISSING, PRESUMED LOST: Drifter (%s)" % SITE, "missing again")
	PlayerProgress.expedition_started.emit()
	check_eq(_wall().player_notice_lines()[1], "Withdrawn 2 times", "and counted")
	var data = JSON.parse_string(JSON.stringify(PilotNet.get_save_data()))
	PilotNet.set_save_data(data)
	check_eq(_wall().player_notice_lines()[1], "Withdrawn 2 times", "saved")
	StoryDirector.set_flag(MemorialWall.HIDE_PLAYER_FLAG, true, false)
	check(_wall().player_notice_lines().is_empty(), "memorial_hide_player hides it")
	window.navigate("memorialwall.org/about")
	check(not "NOTICE WITHDRAWN" in window.page.get_text(), "on the page too")


func _test_dates() -> void:
	check_eq(PilotNet.date_text(1), "Mon 1 Jan 2035", "Day 1")
	check_eq(PilotNet.date_text(32), "Thu 1 Feb 2035", "Day 32")
	check_eq(PilotNet.date_text(100), "Tue 10 Apr 2035", "Day 100")
	check_eq(PilotNet.short_date(15), "15/01/2035", "a short date")
	check_eq(PilotNet.long_date(15), "15 Jan 2035", "a long date")
	check_eq(PilotNet.stamp(15, "03:14"), "15 Jan 2035 · 03:14", "a stamp")
	check_eq(PilotNet.short_date(0), "31/12/2034", "the day before Day 1")
	PilotNet.day = 46
	check_eq(PilotNet.fill_tags("{date}"), "Thu 15 Feb 2035", "the {date} tag")
	check(PilotNet.unknown_tags("{date}").is_empty(), "is a known tag")


func _test_prune() -> void:
	_wall().reset()
	var keep := []
	for i in MemorialWall.MAX_RECORDS + 10:
		var record := _wall()._new_record()
		record.callsign = "Pilot%d" % i
		record.named = i == 0
		record.player_kill = i == 3
		if record.named or record.player_kill:
			keep.append(int(record.id))
		_wall()._publish(record, false)
	_wall()._prune()
	check_eq(_wall().records.size(), MemorialWall.MAX_RECORDS, "at most MAX_RECORDS")
	check(keep.all(func(id): return not _wall().get_record(id).is_empty()), "the named and player-kill records stay")
	check(_wall().record_of("Pilot1").is_empty() and not _wall().record_of("Pilot20").is_empty(), "the oldest others go first")
	check_eq(_wall().registry_total(), MemorialWall.REGISTRY_BASE + MemorialWall.MAX_RECORDS + 10, "the registry still counts them")


# ---- pages ----------------------------------------------------------------------

func _test_pages() -> void:
	var named := _wall().record_loss(_mecha(NAMED), null)
	PilotNet.advance_day()
	var background: Dictionary = _wall().records[0]
	var pages := ceili(_wall().records.size() / float(MemorialWallPage.PER_PAGE))
	var window := _net("memorialwall.org/")
	var page: MemorialWallPage = window.page
	var text := page.get_text()
	check(page.page_title.begins_with("The Memorial Wall") and "Remembering the pilots who did not come home." in text, "the header")
	for part in ["Welcome", "Recently Lost", "This week", "Most remembered", "Causes and regions", "Registry",
			"Pilots registered: %s" % BbsText.thousands(_wall().registry_total()), "Lost this week: ", "Candles lit: ",
			MemorialWallPage.SMALL_PRINT, "BETA", "RSS", "XHTML", "FIREFOX"]:
		check(part in text, "the home page's %s" % part)
	var cards := page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("record"))
	check_eq(cards.size(), MemorialWallPage.HOME_COUNT, "the newest records as cards")
	check_eq(int(cards[0].get_meta("record")), int(_wall().newest(1)[0].id), "newest first")
	var tabs := page.find_children("*", "Button", true, false).filter(func(b): return str(b.theme_type_variation).begins_with("NetMemTab"))
	check_eq(tabs.map(func(b): return b.text), MemorialWallPage.TABS.map(func(t): return t[0]), "the nav tabs")
	check_eq(tabs.filter(func(b): return b.theme_type_variation == &"NetMemTabActive").map(func(b): return b.text), ["Home"], "Home open")
	var tags := page.find_children("*", "LinkButton", true, false).filter(func(l): return l.has_meta("tag_level"))
	check_eq(tags.size(), _wall().tag_counts().size(), "a tag for every cause and region")
	var levels := {}
	for tag in tags:
		levels[int(tag.get_meta("tag_level"))] = true
		var style: StringName = MemorialWallPage.TAG_STYLES[int(tag.get_meta("tag_level"))]
		check(MemorialWallPage.theme_font(style).get_string_size(tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				MemorialWallPage.theme_font_size(style)).x <= MemorialWallPage.SIDE_INNER, "the tag '%s' fits" % tag.text)
	check(levels.size() >= 2, "in more than one size (%s)" % str(levels.keys()))
	var frame := page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.theme_type_variation == &"NetMemColumn")
	check(frame.size() == 1 and frame[0].custom_minimum_size.x == MemorialWallPage.COLUMN_WIDTH, "a 760 px column")
	check(not page.find_children("*", "PanelContainer", true, false).any(func(n): return n.has_meta("player_notice")), "no notice")
	var counter := page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("digits"))
	check(counter.size() == 1 and str(counter[0].get_meta("digits")).length() == MemorialWallPage.COUNTER_DIGITS, "the hit counter")
	check_eq(page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("web_badge")).size(),
			MemorialWallPage.WEB_BADGES.size(), "the web badges")

	var paths := ["/recent", "/recent?page=2", "/recent?page=%d" % pages, "/recent?page=999", "/pilot/%d" % int(named.id),
			"/pilot/%d" % int(background.id), "/pilot/1", "/pilot/abc", "/search", "/search?q=", "/search?q=" + str(background.callsign),
			"/search?q=zzzzzz", "/tag/unknown", "/tag/entity", "/tag/pilot", "/tag/%5BREGION%20A%5D", "/about", "/submit", "/nonsense"]
	for path in paths:
		window.navigate("memorialwall.org" + path)
		check(window.page is MemorialWallPage and window.page.page_title.begins_with("The Memorial Wall"), "%s opens" % path)
		check(not window.page.get_text().is_empty(), "%s has text" % path)
	window.navigate("memorialwall.org/recent?page=%d" % pages)
	check_eq(window.page.get_meta("page"), pages, "the last page")
	check(window.page.get_links().has(MemorialWallPage.url("/recent", {"page": str(pages - 1)})) and "« Prev" in window.page.get_text(),
			"with « Prev")
	window.navigate("memorialwall.org/recent")
	check(window.page.get_links().has(MemorialWallPage.url("/recent", {"page": "2"})) and "Next »" in window.page.get_text(),
			"page 1 links to page 2")
	window.navigate("memorialwall.org/search?q=" + str(background.callsign))
	var found := window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("record"))
	check(found.any(func(n): return int(n.get_meta("record")) == int(background.id)), "a callsign search finds the record")
	window.navigate("memorialwall.org/search?q=" + SITE.left(3))
	check("pilots found" in window.page.get_text() or "pilot found" in window.page.get_text() or "No pilots found." in window.page.get_text(),
			"a search says how many")
	window.navigate("memorialwall.org/tag/entity")
	found = window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("record"))
	check(found.all(func(n): return _wall().get_record(int(n.get_meta("record"))).cause == "entity"), "a cause's tag lists its records")
	window.navigate("memorialwall.org/about")
	check(_wall().site_text("about").left(20) in window.page.get_text() and "Pilots registered" in window.page.get_text(),
			"About: the moderator's text and the registry total")
	window.navigate("memorialwall.org/submit")
	var submit := window.page.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("submit"))
	check(submit.size() == 1 and submit[0].disabled, "the submit button is disabled")
	check(MemorialWallPage.SUBMIT_NOTE in window.page.get_text(), "submissions are moderated")
	check(NetSites.kind_of(NetSites.MEMORIAL_DOMAIN) == NetSites.BUILT, "memorialwall.org is a built site")
	check(NetSites.FAVORITES.any(func(f): return f[1] == NetSites.MEMORIAL_DOMAIN), "in the favourites")


func _test_record_page() -> void:
	var player := _player()
	var volk := _mecha(NAMED)
	_arena.local_pilots.post_bark(volk, "Hold the line!")
	volk.squad_tag = "VLK"
	var named := _wall().record_loss(volk, player)
	PilotNet.advance_day()
	var window := _net("memorialwall.org/pilot/%d" % int(named.id))
	var page: MemorialWallPage = window.page
	var text := page.get_text()
	check(MemorialWallPage.registry_number(named) in text and NAMED in text, "the registry number and callsign")
	check("Lost %s · " % PilotNet.long_date(int(named.day)) in text, "Lost <date> · <site>")
	check("Hold the line!" in text and page.find_children("*", "PanelContainer", true, false).any(func(n): return n.has_meta("last_words")),
			"the last words in a quote box")
	check("Pilot engagement. Last seen with: [VLK] DRIFTER" in text or "Pilot engagement. Last seen with: DRIFTER" in text,
			"the cause names the player who wasn't Anonymous")
	check(page.find_children("*", "Label", true, false).any(func(n): return n.has_meta("tribute")), "the tribute")
	var build_tables := page.find_children("*", "VBoxContainer", true, false).filter(func(n): return n.has_meta("rows"))
	check(build_tables.size() == 1 and int(build_tables[0].get_meta("rows")) == named.build.size(), "the build table")
	check(page.get_links().has(NetSites.wiki_url(str(named.build.core))), "parts link to Steelapedia")
	var shown := _wall().visible_comments(named).size()
	check("Messages (%d)" % shown in text and (shown == 0 or "#1" in text and "posted by " in text), "numbered messages")
	var candle: MemorialCandle = page.candle
	check(candle != null and candle.big, "a drawn candle")
	check_eq(candle.is_flickering(), candle.is_visible_in_tree(), "its flame runs while it can be seen")
	var heights := {}
	for i in 40:
		candle.flicker()
		heights[candle.flame_height] = true
		check(candle.flame_lean in MemorialCandle.FLAME_LEANS, "a small lean")
	check(heights.keys().all(func(h): return h in MemorialCandle.FLAME_HEIGHTS) and heights.size() > 1, "and a changing height")
	page.visible = false
	await wait_frames(1)
	check(not candle.is_flickering(), "it stops while the page isn't shown")
	page.visible = true
	await wait_frames(1)
	check_eq(candle.is_flickering(), candle.is_visible_in_tree(), "and runs again when it is")
	var holder := VBoxContainer.new()
	holder.visible = false
	add_child(holder)
	var lone := MemorialCandle.new(true)
	holder.add_child(lone)
	await wait_frames(1)
	check(not lone.is_flickering(), "a candle built on a hidden page stays still")
	holder.visible = true
	check(lone.is_flickering(), "it runs once the page shows")
	holder.visible = false
	check(not lone.is_flickering(), "and stops when it's hidden")
	holder.queue_free()
	var count := MemorialWall.candle_count(named)
	check_eq(page.candle_button.text, MemorialWallPage.LIGHT_TEXT, "Light a candle")
	page.candle_button.pressed.emit()
	check(page.candle_button.text == MemorialWallPage.LIT_TEXT and page.candle_button.disabled, "then You lit a candle")
	check_eq(page.candle_count_label.text, MemorialWallPage.candles_text(count + 1), "and the count goes up")
	check_eq(StoryDirector.get_flag(MemorialWall.OWN_KILL_FLAG, 0), 1, "the player's kill counts in the flag")
	check(page.message_field != null and page.message_field.max_length == MemorialWall.MESSAGE_LENGTH, "a 100-character message field")
	page.post_message("Rest easy, Volk.")
	page = window.page
	text = page.get_text()
	check("Rest easy, Volk." in text and "posted by Drifter on %s" % PilotNet.long_date(PilotNet.day) in text, "the message shows")
	check(page.message_field == null and "You left a message" in text, "and the form is gone")
	check(page.candle_button.disabled, "the candle stays lit")
	MechOS.close_all()
	await wait_frames(1)
	check(not is_instance_valid(candle) or not candle.is_flickering(), "closing the NET stops the flame")
	var ghost := _mecha("Ghosty")
	ghost.is_anonymous = true
	var unknown := _wall().record_loss(ghost, null)
	PilotNet.advance_day()
	window = _net("memorialwall.org/pilot/%d" % int(unknown.id))
	text = window.page.get_text()
	check(MemorialWall.UNIDENTIFIED in text and not "Ghosty" in text, "an Unidentified pilot's page keeps its name hidden")
	check_eq(MemorialWallPage.initials_of(MemorialWall.UNIDENTIFIED), "?", "its tile shows ?")


func _test_links() -> void:
	PilotNet.note_met("ASH")
	var volk := _wall().record_loss(_mecha(NAMED), null)
	var ash := _wall().record_loss(_mecha("ASH"), null)
	var sample := _wall().record_loss(_mecha(SAMPLE_PILOT), null)
	var window := _net("pilot.net/")
	check(not window.page.get_links().has(NetSites.memorial_record_url(int(volk.id))), "nothing from today yet")
	PilotNet.advance_day()
	window.navigate("pilot.net/")
	var text: String = window.page.get_text()
	check("IN MEMORIAM" in text, "the text-mode front page has In memoriam")
	var newest: Array = _wall().newest(PilotNetSite.MEMORIAL_COUNT)
	for entry in newest:
		check(window.page.get_links().has(NetSites.memorial_record_url(int(entry.id))), "it links to %s" % entry.callsign)
	check(window.page.get_links().has(NetSites.memorial_url()), "and to the Wall")
	var lines: Array = Array(window.page.screen.get_parsed_text().split("\n"))
	check(lines.all(func(l): return str(l).length() <= PilotNetPage.WIDTH), "the layout still fits")
	window.navigate("pilot.net/pilot/Lady%20Volk")
	text = window.page.get_text()
	check("† Lost %s — Memorial Wall" % PilotNet.long_date(int(volk.day)) in text, "a lost pilot's profile")
	check(window.page.get_links().has(NetSites.memorial_record_url(int(volk.id))), "links to its record")
	window.navigate("pilot.net/pilot/ASH")
	check("† Lost %s — Memorial Wall" % PilotNet.long_date(int(ash.day)) in window.page.get_text(), "a met pilot's page")
	window.navigate("pilot.net/pilot/Kestrel")
	check(not "† Lost" in window.page.get_text(), "not for a pilot who isn't on the Wall")
	StoryDirector.set_flag(NEW_LOOK_FLAG, true, false)
	window.navigate("pilot.net/")
	text = window.page.get_text()
	check("IN MEMORIAM" in text and window.page.get_links().has(NetSites.memorial_record_url(int(newest[0].id))),
			"the portal front page has In memoriam")
	window.navigate("pilot.net/pilot/Lady%20Volk")
	check("† Lost %s — Memorial Wall" % PilotNet.long_date(int(volk.day)) in window.page.get_text()
			and window.page.get_links().has(NetSites.memorial_record_url(int(volk.id))), "and the portal profile")
	window.navigate("steelapedia.net/wiki/sample_pilot")
	text = window.page.get_text()
	check("† Lost %s — Memorial Wall" % PilotNet.long_date(int(sample.day)) in text, "a Steelapedia pilot article")
	var line := window.page.find_children("*", "RichTextLabel", true, false).filter(func(n): return n.has_meta("memorial"))
	check(line.size() == 1 and NetSites.memorial_record_url(int(sample.id)) in str(line[0].text), "links to its record")
	window.navigate("steelapedia.net/wiki/martel")
	check(not "† Lost" in window.page.get_text(), "not on other articles")
