extends TestSuite

# PilotNetTest: pilot.net (PilotNet, the pilot.net pages) and the story hooks.
#   - every data file in database/pilotnet/ is valid, and the checks catch
#     mistakes
#   - the five ways in: data files gated by the story (A), code (B), story
#     effects through a mission and a Messenger reply (C), map triggers (D),
#     world status (E); the old triggers and StoryDirector behave as before
#   - text tags, unread and the NET badge, on_read once, save and load, the day
#   - gigs: the board, expiry, accepting and the limit, kills by kind, cargo,
#     a lost run, payment once, abandoning
#   - pilots met and the known build; every pilot.net page opening and
#     fitting the text layout; the front page's widgets, forum paging, post
#     cards and the NET search
# Each case starts from a fresh story and pilot.net.

const SAMPLE_GATED := "sample_gated"
const SAMPLE_HIDDEN_IF := "sample_hidden_if"
const SAMPLE_MANUAL := "sample_news_manual"
const SAMPLE_NOTIFY := "sample_notify"
const SAMPLE_THREAD := "sample_thread"
const SAMPLE_PINNED := "sample_news_pinned"
const COYOTE_GIG := "sample_coyote_cull"
const BIO_GIG := "sample_bio_haul"
const BIO_ITEM := preload("res://database/items/bio/acid_gland.tres")


func run_tests() -> void:
	await case("every data file is valid", _test_content)
	await case("the content checks catch mistakes", _test_checks_catch)
	await case("way A: posts that the story shows and hides", _test_way_a)
	await case("way B: posts from code", _test_way_b)
	await case("way C: story effects, from a mission and a Messenger reply", _test_way_c)
	await case("way D: map triggers, and the old ones still work", _test_way_d)
	await case("way E: world status", _test_way_e)
	await case("text tags", _test_tags)
	await case("unread and the NET badge", _test_unread)
	await case("on_read runs once", _test_on_read)
	await case("boards, order and search", _test_order)
	await case("save and load", _test_save)
	await case("the day", _test_day)
	await case("gigs: the board and expiry", _test_gig_board)
	await case("gigs: accepting and the limit", _test_gig_accept)
	await case("gigs: kills by kind and a lost run", _test_gig_kills)
	await case("gigs: extract and extract_with", _test_gig_extract)
	await case("gigs: payment once, and abandoning", _test_gig_pay)
	await case("pilots met and the known build", _test_pilots)
	await case("every pilot.net page opens", _test_pages)
	await case("forum pages, post cards and the NET search", _test_forum_layout)
	await case("reading, gigs and profiles on the pages", _test_page_actions)
	NetWindow.load_time_scale = 1.0


func before_each() -> void:
	StoryDirector.reset(false)
	PlayerProgress.reset()
	PilotNet.rng.seed = 4242
	PilotNet.reset(false)
	MechOS.close_all()
	MechOS.set_app_available("net", false)
	NetWindow.load_time_scale = 0.0


func _net(url: String) -> NetWindow:
	MechOS.set_app_available("net", true)
	var window: NetWindow = MechOS.open_net(url)
	check(window != null, "NET opens")
	return window


# ---- helpers ----------------------------------------------------------------------

func _visible_ids(board := "") -> Array:
	return PilotNet.visible_posts(board).map(func(p): return p.id)


func _active_gig(template_id: String) -> Dictionary:
	var gig := PilotNet.roll_gig(PilotNet.get_template(template_id))
	PilotNet.gigs.append(gig)
	check(PilotNet.accept_gig(gig.id), "%s accepted" % template_id)
	return gig


# ---- content --------------------------------------------------------------------

func _test_content() -> void:
	PilotNet.reload_content()
	var errors := PilotNet.check_content()
	check(errors.is_empty(), "no mistakes in database/pilotnet (%s)" % "; ".join(errors))
	for path in PilotNet.post_files() + [PilotNet.BOARDS_PATH, PilotNet.WORLD_PATH, PilotNet.GIGS_PATH, PilotNet.PILOTS_PATH]:
		var json := JSON.new()
		check(json.parse(FileAccess.get_file_as_string(path)) == OK, "%s parses" % path)
		check(json.data is Dictionary and json.data.has("_about"), "%s says what it is (_about)" % path.get_file())
	check(PilotNet.post_files().has(PilotNet.POSTS_DIR + "samples.json"), "the samples are one file")
	for id in PilotNet.all_ids():
		var post: Dictionary = PilotNet.get_post(id)
		if post.source == "file":
			check(post.title.begins_with("[SAMPLE]"), "%s is marked [SAMPLE]" % id)
	for template in PilotNet.gig_templates:
		check(str(template.title).begins_with("[SAMPLE]"), "gig %s is marked [SAMPLE]" % template.id)
	check(not PilotNet.get_board("news").is_empty() and not PilotNet.get_board("gigs").is_empty()
			and not PilotNet.get_board("general").is_empty() and not PilotNet.get_board("trade").is_empty(), "the four boards")
	check(PilotNet.pilots.has("Lady Volk") and not PilotNet.pilots.has("Test Dummy"), "the named NPCs, not the test dummy")


func _test_checks_catch() -> void:
	var bad := PilotNet._normal_post({"id": "bad_post", "board": "nowhere", "title": "T {nonsense}", "body": "B",
			"colour": "red", "requires": {"flag": {"x": true}}, "on_read": {"pilotnet": {"show": ["no_such_post"], "bogus": 1}},
			"gig": "no_such_gig"}, "file")
	PilotNet._file_posts["bad_post"] = bad
	var errors := " | ".join(PilotNet.check_content())
	PilotNet._file_posts.erase("bad_post")
	for wanted in ["board 'nowhere' doesn't exist", "unknown key 'colour'", "unknown condition 'flag'",
			"show names no post 'no_such_post'", "unknown pilotnet key 'bogus'", "gig 'no_such_gig' isn't a template",
			"unknown tag {nonsense}"]:
		check(wanted in errors, "the checks catch: %s" % wanted)
	PilotNet.world["bad_world"] = {"label": "x", "values": {"1": 2}}
	errors = " | ".join(PilotNet.check_content())
	PilotNet.world.erase("bad_world")
	check("world bad_world: the text for '1' isn't a string" in errors, "world values must be strings")
	check(PilotNet.check_content().is_empty(), "and nothing left over")


# ---- ways in ----------------------------------------------------------------------

func _test_way_a() -> void:
	check(not PilotNet.is_post_visible(SAMPLE_GATED), "a gated post is hidden at first")
	check(PilotNet.why_hidden(SAMPLE_GATED).begins_with("requires fails"), "and says why")
	var appeared := []
	var on_appeared := func(p): appeared.append(p.id)
	PilotNet.post_appeared.connect(on_appeared)
	StoryDirector.set_flag("sample_flag", true, false)
	PilotNet.post_appeared.disconnect(on_appeared)
	check(PilotNet.is_post_visible(SAMPLE_GATED), "it appears when its flag is set")
	check(appeared.has(SAMPLE_GATED), "post_appeared says so")
	check_eq(PilotNet.first_seen_day(SAMPLE_GATED), PilotNet.day, "stamped with the day")
	check(PilotNet.is_post_visible(SAMPLE_HIDDEN_IF), "a hidden_if post shows")
	StoryDirector.set_flag("sample_hide", true, false)
	check(not PilotNet.is_post_visible(SAMPLE_HIDDEN_IF), "and goes away once hidden_if passes")
	check(not PilotNet.is_post_visible(SAMPLE_MANUAL), "requires manual never passes by itself")
	StoryDirector.advance_to("chapter_9", "end", false)
	check(not PilotNet.is_post_visible(SAMPLE_MANUAL), "not even as the story moves")


func _test_way_b() -> void:
	PilotNet.post({"id": "code_post", "board": "general", "title": "From code", "body": "Body."})
	check(PilotNet.is_post_visible("code_post"), "post() adds a post")
	PilotNet.post({"id": "code_post", "board": "general", "title": "Replaced", "body": "Body."})
	check_eq(PilotNet.get_post("code_post").title, "Replaced", "the same id replaces it")
	check_eq(_visible_ids().count("code_post"), 1, "once")
	PilotNet.show_post(SAMPLE_MANUAL)
	check(PilotNet.is_post_visible(SAMPLE_MANUAL), "show_post shows a post its requires keeps hidden")
	PilotNet.hide_post(SAMPLE_PINNED)
	check(not PilotNet.is_post_visible(SAMPLE_PINNED), "hide_post hides any post")
	PilotNet.reply(SAMPLE_THREAD, {"author": "ROOK", "body": "A reply from code."})
	check(PilotNet.visible_replies(SAMPLE_THREAD).any(func(r): return r.author == "ROOK"), "reply() adds a reply")


func _test_way_c() -> void:
	StoryDirector.apply_effects({"flags": {"volk_met": true}, "pilotnet": {"show": [SAMPLE_MANUAL]}})
	check(StoryDirector.has_flag("volk_met") and PilotNet.is_post_visible(SAMPLE_MANUAL), "apply_effects with a pilotnet key")
	StoryDirector.apply_effects({"pilotnet": {"hide": [SAMPLE_MANUAL],
			"post": {"id": "effect_post", "board": "news", "title": "From an effect", "body": "Body."}}})
	check(not PilotNet.is_post_visible(SAMPLE_MANUAL) and PilotNet.is_post_visible("effect_post"), "hide and post too")

	var mission := MissionData.new()
	mission.mission_name = "PilotNet test mission"
	mission.add_objective("kill", "Kill 1", 1)
	mission.story_effects = {"pilotnet": {"show": [SAMPLE_GATED]}}
	MissionManager.start_mission(mission)
	MissionManager.report_kill()
	check(mission.completed and PilotNet.is_post_visible(SAMPLE_GATED), "a completed mission's story_effects show a post")
	MissionManager.current_mission = null

	var contact := ContactData.new()
	contact.name = "PilotNet test contact"
	var reply := contact.add_reply_option("Sure.", [], null, {"pilotnet": {"post": {"id": "reply_post", "board": "general",
			"title": "From a reply", "body": "Body."}}})
	Messenger.choose_reply(contact, reply)
	check(PilotNet.is_post_visible("reply_post"), "a Messenger reply's story_effects post one")
	StoryDirector.register_effect("test_other_key", func(value): StoryDirector.set_flag("other_key_ran", value, false))
	StoryDirector.apply_effects({"test_other_key": 7, "unknown_key": 1})
	check_eq(StoryDirector.get_flag("other_key_ran"), 7, "any system can register an effect key")
	StoryDirector._effect_handlers.erase("test_other_key")


func _test_way_d() -> void:
	StoryDirector.handle_trigger("pilotnet=" + SAMPLE_MANUAL)
	check(PilotNet.is_post_visible(SAMPLE_MANUAL), "story:pilotnet=<id> shows the post")
	StoryDirector.handle_trigger("flag=saw_wreck")
	StoryDirector.handle_trigger("advance=ch2/wreck")
	check(StoryDirector.has_flag("saw_wreck") and StoryDirector.is_at("ch2", "wreck"), "flag= and advance= as before")
	expect_error("Unknown story trigger command: nonsense=1")
	StoryDirector.handle_trigger("nonsense=1")
	expect_error("Invalid story trigger: broken")
	StoryDirector.handle_trigger("broken")


func _test_way_e() -> void:
	var lines := PilotNet.world_lines().map(func(l): return "%s: %s" % [l.label, l.text])
	check(lines.has("[SAMPLE] Helwan threat: Quiet") and lines.has("[SAMPLE] Ice road: Closed"), "defaults (%s)" % str(lines))
	check(not lines.any(func(l): return l.begins_with("[SAMPLE] Gated line")), "a gated line is hidden")
	StoryDirector.set_flag("sample_threat", 2, false)
	check_eq(PilotNet.world_text("sample_threat"), "Swarming", "a set flag's text")
	StoryDirector.set_flag("sample_road", true, false)
	check_eq(PilotNet.world_text("sample_road"), "Open", "a bool flag")
	StoryDirector.set_flag("sample_threat", 7, false)
	check_eq(PilotNet.world_text("sample_threat"), "7", "a value with no text shows as it is")
	StoryDirector.set_flag("sample_threat", 1.0, false)
	check_eq(PilotNet.world_text("sample_threat"), "Active", "a float from a loaded save reads as its whole number")
	StoryDirector.set_flag("sample_world_gate", true, false)
	check(PilotNet.world_lines().any(func(l): return l.flag == "sample_gated"), "a gated line shows once it passes")


func _test_tags() -> void:
	PlayerProgress.set_callsign("Tester", false)
	PilotNet.day = 3
	StoryDirector.set_flag("sample_threat", 1, false)
	check_eq(PilotNet.fill_tags("{player} day {day} {flag:sample_threat} {world:sample_threat} {other}"),
			"Tester day 3 1 Active {other}", "the four tags, an unknown one left alone")
	check_eq(PilotNet.unknown_tags("{player} {day} {flag:a} {world:b} {oops} {}"), ["{oops}", "{}"], "unknown tags are found")
	check_eq(PilotNet.author_name(PilotNet.get_post("sample_tags")), "Tester", "{player} as an author")


func _test_unread() -> void:
	check_eq(PilotNet.unread_count(), 1, "only the notify post is unread")
	check_eq(MechOS.taskbar.badges["net"].text, "1", "the NET tile shows it")
	var log_size := MechLog.lines.size()
	PilotNet.show_post(SAMPLE_MANUAL)
	check_eq(PilotNet.unread_count(), 2, "a shown notify post counts")
	check(MechLog.lines.size() > log_size and MechLog.lines[-1].text == "New on pilot.net: [SAMPLE] Shown only by show_post or a story effect"
			and MechLog.lines[-1].source == "NET", "one log line when it appears")
	PilotNet.open_post(SAMPLE_NOTIFY)
	PilotNet.open_post(SAMPLE_MANUAL)
	PilotNet.open_post(SAMPLE_PINNED)
	check_eq(PilotNet.unread_count(), 0, "opening clears it")
	check(not MechOS.taskbar.badges["net"].visible, "and the badge")
	check(PilotNet.is_read(SAMPLE_PINNED) and not PilotNet.is_new(SAMPLE_PINNED), "a read post isn't *NEW*")
	check(PilotNet.is_new(SAMPLE_THREAD), "an unopened one is")


func _test_on_read() -> void:
	check(not StoryDirector.has_flag("sample_thread_read"), "not read yet")
	check_eq(PilotNet.visible_replies(SAMPLE_THREAD).size(), 1, "the gated reply is hidden")
	PilotNet.open_post(SAMPLE_THREAD)
	check(StoryDirector.has_flag("sample_thread_read"), "opening runs on_read")
	check_eq(PilotNet.visible_replies(SAMPLE_THREAD).size(), 2, "which shows the gated reply")
	StoryDirector.set_flag("sample_thread_read", false, false)
	PilotNet.open_post(SAMPLE_THREAD)
	check_eq(StoryDirector.get_flag("sample_thread_read"), false, "only once")


func _test_order() -> void:
	PilotNet.post({"id": "later_news", "board": "news", "title": "Later", "body": "Body."})
	PilotNet.day = 2
	PilotNet.post({"id": "newest_news", "board": "news", "title": "Newest", "body": "Body."})
	var news := _visible_ids("news")
	check_eq(news[0], SAMPLE_PINNED, "pinned first")
	check(news.find("newest_news") < news.find("later_news"), "then the newest day first (%s)" % str(news))
	check_eq(PilotNet.latest("news", 1)[0].id, "newest_news", "latest skips pinning")
	check_eq(PilotNet.post_time("newest_news"), PilotNet.post_time("newest_news"), "a post's time is fixed")
	check(PilotNet.post_time("newest_news").length() == 5 and PilotNet.post_time("newest_news")[2] == ":", "hh:mm")
	var found := PilotNet.search("TRADE POST")
	check(found.size() == 1 and found[0].id == "sample_trade", "search finds by title, any case")
	check(PilotNet.search("perspiciatis").is_empty(), "never a hidden post")
	check(PilotNet.visible_boards().size() == 4, "four boards")


func _test_save() -> void:
	PilotNet.day = 4
	PilotNet.open_post(SAMPLE_NOTIFY)
	PilotNet.post({"id": "saved_post", "board": "news", "title": "Saved", "body": "Body."})
	PilotNet.show_post(SAMPLE_MANUAL)
	PilotNet.hide_post(SAMPLE_PINNED)
	PilotNet.reply(SAMPLE_THREAD, {"author": "ROOK", "body": "Saved reply."})
	var gig := _active_gig(COYOTE_GIG)
	gig.progress = 2
	PilotNet.note_met("Lady Volk")
	var first_seen := PilotNet.first_seen_day("saved_post")
	var data: Dictionary = JSON.parse_string(JSON.stringify(PilotNet.get_save_data()))
	check(not str(data.pushed).contains(PilotNet.get_post(SAMPLE_TRADE_ID).body), "data-file posts aren't saved")
	PilotNet.reset(false)
	check(not PilotNet.is_post_visible("saved_post") and PilotNet.day == 1, "reset clears it")
	var file_post: Dictionary = PilotNet._file_posts[SAMPLE_TRADE_ID]
	var original: String = file_post.title
	file_post.title = "[SAMPLE] Edited in the file"
	PilotNet.set_save_data(data)
	check_eq(PilotNet.day, 4, "the day")
	check(PilotNet.is_read(SAMPLE_NOTIFY), "read posts")
	check(PilotNet.is_post_visible("saved_post") and PilotNet.first_seen_day("saved_post") == first_seen, "pushed posts and their day")
	check(PilotNet.is_post_visible(SAMPLE_MANUAL) and not PilotNet.is_post_visible(SAMPLE_PINNED), "shown and hidden posts")
	check(PilotNet.visible_replies(SAMPLE_THREAD).any(func(r): return r.body == "Saved reply."), "replies from code")
	var loaded := PilotNet.get_gig(gig.id)
	check(loaded.state == "active" and loaded.progress == 2 and loaded.count is int, "gigs and their progress")
	check(PilotNet.is_met("Lady Volk"), "met pilots")
	check_eq(PilotNet.get_post(SAMPLE_TRADE_ID).title, "[SAMPLE] Edited in the file", "file posts read the file, not the save")
	file_post.title = original


const SAMPLE_TRADE_ID := "sample_trade"


func _test_day() -> void:
	check_eq(PilotNet.day, 1, "day 1")
	PlayerProgress.begin_expedition()
	PlayerProgress.extract_expedition()
	check_eq(PilotNet.day, 2, "an extraction ends a day")
	PlayerProgress.begin_expedition()
	PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)
	check_eq(PilotNet.day, 3, "so does a loss")
	PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)
	check_eq(PilotNet.day, 3, "no run, no day")
	PilotNet.post({"id": "day_post", "board": "news", "title": "Day {day}", "body": "Body."})
	check_eq(PilotNet.first_seen_day("day_post"), 3, "new posts get the day")


# ---- gigs -------------------------------------------------------------------------

func _test_gig_board() -> void:
	check_eq(PilotNet.open_gigs().size(), PilotNet.GIG_BOARD_SIZE, "the board is full")
	check(not PilotNet.open_gigs().any(func(g): return g.template == "sample_gated_gig"), "never a gig the story keeps back")
	var kinds := PilotNet.spawnable_kinds()
	for kind in ["mech", "Coyote", "Coyote Spitter", "Fisher", "Tick Swarm"]:
		check(kind in kinds, "%s can be a kill gig's kind (%s)" % [kind, str(kinds)])
	check(not "Stalker" in kinds and not "Brute" in kinds, "not species the Expedition never spawns")
	for gig in PilotNet.open_gigs():
		check(gig.reward % 10 == 0 and gig.count >= 1, "%s: a rolled count and a reward in tens" % gig.title)
		check(not "{" in gig.title, "%s: its title is filled in" % gig.title)
		check(PilotNet.is_post_visible("gig:" + gig.id), "%s: a post on the GIGS board" % gig.title)
	var first: Dictionary = PilotNet.open_gigs()[0]
	PilotNet.accept_gig(first.id)
	var old_ids := PilotNet.open_gigs().map(func(g): return g.id)
	PilotNet.advance_day()
	PilotNet.advance_day()
	check(PilotNet.open_gigs().all(func(g): return g.id in old_ids or g.posted > 1), "open gigs last a while")
	PilotNet.advance_day()
	check(not PilotNet.open_gigs().any(func(g): return g.id in old_ids), "then go after %d days" % PilotNet.GIG_LIFETIME_DAYS)
	check_eq(PilotNet.open_gigs().size(), PilotNet.GIG_BOARD_SIZE, "and new ones fill the board")
	check_eq(PilotNet.get_gig(first.id).state, "active", "an accepted gig stays")
	StoryDirector.set_flag("sample_gig_gate", true, false)
	check(PilotNet.offerable_templates().any(func(t): return t.id == "sample_gated_gig"), "a gated template once it passes")


func _test_gig_accept() -> void:
	var open := PilotNet.open_gigs()
	for i in PilotNet.MAX_ACTIVE_GIGS:
		check(PilotNet.accept_gig(open[i].id), "accept %d" % (i + 1))
	check_eq(PilotNet.accept_block_reason(), "GIG LIMIT REACHED (3)", "the limit says why")
	check(not PilotNet.accept_gig(open[PilotNet.MAX_ACTIVE_GIGS].id), "and refuses a fourth")
	check(not PilotNet.accept_post_gig("sample_gig_post"), "from a post too")
	PilotNet.abandon_gig(open[0].id)
	check(PilotNet.accept_post_gig("sample_gig_post"), "a post's gig once there's room")
	var taken := PilotNet.gig_of_post("sample_gig_post")
	check(taken.state == "active" and taken.template == COYOTE_GIG, "rolled from the post's template")
	PilotNet.abandon_gig(open[1].id)
	check(not PilotNet.accept_post_gig("sample_gig_post"), "a post offers its gig once")


func _test_gig_kills() -> void:
	var gig := _active_gig(COYOTE_GIG)
	PilotNet.report_kind("Coyote")
	check_eq(PilotNet.run_progress(gig.id), 0, "no kill counts outside an expedition")
	PlayerProgress.begin_expedition()
	var coyote := Entity.new()
	coyote.species = "Coyote"
	coyote.add_to_group("entity")
	PilotNet.report_kill(coyote)
	coyote.free()
	PilotNet.report_kind("Coyote")
	PilotNet.report_kind("Coyote Spitter")
	var mecha := Node2D.new()
	PilotNet.report_kill(mecha)
	check_eq(PilotNet.run_progress(gig.id), 2, "kills of its kind count, others don't")
	check_eq(int(gig.progress), 0, "not kept until the run ends")
	PlayerProgress.extract_expedition()
	check_eq(int(PilotNet.get_gig(gig.id).progress), 2, "an extraction keeps them")
	PlayerProgress.begin_expedition()
	PilotNet.report_kind("Coyote")
	PilotNet.report_kind("Coyote")
	PlayerProgress.lose_expedition(PlayerProgress.LOSS_DESTROYED)
	check_eq(int(PilotNet.get_gig(gig.id).progress), 2, "a lost run's kills are dropped, earlier ones stay")
	var mech_gig := _active_gig("sample_mech_contract")
	PlayerProgress.begin_expedition()
	PilotNet.report_kill(mecha)
	mecha.free()
	PlayerProgress.extract_expedition()
	check(int(PilotNet.get_gig(mech_gig.id).progress) == 1 or PilotNet.get_gig(mech_gig.id).state == "complete", "a mecha kill counts as mech")
	check_eq(PilotNet.progress_text(PilotNet.get_gig(gig.id)), "2/%d Coyotes" % gig.count, "progress like 3/6 Coyotes")


func _test_gig_extract() -> void:
	var courier := _active_gig("sample_courier")
	var haul := _active_gig(BIO_GIG)
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 8)
	PlayerProgress.set_mech_inventory(cargo)
	for i in 2:
		cargo.add_stack_anywhere(item_stack.from_generic(BIO_ITEM))
	cargo.add_stack_anywhere(item_stack.from_generic(load("res://database/items/salvage/wiring_loom.tres")))
	check_eq(PilotNet.cargo_count("bio"), 2, "cargo counted by tag")
	check_eq(PilotNet.cargo_count("acid_gland"), 2, "or by item id")
	PlayerProgress.begin_expedition()
	PlayerProgress.extract_expedition()
	check_eq(int(PilotNet.get_gig(haul.id).progress), mini(2, haul.count), "extract_with counts the cargo")
	var courier_now := PilotNet.get_gig(courier.id)
	check(courier_now.is_empty() == false and (int(courier_now.progress) == 1 or courier_now.state == "complete"), "extract counts an extraction")


func _test_gig_pay() -> void:
	var gig := _active_gig(COYOTE_GIG)
	PlayerProgress.begin_expedition()
	for i in gig.count:
		PilotNet.report_kind("Coyote")
	PlayerProgress.extract_expedition()
	check_eq(PilotNet.get_gig(gig.id).state, "complete", "complete once progress reaches the count")
	var money := PlayerProgress.get_money()
	var rep := PlayerProgress.get_reputation()
	check_eq(PlayerProgress.get_money(), money, "not paid away from home")
	MechOS.set_app_available("net", true)
	PilotNet.pay_completed()
	check_eq(PlayerProgress.get_money(), money + gig.reward, "paid at home")
	check_eq(PlayerProgress.get_reputation(), rep + gig.reputation, "with reputation")
	check(PilotNet.get_gig(gig.id).is_empty() and PilotNet.gigs_completed == 1, "and done with")
	var paid := PilotNet.get_post("paid_" + gig.id)
	check(paid.notify and paid.board == "gigs" and paid.title == "Payment sent: %d CT" % gig.reward and paid.author == gig.poster,
			"a notify post from the poster: Payment sent")
	PilotNet.pay_completed()
	check_eq(PlayerProgress.get_money(), money + gig.reward, "once")
	var dropped := _active_gig(COYOTE_GIG)
	PilotNet.abandon_gig(dropped.id)
	check(PilotNet.get_gig(dropped.id).is_empty(), "abandoned, with no penalty")
	check_eq(PlayerProgress.get_reputation(), rep + gig.reputation, "no reputation lost")


func _test_pilots() -> void:
	check(not PilotNet.is_met("Lady Volk"), "nobody met yet")
	PilotNet.day = 5
	PilotNet.note_met("Lady Volk")
	PilotNet.note_met(PlayerProgress.get_callsign())
	check(PilotNet.is_met("Lady Volk") and PilotNet.last_seen("Lady Volk") == 5, "met, on day 5")
	check(not PilotNet.is_met(PlayerProgress.get_callsign()), "never the player")
	var build := PilotNet.known_build("Lady Volk")
	check(build.any(func(b): return b[1] == "head" and b[2] == "MSV-L3J-H"), "the named NPC's frame (%s)" % str(build))
	check(PilotNet.known_build("Nobody").is_empty(), "no frame for an unknown pilot")
	check(not PilotNet.pilot_profile("lady volk").is_empty(), "profiles by callsign, any case")
	check(PilotNet.posts_by("Lady Volk").any(func(p): return p.id == SAMPLE_THREAD), "their posts")


# ---- pages ------------------------------------------------------------------------

func _test_pages() -> void:
	PilotNet.note_met("ASH")
	var gig: Dictionary = PilotNet.open_gigs()[0]
	var window := _net("pilot.net/")
	var page: PilotNetPage = window.page
	var text := page.get_text()
	check("PILOT.NET" in text and "the independent pilots' exchange" in text, "the banner")
	check("Logged in as %s · Rep 0 · %s" % [PlayerProgress.get_callsign().to_upper(), PilotNet.date_text(1)] in text, "the login line")
	check("[1] HOME  [2] NEWS  [3] GIGS  [4] FORUMS  [5] PILOTS" in text
			and "[6] STEELAPEDIA  [7] FOURX.NET  [8] AMAZING.COM" in text, "the nav")
	for widget in ["TOP STORY", "NEWS", "HOT IN THE FORUMS", "GIG BOARD", "MY PILOT", "FOURX MARKETS",
			"TOP DEALS ON AMAZING.COM", "WORLD STATUS", "FROM STEELAPEDIA", "WHO'S ONLINE"]:
		check("+- %s " % widget in text or widget == "WHO'S ONLINE" and widget in text, "the front page's %s" % widget)
	check("[SAMPLE] A pinned news post" in text, "the pinned news post is the top story")
	check(FourX.COMPOSITE in text and FourX.SALVAGE_INDEX in text, "the market widget quotes the indexes")
	AmazingPage.ensure_picks()
	check(AmazingPage.picks.is_empty() or Store.part_name(AmazingPage.picks[0][0], AmazingPage.picks[0][1]).left(10) in text,
			"the deals are amazing.com's picks")
	check(page.get_code().count("[bgcolor=") == 1, "one inverted link")
	var lines: Array = Array(page.screen.get_parsed_text().split("\n"))
	check(lines.all(func(l): return str(l).length() <= PilotNetPage.WIDTH), "no line is wider than the layout")
	for site in ["steelapedia.net", "fourx.net", "amazing.com"]:
		check(page.get_links().has(site), "the nav goes to %s" % site)
	check(page.search_field != null, "a search box")
	var paths := ["/forums", "/boards", "/board/news", "/board/gigs", "/board/general", "/board/general?page=9",
			"/board/trade", "/board/nowhere", "/post/" + SAMPLE_THREAD, "/post/%s?page=4" % SAMPLE_THREAD,
			"/post/gig:" + gig.id, "/post/sample_gig_post", "/post/no_such_post", "/gigs", "/pilots", "/pilots?l=L",
			"/pilot/Lady%20Volk", "/pilot/ASH", "/pilot/" + PlayerProgress.get_callsign(), "/pilot/Nobody",
			"/search?q=sample", "/search", "/nonsense"]
	for path in paths:
		window.navigate("pilot.net" + path)
		check(window.page is PilotNetPage and window.page.page_title.begins_with("pilot.net"), "%s opens" % path)
		check(not window.page.get_text().is_empty(), "%s has text" % path)
		var widths: Array = Array(window.page.screen.get_parsed_text().split("\n")).map(func(l): return str(l).length())
		check(widths.max() <= PilotNetPage.WIDTH, "%s fits the layout (%d)" % [path, widths.max()])
	window.navigate("pilot.net/board/nowhere")
	check("404" in window.page.get_text(), "an unknown board is a 404")
	window.navigate("pilot.net/forums")
	text = window.page.get_text()
	check("FORUM" in text and "TOPICS" in text and "LAST POST" in text and "GENERAL CHATTER" in text, "the forum index")
	check("WHO IS ONLINE" in text and "STATISTICS" in text, "who's online and the statistics")
	window.navigate("pilot.net/board/news")
	text = window.page.get_text()
	check(text.find("[SAMPLE] A pinned news post") < text.find("[SAMPLE] A notify post"), "pinned first")
	check("TOPIC" in text and "STARTED BY" in text and "REPLIES" in text and "LAST POST" in text, "the columns")


func _test_forum_layout() -> void:
	for i in 25:
		PilotNet.post({"id": "filler_%02d" % i, "board": "general", "title": "Filler %02d" % i, "body": "Body."})
	var window := _net("pilot.net/board/general")
	var text: String = window.page.get_text()
	check("Page 1 of 2" in text and window.page.get_links().has("pilot.net/board/general?page=2"), "a long board pages")
	window.navigate("pilot.net/board/general?page=2")
	text = window.page.get_text()
	check("Page 2 of 2" in text and window.page.get_links().has("pilot.net/board/general?page=1"), "page 2")
	window.navigate("pilot.net/post/" + SAMPLE_THREAD)
	text = window.page.get_text()
	check("#1" in text and "#2" in text and "Posts: " in text, "a topic's posts are numbered cards")
	var art := PilotNetPage.avatar("Lady Volk")
	check_eq(art.size(), 3, "an avatar is three lines")
	check_eq(art, PilotNetPage.avatar("lady volk"), "the same for a callsign in any case")
	check(art.all(func(line): return str(line).length() == 5), "five characters wide")
	check(art[1] in text, "the card shows the author's avatar")
	check(PilotNet.post_count("KESTREL") >= 1, "post counts include replies")
	window.navigate("pilot.net/search?q=martel")
	text = window.page.get_text()
	check("STEELAPEDIA: " in text and "AMAZING.COM: " in text and "FOURX.NET: " in text, "the NET search covers every site")
	check(window.page.get_links().has(NetSites.wiki_url("martel")), "and links to what it finds")


func _test_page_actions() -> void:
	var window := _net("pilot.net/post/" + SAMPLE_NOTIFY)
	check(PilotNet.is_read(SAMPLE_NOTIFY) and PilotNet.unread_count() == 0, "opening a post reads it")
	window.navigate("pilot.net/post/" + SAMPLE_THREAD)
	check(StoryDirector.has_flag("sample_thread_read"), "and runs its on_read")
	var text: String = window.page.get_text()
	check("2 replies" in text and "KESTREL" in text and "GREYWAKE" in text, "replies, the gated one shown by on_read")
	check(window.page.get_links().has("pilot.net/pilot/Lady%20Volk"), "the author links to the profile")

	var gig: Dictionary = PilotNet.open_gigs()[0]
	window.navigate("pilot.net/post/gig:" + gig.id)
	check("[ACCEPT]" in window.page.get_text() and gig.title in window.page.get_text(), "a gig post offers its gig")
	(window.page as PilotNetPage).click("do:accept:" + gig.id)
	check_eq(PilotNet.get_gig(gig.id).state, "active", "ACCEPT accepts it")
	check("ACCEPTED" in window.page.get_text(), "and the page says so")
	window.navigate("pilot.net/gigs")
	text = window.page.get_text()
	check("MY GIGS (1/3)" in text and PilotNet.progress_text(PilotNet.get_gig(gig.id)) in text and "[ABANDON]" in text, "MY GIGS")
	(window.page as PilotNetPage).click("do:abandon:" + gig.id)
	check(PilotNet.get_gig(gig.id).is_empty(), "ABANDON drops it")
	for i in 3:
		PilotNet.accept_gig(PilotNet.open_gigs()[0].id)
	window.navigate("pilot.net/gigs")
	check("GIG LIMIT REACHED (3)" in window.page.get_text(), "the limit shows")
	window.navigate("pilot.net/post/sample_gig_post")
	check("GIG LIMIT REACHED (3)" in window.page.get_text(), "on a gig post too")

	PilotNet.day = 2
	PilotNet.note_met("Lady Volk")
	PilotNet.note_met("ASH")
	window.navigate("pilot.net/pilot/Lady%20Volk")
	text = window.page.get_text()
	check("[AFFILIATION]" in text and "Last seen: %s" % PilotNet.short_date(2) in text and "KNOWN BUILD" in text, "a profile")
	check(window.page.get_links().has(NetSites.wiki_url("MSV-L3J-H")), "the build links to Steelapedia")
	check("[SAMPLE] A thread with a gated reply" in text, "with their posts")
	window.navigate("pilot.net/pilot/ASH")
	check("No profile on file." in window.page.get_text() and "Last seen: %s" % PilotNet.short_date(2) in window.page.get_text(),
			"a met pilot with no profile")
	window.navigate("pilot.net/pilot/" + PlayerProgress.get_callsign())
	text = window.page.get_text()
	check("YOUR PROFILE" in text and "Reputation: 0" in text and "Gigs completed: 0" in text and "[SAMPLE] Text tags" in text,
			"the player's own profile")
	window.navigate("pilot.net/pilots")
	text = window.page.get_text()
	check("Lady Volk" in text and "ASH" in text and "CALLSIGN" in text and "LAST SEEN" in text, "the directory")
	window.navigate("pilot.net/pilots?l=A")
	check(not "Lady Volk" in window.page.get_text() and "ASH" in window.page.get_text(), "A-Z")
	window.navigate("pilot.net/search?q=trade")
	check("[SAMPLE] A trade post" in window.page.get_text() and "1 post found" in window.page.get_text(), "search")
	(window.page as PilotNetPage).search_field.text_submitted.emit("thread")
	check_eq(window.current_url, "pilot.net/search?q=thread", "the search box searches")
