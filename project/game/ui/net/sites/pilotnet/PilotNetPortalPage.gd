class_name PilotNetPortalPage
extends NetPortalBase

## pilot.net's new look (PilotNet.look() "portal"): a mid-2000s web portal in
## MechOS greys, for when the story has someone rebuild the site. It shows
## what the text-mode board (PilotNetPage) shows, from the same picks
## (PilotNetSite) and at the same paths, built from controls:
##   top strip    site.json's notice; who is logged in, the day, unread posts
##   header band  the wordmark and emblem (PilotNetLogo), the section tabs
##                (the open one light), Search the NET
##   page         the front page in three columns: link lists; the feature
##                box (slides with back and next), news, forums and gigs; the
##                site buttons, an amazing.com ad and the MONEY, SHOPPING,
##                WORLD STATUS, PILOTS ONLINE and IN MEMORIAM (the Memorial
##                Wall's newest) boxes. Other pages: a trail
##                of links, a title, striped tables, message blocks with the
##                pilots' avatars (PilotAvatar)
##   footer       links and the small print
## Paths: / , /forums (/boards), /board/<id>?page=, /post/<id>?page=, /gigs,
## /pilots?l=, /pilot/<callsign>, /search?q=. The gig buttons act
## (PilotNetSite.act) and load the page again.

const DOMAIN := PilotNetSite.DOMAIN
const LEFT_WIDTH := 180
const RIGHT_WIDTH := 300
const AUTHOR_WIDTH := 170
const FEATURE_PICTURE := Vector2(180, 140)
const AD_PICTURE := Vector2(96, 96)
const NEWS_COUNT := 6
const FORUM_COUNT := 4
const GIG_COUNT := 4
const DEAL_COUNT := 4
const MOVER_COUNT := 2
const SEARCH_COUNT := 8
const TEASER_LENGTH := 240
const TOPICS_PER_PAGE := 20
const REPLIES_PER_PAGE := 10
## The section tabs: [label, path, section].
const TABS := [["Home", "/", "HOME"], ["News", "/board/news", "NEWS"], ["Gigs", "/gigs", "GIGS"],
		["Forums", "/forums", "FORUMS"], ["Pilots", "/pilots", "PILOTS"]]
const SITE_BUTTONS := [["STEELAPEDIA", "steelapedia.net"], ["AMAZING.COM", "amazing.com"], ["FOURX.NET", "fourx.net"]]
const FOOTER_LINKS := [["pilot.net Home", "/"], ["Forums", "/forums"], ["Gigs", "/gigs"], ["Pilots", "/pilots"]]
const SMALL_PRINT := "© pilot.net · Privacy · Terms of use · Advertise"
const NOT_FOUND := "We can't find that page."

var search_field: LineEdit = null
var quote_field: LineEdit = null
var _section := ""
var _slides: Array = []
var _slide := 0
var _feature: PanelContainer = null


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	var segments := Array(page_path.split("/", false))
	var first: String = str(segments[0]).to_lower() if not segments.is_empty() else ""
	var page_number := maxi(int(str(page_query.get("page", "1"))), 1)
	page_title = DOMAIN
	main = NetUI.vbox(&"NetPortalStack")
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if first == "":
		_home()
	elif first in ["forums", "boards"] and segments.size() == 1:
		_forums()
	elif first == "board" and segments.size() == 2:
		_board(str(segments[1]).to_lower(), page_number)
	elif first == "post" and segments.size() == 2:
		_post(str(segments[1]), page_number)
	elif first == "gigs" and segments.size() == 1:
		_gigs()
	elif first == "pilots" and segments.size() == 1:
		_pilots(str(page_query.get("l", "")).to_upper())
	elif first == "pilot" and segments.size() == 2:
		_pilot(str(segments[1]))
	elif first == "search":
		_search(str(page_query.get("q", "")))
	else:
		_not_found()
	_build(str(page_query.get("q", "")) if first == "search" else "")


## The feature box's slide count (tests).
func slide_count() -> int:
	return _slides.size()


## Shows the feature box's slide at index (wrapping round).
func show_slide(index: int) -> void:
	if _feature == null:
		return
	for child in _feature.get_children():
		_feature.remove_child(child)
		child.queue_free()
	if _slides.is_empty():
		_feature.add_child(NetUI.text("Nothing new today.", &"NetPortalMeta"))
		return
	_slide = posmod(index, _slides.size())
	var slide: Dictionary = _slides[_slide]
	var column := NetUI.vbox(&"NetPortalTight")
	var row := NetUI.hbox(&"NetPortalColumns")
	var holder := CenterContainer.new()
	holder.custom_minimum_size = FEATURE_PICTURE
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var picture := _slide_picture(str(slide.picture))
	if picture != null:
		holder.add_child(picture)
	row.add_child(holder)
	var words := NetUI.vbox(&"NetPortalTight")
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(NetUI.text(str(slide.kicker), &"NetPortalMeta"))
	words.add_child(_rich("[b]%s[/b]" % _link_code(str(slide.title), str(slide.url))))
	words.add_child(_rich(esc(str(slide.text))))
	var links := []
	for entry in slide.links:
		links.append("» " + _link_code(str(entry[0]), str(entry[1])))
	words.add_child(_rich("\n".join(links)))
	row.add_child(words)
	column.add_child(row)
	var nav := NetUI.hbox(&"NetPortalToolbar")
	nav.alignment = BoxContainer.ALIGNMENT_END
	nav.add_child(_action_link("« back", show_slide.bind(_slide - 1)))
	nav.add_child(NetUI.text("%d of %d" % [_slide + 1, _slides.size()], &"NetPortalMeta"))
	nav.add_child(_action_link("next »", show_slide.bind(_slide + 1)))
	column.add_child(nav)
	_feature.add_child(column)
	_feature.set_meta("slide", _slide)


# ---- the front page -------------------------------------------------------------

func _home() -> void:
	_section = "HOME"
	page_title = "%s - Home" % DOMAIN
	var columns := NetUI.hbox(&"NetPortalColumns")
	main.add_child(columns)
	columns.add_child(_left_column())
	var middle := NetUI.vbox(&"NetPortalStack")
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	var right := NetUI.vbox(&"NetPortalStack")
	right.custom_minimum_size.x = RIGHT_WIDTH
	columns.add_child(right)
	_front_middle(middle)
	_front_right(right)


func _left_column() -> VBoxContainer:
	var column := NetUI.vbox(&"NetPortalStack")
	column.custom_minimum_size.x = LEFT_WIDTH
	var wiki := NetSites.STEELAPEDIA_DOMAIN
	var money := [["FourX.net", NetSites.fourx_url()]]
	for group in FourX.groups():
		if group.id != FourX.INDEX_GROUP:
			money.append([str(group.name).capitalize(), NetSites.fourx_url("/group/" + str(group.id))])
	var groups := [
		["News & Gigs", [["News", _url("/board/news")], ["Gigs (%d open)" % PilotNet.open_gigs().size(), _url("/gigs")],
				["Forums", _url("/forums")], ["Pilot directory", _url("/pilots")],
				["Your profile", PilotNetSite.pilot_url(PlayerProgress.get_callsign())]]],
		["Look it Up", [["Steelapedia", NetSites.make_url(wiki)], ["Random article", NetSites.make_url(wiki, "/special/random")],
				["Parts", NetSites.make_url(wiki, "/category/parts")], ["Manufacturers", NetSites.make_url(wiki, "/category/manufacturers")],
				["Entities", NetSites.make_url(wiki, "/category/entities")]]],
		["Shopping", [["amazing.com", NetSites.store_url()], ["Hardware", NetSites.store_url("/hardware")],
				["Wetware", NetSites.store_url("/wetware")], ["Weapons", NetSites.store_url("/weapons")],
				["Makers A-Z", NetSites.store_url("/makers")], ["Your cart (%d)" % Store.cart_count(), NetSites.store_url("/cart")]]],
		["Money", money],
	]
	for i in groups.size():
		if i > 0:
			column.add_child(_rule())
		column.add_child(NetUI.text(groups[i][0], &"NetPortalSection"))
		var links := NetUI.vbox(&"NetPortalTight")
		for entry in groups[i][1]:
			links.add_child(_link(str(entry[0]), str(entry[1])))
		column.add_child(links)
	return column


func _front_middle(middle: VBoxContainer) -> void:
	middle.add_child(NetUI.text(PilotNet.date_text(PilotNet.day), &"NetPortalLabel"))
	_slides = _make_slides()
	_feature = NetUI.panel(&"NetPortalFeature")
	middle.add_child(_feature)
	show_slide(0)

	var news := []
	for post_data in PilotNetSite.headlines(NEWS_COUNT):
		news.append(_bullet(PilotNet.fill_tags(post_data.title), PilotNetSite.post_url(post_data.id),
				PilotNet.long_date(PilotNet.first_seen_day(post_data.id)), PilotNet.is_new(post_data.id)))
	middle.add_child(_list("PILOT.NET NEWS", news, ["All news", _url("/board/news")]))

	var topics := []
	for post_data in PilotNetSite.hot_topics(FORUM_COUNT):
		var board := PilotNet.get_board(str(post_data.board))
		var replies := PilotNet.visible_replies(post_data.id).size()
		topics.append(_bullet(PilotNet.fill_tags(post_data.title), PilotNetSite.post_url(post_data.id),
				"%d repl%s · %s" % [replies, "y" if replies == 1 else "ies", str(board.get("name", post_data.board))],
				PilotNet.is_new(post_data.id)))
	middle.add_child(_list("HOT IN THE FORUMS", topics, ["All forums", _url("/forums")]))

	var gigs_open := PilotNet.open_gigs()
	var gigs := []
	for gig in gigs_open.slice(0, GIG_COUNT):
		gigs.append(_bullet(str(gig.title), PilotNetSite.post_url("gig:" + str(gig.id)),
				"%s CT" % BbsText.thousands(int(gig.reward))))
	middle.add_child(_list("GIG BOARD", gigs, ["%d open · %d/%d yours · All gigs" % [gigs_open.size(), PilotNet.active_gigs().size(),
			PilotNet.MAX_ACTIVE_GIGS], _url("/gigs")]))


# The feature box's slides: {"kicker", "title", "url", "text", "links":
# [[label, url]], "picture": "avatar:<callsign>", "part:<type>:<id>",
# "chart:<symbol>", "globe" or ""}.
func _make_slides() -> Array:
	var slides := []
	var top := PilotNetSite.top_story()
	if not top.is_empty():
		slides.append({"kicker": "TOP STORY", "title": PilotNet.fill_tags(top.title), "url": PilotNetSite.post_url(top.id),
				"text": BbsText.cut(PilotNetSite.teaser(top), TEASER_LENGTH),
				"links": [["Full story", PilotNetSite.post_url(top.id)], ["More news", _url("/board/news")]],
				"picture": "avatar:" + PilotNet.author_name(top)})
	var gigs_open := PilotNet.open_gigs()
	if not gigs_open.is_empty():
		var best: Dictionary = gigs_open[0]
		for gig in gigs_open:
			if int(gig.reward) > int(best.reward):
				best = gig
		slides.append({"kicker": "GIG BOARD", "title": str(best.title), "url": PilotNetSite.post_url("gig:" + str(best.id)),
				"text": "%s CT and +%d reputation, posted by %s. %d open gigs on the board." % [BbsText.thousands(int(best.reward)),
				int(best.reputation), str(best.poster), gigs_open.size()],
				"links": [["See the gig board", _url("/gigs")]], "picture": "avatar:" + str(best.poster)})
	AmazingPage.ensure_picks()
	if not AmazingPage.featured.is_empty():
		var part_type: String = AmazingPage.featured[0]
		var part_id: String = AmazingPage.featured[1]
		slides.append({"kicker": "SHOPPING", "title": Store.part_name(part_type, part_id), "url": NetSites.product_url(part_type, part_id),
				"text": "%s by %s · %s CT" % [Store.type_name(part_type), Manufacturers.display_name(Store.maker_of(part_type, part_id)),
				BbsText.thousands(Store.price(part_type, part_id))],
				"links": [["Shop amazing.com", NetSites.store_url()]], "picture": "part:%s:%s" % [part_type, part_id]})
	var composite := FourX.quote(FourX.COMPOSITE)
	if not composite.is_empty():
		var moves := FourX.movers(1)
		var text := []
		if not moves.gainers.is_empty():
			text.append("Biggest rise: %s %s." % [moves.gainers[0].name, FourX.format_pct(moves.gainers[0].change_pct)])
		if not moves.losers.is_empty():
			text.append("Biggest fall: %s %s." % [moves.losers[0].name, FourX.format_pct(moves.losers[0].change_pct)])
		slides.append({"kicker": "MONEY", "title": "%s %s (%s)" % [composite.name, FourX.format_price(composite.last),
				FourX.format_pct(composite.change_pct)], "url": NetSites.quote_url(FourX.COMPOSITE), "text": " ".join(text),
				"links": [["Markets at FourX.net", NetSites.fourx_url()]], "picture": "chart:" + FourX.COMPOSITE})
	var article = SteelapediaPage.featured()
	if article != null:
		slides.append({"kicker": "LOOK IT UP", "title": str(article.title), "url": NetSites.wiki_url(article.slug),
				"text": str(article.summary), "links": [["Read more on Steelapedia", NetSites.wiki_url(article.slug)]],
				"picture": "globe"})
	return slides


func _slide_picture(kind: String) -> Control:
	if kind.begins_with("avatar:"):
		return PilotAvatar.new(kind.substr(7), 20)
	if kind.begins_with("part:"):
		var parts := kind.split(":")
		var part := Store.get_part(parts[1], parts[2])
		var texture = part.get("image") if part != null else null
		return _picture(texture, FEATURE_PICTURE) if texture is Texture2D else null
	if kind.begins_with("chart:"):
		return PortalChart.new(FourX.quote(kind.substr(6)).get("prices", []), FEATURE_PICTURE)
	if kind == "globe":
		return SteelapediaLogo.new()
	return null


func _front_right(right: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.theme_type_variation = &"NetPortalGrid"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	var me := PlayerProgress.get_callsign()
	for entry in [["MY PROFILE", PilotNetSite.pilot_url(me)]] + SITE_BUTTONS:
		grid.add_child(_pill(str(entry[0]), str(entry[1])))
	right.add_child(grid)

	AmazingPage.ensure_picks()
	if not AmazingPage.featured.is_empty():
		var part_type: String = AmazingPage.featured[0]
		var part_id: String = AmazingPage.featured[1]
		var tag := NetUI.text("Advertisement", &"NetPortalMeta")
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(tag)
		var ad := NetUI.hbox(&"NetPortalColumns")
		var part := Store.get_part(part_type, part_id)
		var texture = part.get("image") if part != null else null
		if texture is Texture2D and _fits(texture, AD_PICTURE):
			ad.add_child(_picture(texture, AD_PICTURE))
		var words := NetUI.vbox(&"NetPortalTight")
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(NetUI.text("Now at amazing.com", &"NetPortalLabel"))
		words.add_child(_rich(_link_code(Store.part_name(part_type, part_id), NetSites.product_url(part_type, part_id))))
		words.add_child(NetUI.text("%s CT" % BbsText.thousands(Store.price(part_type, part_id)), &"NetPortalText"))
		words.add_child(_link("Shop now »", NetSites.product_url(part_type, part_id)))
		ad.add_child(words)
		var box := NetUI.panel(&"NetPortalBox", ad)
		box.set_meta("net_part", [part_type, part_id])
		right.add_child(box)

	var money := NetUI.vbox(&"NetPortalTight")
	var shown := []
	for symbol in [FourX.COMPOSITE, FourX.SALVAGE_INDEX]:
		var quote := FourX.quote(symbol)
		if not quote.is_empty():
			shown.append(quote)
	var moves := FourX.movers(MOVER_COUNT)
	shown.append_array((moves.gainers as Array) + (moves.losers as Array))
	for quote in shown:
		var line := NetUI.hbox(&"NetPortalToolbar")
		var symbol_link := _link(str(quote.symbol), NetSites.quote_url(str(quote.symbol)))
		symbol_link.custom_minimum_size.x = 56
		line.add_child(symbol_link)
		var last := NetUI.text(FourX.format_price(float(quote.last)), &"NetPortalText")
		last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		last.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(last)
		var change := NetUI.text(FourX.format_change(float(quote.change)), &"NetPortalLabel")
		change.custom_minimum_size.x = 80
		change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(change)
		money.add_child(line)
	var lookup := NetUI.hbox(&"NetPortalToolbar")
	lookup.add_child(NetUI.text("Get quote:", &"NetPortalText"))
	quote_field = NetUI.input("symbol")
	quote_field.theme_type_variation = &"NetPortalInput"
	quote_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quote_field.context_menu_enabled = false
	quote_field.text_submitted.connect(_submit_quote)
	lookup.add_child(quote_field)
	var go := NetUI.button("GO")
	go.pressed.connect(func(): _submit_quote(quote_field.text))
	lookup.add_child(go)
	money.add_child(lookup)
	money.add_child(NetUI.text("Quotes: %s close" % PilotNet.long_date(FourX.day()), &"NetPortalMeta"))
	right.add_child(_widget("MONEY", money))

	var deals := []
	for entry in AmazingPage.picks.slice(0, DEAL_COUNT):
		deals.append("• %s %s" % [_link_code(Store.part_name(entry[0], entry[1]), NetSites.product_url(entry[0], entry[1])),
				_meta_code("%s CT" % BbsText.thousands(Store.price(entry[0], entry[1])))])
	deals.append("» " + _link_code("More at amazing.com", NetSites.store_url()))
	right.add_child(_widget("SHOPPING", _rich("\n".join(deals))))

	var lines := PilotNet.world_lines()
	if not lines.is_empty():
		var status := NetUI.vbox(&"NetPortalTight")
		for line in lines:
			var row := NetUI.hbox(&"NetPortalToolbar")
			var label := NetUI.text(str(line.label), &"NetPortalText", true)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			row.add_child(NetUI.text(str(line.text), &"NetPortalLabel"))
			status.add_child(row)
		right.add_child(_widget("WORLD STATUS", status))

	var names := []
	for callsign in PilotNetSite.online():
		names.append(_link_code(callsign, PilotNetSite.pilot_url(callsign)) if PilotNetSite.is_known(callsign) else esc(callsign))
	right.add_child(_widget("PILOTS ONLINE", _rich(", ".join(names) + "\n" + _meta_code("and %d guests" % PilotNetSite.guests()))))

	var lost := []
	for entry in PilotNetSite.in_memoriam():
		lost.append("† %s\n%s" % [_link_code(str(entry.callsign), NetSites.memorial_record_url(int(entry.id))),
				_meta_code("%s · %s" % [PilotNet.long_date(int(entry.day)), str(entry.site)])])
	if lost.is_empty():
		lost.append(_meta_code(PilotNetSite.NO_POSTS))
	lost.append("» " + _link_code("Visit the %s" % PilotNetSite.MEMORIAL_NAME, NetSites.memorial_url()))
	right.add_child(_widget("IN MEMORIAM", _rich("\n".join(lost))))


func _submit_quote(text: String) -> void:
	if text.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	follow(NetSites.fourx_url("/search", {"q": text.strip_edges()}))


# ---- forums -----------------------------------------------------------------------

func _forums() -> void:
	_section = "FORUMS"
	page_title = "%s - Forums" % DOMAIN
	main.add_child(_trail([["Forums", ""]]))
	main.add_child(_title("Forums"))
	var rows := []
	for row in PilotNetSite.forum_rows():
		var board: Dictionary = row.board
		var last: Dictionary = row.last
		var board_link := "[b]%s[/b]" % _link_code(str(board.name), _url("/board/" + str(board.id)))
		if row.unread:
			board_link += "  " + _meta_code("NEW")
		var last_cell: Control = NetUI.text("-", &"NetPortalMeta")
		if not last.is_empty():
			last_cell = _rich("%s\n%s" % [_meta_code("%s by %s" % [PilotNet.stamp(PilotNet.first_seen_day(last.id), PilotNet.post_time(last.id)),
					PilotNet.author_name(last)]), _link_code(PilotNet.fill_tags(last.title), PilotNetSite.post_url(last.id))])
		rows.append([_rich("%s\n%s" % [board_link, _meta_code(str(board.get("blurb", "")))]), str(row.topics), str(row.posts), last_cell])
	main.add_child(_table([{"title": "Forum", "width": 0}, {"title": "Topics", "width": 70, "align": "right"},
			{"title": "Posts", "width": 70, "align": "right"}, {"title": "Last post", "width": 280}], rows))
	main.add_child(NetUI.text("Boards with posts you haven't read are marked NEW.", &"NetPortalMeta"))
	var columns := NetUI.hbox(&"NetPortalColumns")
	var names := []
	for callsign in PilotNetSite.online():
		names.append(_link_code(callsign, PilotNetSite.pilot_url(callsign)) if PilotNetSite.is_known(callsign) else esc(callsign))
	var online := _widget("WHO IS ONLINE", _rich(_meta_code("%d pilots and %d guests" % [names.size(), PilotNetSite.guests()])
			+ "\n" + ", ".join(names)))
	online.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(online)
	var figures := PilotNetSite.stats()
	var stats := NetUI.vbox(&"NetPortalTight")
	for entry in [["Topics", str(figures.topics)], ["Posts", str(figures.posts)], ["Pilots", str(figures.pilots)],
			["Newest pilot", str(figures.newest)]]:
		var line := NetUI.hbox(&"NetPortalToolbar")
		var label := NetUI.text(str(entry[0]), &"NetPortalText")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(NetUI.text(str(entry[1]), &"NetPortalLabel"))
		stats.add_child(line)
	var stats_box := _widget("STATISTICS", stats)
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(stats_box)
	main.add_child(columns)


func _board(id: String, page_number: int) -> void:
	var board := PilotNet.get_board(id)
	if board.is_empty() or not PilotNet.board_visible(id):
		_not_found()
		return
	_section = PilotNetSite.section_of(id)
	page_title = "%s - %s" % [DOMAIN, str(board.name)]
	main.add_child(_trail([["Forums", _url("/forums")], [str(board.name), ""]]))
	main.add_child(_title(str(board.name)))
	main.add_child(NetUI.text(str(board.get("blurb", "")), &"NetPortalMeta", true))
	var posts := PilotNet.visible_posts(id)
	var pages := maxi(ceili(posts.size() / float(TOPICS_PER_PAGE)), 1)
	page_number = mini(page_number, pages)
	main.add_child(NetUI.text("%d topic%s · Page %d of %d" % [posts.size(), "" if posts.size() == 1 else "s", page_number, pages],
			&"NetPortalMeta"))
	var rows := []
	for post_data in posts.slice((page_number - 1) * TOPICS_PER_PAGE, page_number * TOPICS_PER_PAGE):
		var marks := []
		if post_data.pinned:
			marks.append("Sticky")
		if PilotNet.is_new(post_data.id):
			marks.append("New")
		if PilotNetSite.has_gig(post_data):
			marks.append("Gig")
		rows.append([NetUI.text(", ".join(marks), &"NetPortalMeta"),
				_rich(_link_code(PilotNet.fill_tags(post_data.title), PilotNetSite.post_url(post_data.id))),
				_author_link(post_data), str(PilotNet.visible_replies(post_data.id).size()),
				PilotNet.stamp(PilotNet.first_seen_day(post_data.id), PilotNet.post_time(post_data.id))])
	if rows.is_empty():
		rows.append(["", NetUI.text(PilotNetSite.NO_POSTS, &"NetPortalMeta"), "", "", ""])
	main.add_child(_table([{"title": "", "width": 90}, {"title": "Topic", "width": 0}, {"title": "Started by", "width": 140},
			{"title": "Replies", "width": 70, "align": "right"}, {"title": "Last post", "width": 160}], rows))
	_add_pages("/board/" + id, page_number, pages)
	if id == PilotNet.GIGS_BOARD:
		main.add_child(_link("See the gig board: open gigs, your gigs and their progress »", _url("/gigs")))


func _post(id: String, page_number: int) -> void:
	var post_data := PilotNet.get_post(id)
	if post_data.is_empty() or not PilotNet.is_post_visible(id):
		_not_found()
		return
	PilotNet.open_post(id)
	var board := PilotNet.get_board(str(post_data.board))
	var board_name := str(board.get("name", post_data.board))
	_section = PilotNetSite.section_of(str(post_data.board))
	var title := PilotNet.fill_tags(post_data.title)
	page_title = "%s - %s" % [DOMAIN, title]
	main.add_child(_trail([["Forums", _url("/forums")], [board_name, _url("/board/" + str(post_data.board))], [title, ""]]))
	main.add_child(_title(title))
	var replies := PilotNet.visible_replies(id)
	var pages := maxi(ceili(replies.size() / float(REPLIES_PER_PAGE)), 1)
	page_number = mini(page_number, pages)
	main.add_child(NetUI.text("%d repl%s · Page %d of %d" % [replies.size(), "y" if replies.size() == 1 else "ies", page_number, pages],
			&"NetPortalMeta"))
	var day := PilotNet.first_seen_day(id)
	if page_number == 1:
		var offer := _offer_box(id, post_data)
		main.add_child(_message(PilotNet.author_name(post_data), post_data, 1, day, PilotNet.post_time(id),
				PilotNet.fill_tags(post_data.body), [offer] if offer != null else []))
	var start := (page_number - 1) * REPLIES_PER_PAGE
	for i in range(start, mini(start + REPLIES_PER_PAGE, replies.size())):
		var reply_data: Dictionary = replies[i]
		main.add_child(_message(PilotNetSite.author_of(reply_data), reply_data, i + 2, day, PilotNetSite.reply_time(id, i),
				PilotNet.fill_tags(str(reply_data.get("body", ""))), []))
	_add_pages("/post/" + id, page_number, pages)
	main.add_child(_link("« Back to %s" % board_name, _url("/board/" + str(post_data.board))))


# A post or reply: the author's panel (callsign, avatar, rank, posts, last
# seen) beside the message (time, number, text, then extra controls).
func _message(author: String, entry: Dictionary, number: int, day: int, time: String, text: String, extra: Array) -> PanelContainer:
	var row := NetUI.hbox(&"NetZeroRow")
	var side := NetUI.vbox(&"NetPortalTight")
	side.add_child(_author_link(entry))
	side.add_child(PilotAvatar.new(author, 8))
	side.add_child(NetUI.text(PilotNetSite.rank(author), &"NetPortalMeta"))
	side.add_child(NetUI.text("Posts: %d" % PilotNet.post_count(author), &"NetPortalMeta"))
	if PilotNet.is_met(author):
		side.add_child(NetUI.text("Seen: %s" % PilotNet.long_date(PilotNet.last_seen(author)), &"NetPortalMeta"))
	var panel := NetUI.panel(&"NetPortalAuthor", side)
	panel.custom_minimum_size.x = AUTHOR_WIDTH
	row.add_child(panel)
	var content := NetUI.vbox(&"NetPortalStack")
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := NetUI.hbox(&"NetPortalToolbar")
	var stamp := NetUI.text(PilotNet.stamp(day, time), &"NetPortalMeta")
	stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(stamp)
	head.add_child(NetUI.text("#%d" % number, &"NetPortalMeta"))
	content.add_child(head)
	content.add_child(_rule())
	content.add_child(_rich(esc(text)))
	for control in extra:
		content.add_child(control)
	var body := NetUI.panel(&"NetPortalBody", content)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	var box := NetUI.panel(&"NetPortalBox", row)
	box.set_meta("message", number)
	return box


# The gig a post offers, as a box: the gig with Accept, the gig taken from it,
# or its template's terms with Accept; null for none.
func _offer_box(id: String, post_data: Dictionary) -> Control:
	var offer := PilotNetSite.gig_offer(id, post_data)
	if offer.is_empty():
		return null
	var body := NetUI.vbox(&"NetPortalTight")
	if offer.kind == "offer":
		body.add_child(NetUI.text(PilotNetSite.offer_title(offer.template), &"NetPortalLabel", true))
		body.add_child(NetUI.text(PilotNetSite.offer_terms(offer.template), &"NetPortalText", true))
		body.add_child(_accept_row(PilotNetSite.ACCEPT_POST, id))
		return _widget("GIG OFFER", body)
	var gig: Dictionary = offer.gig
	body.add_child(NetUI.text(str(gig.title), &"NetPortalLabel", true))
	body.add_child(NetUI.text(PilotNetSite.gig_terms(gig), &"NetPortalText", true))
	if offer.kind == "gig" and gig.state == "open":
		body.add_child(_accept_row(PilotNetSite.ACCEPT, str(gig.id)))
	elif gig.state == "active":
		var row := NetUI.hbox(&"NetPortalToolbar")
		row.add_child(NetUI.text("ACCEPTED: %s" % PilotNet.progress_text(gig), &"NetPortalLabel"))
		row.add_child(_link("Your gigs »", _url("/gigs")))
		body.add_child(row)
	elif gig.state == "complete":
		body.add_child(NetUI.text("COMPLETE: paid when you are next home", &"NetPortalLabel"))
	return _widget("GIG", body)


# Accept, or Accept greyed out with the reason it can't be pressed.
func _accept_row(action_name: String, target: String) -> HBoxContainer:
	var row := NetUI.hbox(&"NetPortalToolbar")
	var button := _action_button("Accept", action_name, target)
	var reason := PilotNet.accept_block_reason()
	if reason != "":
		button.disabled = true
		row.add_child(button)
		row.add_child(NetUI.text(reason, &"NetPortalMeta"))
	else:
		row.add_child(button)
	return row


# ---- gigs -------------------------------------------------------------------------

func _gigs() -> void:
	_section = "GIGS"
	page_title = "%s - Gigs" % DOMAIN
	main.add_child(_trail([["Gigs", ""]]))
	main.add_child(_title("Gig board"))
	var active := PilotNet.active_gigs()
	main.add_child(NetUI.text("Accepted %d/%d · Completed %d" % [active.size(), PilotNet.MAX_ACTIVE_GIGS, PilotNet.gigs_completed],
			&"NetPortalMeta"))
	var gigs_open := PilotNet.open_gigs()
	var reason := PilotNet.accept_block_reason()
	var head := NetUI.hbox(&"NetPortalToolbar")
	head.add_child(NetUI.text("Open gigs (%d)" % gigs_open.size(), &"NetPortalSection"))
	if reason != "":
		head.add_child(NetUI.text(reason, &"NetPortalMeta"))
	main.add_child(head)
	if gigs_open.is_empty():
		main.add_child(NetUI.text(PilotNetSite.NO_POSTS, &"NetPortalMeta"))
	else:
		var rows := []
		for gig in gigs_open:
			var button := _action_button("Accept", PilotNetSite.ACCEPT, str(gig.id))
			button.disabled = reason != ""
			rows.append([_rich(_link_code(str(gig.title), PilotNetSite.post_url("gig:" + str(gig.id)))),
					"%s CT" % BbsText.thousands(int(gig.reward)), "+%d" % int(gig.reputation), str(gig.poster),
					PilotNetSite.expires_text(gig), button])
		main.add_child(_table([{"title": "Gig", "width": 0}, {"title": "Reward", "width": 90, "align": "right"},
				{"title": "Rep", "width": 50, "align": "right"}, {"title": "Posted by", "width": 120},
				{"title": "Expires", "width": 80}, {"title": "", "width": 100}], rows))
	main.add_child(NetUI.text("Your gigs (%d/%d)" % [active.size(), PilotNet.MAX_ACTIVE_GIGS], &"NetPortalSection"))
	if active.is_empty():
		main.add_child(NetUI.text("None. Accept a gig above.", &"NetPortalMeta"))
	else:
		var rows := []
		for gig in active:
			var progress := NetUI.hbox(&"NetPortalToolbar")
			var bar := ProgressBar.new()
			bar.theme_type_variation = &"NetPortalProgress"
			bar.show_percentage = false
			bar.max_value = maxi(int(gig.count), 1)
			bar.value = int(gig.progress)
			bar.custom_minimum_size = Vector2(100, 14)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			progress.add_child(bar)
			progress.add_child(NetUI.text(PilotNet.progress_text(gig), &"NetPortalText"))
			var run := PilotNet.run_progress(str(gig.id))
			rows.append([NetUI.text(str(gig.title), &"NetPortalLabel", true), progress, "+%d (unbanked)" % run if run > 0 else "",
					_action_button("Abandon", PilotNetSite.ABANDON, str(gig.id))])
		main.add_child(_table([{"title": "Gig", "width": 0}, {"title": "Progress", "width": 260},
				{"title": "This run", "width": 110}, {"title": "", "width": 100}], rows))
	main.add_child(NetUI.text("Complete: paid when you are next home", &"NetPortalSection"))
	var complete := PilotNet.complete_gigs()
	if complete.is_empty():
		main.add_child(NetUI.text("None.", &"NetPortalMeta"))
	else:
		var rows := []
		for gig in complete:
			rows.append([str(gig.title), "%s CT" % BbsText.thousands(int(gig.reward))])
		main.add_child(_table([{"title": "Gig", "width": 0}, {"title": "Reward", "width": 110, "align": "right"}], rows))
	main.add_child(NetUI.text("Kills and cargo count when you extract. Lost runs count for nothing.", &"NetPortalMeta"))


# ---- pilots -----------------------------------------------------------------------

func _pilots(letter: String) -> void:
	_section = "PILOTS"
	page_title = "%s - Pilots" % DOMAIN
	main.add_child(_trail([["Pilots", ""]]))
	main.add_child(_title("Pilot directory"))
	var letters := NetUI.hbox(&"NetPortalToolbar")
	for code in range(65, 91):
		var l := String.chr(code)
		letters.add_child((NetUI.text(l, &"NetPortalLabel") as Control) if l == letter else _link(l, _url("/pilots", {"l": l})))
	letters.add_child((NetUI.text("All", &"NetPortalLabel") as Control) if letter == "" else _link("All", _url("/pilots")))
	main.add_child(letters)
	var listed := PilotNetSite.directory(letter)
	var rows := []
	for callsign in listed:
		var profile := PilotNet.pilot_profile(callsign)
		rows.append([_link(callsign, PilotNetSite.pilot_url(callsign)), str(profile.get("affiliation", "-")) if not profile.is_empty() else "-",
				str(PilotNet.post_count(callsign)), PilotNet.long_date(PilotNet.last_seen(callsign)) if PilotNet.is_met(callsign) else "-"])
	if rows.is_empty():
		rows.append([NetUI.text(PilotNetSite.NO_POSTS, &"NetPortalMeta"), "", "", ""])
	main.add_child(_table([{"title": "Callsign", "width": 200}, {"title": "Affiliation", "width": 0},
			{"title": "Posts", "width": 70, "align": "right"}, {"title": "Last seen", "width": 120}], rows))
	main.add_child(NetUI.text("%d pilot%s: profiles and the pilots you have met in the field" % [listed.size(),
			"" if listed.size() == 1 else "s"], &"NetPortalMeta"))


func _pilot(callsign: String) -> void:
	_section = "PILOTS"
	page_title = "%s - %s" % [DOMAIN, callsign]
	var me := PlayerProgress.get_callsign()
	if callsign.to_lower() == me.to_lower():
		main.add_child(_trail([["Pilots", _url("/pilots")], [me, ""]]))
		main.add_child(_profile_head(me, ["YOUR PROFILE", "Reputation: %d" % PlayerProgress.get_reputation(),
				"Gigs completed: %d" % PilotNet.gigs_completed, "Posts: %d" % PilotNet.post_count(me)]))
		_posts_table(me)
		return
	var profile := PilotNet.pilot_profile(callsign)
	if profile.is_empty() and not PilotNet.is_met(callsign):
		main.add_child(_title("No pilot by that callsign"))
		main.add_child(_link("Back to the directory", _url("/pilots")))
		return
	var shown: String = profile.get("callsign", callsign)
	main.add_child(_trail([["Pilots", _url("/pilots")], [shown, ""]]))
	var lines := []
	if profile.has("affiliation"):
		lines.append(str(profile.affiliation))
	lines.append("Rank: %s · Posts: %d" % [PilotNetSite.rank(shown), PilotNet.post_count(shown)])
	if PilotNet.is_met(shown):
		lines.append("Last seen: %s" % PilotNet.long_date(PilotNet.last_seen(shown)))
	var lost := PilotNetSite.memorial_record(shown)
	var lost_line: Control = null
	if not lost.is_empty():
		lost_line = _rich("%s — %s" % [esc(PilotNetSite.lost_text(lost)), _link_code(PilotNetSite.MEMORIAL_NAME,
				NetSites.memorial_record_url(int(lost.id)))])
	main.add_child(_profile_head(shown, lines, lost_line))
	main.add_child(NetUI.text("Bio", &"NetPortalSection"))
	main.add_child(_rich(esc(PilotNet.fill_tags(str(profile.get("bio", "")))) if not profile.is_empty() else esc("No profile on file.")))
	var build := PilotNet.known_build(shown)
	if not build.is_empty():
		main.add_child(NetUI.text("Known build", &"NetPortalSection"))
		var rows := []
		for entry in build:
			var part_type: String = entry[1]
			var part_id: String = entry[2]
			rows.append([str(entry[0]), _link(Store.part_name(part_type, part_id), NetSites.wiki_url(part_id)),
					Manufacturers.display_name(Store.maker_of(part_type, part_id))])
		main.add_child(_table([{"title": "Slot", "width": 140}, {"title": "Part", "width": 0}, {"title": "Maker", "width": 280}], rows))
	if str(profile.get("steelapedia", "")) != "":
		main.add_child(_link("Read about %s on Steelapedia »" % shown, NetSites.wiki_url(str(profile.steelapedia))))
	_posts_table(shown)


func _profile_head(callsign: String, lines: Array, extra: Control = null) -> PanelContainer:
	var row := NetUI.hbox(&"NetPortalColumns")
	row.add_child(PilotAvatar.new(callsign, 12))
	var words := NetUI.vbox(&"NetPortalTight")
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(NetUI.text(callsign, &"NetPortalTitle", true))
	for line in lines:
		words.add_child(NetUI.text(str(line), &"NetPortalText", true))
	if extra != null:
		words.add_child(extra)
	row.add_child(words)
	return NetUI.panel(&"NetPortalBox", row)


func _posts_table(callsign: String) -> void:
	main.add_child(NetUI.text("Posts", &"NetPortalSection"))
	var posts := PilotNet.posts_by(callsign)
	if posts.is_empty():
		main.add_child(NetUI.text(PilotNetSite.NO_POSTS, &"NetPortalMeta"))
		return
	var rows := []
	for post_data in posts:
		rows.append([PilotNet.long_date(PilotNet.first_seen_day(post_data.id)),
				_rich(_link_code(PilotNet.fill_tags(post_data.title), PilotNetSite.post_url(post_data.id))),
				str(PilotNet.get_board(str(post_data.board)).get("name", post_data.board))])
	main.add_child(_table([{"title": "Date", "width": 110}, {"title": "Topic", "width": 0}, {"title": "Forum", "width": 220}], rows))


# ---- search -----------------------------------------------------------------------

func _search(text: String) -> void:
	page_title = "%s - Search" % DOMAIN
	main.add_child(_title("Search the NET"))
	var wanted := text.strip_edges()
	if wanted == "":
		main.add_child(NetUI.text("Type what you are looking for in the box above.", &"NetPortalMeta"))
		return
	main.add_child(NetUI.text("Results for \"%s\"" % wanted, &"NetPortalMeta", true))
	var found := PilotNet.search(wanted)
	var results := []
	for post_data in found.slice(0, SEARCH_COUNT):
		var board := PilotNet.get_board(str(post_data.board))
		results.append([PilotNet.fill_tags(post_data.title), PilotNetSite.post_url(post_data.id),
				"%s · by %s · %s" % [str(board.get("name", post_data.board)), PilotNet.author_name(post_data),
				PilotNet.long_date(PilotNet.first_seen_day(post_data.id))]])
	main.add_child(_results("pilot.net: %d post%s found" % [found.size(), "" if found.size() == 1 else "s"], results, found.size(), []))
	var pilots := PilotNetSite.directory("").filter(func(c): return wanted.to_lower() in str(c).to_lower())
	if not pilots.is_empty():
		results = []
		for callsign in pilots.slice(0, SEARCH_COUNT):
			results.append([callsign, PilotNetSite.pilot_url(callsign), str(PilotNet.pilot_profile(callsign).get("affiliation", ""))])
		main.add_child(_results("Pilots: %d" % pilots.size(), results, pilots.size(), []))
	var articles := Steelapedia.search(wanted)
	results = []
	for entry in articles.slice(0, SEARCH_COUNT):
		results.append([str(entry.title), NetSites.wiki_url(entry.slug), str(entry.summary)])
	main.add_child(_results("Steelapedia: %d article%s" % [articles.size(), "" if articles.size() == 1 else "s"], results, articles.size(),
			["Search Steelapedia for \"%s\"" % wanted, NetSites.make_url(NetSites.STEELAPEDIA_DOMAIN, "/search", {"q": wanted, "fulltext": "1"})]))
	var parts := Store.search(wanted)
	results = []
	for entry in parts.slice(0, SEARCH_COUNT):
		results.append([Store.part_name(entry[0], entry[1]), NetSites.product_url(entry[0], entry[1]),
				"%s by %s · %s CT" % [Store.type_name(entry[0]), Manufacturers.short_name(Store.maker_of(entry[0], entry[1])),
				BbsText.thousands(Store.price(entry[0], entry[1]))]])
	main.add_child(_results("amazing.com: %d part%s" % [parts.size(), "" if parts.size() == 1 else "s"], results, parts.size(),
			["Search amazing.com for \"%s\"" % wanted, NetSites.search_url(wanted)]))
	var quotes := FourX.search(wanted)
	results = []
	for entry in quotes.slice(0, SEARCH_COUNT):
		var quote := FourX.quote(entry.symbol)
		results.append(["%s · %s" % [entry.symbol, entry.name], NetSites.quote_url(entry.symbol),
				"%s (%s)" % [FourX.format_price(float(quote.last)), FourX.format_pct(float(quote.change_pct))]])
	main.add_child(_results("FourX.net: %d quote%s" % [quotes.size(), "" if quotes.size() == 1 else "s"], results, quotes.size(),
			["Look up \"%s\" on FourX.net" % wanted, NetSites.fourx_url("/search", {"q": wanted})]))


# One site's results: a heading, then each result's title (a link), its
# line of detail and its address; "... and n more"; a link to search more.
func _results(heading: String, results: Array, total: int, more: Array) -> VBoxContainer:
	var column := NetUI.vbox(&"NetPortalTight")
	column.add_child(NetUI.text(heading, &"NetPortalSection"))
	if results.is_empty():
		column.add_child(NetUI.text("No results.", &"NetPortalMeta"))
	for entry in results:
		column.add_child(_rich("[b]%s[/b]\n%s\n%s" % [_link_code(str(entry[0]), str(entry[1])), esc(str(entry[2])),
				_meta_code(NetSites.display(str(entry[1])))]))
	if total > results.size():
		column.add_child(NetUI.text("... and %d more" % (total - results.size()), &"NetPortalMeta"))
	if not more.is_empty():
		column.add_child(_link("%s »" % more[0], str(more[1])))
	return column


func _not_found() -> void:
	page_title = "%s - Not found" % DOMAIN
	main.add_child(_title(NOT_FOUND))
	main.add_child(NetUI.text("The page may have moved, or the address may be wrong.", &"NetPortalText", true))
	main.add_child(_link("Go to the pilot.net home page", _url("/")))


# ---- the frame --------------------------------------------------------------------

func _build(search_text: String) -> void:
	var page := NetUI.panel(&"NetPortalPage")
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)
	var column := NetUI.vbox(&"NetZeroStack")
	page.add_child(column)
	column.add_child(_strip())
	column.add_child(_band(search_text))
	var body := NetUI.panel(&"NetPortalBody", main)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	column.add_child(_footer())


# The top strip: the notice on the left; who is logged in on the right.
func _strip() -> PanelContainer:
	var row := NetUI.hbox(&"NetPortalToolbar")
	var notice := NetUI.text(PilotNet.look_notice(), &"NetPortalLabel")
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(notice)
	var me := PlayerProgress.get_callsign()
	row.add_child(NetUI.text("Logged in as", &"NetPortalText"))
	row.add_child(_link(me.to_upper(), PilotNetSite.pilot_url(me)))
	row.add_child(NetUI.text("· %s · %d unread · %s CT" % [PilotNet.date_text(PilotNet.day), PilotNet.unread_count(),
			BbsText.thousands(int(PlayerProgress.get_money()))], &"NetPortalText"))
	return NetUI.panel(&"NetPortalStrip", row)


# The header band: the wordmark and emblem, then the section tabs over Search
# the NET.
func _band(search_text: String) -> PanelContainer:
	var row := NetUI.hbox(&"NetPortalColumns")
	var logo := NetUI.hbox(&"NetPortalToolbar")
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wordmark := NetUI.text("pilot.net", &"NetPortalLogo")
	logo.add_child(wordmark)
	logo.add_child(PilotNetLogo.new())
	logo.custom_minimum_size.x = LEFT_WIDTH
	row.add_child(logo)
	var right := NetUI.vbox(&"NetPortalTight")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tabs := NetUI.hbox(&"NetPortalToolbar")
	tabs.add_child(NetUI.text("Go to:", &"NetPortalBandText"))
	for tab in TABS:
		var button := MechUI.button(str(tab[0]), &"NetPortalTabActive" if tab[2] == _section else &"NetPortalTab")
		var target := _url(str(tab[1]))
		button.set_meta("url", target)
		button.pressed.connect(follow.bind(target))
		button.mouse_entered.connect(hover.bind(target))
		button.mouse_exited.connect(hover.bind(""))
		tabs.add_child(button)
	right.add_child(tabs)
	var search := NetUI.hbox(&"NetPortalToolbar")
	search.add_child(NetUI.text("Search the NET:", &"NetPortalBandText"))
	search_field = NetUI.input("posts, pilots, articles, parts, quotes")
	search_field.theme_type_variation = &"NetPortalInput"
	search_field.text = search_text
	search_field.context_menu_enabled = false
	search_field.custom_minimum_size.x = 360
	search_field.text_submitted.connect(_submit_search)
	search.add_child(search_field)
	var go := NetUI.button("Search")
	go.pressed.connect(func(): _submit_search(search_field.text))
	search.add_child(go)
	right.add_child(search)
	row.add_child(right)
	return NetUI.panel(&"NetPortalBand", row)


func _footer() -> PanelContainer:
	var column := NetUI.vbox(&"NetPortalTight")
	var links := NetUI.hbox(&"NetPortalToolbar")
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	var all := FOOTER_LINKS.map(func(e): return [e[0], _url(e[1])]) + [["Steelapedia", "steelapedia.net"],
			["amazing.com", "amazing.com"], ["FourX.net", "fourx.net"]]
	for i in all.size():
		if i > 0:
			links.add_child(NetUI.text("|", &"NetPortalMeta"))
		links.add_child(_link(str(all[i][0]), str(all[i][1])))
	column.add_child(links)
	var small := NetUI.text(SMALL_PRINT, &"NetPortalMeta")
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(small)
	return NetUI.panel(&"NetPortalFooter", column)


func _submit_search(value: String) -> void:
	if value.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	follow(_url("/search", {"q": value.strip_edges()}))


# ---- pieces -----------------------------------------------------------------------

func _url(page_path: String, page_query := {}) -> String:
	return PilotNetSite.url(page_path, page_query)


# A box with a dark bar holding title over body.
func _widget(title: String, body: Control) -> VBoxContainer:
	var column := NetUI.vbox(&"NetZeroStack")
	column.add_child(NetUI.panel(&"NetPortalBar", NetUI.text(title, &"NetPortalBarText")))
	column.add_child(NetUI.panel(&"NetPortalBox", body))
	return column


# A titled list for the front page's middle: a heading, the rows, a link to
# the rest.
func _list(title: String, rows: Array, more: Array) -> VBoxContainer:
	var column := NetUI.vbox(&"NetPortalTight")
	column.add_child(NetUI.text(title, &"NetPortalSection"))
	column.add_child(_rule())
	if rows.is_empty():
		column.add_child(NetUI.text(PilotNetSite.NO_POSTS, &"NetPortalMeta"))
	for row in rows:
		column.add_child(row)
	column.add_child(_link("%s »" % more[0], str(more[1])))
	return column


# "• title (a link)  meta", with "NEW" when it's unread.
func _bullet(text: String, url: String, meta := "", fresh := false) -> RichTextLabel:
	var code := "• " + _link_code(text, url)
	if meta != "":
		code += "  " + _meta_code(meta)
	if fresh:
		code += "  [b]NEW[/b]"
	return _rich(code)


func _pill(label: String, url: String) -> Button:
	var button := MechUI.button(label, &"NetPortalPill")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("url", url)
	button.pressed.connect(follow.bind(url))
	button.mouse_entered.connect(hover.bind(url))
	button.mouse_exited.connect(hover.bind(""))
	return button


# A bevelled button that runs a gig action and loads the page again.
func _action_button(label: String, action_name: String, target: String) -> Button:
	var button := NetUI.button(label)
	button.set_meta("action", "%s:%s" % [action_name, target])
	button.pressed.connect(_act.bind(action_name, target))
	return button


func _act(action_name: String, target: String) -> void:
	PilotNetSite.act(action_name, target)
	follow(NetSites.make_url(domain, path, query))


func _author_link(entry: Dictionary) -> Control:
	var author := PilotNetSite.author_of(entry)
	if PilotNetSite.is_known(author):
		return _link(author, PilotNetSite.pilot_url(author))
	return NetUI.text(author, &"NetPortalLabel")


# "pilot.net » Forums » GENERAL CHATTER": [label, url] steps, the last (url
# "") the page itself.
func _trail(steps: Array) -> HBoxContainer:
	var row := NetUI.hbox(&"NetPortalToolbar")
	row.add_child(_link("pilot.net", _url("/")))
	for step in steps:
		row.add_child(NetUI.text("»", &"NetPortalMeta"))
		if str(step[1]) != "":
			row.add_child(_link(str(step[0]), str(step[1])))
		else:
			var here := NetUI.text(BbsText.cut(str(step[0]), 70), &"NetPortalLabel")
			row.add_child(here)
	return row


func _add_pages(page_path: String, page_number: int, pages: int) -> void:
	if pages <= 1:
		return
	var row := NetUI.hbox(&"NetPortalToolbar")
	row.add_child(NetUI.text("Pages:", &"NetPortalMeta"))
	if page_number > 1:
		row.add_child(_link("« Prev", _url(page_path, {"page": str(page_number - 1)})))
	for number in range(1, pages + 1):
		row.add_child((NetUI.text(str(number), &"NetPortalLabel") as Control) if number == page_number
				else _link(str(number), _url(page_path, {"page": str(number)})))
	if page_number < pages:
		row.add_child(_link("Next »", _url(page_path, {"page": str(page_number + 1)})))
	main.add_child(row)
