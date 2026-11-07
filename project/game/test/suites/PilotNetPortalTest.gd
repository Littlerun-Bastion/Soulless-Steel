extends TestSuite

# PilotNetPortalTest: pilot.net's new look (PilotNetPortalPage) and the switch
# between the looks (PilotNet.look(), database/pilotnet/site.json).
#   - site.json valid, and its checks catch mistakes
#   - the board look first; the portal once site.json's flag is set; the
#     override winning and cycling; the NET building the page for the look;
#     the sample post that comes with the new look
#   - every portal page opening; the front page's parts, the feature box's
#     slides, the tabs, the site buttons, the quote and search boxes
#   - forum tables and paging, message blocks with avatars, gig buttons
#     (accept, the limit, abandon), profiles, the directory, the NET search
#   - the avatar's pattern and the chart's points
# Loads are instant (NetWindow.load_time_scale 0).

const NEW_LOOK_FLAG := "pilotnet_new_look"
const SAMPLE_THREAD := "sample_thread"
const SAMPLE_NEW_LOOK := "sample_new_look"


func run_tests() -> void:
	await case("site.json is valid, and its checks catch mistakes", _test_site_file)
	await case("the story switches the look", _test_switch)
	await case("every page in the new look opens", _test_pages)
	await case("the front page", _test_front_page)
	await case("forums, messages and the NET search", _test_forums)
	await case("gig buttons", _test_gig_buttons)
	await case("profiles and the directory", _test_pilots)
	await case("the avatar and the chart", _test_drawings)
	PilotNet.look_override = ""
	NetWindow.load_time_scale = 1.0


func before_each() -> void:
	StoryDirector.reset(false)
	PlayerProgress.reset()
	PilotNet.rng.seed = 4242
	PilotNet.reset(false)
	PilotNet.look_override = ""
	MechOS.close_all()
	MechOS.set_app_available("net", false)
	NetWindow.load_time_scale = 0.0


func _net(url: String) -> NetWindow:
	MechOS.set_app_available("net", true)
	var window: NetWindow = MechOS.open_net(url)
	check(window != null, "NET opens")
	return window


func _portal(url: String) -> NetWindow:
	StoryDirector.set_flag(NEW_LOOK_FLAG, true, false)
	return _net(url)


func _buttons(page: Node, action: String) -> Array:
	return page.find_children("*", "Button", true, false).filter(func(b): return str(b.get_meta("action", "")) == action)


# ---- the switch ---------------------------------------------------------------

func _test_site_file() -> void:
	check(PilotNet.check_site(PilotNet.site).is_empty(), "site.json is valid (%s)" % "; ".join(PilotNet.check_site(PilotNet.site)))
	check(PilotNet.site.has("new_look"), "it has a new look")
	var problems := " | ".join(PilotNet.check_site({"colour": 1, "new_look": {"requires": {"when": 2}, "notice": "{nope}", "x": 1}}))
	for wanted in ["site.json: unknown key 'colour'", "new_look: unknown key 'x'", "unknown condition", "unknown tag {nope}"]:
		check(wanted in problems, "catches: %s (%s)" % [wanted, problems])
	check(" ".join(PilotNet.check_site({"new_look": 3})).contains("isn't an object"), "catches a new_look that isn't an object")


func _test_switch() -> void:
	check_eq(PilotNet.look(), PilotNet.LOOK_BBS, "the board look first")
	var window := _net("pilot.net/")
	check(window.page is PilotNetPage, "the NET builds the board")
	check(not PilotNet.is_post_visible(SAMPLE_NEW_LOOK), "the new look's post waits for it")
	StoryDirector.set_flag(NEW_LOOK_FLAG, true, false)
	check_eq(PilotNet.look(), PilotNet.LOOK_PORTAL, "the flag switches to the portal")
	check(window.page is PilotNetPage, "the open page stays as it is")
	window.reload()
	check(window.page is PilotNetPortalPage, "the next load is the portal")
	check(PilotNet.is_post_visible(SAMPLE_NEW_LOOK), "and the new look's post shows")
	check(PilotNet.look_notice() != "" and PilotNet.look_notice() in window.page.get_text(), "the notice line")
	PilotNet.look_override = PilotNet.LOOK_BBS
	check_eq(PilotNet.look(), PilotNet.LOOK_BBS, "the override wins over the story")
	window.reload()
	check(window.page is PilotNetPage, "and the NET follows it")
	PilotNet.look_override = ""
	PilotNet.cycle_look_override()
	check_eq(PilotNet.look_override, PilotNet.LOOK_PORTAL, "Shift+F9: the portal")
	PilotNet.cycle_look_override()
	check_eq(PilotNet.look_override, PilotNet.LOOK_BBS, "then the board")
	PilotNet.cycle_look_override()
	check_eq(PilotNet.look_override, "", "then the story's choice")
	StoryDirector.set_flag(NEW_LOOK_FLAG, false, false)
	check_eq(PilotNet.look(), PilotNet.LOOK_BBS, "clearing the flag switches back")
	check(PilotNet.get_save_data().keys().all(func(k): return k != "look_override"), "the override isn't saved")


# ---- pages --------------------------------------------------------------------

func _test_pages() -> void:
	PilotNet.note_met("ASH")
	var gig: Dictionary = PilotNet.open_gigs()[0]
	var window := _portal("pilot.net/")
	var paths := ["/", "/forums", "/boards", "/board/news", "/board/gigs", "/board/general", "/board/general?page=9",
			"/board/trade", "/board/nowhere", "/post/" + SAMPLE_THREAD, "/post/%s?page=4" % SAMPLE_THREAD,
			"/post/gig:" + gig.id, "/post/sample_gig_post", "/post/no_such_post", "/gigs", "/pilots", "/pilots?l=L",
			"/pilot/Lady%20Volk", "/pilot/ASH", "/pilot/" + PlayerProgress.get_callsign(), "/pilot/Nobody",
			"/search?q=sample", "/search", "/nonsense"]
	for path in paths:
		window.navigate("pilot.net" + path)
		check(window.page is PilotNetPortalPage and window.page.page_title.begins_with("pilot.net"), "%s opens" % path)
		check(not window.page.get_text().is_empty(), "%s has text" % path)
	window.navigate("pilot.net/board/nowhere")
	check(PilotNetPortalPage.NOT_FOUND in window.page.get_text(), "an unknown board isn't found")
	window.navigate("pilot.net/board/news")
	var text: String = window.page.get_text()
	check(text.find("[SAMPLE] A post that comes with the new look") < text.find("[SAMPLE] A notify post"), "pinned first")
	for column in ["Topic", "Started by", "Replies", "Last post"]:
		check(column in text, "the board's %s column" % column)


func _test_front_page() -> void:
	var window := _portal("pilot.net/")
	var page: PilotNetPortalPage = window.page
	var text := page.get_text()
	for part in ["News & Gigs", "Look it Up", "Shopping", "Money", "PILOT.NET NEWS", "HOT IN THE FORUMS", "GIG BOARD",
			"MONEY", "SHOPPING", "WORLD STATUS", "PILOTS ONLINE", "Advertisement", "Search the NET:", PilotNetPortalPage.SMALL_PRINT]:
		check(part in text, "the front page's %s" % part)
	check("Logged in as" in text and PlayerProgress.get_callsign().to_upper() in text and PilotNet.date_text(1) in text, "the strip")
	var tabs := page.find_children("*", "Button", true, false).filter(func(b): return str(b.theme_type_variation).begins_with("NetPortalTab"))
	check_eq(tabs.size(), PilotNetPortalPage.TABS.size(), "the section tabs")
	check_eq(tabs.filter(func(b): return b.theme_type_variation == &"NetPortalTabActive").map(func(b): return b.text), ["Home"],
			"the open section's tab shows light")
	check(page.get_links().has("steelapedia.net") and page.get_links().has("amazing.com") and page.get_links().has("fourx.net"),
			"the site buttons")
	check(page.get_links().has(NetSites.quote_url(FourX.COMPOSITE)), "the MONEY box links to quotes")
	check(page.slide_count() >= 4, "the feature box's slides (%d)" % page.slide_count())
	var first = page._feature.get_meta("slide")
	check_eq(first, 0, "the first slide shows first")
	check("TOP STORY" in page.get_text() and "1 of %d" % page.slide_count() in page.get_text(), "the top story")
	page.show_slide(page.slide_count())
	check_eq(page._feature.get_meta("slide"), 0, "next after the last goes round")
	page.show_slide(-1)
	check_eq(page._feature.get_meta("slide"), page.slide_count() - 1, "back from the first goes to the last")
	var market := -1
	for i in page.slide_count():
		page.show_slide(i)
		if not page.find_children("*", "PortalChart", true, false).is_empty():
			market = i
	check(market >= 0, "the market slide has a chart")
	page.quote_field.text_submitted.emit("mrtl")
	await wait_frames(2)
	check(window.current_url.begins_with("fourx.net/"), "Get quote goes to FourX.net (%s)" % window.current_url)
	window.navigate("pilot.net/")
	(window.page as PilotNetPortalPage).search_field.text_submitted.emit("thread")
	check_eq(window.current_url, "pilot.net/search?q=thread", "the search box searches")


func _test_forums() -> void:
	for i in 25:
		PilotNet.post({"id": "filler_%02d" % i, "board": "general", "title": "Filler %02d" % i, "body": "Body."})
	var window := _portal("pilot.net/forums")
	var text: String = window.page.get_text()
	check("Forum" in text and "Topics" in text and "Last post" in text and "GENERAL CHATTER" in text, "the forum index")
	check("WHO IS ONLINE" in text and "STATISTICS" in text, "who is online and the statistics")
	window.navigate("pilot.net/board/general")
	text = window.page.get_text()
	check("Page 1 of 2" in text and window.page.get_links().has("pilot.net/board/general?page=2"), "a long board pages")
	window.navigate("pilot.net/post/" + SAMPLE_THREAD)
	check(StoryDirector.has_flag("sample_thread_read"), "opening a topic runs its on_read")
	text = window.page.get_text()
	check("2 replies" in text and "KESTREL" in text and "GREYWAKE" in text and "#1" in text and "#3" in text, "the messages")
	var messages := window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("message"))
	check_eq(messages.size(), 3, "one block a message")
	var avatars := window.page.find_children("*", "PilotAvatar", true, false)
	check(avatars.size() == 3 and avatars[0].callsign == "Lady Volk", "each with its author's avatar")
	check(window.page.get_links().has("pilot.net/pilot/Lady%20Volk"), "the author links to the profile")
	window.navigate("pilot.net/search?q=martel")
	text = window.page.get_text()
	check("Steelapedia: " in text and "amazing.com: " in text and "FourX.net: " in text, "the NET search covers every site")
	window.navigate("pilot.net/search?q=trade")
	check("[SAMPLE] A trade post" in window.page.get_text() and "1 post found" in window.page.get_text(), "and pilot.net's posts")


func _test_gig_buttons() -> void:
	var gig: Dictionary = PilotNet.open_gigs()[0]
	var window := _portal("pilot.net/post/gig:" + gig.id)
	var accept := _buttons(window.page, "%s:%s" % [PilotNetSite.ACCEPT, gig.id])
	check(accept.size() == 1 and not accept[0].disabled and gig.title in window.page.get_text(), "a gig post offers its gig")
	accept[0].pressed.emit()
	check_eq(PilotNet.get_gig(gig.id).state, "active", "Accept accepts it")
	check("ACCEPTED" in window.page.get_text(), "and the page says so")
	window.navigate("pilot.net/gigs")
	var text: String = window.page.get_text()
	check("Your gigs (1/3)" in text and PilotNet.progress_text(PilotNet.get_gig(gig.id)) in text, "your gigs")
	check(not window.page.find_children("*", "ProgressBar", true, false).is_empty(), "with a progress bar")
	var abandon := _buttons(window.page, "%s:%s" % [PilotNetSite.ABANDON, gig.id])
	check_eq(abandon.size(), 1, "an Abandon button")
	abandon[0].pressed.emit()
	check(PilotNet.get_gig(gig.id).is_empty(), "Abandon drops it")
	for i in 3:
		PilotNet.accept_gig(PilotNet.open_gigs()[0].id)
	window.navigate("pilot.net/gigs")
	check("GIG LIMIT REACHED (3)" in window.page.get_text(), "the limit shows")
	var open := PilotNet.open_gigs()
	if not open.is_empty():
		var blocked := _buttons(window.page, "%s:%s" % [PilotNetSite.ACCEPT, open[0].id])
		check(blocked.size() == 1 and blocked[0].disabled, "and Accept is greyed out")
	window.navigate("pilot.net/post/sample_gig_post")
	check("GIG LIMIT REACHED (3)" in window.page.get_text(), "on a gig post too")


func _test_pilots() -> void:
	PilotNet.day = 2
	PilotNet.note_met("Lady Volk")
	PilotNet.note_met("ASH")
	var window := _portal("pilot.net/pilot/Lady%20Volk")
	var text: String = window.page.get_text()
	check("[AFFILIATION]" in text and "Last seen: %s" % PilotNet.long_date(2) in text and "Known build" in text, "a profile")
	check(window.page.get_links().has(NetSites.wiki_url("MSV-L3J-H")), "the build links to Steelapedia")
	check("[SAMPLE] A thread with a gated reply" in text, "with their posts")
	window.navigate("pilot.net/pilot/ASH")
	check("No profile on file." in window.page.get_text() and "Last seen: %s" % PilotNet.long_date(2) in window.page.get_text(),
			"a met pilot with no profile")
	window.navigate("pilot.net/pilot/" + PlayerProgress.get_callsign())
	text = window.page.get_text()
	check("YOUR PROFILE" in text and "Reputation: 0" in text and "Gigs completed: 0" in text, "the player's own profile")
	window.navigate("pilot.net/pilots")
	text = window.page.get_text()
	check("Lady Volk" in text and "ASH" in text and "Callsign" in text and "Last seen" in text, "the directory")
	window.navigate("pilot.net/pilots?l=A")
	check(not "Lady Volk" in window.page.get_text() and "ASH" in window.page.get_text(), "A-Z")


func _test_drawings() -> void:
	var rows := PilotAvatar.pattern("Lady Volk")
	check_eq(rows.size(), PilotAvatar.CELLS, "an avatar has %d rows" % PilotAvatar.CELLS)
	check(rows.all(func(r): return r.size() == PilotAvatar.CELLS and r[0] == r[PilotAvatar.CELLS - 1] and r[1] == r[PilotAvatar.CELLS - 2]),
			"mirrored left to right")
	check_eq(rows, PilotAvatar.pattern("LADY VOLK"), "the same for a callsign in any case")
	check(PilotAvatar.pattern("Lady Volk") != PilotAvatar.pattern("KESTREL"), "different callsigns, different pictures")
	var filled := 0
	for callsign in ["", "a", "SYSOP", "Drifter"]:
		filled += 1 if PilotAvatar.pattern(callsign).any(func(r): return r.has(true)) else 0
	check_eq(filled, 4, "never an empty picture")
	var avatar := PilotAvatar.new("X", 6)
	check_eq(avatar.custom_minimum_size, Vector2.ONE * (PilotAvatar.CELLS * 6 + 2), "its size from the cell size")
	avatar.free()
	var chart := PortalChart.new([1.0, 3.0, 2.0, 5.0], Vector2(100, 50))
	chart.size = Vector2(100, 50)
	var points := chart.points()
	check_eq(points.size(), 4, "a point a price")
	check(points[0].x < points[1].x and points[1].x < points[3].x, "oldest to newest, left to right")
	check(is_equal_approx(points[3].y, 1.5) and is_equal_approx(points[0].y, 48.5), "the highest at the top, the lowest at the bottom")
	chart.free()
