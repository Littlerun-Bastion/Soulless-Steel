class_name SteelapediaPage
extends NetPage

## Steelapedia (steelapedia.net), the in-world encyclopedia, as a mid-2000s
## wiki: the NET's one light site, in MechOS greys. Down the left: the logo
## (SteelapediaLogo, a link to the Main Page) and the portlets (navigation,
## search, toolbox). On the right: the user line, tabs over a bordered sheet
## that holds the page, and the footer under it. Its articles are
## Steelapedia's. Paths:
##   /                             the Main Page: the welcome banner and
##                                 portals, today's featured article (one a
##                                 session), In the news (pilot.net's latest
##                                 NEWS), Did you know..., new articles,
##                                 today's featured picture (a part, one a
##                                 session), the sister sites
##   /?action=talk                 the Main Page's discussion
##   /wiki/<slug>                  an article: title (and under it, for a
##                                 lost pilot, a link to its Memorial Wall
##                                 record), infobox (with a part's
##                                 picture), contents (three or more sections),
##                                 sections with [edit] links, Links, See also,
##                                 categories, last modified
##   /wiki/<slug>?action=edit      view source: the article as markup
##   /wiki/<slug>?action=history   its revision history
##   /wiki/<slug>?action=talk      its discussion
##   /category/<id>                a category's articles, A-Z in columns
##   /special/all                  every article, A-Z in columns
##   /special/random               goes to a random article
##   /special/categories           every category with its count
##   /special/whatlinkshere/<slug> the articles that link to one
##   /special/specialpages         the special pages
##   /search?q=[&fulltext=1]       results with summaries; one exact title
##                                 goes straight to its article (unless
##                                 fulltext)
## Article text is SteelapediaMarkup in RichTextLabels; their links are
## [url=wiki:<slug>] and [url=net:<address>].

const DOMAIN := "steelapedia.net"
const LOGO := "Steelapedia"
const MOTTO := "The Free Pilot Encyclopedia"
const WELCOME := "Welcome to Steelapedia, the free pilot encyclopedia that any pilot can edit."
const FROM := "From Steelapedia, the free pilot encyclopedia"
const MISSING := "Steelapedia does not have an article with this exact name."
const PROTECTED := "This page is protected from editing. You can view and copy its source:"
const NO_TALK := "There is no discussion on this page yet."
const NO_RESULTS := "There were no results matching the query."
const LICENSE := "Content is available under the Pilot Commons License."
const FOOTER_LINKS := "Privacy policy · About Steelapedia · Disclaimers"
const PERSONAL := "%s · talk for this IP · log in / create account"
const BADGES := [["POWERED BY", "STEELWIKI"], ["PILOT", "COMMONS"]]
const EDITOR := "SteelBot"
const SIDEBAR_WIDTH := 176
const INFOBOX_WIDTH := 300
const INFOBOX_LABEL_WIDTH := 120
const INFOBOX_IMAGE := Vector2(284, 200)
const PICTURE_BOX := Vector2(240, 200)
const BADGE_SIZE := Vector2(88, 31)
const CONTENTS_MIN := 3
const NEWS_COUNT := 3
const NEW_COUNT := 5
const LIST_COLUMNS := 3
const NAV := [["Main Page", "/"], ["Parts", "/category/parts"], ["Manufacturers", "/category/manufacturers"],
		["Entities", "/category/entities"], ["Pilots", "/category/pilots"], ["Places", "/category/places"],
		["History", "/category/history"], ["Random article", "/special/random"], ["All pages", "/special/all"]]
const PORTALS := ["parts", "manufacturers", "entities", "pilots", "places", "history", "misc"]
const SISTERS := [["pilot.net", "pilot.net", "the independent pilots' exchange"],
		["amazing.com", "amazing.com", "the region's general store"], ["FourX.net", "fourx.net", "the regional exchange"]]
const SPECIAL := [["All pages", "/special/all"], ["Categories", "/special/categories"], ["Random article", "/special/random"],
		["Search", "/search"]]

## The Main Page's featured article and picture ([part_type, part_id]),
## picked once a session.
static var featured_slug := ""
static var picture_part: Array = []

## The page's column inside the sheet.
var main: VBoxContainer
## The article shown, {} on other pages (tests).
var article: Dictionary = {}
## Where a redirect (random, an exact search match) goes, "" for none (tests).
var redirect := ""
var _headings: Array = []
var _tabs: Array = []
var _modified := 0


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	var segments := Array(page_path.split("/", false))
	var first: String = str(segments[0]).to_lower() if not segments.is_empty() else ""
	var action := str(page_query.get("action", "")).to_lower()
	page_title = "Steelapedia"
	var frame := NetUI.panel(&"NetWikiPage")
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(frame)
	var columns := NetUI.hbox(&"NetWikiColumns")
	frame.add_child(columns)
	var slug := SteelapediaMarkup.slug_of(str(segments[1])) if first == "wiki" and segments.size() == 2 else ""
	columns.add_child(_sidebar(str(page_query.get("q", "")) if first == "search" else "", slug))
	var right := NetUI.vbox(&"NetZeroStack")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_personal_line())
	var sheet := NetUI.panel(&"NetWikiSheet")
	main = NetUI.vbox(&"NetWikiStack")
	sheet.add_child(main)
	if first == "" and action == "talk":
		_talk("Main Page", "/")
	elif first == "":
		_main_page()
	elif first == "wiki" and segments.size() == 2:
		_wiki(slug, action)
	elif first == "category" and segments.size() == 2:
		_category(SteelapediaMarkup.slug_of(str(segments[1])))
	elif first == "special" and segments.size() >= 2:
		_special(str(segments[1]).to_lower(), str(segments[2]) if segments.size() >= 3 else "")
	elif first == "search":
		_search(str(page_query.get("q", "")), str(page_query.get("fulltext", "")) != "")
	else:
		_missing(page_path.trim_prefix("/"))
	right.add_child(_tab_row())
	right.add_child(sheet)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(gap)
	right.add_child(_footer())


## Every text on the page (tests).
func get_text() -> String:
	var bits := []
	for node in find_children("*", "", true, false):
		if node is RichTextLabel:
			bits.append(node.get_parsed_text())
		elif node is Label or node is LinkButton or node is Button:
			bits.append(node.text)
	return "\n".join(bits)


## The Main Page's featured article, picked once a session (again if it has
## gone); null when there are no articles.
static func featured():
	var chosen = Steelapedia.get_article(featured_slug, false) if featured_slug != "" else null
	if chosen == null:
		chosen = Steelapedia.random_article()
		featured_slug = chosen.slug if chosen != null else ""
	return chosen


## The Memorial Wall's record of a pilot article (one in "pilots", its title
## the callsign), {} for none or another kind of article.
static func memorial_record(entry: Dictionary) -> Dictionary:
	if not "pilots" in entry.get("categories", []):
		return {}
	return PilotNetSite.memorial_record(str(entry.get("title", "")))


## The Main Page's featured picture: a listed part whose picture fits
## PICTURE_BOX, picked once a session; [] when none does.
static func featured_picture() -> Array:
	if not picture_part.is_empty() and Store.is_listed(picture_part[0], picture_part[1]):
		return picture_part
	var pool := []
	for part_type in Store.CATEGORIES:
		for part_id in Store.catalogue(part_type):
			if _fits(_image_of(part_type, part_id), PICTURE_BOX):
				pool.append([part_type, part_id])
	picture_part = pool.pick_random() if not pool.is_empty() else []
	return picture_part


static func _image_of(part_type: String, part_id: String) -> Texture2D:
	var part := Store.get_part(part_type, part_id)
	var image = part.get("image") if part != null else null
	return image if image is Texture2D else null


static func _fits(texture: Texture2D, box: Vector2) -> bool:
	return texture != null and texture.get_width() <= box.x and texture.get_height() <= box.y


# ---- the frame --------------------------------------------------------------------

func _sidebar(search_text: String, slug: String) -> VBoxContainer:
	var column := NetUI.vbox(&"NetWikiStack")
	column.custom_minimum_size.x = SIDEBAR_WIDTH
	var logo := SteelapediaLogo.new()
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_STOP
	logo.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	logo.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			follow(_url("/")))
	logo.mouse_entered.connect(hover.bind(_url("/")))
	logo.mouse_exited.connect(hover.bind(""))
	column.add_child(logo)
	var words := NetUI.vbox(&"NetZeroStack")
	for line in [[LOGO, &"NetWikiLogo"], [MOTTO, &"NetWikiMotto"]]:
		var label := NetUI.text(line[0], line[1])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		words.add_child(label)
	column.add_child(words)

	var links := NetUI.vbox(&"NetTightStack")
	for entry in NAV:
		links.add_child(_link(entry[0], _url(entry[1])))
	column.add_child(_portlet("navigation", links))

	var search := NetUI.vbox(&"NetTightStack")
	var field := NetUI.input("")
	field.theme_type_variation = &"NetWikiInput"
	field.text = search_text
	field.context_menu_enabled = false
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(text: String): _submit_search(text, false))
	search.add_child(field)
	var buttons := NetUI.hbox(&"NetWikiToolbar")
	var go := NetUI.button("Go")
	go.pressed.connect(func(): _submit_search(field.text, false))
	var full := NetUI.button("Search")
	full.pressed.connect(func(): _submit_search(field.text, true))
	buttons.add_child(go)
	buttons.add_child(full)
	search.add_child(buttons)
	column.add_child(_portlet("search", search))

	var tools := NetUI.vbox(&"NetTightStack")
	if slug != "":
		tools.add_child(_link("What links here", _url("/special/whatlinkshere/" + slug)))
	tools.add_child(_link("Special pages", _url("/special/specialpages")))
	tools.add_child(_link("All categories", _url("/special/categories")))
	column.add_child(_portlet("toolbox", tools))
	return column


# A portlet: its lower-case name over a bordered box.
func _portlet(title: String, body: Control) -> VBoxContainer:
	var holder := NetUI.vbox(&"NetZeroStack")
	var label := NetUI.text(title, &"NetWikiPortletTitle")
	holder.add_child(label)
	holder.add_child(NetUI.panel(&"NetWikiPortlet", body))
	return holder


# The user line over the tabs, like an address that isn't logged in.
func _personal_line() -> HBoxContainer:
	var row := NetUI.hbox(&"NetWikiToolbar")
	row.alignment = BoxContainer.ALIGNMENT_END
	var h := absi(PlayerProgress.get_callsign().hash())
	var address := "10.%d.%d.%d" % [h % 250 + 1, (h / 250) % 250 + 1, (h / 62500) % 250 + 1]
	row.add_child(NetUI.text(PERSONAL % address, &"NetWikiMeta"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	return row


# The tabs over the sheet (_tabs: [label, url, open]); the open one meets the
# sheet, so the row draws over the sheet's top edge.
func _tab_row() -> HBoxContainer:
	var row := NetUI.hbox(&"NetWikiTabs")
	row.z_index = 1
	var indent := Control.new()
	indent.custom_minimum_size.x = 8
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(indent)
	for tab in _tabs:
		var button := MechUI.button(str(tab[0]), &"NetWikiTabActive" if tab[2] else &"NetWikiTab")
		button.size_flags_vertical = Control.SIZE_SHRINK_END
		button.set_meta("url", tab[1])
		button.pressed.connect(follow.bind(str(tab[1])))
		button.mouse_entered.connect(hover.bind(str(tab[1])))
		button.mouse_exited.connect(hover.bind(""))
		row.add_child(button)
	return row


func _footer() -> PanelContainer:
	var row := NetUI.hbox(&"NetWikiColumns")
	row.add_child(_badge(BADGES[0]))
	var lines := NetUI.vbox(&"NetZeroStack")
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var texts := [LICENSE, FOOTER_LINKS]
	if _modified > 0:
		texts.push_front("This page was last modified on %s." % PilotNet.long_date(_modified))
	for text in texts:
		var label := NetUI.text(text, &"NetWikiMeta", true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lines.add_child(label)
	row.add_child(lines)
	row.add_child(_badge(BADGES[1]))
	return NetUI.panel(&"NetWikiFooter", row)


# An 88x31 button in the footer, its two lines of tiny type in a frame.
func _badge(words: Array) -> PanelContainer:
	var column := NetUI.vbox(&"NetZeroStack")
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	for word in words:
		var label := NetUI.text(str(word), &"NetWikiBadgeText")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	var badge := NetUI.panel(&"NetWikiBadge", column)
	badge.custom_minimum_size = BADGE_SIZE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return badge


func _submit_search(text: String, fulltext: bool) -> void:
	if text.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	var wanted := {"q": text.strip_edges()}
	if fulltext:
		wanted["fulltext"] = "1"
	follow(_url("/search", wanted))


# ---- the Main Page ----------------------------------------------------------------

func _main_page() -> void:
	page_title = "Steelapedia - Main Page"
	_tabs = [["main page", _url("/"), true], ["discussion", _url("/", {"action": "talk"}), false]]
	var banner := NetUI.hbox(&"NetWikiColumns")
	var welcome := NetUI.vbox(&"NetTightStack")
	welcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	welcome.add_child(NetUI.text(WELCOME, &"NetWikiLabel", true))
	welcome.add_child(NetUI.text("%d articles" % Steelapedia.all_articles().size(), &"NetWikiMeta"))
	banner.add_child(welcome)
	var counts := Steelapedia.category_counts()
	var portals := NetUI.vbox(&"NetTightStack")
	portals.custom_minimum_size.x = 260
	portals.add_child(NetUI.text("Portals:", &"NetWikiLabel"))
	var portal_row := NetUI.hbox(&"NetWikiToolbar")
	for i in PORTALS.size():
		if i > 0 and i % 3 == 0:
			portals.add_child(portal_row)
			portal_row = NetUI.hbox(&"NetWikiToolbar")
		var category: String = PORTALS[i]
		portal_row.add_child(_link("%s (%d)" % [Steelapedia.category_name(category), int(counts.get(category, 0))],
				_url("/category/" + category)))
	portals.add_child(portal_row)
	banner.add_child(portals)
	main.add_child(NetUI.panel(&"NetWikiBox", banner))

	var columns := NetUI.hbox(&"NetWikiColumns")
	main.add_child(columns)
	var left := NetUI.vbox(&"NetWikiStack")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	var right := NetUI.vbox(&"NetWikiStack")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	columns.add_child(right)

	var chosen = featured()
	var feature := NetUI.vbox(&"NetTightStack")
	if chosen != null:
		feature.add_child(_link(chosen.title, _wiki_url(chosen.slug)))
		feature.add_child(_rich(_inline(chosen.summary)))
		var excerpt := _excerpt(chosen)
		if excerpt != "":
			feature.add_child(_rich(_markup(excerpt)))
		feature.add_child(_link("Read more...", _wiki_url(chosen.slug)))
	else:
		feature.add_child(NetUI.text("No articles yet.", &"NetWikiMeta"))
	left.add_child(_mp_box("Today's featured article", feature))
	var know := []
	for i in 3:
		know.append("* ..." + Steelapedia.lorem_sentence("did_you_know_%d" % i).to_lower().trim_suffix(".") + "?")
	left.add_child(_mp_box("Did you know...", _rich(_markup("\n".join(know)))))

	var news := []
	for post_data in PilotNet.latest(PilotNet.NEWS_BOARD, NEWS_COUNT):
		news.append([PilotNet.fill_tags(post_data.title), NetSites.make_url(PilotNetPage.DOMAIN, "/post/" + post_data.id)])
	right.add_child(_mp_box("In the news", _bullets(news) if not news.is_empty()
			else NetUI.text("Nothing in the news.", &"NetWikiMeta")))
	var fresh := []
	for entry in Steelapedia.recent_articles(NEW_COUNT):
		fresh.append("* [[%s]] (%s)" % [entry.slug, PilotNet.long_date(Steelapedia.last_modified_day(entry.slug))])
	right.add_child(_mp_box("New articles", _rich(_markup("\n".join(fresh))) if not fresh.is_empty()
			else NetUI.text("No articles yet.", &"NetWikiMeta")))

	var shown := featured_picture()
	if not shown.is_empty():
		var row := NetUI.hbox(&"NetWikiColumns")
		row.add_child(_picture(_image_of(shown[0], shown[1]), PICTURE_BOX))
		var caption := NetUI.vbox(&"NetTightStack")
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_child(_link(Store.part_name(shown[0], shown[1]), _wiki_url(SteelapediaMarkup.slug_of(shown[1]))))
		caption.add_child(NetUI.text("%s by %s" % [Store.type_name(shown[0]), Manufacturers.display_name(Store.maker_of(shown[0], shown[1]))],
				&"NetWikiMeta", true))
		caption.add_child(_rich(_markup(Steelapedia.lorem_sentence("picture:" + str(shown[1])))))
		row.add_child(caption)
		row.set_meta("net_part", shown)
		main.add_child(_mp_box("Today's featured picture", row))

	var sisters := []
	for entry in SISTERS:
		sisters.append("* [[net:%s|%s]]: %s" % [entry[1], entry[0], entry[2]])
	main.add_child(_mp_box("Steelapedia's sister sites", _rich(_markup("\n".join(sisters)))))


func _mp_box(title: String, body: Control) -> PanelContainer:
	var column := NetUI.vbox(&"NetWikiStack")
	column.add_child(NetUI.panel(&"NetWikiHeader", NetUI.text(title, &"NetWikiLabel")))
	column.add_child(body)
	return NetUI.panel(&"NetWikiBox", column)


# The first paragraph of the article's text as it shows now: its lead, or
# its first section's when it has no lead.
func _excerpt(chosen: Dictionary) -> String:
	var meets := func(conditions: Dictionary) -> bool: return StoryDirector.meets(conditions)
	for section in SteelapediaMarkup.visible_sections(str(chosen.body), meets):
		var text := str(section.text).strip_edges()
		if text != "":
			return text.split("\n\n")[0]
	return ""


# A bulleted list of links ([label, url]); the labels show as they are.
func _bullets(entries: Array) -> VBoxContainer:
	var list := NetUI.vbox(&"NetTightStack")
	for entry in entries:
		var row := NetUI.hbox(&"NetWikiToolbar")
		row.add_child(NetUI.text("•", &"NetWikiText"))
		row.add_child(_link(str(entry[0]), str(entry[1])))
		list.add_child(row)
	return list


# ---- articles ---------------------------------------------------------------------

func _wiki(slug: String, action: String) -> void:
	var found = Steelapedia.get_article(slug)
	if found == null:
		_missing(slug)
		return
	article = found
	_modified = Steelapedia.last_modified_day(article.slug)
	_tabs = [["article", _wiki_url(slug), action == ""], ["discussion", _url("/wiki/" + slug, {"action": "talk"}), action == "talk"],
			["view source", _url("/wiki/" + slug, {"action": "edit"}), action == "edit"],
			["history", _url("/wiki/" + slug, {"action": "history"}), action == "history"]]
	if action == "edit":
		_view_source()
	elif action == "history":
		_history()
	elif action == "talk":
		_talk(article.title, "/wiki/" + slug)
	else:
		_article()


func _article() -> void:
	page_title = "Steelapedia - %s" % article.title
	_title(article.title)
	main.add_child(NetUI.text(FROM, &"NetWikiMeta"))
	var lost := memorial_record(article)
	if not lost.is_empty():
		var line := _rich(_markup("%s — [[net:%s|%s]]" % [PilotNetSite.lost_text(lost), NetSites.memorial_record_url(int(lost.id)),
				PilotNetSite.MEMORIAL_NAME]))
		line.set_meta("memorial", int(lost.id))
		main.add_child(line)
	var columns := NetUI.hbox(&"NetWikiColumns")
	main.add_child(columns)
	var body := NetUI.vbox(&"NetWikiStack")
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(body)
	if not article.infobox.is_empty():
		columns.add_child(_infobox(article))

	var meets := func(conditions: Dictionary) -> bool: return StoryDirector.meets(conditions)
	var sections := SteelapediaMarkup.visible_sections(article.body, meets)
	var extra: Dictionary = article.extra_sections.duplicate()
	var headed := sections.filter(func(s): return s.level > 0)
	var titles := headed.map(func(s): return s.title)
	for title in extra:
		if not title in titles:
			headed.append({"level": 2, "title": title, "requires": {}, "text": ""})
			sections.append(headed[-1])
	if sections[0].text != "":
		body.add_child(_rich(_markup(sections[0].text)))
	if headed.size() >= CONTENTS_MIN:
		body.add_child(_contents(headed))
	for section in sections:
		if section.level == 0:
			continue
		_heading(body, section.title, section.level)
		var text: String = section.text
		if extra.has(section.title):
			text = (text + "\n\n" + str(extra[section.title])).strip_edges()
		if text != "":
			body.add_child(_rich(_markup(text)))
	if not article.links.is_empty():
		_heading(body, "Links", 2, false)
		var lines: Array = article.links.map(func(l): return "* [[net:%s|%s]]" % [l[1], l[0]])
		body.add_child(_rich(_markup("\n".join(lines))))
	if not article.see_also.is_empty():
		_heading(body, "See also", 2, false)
		var lines: Array = article.see_also.map(func(s): return "* [[%s]]" % s)
		body.add_child(_rich(_markup("\n".join(lines))))
	main.add_child(_category_bar(article.categories))


# A section heading: the title, [edit] on the right (view source), and a
# rule under a level-2 one, which also gets some room above it.
func _heading(body: VBoxContainer, title: String, level: int, editable := true) -> void:
	if level == 2 and body.get_child_count() > 0:
		var room := Control.new()
		room.custom_minimum_size.y = 4
		room.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(room)
	var row := NetUI.hbox(&"NetWikiToolbar")
	var label := NetUI.text(title, &"NetWikiHeading" if level == 2 else &"NetWikiSubheading", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if editable:
		row.add_child(_bracketed(_link("edit", _url("/wiki/" + article.slug, {"action": "edit"}))))
	body.add_child(row)
	_headings.append(row)
	if level == 2:
		body.add_child(_rule())


# "[link]" with no gaps.
func _bracketed(link: LinkButton) -> HBoxContainer:
	var row := NetUI.hbox(&"NetZeroRow")
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(NetUI.text("[", &"NetWikiMeta"))
	row.add_child(link)
	row.add_child(NetUI.text("]", &"NetWikiMeta"))
	return row


func _infobox(shown: Dictionary) -> PanelContainer:
	var rows := NetUI.vbox(&"NetTightStack")
	var title := NetUI.text(shown.title, &"NetWikiLabel", true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(NetUI.panel(&"NetWikiHeader", title))
	var data: Dictionary = shown.get("data", {})
	if data.get("kind") == "part":
		var image := _image_of(str(data.part_type), str(data.part_id))
		if _fits(image, INFOBOX_IMAGE):
			var picture := _picture(image, Vector2(INFOBOX_IMAGE.x, image.get_height() + 8))
			picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			picture.set_meta("net_part", [data.part_type, data.part_id])
			rows.add_child(picture)
	for entry in shown.infobox:
		var line := NetUI.hbox(&"NetWikiToolbar")
		var label := NetUI.text(str(entry[0]), &"NetWikiLabel", true)
		label.custom_minimum_size.x = INFOBOX_LABEL_WIDTH
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(label)
		var value := _rich(_inline(str(entry[1])))
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		rows.add_child(line)
	var box := NetUI.panel(&"NetWikiBox", rows)
	box.custom_minimum_size.x = INFOBOX_WIDTH
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.set_meta("infobox", true)
	return box


# A part's picture at 1:1, centred in a box of box_size.
func _picture(texture: Texture2D, box_size: Vector2) -> CenterContainer:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = box_size
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var image := TextureRect.new()
	image.texture = texture
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(image)
	return holder


# The contents box: "Contents [hide]" and the numbered sections, each a link
# that scrolls to its heading; hide folds the list away.
func _contents(headed: Array) -> PanelContainer:
	var column := NetUI.vbox(&"NetTightStack")
	var head := NetUI.hbox(&"NetWikiToolbar")
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(NetUI.text("Contents", &"NetWikiLabel"))
	var toggle := LinkButton.new()
	toggle.theme_type_variation = &"NetWikiLink"
	toggle.text = "hide"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	head.add_child(_bracketed(toggle))
	column.add_child(head)
	var list := NetUI.vbox(&"NetTightStack")
	var major := 0
	var minor := 0
	for i in headed.size():
		var section: Dictionary = headed[i]
		var number := ""
		if section.level == 2:
			major += 1
			minor = 0
			number = str(major)
		else:
			minor += 1
			number = "%d.%d" % [major, minor]
		var line := NetUI.hbox(&"NetZeroRow")
		var indent := Control.new()
		indent.custom_minimum_size.x = 0 if section.level == 2 else 20
		indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(indent)
		var link := LinkButton.new()
		link.theme_type_variation = &"NetWikiLink"
		link.text = "%s %s" % [number, section.title]
		link.focus_mode = Control.FOCUS_NONE
		link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
		link.pressed.connect(_scroll_to_heading.bind(i))
		line.add_child(link)
		list.add_child(line)
	column.add_child(list)
	toggle.pressed.connect(func():
		list.visible = not list.visible
		toggle.text = "hide" if list.visible else "show")
	var box := NetUI.panel(&"NetWikiBox", column)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.custom_minimum_size.x = 240
	box.set_meta("contents", true)
	return box


func _scroll_to_heading(index: int) -> void:
	if index < 0 or index >= _headings.size():
		return
	var node: Node = self
	while node != null and not node is ScrollContainer:
		node = node.get_parent()
	if node == null:
		return
	var scroll := node as ScrollContainer
	var heading: Control = _headings[index]
	scroll.scroll_vertical = int(heading.global_position.y - scroll.get_child(0).global_position.y)


func _category_bar(categories: Array) -> PanelContainer:
	var row := NetUI.hbox(&"NetWikiToolbar")
	var head := NetUI.hbox(&"NetZeroRow")
	head.add_child(_link("Categories", _url("/special/categories")))
	head.add_child(NetUI.text(":", &"NetWikiText"))
	row.add_child(head)
	for i in categories.size():
		if i > 0:
			row.add_child(NetUI.text("|", &"NetWikiMeta"))
		row.add_child(_link(Steelapedia.category_name(categories[i]), _url("/category/" + categories[i])))
	var bar := NetUI.panel(&"NetWikiBox", row)
	bar.set_meta("categories", true)
	return bar


func _view_source() -> void:
	page_title = "Steelapedia - View source for %s" % article.title
	_title("View source")
	main.add_child(NetUI.text("for %s" % article.title, &"NetWikiMeta"))
	main.add_child(NetUI.text(PROTECTED, &"NetWikiText", true))
	var source := RichTextLabel.new()
	source.theme_type_variation = &"NetWikiBody"
	source.bbcode_enabled = false
	source.fit_content = true
	source.scroll_active = false
	source.selection_enabled = true
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.mouse_filter = Control.MOUSE_FILTER_PASS
	source.text = Steelapedia.source_of(article)
	var box := NetUI.panel(&"NetWikiBox", source)
	box.set_meta("source", true)
	main.add_child(box)
	main.add_child(_rich(_markup("Return to [[%s]]." % article.slug)))


func _history() -> void:
	page_title = "Steelapedia - %s: Revision history" % article.title
	_title("%s: Revision history" % article.title)
	main.add_child(NetUI.text("(cur) = this version, (last) = the one before", &"NetWikiMeta"))
	var lines := []
	if article.generated:
		lines.append("* (cur) (last) '''%s''' . . %s (page made from the catalogue)" % [PilotNet.long_date(1), EDITOR])
	if str(article.file) != "":
		var day := Steelapedia.last_modified_day(article.slug)
		lines.push_front("* (cur) (last) '''%s''' . . Steelapedia (%s)" % [PilotNet.long_date(day),
				"text added" if article.generated else "page created"])
	main.add_child(_rich(_markup("\n".join(lines))))


func _talk(title: String, back: String) -> void:
	page_title = "Steelapedia - Talk:%s" % title
	if _tabs.is_empty():
		_tabs = [["main page", _url(back), false], ["discussion", _url(back, {"action": "talk"}), true]]
	_title("Talk:%s" % title)
	main.add_child(NetUI.text(FROM, &"NetWikiMeta"))
	main.add_child(NetUI.text(NO_TALK, &"NetWikiText", true))
	main.add_child(_link("« Back to %s" % title, _url(back)))


# ---- lists ------------------------------------------------------------------------

func _category(category: String) -> void:
	var name := Steelapedia.category_name(category)
	page_title = "Steelapedia - Category: %s" % name
	_tabs = [["category", _url("/category/" + category), true]]
	_title("Category:%s" % name)
	if category == "parts":
		var counts := Steelapedia.category_counts()
		var subs := []
		for part_type in Store.CATEGORIES:
			var sub := Steelapedia.type_category(part_type)
			if counts.has(sub):
				subs.append("* [[net:%s|%s]] (%d)" % [_url("/category/" + sub), Steelapedia.category_name(sub), int(counts[sub])])
		for maker in Manufacturers.real_ids():
			if counts.has(maker):
				subs.append("* [[net:%s|%s]] (%d)" % [_url("/category/" + maker), Steelapedia.category_name(maker), int(counts[maker])])
		if not subs.is_empty():
			_heading(main, "Subcategories", 2, false)
			main.add_child(_columns(subs))
	var articles := Steelapedia.articles_in(category)
	_heading(main, "Pages in category \"%s\" (%d)" % [name, articles.size()], 2, false)
	if articles.is_empty():
		main.add_child(NetUI.text("This category has no pages yet.", &"NetWikiMeta"))
		return
	main.add_child(_columns(_az_lines(articles)))


func _special(page: String, target: String) -> void:
	_tabs = [["special page", _url("/special/" + page), true]]
	if page == "all":
		page_title = "Steelapedia - All pages"
		_title("All pages")
		main.add_child(_columns(_az_lines(Steelapedia.all_articles())))
	elif page == "random":
		page_title = "Steelapedia - Random article"
		var chosen = Steelapedia.random_article()
		if chosen == null:
			main.add_child(NetUI.text("There are no articles yet.", &"NetWikiMeta"))
			return
		main.add_child(NetUI.text("Taking you to a random article...", &"NetWikiMeta"))
		_redirect(_wiki_url(chosen.slug))
	elif page == "categories":
		page_title = "Steelapedia - Categories"
		_title("Categories")
		var counts := Steelapedia.category_counts()
		var ids: Array = counts.keys()
		ids.sort_custom(func(a, b): return Steelapedia.category_name(a).naturalnocasecmp_to(Steelapedia.category_name(b)) < 0)
		main.add_child(_columns(ids.map(func(c): return "* [[net:%s|%s]] (%d)" % [_url("/category/" + c),
				Steelapedia.category_name(c), int(counts[c])])))
	elif page == "whatlinkshere" and target != "":
		var slug := SteelapediaMarkup.slug_of(target)
		var title := Steelapedia.title_of(slug)
		var shown := title if title != "" else slug.replace("_", " ")
		page_title = "Steelapedia - Pages that link to %s" % shown
		_title("Pages that link to \"%s\"" % shown)
		var linking := Steelapedia.links_to(slug)
		if linking.is_empty():
			main.add_child(NetUI.text("No pages link to %s." % shown, &"NetWikiText", true))
		else:
			main.add_child(_rich(_markup("\n".join(linking.map(func(a): return "* [[%s]]" % a.slug)))))
		main.add_child(_link("« Back to %s" % shown, _wiki_url(slug)))
	elif page == "specialpages":
		page_title = "Steelapedia - Special pages"
		_title("Special pages")
		main.add_child(_rich(_markup("\n".join(SPECIAL.map(func(s): return "* [[net:%s|%s]]" % [_url(s[1]), s[0]])))))
	else:
		_missing("Special:" + page)


# Articles under their first letters: "'''A'''" then bullets.
func _az_lines(articles: Array) -> Array:
	var lines := []
	var letter := ""
	for entry in articles:
		var first := str(entry.title).substr(0, 1).to_upper()
		if first != letter:
			letter = first
			lines.append("'''%s'''" % letter)
		lines.append("* [[%s]]" % entry.slug)
	return lines


# Lines of markup in LIST_COLUMNS columns side by side, top to bottom.
func _columns(lines: Array) -> HBoxContainer:
	var row := NetUI.hbox(&"NetWikiColumns")
	var per := ceili(lines.size() / float(LIST_COLUMNS))
	for i in LIST_COLUMNS:
		var part := lines.slice(i * per, (i + 1) * per)
		var column := _rich(_markup("\n".join(part)) if not part.is_empty() else "")
		column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(column)
	return row


func _search(text: String, fulltext: bool) -> void:
	page_title = "Steelapedia - Search"
	_tabs = [["special page", _url("/search"), true]]
	_title("Search results")
	var wanted := text.strip_edges()
	if wanted == "":
		main.add_child(NetUI.text("Type what you are looking for in the search box.", &"NetWikiMeta"))
		return
	main.add_child(NetUI.text("You searched for \"%s\"" % wanted, &"NetWikiMeta", true))
	if not fulltext:
		var exact = Steelapedia.exact_title(wanted)
		if exact != null:
			main.add_child(NetUI.text("Going to \"%s\"..." % exact.title, &"NetWikiMeta"))
			_redirect(_wiki_url(exact.slug))
			return
	var found := Steelapedia.search(wanted)
	_heading(main, "%d result%s" % [found.size(), "" if found.size() == 1 else "s"], 2, false)
	if found.is_empty():
		main.add_child(NetUI.text(NO_RESULTS, &"NetWikiText", true))
		return
	for entry in found:
		var item := NetUI.vbox(&"NetZeroStack")
		item.add_child(_link(entry.title, _wiki_url(entry.slug)))
		item.add_child(_rich(_inline(entry.summary)))
		item.add_child(NetUI.text(NetSites.display(_wiki_url(entry.slug)), &"NetWikiMeta"))
		main.add_child(item)


func _missing(text: String) -> void:
	page_title = "Steelapedia - Not found"
	var shown := text.replace("_", " ")
	_tabs = [["article", _url("/" + text), true], ["discussion", _url("/" + text), false]]
	_title(shown if shown != "" else "Not found")
	main.add_child(NetUI.text(MISSING, &"NetWikiText", true))
	var links := NetUI.hbox(&"NetWikiToolbar")
	links.add_child(_link("Search for \"%s\"" % shown, _url("/search", {"q": shown, "fulltext": "1"})))
	links.add_child(NetUI.text("|", &"NetWikiMeta"))
	links.add_child(_link("Main Page", _url("/")))
	main.add_child(links)
	main.set_meta("missing", true)


# ---- pieces -----------------------------------------------------------------------

# The page's title with the rule under it.
func _title(text: String) -> void:
	main.add_child(NetUI.text(text, &"NetWikiTitle", true))
	main.add_child(_rule())


func _rule() -> HSeparator:
	var node := HSeparator.new()
	node.theme_type_variation = &"NetWikiRule"
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _link(label: String, url: String) -> LinkButton:
	var node := NetUI.link(self, label, url)
	node.theme_type_variation = &"NetWikiLink"
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node


func _redirect(url: String) -> void:
	redirect = url
	follow.call_deferred(url)


# Markup to a RichTextLabel whose links work like the page's.
func _rich(bbcode: String) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.theme_type_variation = &"NetWikiBody"
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.selection_enabled = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.focus_mode = Control.FOCUS_NONE
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.text = bbcode
	node.meta_clicked.connect(_on_meta_clicked)
	node.meta_hover_started.connect(func(meta): hover(_address_of(str(meta))))
	node.meta_hover_ended.connect(func(_meta): hover(""))
	return node


func _markup(text: String) -> String:
	return SteelapediaMarkup.to_bbcode(text, _exists, _title_of)


func _inline(text: String) -> String:
	return SteelapediaMarkup.inline(text, _exists, _title_of)


func _exists(slug: String) -> bool:
	return Steelapedia.article_exists(slug)


func _title_of(slug: String) -> String:
	return Steelapedia.title_of(slug)


func _on_meta_clicked(meta) -> void:
	follow(_address_of(str(meta)))


# A link's meta as an address: wiki:<slug> on this site, net:<address>.
func _address_of(meta: String) -> String:
	if meta.begins_with(SteelapediaMarkup.WIKI):
		return _wiki_url(meta.substr(SteelapediaMarkup.WIKI.length()))
	if meta.begins_with(SteelapediaMarkup.NET):
		return meta.substr(SteelapediaMarkup.NET.length())
	return meta


func _url(page_path: String, page_query := {}) -> String:
	return NetSites.make_url(DOMAIN, page_path, page_query)


func _wiki_url(slug: String) -> String:
	return _url("/wiki/" + slug)
