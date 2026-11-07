class_name PilotNetPage
extends NetPage

## pilot.net, the independent pilots' exchange and the NET's home page, in
## its first look (PilotNet.look() "bbs"; PilotNetPortalPage is the other): a
## text-mode board, black with VT323, laid out like a web portal and forum
## in ASCII (BbsText). What it shows comes from PilotNetSite. Paths:
##   /                   the front page: channels on the left; the top story,
##                       the news, the forums and the gig board in the middle;
##                       your pilot, FourX markets, amazing.com deals, world
##                       status and Steelapedia's featured article on the
##                       right; who's online under them
##   /forums  /boards    the forum index: each board's topics, posts and last
##                       post, who's online and the statistics
##   /board/<id>?page=   a board's topics, pinned first, then newest
##   /post/<id>?page=    a topic: the post and its replies as cards (avatar,
##                       rank, posts). Opening it marks it read and runs its
##                       on_read; a gig post offers the gig
##   /gigs               the gig board: open gigs, your gigs with progress
##                       bars, complete gigs waiting for pay
##   /pilots?l=<letter>  the pilot directory
##   /pilot/<callsign>   a pilot's profile (the player's own too)
##   /search?q=          the NET search: pilot.net posts and pilots,
##                       Steelapedia articles, amazing.com parts, FourX quotes
## The page is a header screen, the search row and a body screen. Links are
## [url=<address>]; the gig buttons are [url=do:<action>:<id>], which act and
## load the page again. The open section in the nav is the one inverted block.

const DOMAIN := "pilot.net"
const BANNER := "PILOT.NET"
const TAGLINE := "-- the independent pilots' exchange"
## The layout's width in characters (VT323 at 25 px is 10 px a character).
const WIDTH := 108
const CHAR_WIDTH := 10
## The front page's columns, with GAP between them.
const HOME_COLUMNS := [22, 50, 32]
const GAP := 2
const BANNER_SIZE := 50
const NAV := [["1", "HOME", "/"], ["2", "NEWS", "/board/news"], ["3", "GIGS", "/gigs"],
		["4", "FORUMS", "/forums"], ["5", "PILOTS", "/pilots"]]
const OFFSITE := [["6", "STEELAPEDIA", "steelapedia.net"], ["7", "FOURX.NET", "fourx.net"],
		["8", "AMAZING.COM", "amazing.com"]]
const TOPICS_PER_PAGE := 20
const REPLIES_PER_PAGE := 10
const NEWS_COUNT := 5
const FORUM_COUNT := 4
const GIG_COUNT := 4
const DEAL_COUNT := 4
const MOVER_COUNT := 3
const TEASER_LINES := 5
const SEARCH_COUNT := 8
const NO_POSTS := PilotNetSite.NO_POSTS
const BULLET := "» "
## A post card: the author column and the message column.
const CARD_LEFT := 16
const CARD_RIGHT := WIDTH - CARD_LEFT - 7
## A pilot's avatar: one line of each, picked by the callsign.
const AVATAR_TOPS := [".---.", "/^^^\\", "[===]", ".-^-.", "_____", "/---\\"]
const AVATAR_EYES := ["|o o|", "|O O|", "|- -|", "|0 0|", "[x x]", "|^ ^|", "(o o)", "|@ @|", "|> <|", "|. .|"]
const AVATAR_MOUTHS := ["'-=-'", "\\_-_/", "'---'", "|___|", "`-v-'", "\\===/", "'-o-'"]

## The body screen and the header screen.
var screen: RichTextLabel
var header: RichTextLabel
var search_field: LineEdit = null
var _lines: Array = []
var _section := ""


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	var segments := Array(page_path.split("/", false))
	var first: String = str(segments[0]).to_lower() if not segments.is_empty() else ""
	var page_number := maxi(int(str(page_query.get("page", "1"))), 1)
	page_title = DOMAIN
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


## The page's text without BBCode (tests).
func get_text() -> String:
	if screen == null:
		return ""
	return header.get_parsed_text() + "\n" + screen.get_parsed_text()


## The page's BBCode (tests).
func get_code() -> String:
	return header.text + "\n" + screen.text if screen != null else ""


## Every address and action the page links to (tests).
func get_links() -> Array:
	var regex := RegEx.create_from_string("\\[url=([^\\]]+)\\]")
	return regex.search_all(get_code()).map(func(m): return m.get_string(1))


## Follows a link the way a click does: an address loads, an action acts.
func click(meta: String) -> void:
	_on_meta_clicked(meta)


# ---- the front page -------------------------------------------------------------

func _home() -> void:
	_section = "HOME"
	page_title = "%s - Home" % DOMAIN
	_add_all(BbsText.beside([_channels(), _front_middle(), _front_right()], HOME_COLUMNS, GAP))
	_add(BbsText.Seg.new())
	_add_all(_online_lines())


# The channels on the left: plain link lists under headings.
func _channels() -> Array:
	var width: int = HOME_COLUMNS[0]
	var wiki := NetSites.STEELAPEDIA_DOMAIN
	var money := [["FourX.net", NetSites.fourx_url()]]
	for group in FourX.groups():
		if group.id != FourX.INDEX_GROUP:
			money.append([str(group.name).capitalize(), NetSites.fourx_url("/group/" + str(group.id))])
	var channels := [
		["PILOT.NET", [["News", _url("/board/news")], ["Gigs (%d open)" % PilotNet.open_gigs().size(), _url("/gigs")],
				["Forums", _url("/forums")], ["Pilot directory", _url("/pilots")],
				["Your profile", _pilot_url(PlayerProgress.get_callsign())]]],
		["LOOK IT UP", [["Steelapedia", NetSites.make_url(wiki)], ["Random article", NetSites.make_url(wiki, "/special/random")],
				["Parts", NetSites.make_url(wiki, "/category/parts")],
				["Manufacturers", NetSites.make_url(wiki, "/category/manufacturers")],
				["Entities", NetSites.make_url(wiki, "/category/entities")]]],
		["SHOPPING", [["amazing.com", NetSites.store_url()], ["Hardware", NetSites.store_url("/hardware")],
				["Wetware", NetSites.store_url("/wetware")], ["Weapons", NetSites.store_url("/weapons")],
				["Makers A-Z", NetSites.store_url("/makers")], ["Your cart (%d)" % Store.cart_count(), NetSites.store_url("/cart")]]],
		["MONEY", money],
	]
	var lines := []
	for i in channels.size():
		if i > 0:
			lines.append(BbsText.Seg.new())
		lines.append(BbsText.bright(channels[i][0]))
		lines.append(BbsText.rule(width))
		for entry in channels[i][1]:
			lines.append(BbsText.join([BbsText.dim(BULLET), BbsText.cell(str(entry[0]), width - BULLET.length(), "", str(entry[1]))]))
	return lines


func _front_middle() -> Array:
	var width: int = HOME_COLUMNS[1]
	var inner := width - 4
	var lines := [BbsText.spread(BbsText.bright("FRONT PAGE"), BbsText.dim("Day %d" % PilotNet.day), width), BbsText.Seg.new()]
	var top := PilotNetSite.top_story()
	var story := []
	if top.is_empty():
		story.append(BbsText.dim(NO_POSTS))
	else:
		for line in BbsText.wrap(PilotNet.fill_tags(top.title), inner):
			story.append(BbsText.link(line, _post_url(top.id)))
		story.append(BbsText.dim(BbsText.cut("by %s · Day %d %s" % [PilotNet.author_name(top),
				PilotNet.first_seen_day(top.id), PilotNet.post_time(top.id)], inner)))
		story.append(BbsText.Seg.new())
		var body := BbsText.wrap(PilotNet.fill_tags(top.body), inner)
		for line in body.slice(0, TEASER_LINES):
			story.append(BbsText.plain(line))
		if body.size() > TEASER_LINES:
			story.append(BbsText.dim("..."))
		story.append(BbsText.link("Full story »", _post_url(top.id)))
	lines.append_array(BbsText.box("TOP STORY", width, story))
	lines.append(BbsText.Seg.new())

	var headlines := []
	for post_data in PilotNetSite.headlines(NEWS_COUNT):
		headlines.append(_headline(post_data, inner))
	if headlines.is_empty():
		headlines.append(BbsText.dim(NO_POSTS))
	headlines.append(BbsText.link("All news »", _url("/board/news")))
	lines.append_array(BbsText.box("NEWS", width, headlines))
	lines.append(BbsText.Seg.new())

	var topics := []
	for post_data in PilotNetSite.hot_topics(FORUM_COUNT):
		var replies := PilotNet.visible_replies(post_data.id).size()
		var count := " (%d)" % replies
		topics.append(BbsText.join([BbsText.dim("* " if PilotNet.is_new(post_data.id) else "· "),
				BbsText.cell(PilotNet.fill_tags(post_data.title), inner - 2 - count.length(), "", _post_url(post_data.id)),
				BbsText.dim(count)]))
		var board := PilotNet.get_board(str(post_data.board))
		topics.append(BbsText.dim(BbsText.cut("  in %s · by %s" % [str(board.get("name", post_data.board)),
				PilotNet.author_name(post_data)], inner)))
	if topics.is_empty():
		topics.append(BbsText.dim(NO_POSTS))
	topics.append(BbsText.link("All forums »", _url("/forums")))
	lines.append_array(BbsText.box("HOT IN THE FORUMS", width, topics))
	lines.append(BbsText.Seg.new())

	var open := PilotNet.open_gigs()
	var gig_lines := []
	for gig in open.slice(0, GIG_COUNT):
		gig_lines.append(BbsText.join([BbsText.cell(str(gig.title), inner - 10, "", _post_url("gig:" + str(gig.id))),
				BbsText.cell("%s CT" % BbsText.thousands(int(gig.reward)), 10, "bright", "", "right")]))
	if open.is_empty():
		gig_lines.append(BbsText.dim(NO_POSTS))
	var counts := BbsText.dim("%d open · %d/%d yours" % [open.size(), PilotNet.active_gigs().size(), PilotNet.MAX_ACTIVE_GIGS])
	gig_lines.append(BbsText.spread(counts, BbsText.link("All gigs »", _url("/gigs")), inner))
	lines.append_array(BbsText.box("GIG BOARD", width, gig_lines))
	return lines


func _headline(post_data: Dictionary, width: int) -> BbsText.Seg:
	var stamp := " D%d" % PilotNet.first_seen_day(post_data.id)
	return BbsText.join([BbsText.dim("* " if PilotNet.is_new(post_data.id) else "· "),
			BbsText.cell(PilotNet.fill_tags(post_data.title), width - 2 - stamp.length(), "", _post_url(post_data.id)),
			BbsText.dim(stamp)])


func _front_right() -> Array:
	var width: int = HOME_COLUMNS[2]
	var inner := width - 4
	var lines := []
	var me := PlayerProgress.get_callsign()
	var pay := PilotNetSite.pay_waiting()
	lines.append_array(BbsText.box("MY PILOT", width, [
		BbsText.cell(me.to_upper(), inner, "", _pilot_url(me)),
		BbsText.pair("Balance", "%s CT" % BbsText.thousands(int(PlayerProgress.get_money())), inner),
		BbsText.pair("Reputation", str(PlayerProgress.get_reputation()), inner),
		BbsText.pair("Gigs", "%d/%d" % [PilotNet.active_gigs().size(), PilotNet.MAX_ACTIVE_GIGS], inner),
		BbsText.pair("Unread posts", str(PilotNet.unread_count()), inner),
		BbsText.pair("Pay waiting", "%s CT" % BbsText.thousands(pay), inner),
	]))
	lines.append(BbsText.Seg.new())

	var quotes := []
	for symbol in [FourX.COMPOSITE, FourX.SALVAGE_INDEX]:
		var shown := FourX.quote(symbol)
		if not shown.is_empty():
			quotes.append(_quote_row(shown, inner))
	var moves := FourX.movers(MOVER_COUNT)
	for shown in (moves.gainers as Array).slice(0, 2) + (moves.losers as Array).slice(0, 1):
		quotes.append(_quote_row(shown, inner))
	quotes.append(BbsText.dim(BbsText.cut("Day %d close · delayed" % FourX.day(), inner)))
	quotes.append(BbsText.link("More at FourX.net »", NetSites.fourx_url()))
	lines.append_array(BbsText.box("FOURX MARKETS", width, quotes))
	lines.append(BbsText.Seg.new())

	AmazingPage.ensure_picks()
	var deals := []
	for entry in AmazingPage.picks.slice(0, DEAL_COUNT):
		var price := "%s CT" % BbsText.thousands(Store.price(entry[0], entry[1]))
		deals.append(BbsText.join([BbsText.cell(Store.part_name(entry[0], entry[1]), inner - price.length() - 1, "",
				NetSites.product_url(entry[0], entry[1])), BbsText.space(1), BbsText.bright(price)]))
	if deals.is_empty():
		deals.append(BbsText.dim("Out of stock."))
	deals.append(BbsText.link("Shop amazing.com »", NetSites.store_url()))
	lines.append_array(BbsText.box("TOP DEALS ON AMAZING.COM", width, deals))
	lines.append(BbsText.Seg.new())

	var status := []
	for line in PilotNet.world_lines():
		status.append(BbsText.pair(str(line.label), str(line.text), inner))
	if not status.is_empty():
		lines.append_array(BbsText.box("WORLD STATUS", width, status))
		lines.append(BbsText.Seg.new())

	var featured = SteelapediaPage.featured()
	var wiki := []
	if featured == null:
		wiki.append(BbsText.dim("No articles yet."))
	else:
		wiki.append(BbsText.cell(str(featured.title), inner, "", NetSites.wiki_url(featured.slug)))
		for line in BbsText.wrap(str(featured.summary), inner).slice(0, 3):
			wiki.append(BbsText.dim(line))
		wiki.append(BbsText.link("Read more »", NetSites.wiki_url(featured.slug)))
	lines.append_array(BbsText.box("FROM STEELAPEDIA", width, wiki))
	return lines


func _quote_row(shown: Dictionary, width: int) -> BbsText.Seg:
	var pct := FourX.format_pct(float(shown.change_pct))
	return BbsText.join([BbsText.cell(str(shown.symbol), 5, "", NetSites.quote_url(str(shown.symbol))), BbsText.space(1),
			BbsText.cell(FourX.format_price(float(shown.last)), width - 15, "", "", "right"), BbsText.space(1),
			BbsText.cell(pct, 8, "bright" if float(shown.change_pct) >= 0.0 else "dim", "", "right")])


func _online_lines() -> Array:
	var names := PilotNetSite.online()
	var lines := [BbsText.rule(WIDTH), BbsText.join([BbsText.bright("WHO'S ONLINE"),
			BbsText.dim(" · %d pilots and %d guests" % [names.size(), PilotNetSite.guests()])])]
	for line in BbsText.wrap(", ".join(names), WIDTH):
		lines.append(BbsText.dim(line))
	return lines


# ---- forums -----------------------------------------------------------------------

func _forums() -> void:
	_section = "FORUMS"
	page_title = "%s - Forums" % DOMAIN
	_add(_crumbs([["Forums", ""]]))
	_add(BbsText.Seg.new())
	var columns := [{"title": "FORUM", "width": 53}, {"title": "TOPICS", "width": 6, "align": "right"},
			{"title": "POSTS", "width": 6, "align": "right"}, {"title": "LAST POST", "width": 30}]
	var rows := []
	for row in PilotNetSite.forum_rows():
		var board: Dictionary = row.board
		var last: Dictionary = row.last
		var name_line := BbsText.join([BbsText.dim("(*) " if row.unread else "( ) "),
				BbsText.cell(str(board.name), 49, "", _url("/board/" + str(board.id)))])
		var blurb_line := BbsText.join([BbsText.space(4), BbsText.cell(str(board.get("blurb", "")), 49, "dim")])
		var last_lines := [BbsText.dim("-")]
		if not last.is_empty():
			last_lines = [BbsText.cell("D%d %s by %s" % [PilotNet.first_seen_day(last.id), PilotNet.post_time(last.id),
					PilotNet.author_name(last)], 30, "dim"),
					BbsText.cell(PilotNet.fill_tags(last.title), 30, "", _post_url(last.id))]
		rows.append([[name_line, blurb_line], str(row.topics), str(row.posts), last_lines])
	_add_all(BbsText.table(columns, rows, true))
	_add(BbsText.dim("(*) new posts   ( ) no new posts"))
	_add(BbsText.Seg.new())
	var names := PilotNetSite.online()
	var online := [BbsText.dim("%d pilots and %d guests" % [names.size(), PilotNetSite.guests()])]
	for line in BbsText.wrap(", ".join(names), 49):
		online.append(BbsText.plain(line))
	var figures := PilotNetSite.stats()
	var stats := [BbsText.pair("Topics", str(figures.topics), 49), BbsText.pair("Posts", str(figures.posts), 49),
			BbsText.pair("Pilots", str(figures.pilots), 49), BbsText.pair("Newest pilot", str(figures.newest), 49)]
	_add_all(BbsText.beside([BbsText.box("WHO IS ONLINE", 53, online), BbsText.box("STATISTICS", 53, stats)], [53, 53], GAP))


func _board(id: String, page_number: int) -> void:
	var board := PilotNet.get_board(id)
	if board.is_empty() or not PilotNet.board_visible(id):
		_not_found()
		return
	_section = PilotNetSite.section_of(id)
	page_title = "%s - %s" % [DOMAIN, str(board.name)]
	_add(_crumbs([["Forums", _url("/forums")], [str(board.name), ""]]))
	_add(BbsText.Seg.new())
	var posts := PilotNet.visible_posts(id)
	var pages := maxi(ceili(posts.size() / float(TOPICS_PER_PAGE)), 1)
	page_number = mini(page_number, pages)
	_add(BbsText.spread(BbsText.bright(str(board.name)), BbsText.dim("%d topic%s · Page %d of %d" % [posts.size(),
			"" if posts.size() == 1 else "s", page_number, pages]), WIDTH))
	_add(BbsText.dim(BbsText.cut(str(board.get("blurb", "")), WIDTH)))
	var columns := [{"title": "", "width": 2}, {"title": "TOPIC", "width": 51}, {"title": "STARTED BY", "width": 16},
			{"title": "REPLIES", "width": 7, "align": "right"}, {"title": "LAST POST", "width": 16}]
	var rows := []
	for post_data in posts.slice((page_number - 1) * TOPICS_PER_PAGE, page_number * TOPICS_PER_PAGE):
		var mark := ("!" if post_data.pinned else " ") + ("*" if PilotNet.is_new(post_data.id)
				else ("$" if PilotNetSite.has_gig(post_data) else " "))
		rows.append([BbsText.dim(mark), BbsText.cell(PilotNet.fill_tags(post_data.title), 51, "", _post_url(post_data.id)),
				_author_cell(post_data, 16), str(PilotNet.visible_replies(post_data.id).size()),
				BbsText.cell("D%d %s" % [PilotNet.first_seen_day(post_data.id), PilotNet.post_time(post_data.id)], 16, "dim")])
	if rows.is_empty():
		rows.append(["", BbsText.cell(NO_POSTS, 51, "dim"), "", "", ""])
	_add_all(BbsText.table(columns, rows))
	_add(BbsText.dim("! sticky   * new   $ gig offered"))
	_add_pages("/board/" + id, page_number, pages)
	if id == PilotNet.GIGS_BOARD:
		_add(BbsText.Seg.new())
		_add(BbsText.link("[3] GIGS: the open gigs, your gigs and their progress", _url("/gigs")))


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
	_add(_crumbs([["Forums", _url("/forums")], [board_name, _url("/board/" + str(post_data.board))], [title, ""]]))
	_add(BbsText.Seg.new())
	var replies := PilotNet.visible_replies(id)
	var pages := maxi(ceili(replies.size() / float(REPLIES_PER_PAGE)), 1)
	page_number = mini(page_number, pages)
	var count := "%d repl%s · Page %d of %d" % [replies.size(), "y" if replies.size() == 1 else "ies", page_number, pages]
	_add(BbsText.spread(BbsText.bright(BbsText.cut(title, WIDTH - count.length() - 2)), BbsText.dim(count), WIDTH))
	_add(_card_edge())
	var day := PilotNet.first_seen_day(id)
	if page_number == 1:
		var message := []
		for line in BbsText.wrap(PilotNet.fill_tags(post_data.body), CARD_RIGHT):
			message.append(BbsText.plain(line))
		message.append_array(_gig_lines(id, post_data))
		_add_all(_card(PilotNet.author_name(post_data), post_data, 1, day, PilotNet.post_time(id), message))
	var start := (page_number - 1) * REPLIES_PER_PAGE
	for i in range(start, mini(start + REPLIES_PER_PAGE, replies.size())):
		var reply_data: Dictionary = replies[i]
		var message := []
		for line in BbsText.wrap(PilotNet.fill_tags(str(reply_data.get("body", ""))), CARD_RIGHT):
			message.append(BbsText.plain(line))
		_add_all(_card(PilotNetSite.author_of(reply_data), reply_data, i + 2, day, PilotNetSite.reply_time(id, i), message))
	_add_pages("/post/" + id, page_number, pages)
	_add(BbsText.Seg.new())
	_add(BbsText.link("« Back to %s" % board_name, _url("/board/" + str(post_data.board))))


# The gig a post offers, as a box under its text: the gig itself (a gig
# post), the gig taken from it, or its template's terms with Accept.
func _gig_lines(id: String, post_data: Dictionary) -> Array:
	var offer := PilotNetSite.gig_offer(id, post_data)
	if offer.is_empty():
		return []
	if offer.kind == "gig":
		return _gig_box(offer.gig, PilotNetSite.ACCEPT, str(offer.gig.id))
	if offer.kind == "taken":
		return _gig_box(offer.gig, "", "")
	var inner := CARD_RIGHT - 4
	return [BbsText.Seg.new()] + BbsText.box("GIG OFFER", CARD_RIGHT, [
			BbsText.bright(BbsText.cut(PilotNetSite.offer_title(offer.template), inner)),
			BbsText.plain(BbsText.cut(PilotNetSite.offer_terms(offer.template), inner)),
			_accept_button(PilotNetSite.ACCEPT_POST, id)])


# A gig's terms, with Accept (action_name ACCEPT) or its state.
func _gig_box(gig: Dictionary, action_name: String, target: String) -> Array:
	if gig.is_empty():
		return []
	var inner := CARD_RIGHT - 4
	var rows := [BbsText.bright(BbsText.cut(str(gig.title), inner)), BbsText.plain(BbsText.cut(PilotNetSite.gig_terms(gig), inner))]
	if gig.state == "open" and action_name != "":
		rows.append(_accept_button(action_name, target))
	elif gig.state == "active":
		rows.append(BbsText.join([BbsText.plain("ACCEPTED: %s   " % PilotNet.progress_text(gig)), BbsText.link("[3] GIGS", _url("/gigs"))]))
	elif gig.state == "complete":
		rows.append(BbsText.plain("COMPLETE: paid when you are next home"))
	return [BbsText.Seg.new()] + BbsText.box("GIG", CARD_RIGHT, rows)


func _accept_button(action_name: String, target: String) -> BbsText.Seg:
	var reason := PilotNet.accept_block_reason()
	if reason != "":
		return BbsText.dim("[ACCEPT]  " + reason)
	return BbsText.action("[ACCEPT]", action_name, target)


func _card_edge() -> BbsText.Seg:
	return BbsText.dim("+" + "-".repeat(CARD_LEFT + 2) + "+" + "-".repeat(CARD_RIGHT + 2) + "+")


# A post or reply as a card: the author's column (callsign, avatar, rank,
# posts, last seen) beside the message (time, number, text), then an edge.
func _card(author: String, entry: Dictionary, number: int, day: int, time: String, message: Array) -> Array:
	var left := [_author_cell(entry, CARD_LEFT)]
	for line in avatar(author):
		left.append(BbsText.dim(" " + line))
	left.append(BbsText.dim(BbsText.cut(PilotNetSite.rank(author), CARD_LEFT)))
	left.append(BbsText.dim(BbsText.cut("Posts: %d" % PilotNet.post_count(author), CARD_LEFT)))
	if PilotNet.is_met(author):
		left.append(BbsText.dim(BbsText.cut("Seen: Day %d" % PilotNet.last_seen(author), CARD_LEFT)))
	var right := [BbsText.spread(BbsText.dim("Day %d %s" % [day, time]), BbsText.dim("#%d" % number), CARD_RIGHT),
			BbsText.rule(CARD_RIGHT)]
	right.append_array(message)
	var out := []
	for i in maxi(left.size(), right.size()):
		var a: BbsText.Seg = left[i] if i < left.size() else BbsText.Seg.new()
		var b: BbsText.Seg = right[i] if i < right.size() else BbsText.Seg.new()
		out.append(BbsText.join([BbsText.dim("| "), a.padded(CARD_LEFT), BbsText.dim(" | "), b.padded(CARD_RIGHT), BbsText.dim(" |")]))
	out.append(_card_edge())
	return out


## A pilot's three-line avatar, the same every time for the same callsign.
static func avatar(callsign: String) -> Array:
	var h := absi(callsign.to_lower().hash())
	return [AVATAR_TOPS[h % AVATAR_TOPS.size()], AVATAR_EYES[(h / 7) % AVATAR_EYES.size()],
			AVATAR_MOUTHS[(h / 71) % AVATAR_MOUTHS.size()]]


# ---- gigs -------------------------------------------------------------------------

func _gigs() -> void:
	_section = "GIGS"
	page_title = "%s - Gigs" % DOMAIN
	_add(_crumbs([["Gigs", ""]]))
	_add(BbsText.Seg.new())
	var active := PilotNet.active_gigs()
	_add(BbsText.spread(BbsText.bright("GIG BOARD"), BbsText.dim("Accepted %d/%d · Completed %d" % [active.size(),
			PilotNet.MAX_ACTIVE_GIGS, PilotNet.gigs_completed]), WIDTH))
	_add(BbsText.Seg.new())
	var open := PilotNet.open_gigs()
	var reason := PilotNet.accept_block_reason()
	_add(BbsText.join([BbsText.bright("OPEN GIGS (%d)" % open.size()), BbsText.dim("   " + reason if reason != "" else "")]))
	if open.is_empty():
		_add(BbsText.dim("  " + NO_POSTS))
	else:
		var columns := [{"title": "GIG", "width": 38}, {"title": "REWARD", "width": 9, "align": "right"},
				{"title": "REP", "width": 4, "align": "right"}, {"title": "POSTED BY", "width": 14},
				{"title": "EXPIRES", "width": 10}, {"title": "", "width": 14}]
		var rows := []
		for gig in open:
			rows.append([BbsText.cell(str(gig.title), 38, "", _post_url("gig:" + str(gig.id))),
					"%s CT" % BbsText.thousands(int(gig.reward)), "+%d" % int(gig.reputation), str(gig.poster),
					PilotNetSite.expires_text(gig), _accept_button(PilotNetSite.ACCEPT, str(gig.id))])
		_add_all(BbsText.table(columns, rows))
	_add(BbsText.Seg.new())
	_add(BbsText.bright("MY GIGS (%d/%d)" % [active.size(), PilotNet.MAX_ACTIVE_GIGS]))
	if active.is_empty():
		_add(BbsText.dim("  None. Accept a gig above."))
	else:
		var columns := [{"title": "GIG", "width": 38}, {"title": "PROGRESS", "width": 34},
				{"title": "THIS RUN", "width": 14}, {"title": "", "width": 9}]
		var rows := []
		for gig in active:
			var run := PilotNet.run_progress(str(gig.id))
			rows.append([BbsText.cell(str(gig.title), 38, "bright"),
					"%s %s" % [BbsText.bar(int(gig.progress), int(gig.count)), PilotNet.progress_text(gig)],
					"+%d (unbanked)" % run if run > 0 else "",
					BbsText.action("[ABANDON]", PilotNetSite.ABANDON, str(gig.id))])
		_add_all(BbsText.table(columns, rows))
	_add(BbsText.Seg.new())
	_add(BbsText.bright("COMPLETE: PAID WHEN YOU ARE NEXT HOME"))
	var complete := PilotNet.complete_gigs()
	if complete.is_empty():
		_add(BbsText.dim("  None."))
	else:
		var rows := []
		for gig in complete:
			rows.append([str(gig.title), "%s CT" % BbsText.thousands(int(gig.reward))])
		_add_all(BbsText.table([{"title": "GIG", "width": 90}, {"title": "REWARD", "width": 11, "align": "right"}], rows))
	_add(BbsText.Seg.new())
	_add(BbsText.dim("Kills and cargo count when you extract. Lost runs count for nothing. Gigs completed: %d" % PilotNet.gigs_completed))


# ---- pilots -----------------------------------------------------------------------

func _pilots(letter: String) -> void:
	_section = "PILOTS"
	page_title = "%s - Pilots" % DOMAIN
	_add(_crumbs([["Pilots", ""]]))
	_add(BbsText.Seg.new())
	_add(BbsText.bright("PILOT DIRECTORY"))
	var letters := []
	for code in range(65, 91):
		var l := String.chr(code)
		letters.append(BbsText.bright("[%s]" % l) if l == letter else BbsText.link(l, _url("/pilots", {"l": l})))
		letters.append(BbsText.space(1))
	letters.append(BbsText.bright("[ALL]") if letter == "" else BbsText.link("ALL", _url("/pilots")))
	_add(BbsText.join(letters))
	var listed := PilotNetSite.directory(letter)
	var rows := []
	for callsign in listed:
		var profile := PilotNet.pilot_profile(callsign)
		var seen := "Day %d" % PilotNet.last_seen(callsign) if PilotNet.is_met(callsign) else "-"
		rows.append([BbsText.cell(callsign, 20, "", _pilot_url(callsign)),
				BbsText.cell(str(profile.get("affiliation", "-")) if not profile.is_empty() else "-", 57, "dim"),
				str(PilotNet.post_count(callsign)), seen])
	if rows.is_empty():
		rows.append([BbsText.cell(NO_POSTS, 20, "dim"), "", "", ""])
	_add_all(BbsText.table([{"title": "CALLSIGN", "width": 20}, {"title": "AFFILIATION", "width": 57},
			{"title": "POSTS", "width": 6, "align": "right"}, {"title": "LAST SEEN", "width": 12}], rows))
	_add(BbsText.dim("%d pilot%s · profiles and the pilots you have met in the field" % [listed.size(),
			"" if listed.size() == 1 else "s"]))


func _pilot(callsign: String) -> void:
	_section = "PILOTS"
	page_title = "%s - %s" % [DOMAIN, callsign]
	var me := PlayerProgress.get_callsign()
	if callsign.to_lower() == me.to_lower():
		_add(_crumbs([["Pilots", _url("/pilots")], [me, ""]]))
		_add(BbsText.Seg.new())
		_add_all(_profile_box(me, [BbsText.bright("YOUR PROFILE: %s" % me),
				BbsText.plain("Reputation: %d" % PlayerProgress.get_reputation()),
				BbsText.plain("Gigs completed: %d" % PilotNet.gigs_completed),
				BbsText.plain("Posts: %d" % PilotNet.post_count(me))]))
		_add(BbsText.Seg.new())
		_posts_table(me)
		return
	var profile := PilotNet.pilot_profile(callsign)
	if profile.is_empty() and not PilotNet.is_met(callsign):
		_add(BbsText.bright("NO PILOT BY THAT CALLSIGN"))
		_add(BbsText.link("Back to the directory", _url("/pilots")))
		return
	var shown: String = profile.get("callsign", callsign)
	_add(_crumbs([["Pilots", _url("/pilots")], [shown, ""]]))
	_add(BbsText.Seg.new())
	var info := [BbsText.bright(shown)]
	if profile.has("affiliation"):
		info.append(BbsText.dim(str(profile.affiliation)))
	info.append(BbsText.plain("Rank: %s · Posts: %d" % [PilotNetSite.rank(shown), PilotNet.post_count(shown)]))
	if PilotNet.is_met(shown):
		info.append(BbsText.plain("Last seen: Day %d" % PilotNet.last_seen(shown)))
	_add_all(_profile_box(shown, info))
	_add(BbsText.Seg.new())
	var bio := []
	if profile.is_empty():
		bio.append(BbsText.plain("No profile on file."))
	else:
		for line in BbsText.wrap(PilotNet.fill_tags(str(profile.get("bio", ""))), WIDTH - 4):
			bio.append(BbsText.plain(line))
	_add_all(BbsText.box("BIO", WIDTH, bio))
	var build := PilotNet.known_build(shown)
	if not build.is_empty():
		_add(BbsText.Seg.new())
		_add(BbsText.bright("KNOWN BUILD"))
		var rows := []
		for entry in build:
			var part_type: String = entry[1]
			var part_id: String = entry[2]
			rows.append([str(entry[0]), BbsText.cell(Store.part_name(part_type, part_id), 45, "", NetSites.wiki_url(part_id)),
					Manufacturers.display_name(Store.maker_of(part_type, part_id))])
		_add_all(BbsText.table([{"title": "SLOT", "width": 16}, {"title": "PART", "width": 45}, {"title": "MAKER", "width": 34}], rows))
	if str(profile.get("steelapedia", "")) != "":
		_add(BbsText.Seg.new())
		_add(BbsText.link("Read about %s on Steelapedia »" % shown, NetSites.wiki_url(str(profile.steelapedia))))
	_add(BbsText.Seg.new())
	_posts_table(shown)


func _profile_box(callsign: String, info: Array) -> Array:
	var art := []
	for line in avatar(callsign):
		art.append(BbsText.dim(" " + line))
	return BbsText.box("PILOT PROFILE", WIDTH, BbsText.beside([art, info], [7, WIDTH - 13], 2))


func _posts_table(callsign: String) -> void:
	_add(BbsText.bright("POSTS"))
	var posts := PilotNet.posts_by(callsign)
	if posts.is_empty():
		_add(BbsText.dim("  " + NO_POSTS))
		return
	var rows := []
	for post_data in posts:
		rows.append(["D%d" % PilotNet.first_seen_day(post_data.id),
				BbsText.cell(PilotNet.fill_tags(post_data.title), 60, "", _post_url(post_data.id)),
				str(PilotNet.get_board(str(post_data.board)).get("name", post_data.board))])
	_add_all(BbsText.table([{"title": "DAY", "width": 6}, {"title": "TOPIC", "width": 60}, {"title": "FORUM", "width": 29}], rows))


# ---- search -----------------------------------------------------------------------

func _search(text: String) -> void:
	page_title = "%s - Search" % DOMAIN
	_add(_crumbs([["Search", ""]]))
	_add(BbsText.Seg.new())
	var wanted := text.strip_edges()
	if wanted == "":
		_add(BbsText.bright("SEARCH THE NET"))
		_add(BbsText.dim("Type what you are looking for in the box above and press Enter."))
		return
	_add(BbsText.bright(BbsText.cut("SEARCH THE NET: \"%s\"" % wanted, WIDTH)))
	_add(BbsText.Seg.new())
	var inner := WIDTH - 4
	var found := PilotNet.search(wanted)
	var lines := []
	for post_data in found.slice(0, SEARCH_COUNT):
		var board := PilotNet.get_board(str(post_data.board))
		lines.append(BbsText.cell(PilotNet.fill_tags(post_data.title), inner, "", _post_url(post_data.id)))
		lines.append(BbsText.dim(BbsText.cut("  %s · %s · by %s · Day %d" % [NetSites.display(_post_url(post_data.id)),
				str(board.get("name", post_data.board)), PilotNet.author_name(post_data), PilotNet.first_seen_day(post_data.id)], inner)))
	_more(lines, found.size())
	_add_all(BbsText.box("PILOT.NET: %d post%s found" % [found.size(), "" if found.size() == 1 else "s"], WIDTH,
			lines if not lines.is_empty() else [BbsText.dim("No posts found.")]))
	_add(BbsText.Seg.new())

	var pilots := PilotNetSite.directory("").filter(func(c): return wanted.to_lower() in str(c).to_lower())
	if not pilots.is_empty():
		var names := []
		for callsign in pilots.slice(0, SEARCH_COUNT):
			names.append(BbsText.join([BbsText.cell(callsign, 24, "", _pilot_url(callsign)),
					BbsText.dim(BbsText.cut(str(PilotNet.pilot_profile(callsign).get("affiliation", "")), inner - 24))]))
		_more(names, pilots.size())
		_add_all(BbsText.box("PILOTS: %d" % pilots.size(), WIDTH, names))
		_add(BbsText.Seg.new())

	var articles := Steelapedia.search(wanted)
	var wiki := []
	for entry in articles.slice(0, SEARCH_COUNT):
		wiki.append(BbsText.cell(str(entry.title), inner, "", NetSites.wiki_url(entry.slug)))
		wiki.append(BbsText.dim(BbsText.cut("  " + str(entry.summary), inner)))
	_more(wiki, articles.size())
	wiki.append(BbsText.link("Search Steelapedia for \"%s\" »" % BbsText.cut(wanted, 40),
			NetSites.make_url(NetSites.STEELAPEDIA_DOMAIN, "/search", {"q": wanted, "fulltext": "1"})))
	_add_all(BbsText.box("STEELAPEDIA: %d article%s" % [articles.size(), "" if articles.size() == 1 else "s"], WIDTH, wiki))
	_add(BbsText.Seg.new())

	var parts := Store.search(wanted)
	var shop := []
	for entry in parts.slice(0, SEARCH_COUNT):
		var price := "%s CT" % BbsText.thousands(Store.price(entry[0], entry[1]))
		shop.append(BbsText.join([BbsText.cell(Store.part_name(entry[0], entry[1]), 40, "", NetSites.product_url(entry[0], entry[1])),
				BbsText.cell(Store.type_name(entry[0]), 18, "dim"),
				BbsText.cell(Manufacturers.short_name(Store.maker_of(entry[0], entry[1])), inner - 40 - 18 - 12, "dim"),
				BbsText.cell(price, 12, "bright", "", "right")]))
	_more(shop, parts.size())
	shop.append(BbsText.link("Search amazing.com for \"%s\" »" % BbsText.cut(wanted, 40), NetSites.search_url(wanted)))
	_add_all(BbsText.box("AMAZING.COM: %d part%s" % [parts.size(), "" if parts.size() == 1 else "s"], WIDTH, shop))
	_add(BbsText.Seg.new())

	var quotes := FourX.search(wanted)
	var market := []
	for entry in quotes.slice(0, SEARCH_COUNT):
		var shown := FourX.quote(entry.symbol)
		market.append(BbsText.join([BbsText.cell(entry.symbol, 6, "", NetSites.quote_url(entry.symbol)),
				BbsText.cell(str(entry.name), inner - 6 - 14 - 10, "dim"),
				BbsText.cell(FourX.format_price(float(shown.last)), 14, "", "", "right"),
				BbsText.cell(FourX.format_pct(float(shown.change_pct)), 10, "bright", "", "right")]))
	_more(market, quotes.size())
	market.append(BbsText.link("Look up \"%s\" on FourX.net »" % BbsText.cut(wanted, 40), NetSites.fourx_url("/search", {"q": wanted})))
	_add_all(BbsText.box("FOURX.NET: %d quote%s" % [quotes.size(), "" if quotes.size() == 1 else "s"], WIDTH, market))


func _more(lines: Array, total: int) -> void:
	if total > SEARCH_COUNT:
		lines.append(BbsText.dim("... and %d more" % (total - SEARCH_COUNT)))


func _not_found() -> void:
	page_title = "%s - Not found" % DOMAIN
	_add(BbsText.bright("404 -- NO SUCH PAGE ON THIS BOARD"))
	_add(BbsText.link("[1] HOME", _url("/")))


# ---- building ---------------------------------------------------------------------

func _build(search_text: String) -> void:
	var page := NetUI.panel(&"NetBbsPage")
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)
	var column := NetUI.vbox(&"NetZeroStack")
	page.add_child(column)
	header = _screen(_header_lines())
	column.add_child(header)
	column.add_child(_search_row(search_text))
	screen = _screen([BbsText.rule(WIDTH)] + _lines)
	column.add_child(screen)


func _screen(lines: Array) -> RichTextLabel:
	var node := BbsText.screen(lines)
	node.meta_clicked.connect(_on_meta_clicked)
	node.meta_hover_started.connect(_on_meta_hover)
	node.meta_hover_ended.connect(func(_meta): hover(""))
	return node


func _header_lines() -> Array:
	var nav := []
	for entry in NAV:
		var label := "[%s] %s" % [entry[0], entry[1]]
		if not nav.is_empty():
			nav.append(BbsText.space(2))
		nav.append(BbsText.inverted(label, _url(entry[2])) if entry[1] == _section else BbsText.link(label, _url(entry[2])))
	var offsite := []
	for entry in OFFSITE:
		if not offsite.is_empty():
			offsite.append(BbsText.space(2))
		offsite.append(BbsText.link("[%s] %s" % [entry[0], entry[1]], str(entry[2])))
	var me := PlayerProgress.get_callsign()
	var login := BbsText.join([BbsText.plain("Logged in as "), BbsText.link(me.to_upper(), _pilot_url(me)),
			BbsText.plain(" · Rep %d · Day %d" % [PlayerProgress.get_reputation(), PilotNet.day])])
	var status := BbsText.dim("%d unread · %s CT" % [PilotNet.unread_count(), BbsText.thousands(int(PlayerProgress.get_money()))])
	return [
		BbsText.Seg.new("[font_size=%d]%s[/font_size] %s" % [BANNER_SIZE, BbsText.bright(BANNER).code, BbsText.dim(TAGLINE).code], WIDTH),
		BbsText.spread(login, status, WIDTH),
		BbsText.rule(WIDTH, "="),
		BbsText.spread(BbsText.join(nav), BbsText.join(offsite), WIDTH),
		BbsText.rule(WIDTH),
	]


func _search_row(text: String) -> HBoxContainer:
	var row := NetUI.hbox(&"NetToolbar")
	row.custom_minimum_size.x = WIDTH * CHAR_WIDTH
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(NetUI.text("SEARCH THE NET>", &"NetBbsLink"))
	search_field = NetUI.input("posts, pilots, articles, parts, quotes")
	search_field.theme_type_variation = &"NetBbsInput"
	search_field.text = text
	search_field.context_menu_enabled = false
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.text_submitted.connect(_submit_search)
	row.add_child(search_field)
	var go := MechUI.button("[GO]", &"NetBbsButton")
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func(): _submit_search(search_field.text))
	row.add_child(go)
	return row


func _submit_search(value: String) -> void:
	if value.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	follow(_url("/search", {"q": value.strip_edges()}))


func _on_meta_clicked(meta) -> void:
	var target := str(meta)
	if not target.begins_with(BbsText.ACTION):
		follow(target)
		return
	var parts := target.substr(BbsText.ACTION.length()).split(":", true, 1)
	PilotNetSite.act(parts[0], parts[1] if parts.size() > 1 else "")
	follow(NetSites.make_url(domain, path, query))


func _on_meta_hover(meta) -> void:
	var target := str(meta)
	hover("" if target.begins_with(BbsText.ACTION) else target)


# ---- text -------------------------------------------------------------------------

func _add(line: BbsText.Seg) -> void:
	_lines.append(line)


func _add_all(lines: Array) -> void:
	_lines.append_array(lines)


## "pilot.net » Forums » GENERAL CHATTER": [label, url] steps, the last one
## (url "") the page itself.
func _crumbs(trail: Array) -> BbsText.Seg:
	var runs := [BbsText.link("pilot.net", _url("/"))]
	var used := "pilot.net".length()
	for step in trail:
		runs.append(BbsText.dim(" » "))
		used += 3
		var label := BbsText.cut(str(step[0]), maxi(WIDTH - used, 1))
		runs.append(BbsText.link(label, str(step[1])) if str(step[1]) != "" else BbsText.bright(label))
		used += label.length()
	return BbsText.join(runs)


func _add_pages(page_path: String, page_number: int, pages: int) -> void:
	if pages <= 1:
		return
	var runs := [BbsText.dim("Pages: ")]
	if page_number > 1:
		runs.append(BbsText.link("« Prev", _url(page_path, {"page": str(page_number - 1)})))
		runs.append(BbsText.space(1))
	for number in range(1, pages + 1):
		runs.append(BbsText.bright("[%d]" % number) if number == page_number
				else BbsText.link(str(number), _url(page_path, {"page": str(number)})))
		runs.append(BbsText.space(1))
	if page_number < pages:
		runs.append(BbsText.link("Next »", _url(page_path, {"page": str(page_number + 1)})))
	_add(BbsText.join(runs))


func _url(page_path: String, page_query := {}) -> String:
	return NetSites.make_url(DOMAIN, page_path, page_query)


func _post_url(id: String) -> String:
	return _url("/post/" + id)


func _pilot_url(callsign: String) -> String:
	return _url("/pilot/" + callsign)


# The author, linked to their profile when there is one (or they've been met,
# or it's the player), cut and padded to width.
func _author_cell(entry: Dictionary, width: int) -> BbsText.Seg:
	var author := PilotNetSite.author_of(entry)
	return BbsText.cell(author, width, "bright", _pilot_url(author) if PilotNetSite.is_known(author) else "")
