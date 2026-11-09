class_name MemorialWallPage
extends NetPage

## memorialwall.org, the Memorial Wall's pages (the records are MemorialWall,
## PilotNet.memorial), in the look of a 2003-2006 web site: a COLUMN_WIDTH
## column in the middle of a tiled ground, framed, with a hard shadow.
##   header   a glossy banded bar with the logo and a BETA badge; the
##            tagline; the nav tabs (the open section's joins the page; a
##            record or a tag is under Recently Lost)
##   page     the main column, then the side column (SIDE_WIDTH): search,
##            This week, Most remembered, the player's notice, the tag cloud
##            (causes and sites in four sizes by count; a tag too wide for the
##            column steps down a size) and the registry's stats
##   footer   the nav again, the small print, the web badges and a hit
##            counter
## Paths: / , /recent?page=, /pilot/<id>, /search?q=&page=, /tag/<cause or
## site>?page=, /about, /submit. A record page has the flickering candle
## (MemorialCandle), the Light a candle button and the player's one message.
## Every look comes from a NetMem... variation in MechTheme. Text from data
## goes through plain(), which swaps the punctuation Pixellari lacks.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const DOMAIN := "memorialwall.org"
const SITE_NAME := "The Memorial Wall"
const TAGLINE := "Remembering the pilots who did not come home."
const COLUMN_WIDTH := 760
const SIDE_WIDTH := 230
## The side boxes' room inside their margins (the tag cloud fits to it).
const SIDE_INNER := SIDE_WIDTH - 16
const TILE_SIZE := 48
const PER_PAGE := 20
const HOME_COUNT := 8
const BOX_COUNT := 5
## Page numbers shown each side of the open page.
const PAGE_LINKS := 2
const SLOT_WIDTH := 90
const MAKER_WIDTH := 190
const NUMBER_WIDTH := 44
## The nav tabs: [label, path, section].
const TABS := [["Home", "/", "home"], ["Recently Lost", "/recent", "recent"], ["Search", "/search", "search"],
		["About", "/about", "about"], ["Submit a Pilot", "/submit", "submit"]]
const SMALL_PRINT := "© 2035 The Memorial Wall · Powered by phpRegistry 2.0.4 · Valid XHTML 1.0"
## The footer's 80 x 15 web badges: [left, right].
const WEB_BADGES := [["RSS", "FEED"], ["XHTML", "1.0"], ["GET", "FIREFOX"]]
const WEB_BADGE_SIZE := Vector2(80, 15)
const COUNTER_DIGITS := 7
const HITS_BASE := 180412
const HITS_PER_DAY := 263
## The tag cloud's sizes, smallest first.
const TAG_STYLES := [&"NetMemTag1", &"NetMemTag2", &"NetMemTag3", &"NetMemTag4"]
const SUBMIT_FIELDS := ["Callsign", "Squad tag", "Where lost", "Your callsign", "Message"]
const SUBMIT_NOTE := "Submissions are moderated. Please allow 3-5 days."
const NO_RECORDS := "No pilots found."
const LIGHT_TEXT := "Light a candle"
const LIT_TEXT := "You lit a candle"
## Punctuation Pixellari has no glyph for, and what plain() puts instead.
const PLAIN := {"“": "\"", "”": "\"", "‘": "'", "’": "'", "—": "-", "–": "-",
		"…": "...", "†": "+", "™": "(TM)"}

var main: VBoxContainer
var side: VBoxContainer
var search_field: LineEdit = null
var message_field: LineEdit = null
var candle: MemorialCandle = null
var candle_button: Button = null
var candle_count_label: Label = null
## The record a /pilot/<id> page shows, {} on other pages.
var record: Dictionary = {}
var _section := ""


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	wall().ensure_started()
	var segments := Array(page_path.split("/", false))
	var first: String = str(segments[0]).to_lower() if not segments.is_empty() else ""
	var page_number := maxi(int(str(page_query.get("page", "1"))), 1)
	page_title = SITE_NAME
	main = NetUI.vbox(&"NetMemStack")
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if first == "":
		_home()
	elif first == "recent" and segments.size() == 1:
		_recent(page_number)
	elif first == "pilot" and segments.size() == 2 and str(segments[1]).is_valid_int():
		_pilot(int(str(segments[1])))
	elif first == "search" and segments.size() == 1:
		_search(str(page_query.get("q", "")), page_number)
	elif first == "tag" and segments.size() == 2:
		_tag(str(segments[1]), page_number)
	elif first == "about" and segments.size() == 1:
		_about()
	elif first == "submit" and segments.size() == 1:
		_submit()
	else:
		_not_found()
	_build()


static func wall() -> MemorialWall:
	return PilotNet.memorial


static func url(page_path := "/", page_query := {}) -> String:
	return NetSites.memorial_url(page_path, page_query)


static func record_url(id: int) -> String:
	return NetSites.memorial_record_url(id)


static func tag_url(tag: String) -> String:
	return url("/tag/" + tag)


## "#041221".
static func registry_number(entry: Dictionary) -> String:
	return "#%06d" % int(entry.get("id", 0))


## "Lost 15 Jan 2035 · Helwan".
static func lost_line(entry: Dictionary) -> String:
	return "Lost %s · %s" % [PilotNet.long_date(int(entry.day)), plain(str(entry.site))]


## "Pilot engagement. Last seen with: KESTREL", "Entity activity (Coyote)",
## "Unknown".
static func cause_line(entry: Dictionary) -> String:
	if entry.cause == "pilot":
		var seen := str(entry.get("last_seen_with", ""))
		return "Pilot engagement." + (" Last seen with: %s" % seen.to_upper() if seen != "" else "")
	if entry.cause == "entity":
		var species := str(entry.get("cause_detail", ""))
		return "Entity activity (%s)" % species if species != "" else "Entity activity"
	return "Unknown"


## Two letters for a callsign's tile: the first letters of its first two
## words (split at symbols, digits and lower-to-upper case), ignoring
## one-letter words when there are longer ones; one word gives its first
## two letters; "?" for an Unidentified pilot.
static func initials_of(callsign: String) -> String:
	if callsign == MemorialWall.UNIDENTIFIED or callsign == "":
		return "?"
	var words := []
	var current := ""
	var previous := ""
	for ch in callsign:
		var letter := ch.to_lower() != ch.to_upper()
		if not letter:
			if current != "":
				words.append(current)
			current = ""
		elif current != "" and ch == ch.to_upper() and previous == previous.to_lower():
			words.append(current)
			current = ch
		else:
			current += ch
		previous = ch
	if current != "":
		words.append(current)
	var longer := words.filter(func(w): return str(w).length() >= 2)
	if not longer.is_empty():
		words = longer
	if words.is_empty():
		return callsign.left(2).to_upper()
	if words.size() == 1:
		return str(words[0]).left(2).to_upper()
	return (str(words[0]).left(1) + str(words[1]).left(1)).to_upper()


## text with the punctuation Pixellari lacks swapped for what it has.
static func plain(text: String) -> String:
	var out := text
	for mark in PLAIN:
		out = out.replace(mark, PLAIN[mark])
	return out


## "1 candle lit", "37 candles lit".
static func candles_text(count: int) -> String:
	return "%s candle%s lit" % [BbsText.thousands(count), "" if count == 1 else "s"]


## The hit counter's count: it creeps up with the days and the candles.
static func hits() -> int:
	return HITS_BASE + int(PilotNet.day) * HITS_PER_DAY + wall().candles_lit()


## Every text on the page (tests).
func get_text() -> String:
	var bits := []
	for node in find_children("*", "", true, false):
		if node is RichTextLabel:
			bits.append(node.get_parsed_text())
		elif node is Label or node is LinkButton or node is Button:
			bits.append(node.text)
	return "\n".join(bits)


## Every address the page's links, tabs and buttons go to (tests).
func get_links() -> Array:
	var found := []
	var regex := RegEx.create_from_string("\\[url=([^\\]]+)\\]")
	for node in find_children("*", "", true, false):
		if node is RichTextLabel:
			for match_data in regex.search_all(node.text):
				found.append(match_data.get_string(1))
		elif node is BaseButton and node.has_meta("url"):
			found.append(str(node.get_meta("url")))
	return found


## Lights the player's candle on the open record: the button then reads
## LIT_TEXT and the count goes up. False if there's no record or it's lit.
func light_candle() -> bool:
	if record.is_empty() or not wall().light_candle(int(record.id)):
		return false
	candle_button.text = LIT_TEXT
	candle_button.disabled = true
	candle_count_label.text = candles_text(MemorialWall.candle_count(record))
	return true


## Posts the player's message on the open record and loads the page again;
## false (and a buzz) when it can't.
func post_message(text: String) -> bool:
	if record.is_empty() or not wall().post_message(int(record.id), text):
		AudioManager.play_sfx("deny_softer")
		return false
	follow(record_url(int(record.id)))
	return true


# ---- pages ----------------------------------------------------------------------

func _home() -> void:
	_section = "home"
	page_title = "%s - Home" % SITE_NAME
	var welcome := NetUI.vbox(&"NetMemTight")
	welcome.add_child(NetUI.text("Welcome", &"NetMemHeading"))
	welcome.add_child(_body(wall().site_text("welcome")))
	welcome.add_child(NetUI.text("Posted by %s, moderator" % plain(wall().site_text("moderator")), &"NetMemMeta", true))
	main.add_child(NetUI.panel(&"NetMemCard", welcome))
	main.add_child(_heading("Recently Lost"))
	var newest := wall().newest(HOME_COUNT)
	if newest.is_empty():
		main.add_child(NetUI.text(NO_RECORDS, &"NetMemMeta"))
	for entry in newest:
		main.add_child(_card(entry))
	main.add_child(_link("See all recently lost pilots »", url("/recent")))


func _recent(page_number: int) -> void:
	_section = "recent"
	page_title = "%s - Recently Lost" % SITE_NAME
	main.add_child(_heading("Recently Lost"))
	_record_list(wall().newest(), page_number, "/recent", {})


func _search(text: String, page_number: int) -> void:
	_section = "search"
	page_title = "%s - Search" % SITE_NAME
	main.add_child(_heading("Search the Wall"))
	var row := NetUI.hbox(&"NetMemToolbar")
	search_field = _field("Callsign, squad tag, site or part")
	search_field.text = text
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.text_submitted.connect(_submit_search)
	row.add_child(search_field)
	row.add_child(_pill("Search", func(): _submit_search(search_field.text)))
	main.add_child(row)
	var wanted := text.strip_edges()
	if wanted == "":
		main.add_child(NetUI.text("Type a callsign, a squad tag, a site or a part name.", &"NetMemMeta", true))
		return
	var found := wall().search(wanted)
	main.add_child(NetUI.text("%d pilot%s found for \"%s\"" % [found.size(), "" if found.size() == 1 else "s", plain(wanted)],
			&"NetMemMeta", true))
	_record_list(found, page_number, "/search", {"q": wanted})


func _tag(tag: String, page_number: int) -> void:
	_section = "recent"
	var cause := tag.to_lower() in MemorialWall.CAUSES
	var tag_title := plain(MemorialWall.tag_name(tag.to_lower() if cause else tag))
	page_title = "%s - %s" % [SITE_NAME, tag_title]
	main.add_child(_heading(("Lost to: %s" if cause else "Lost in: %s") % tag_title))
	_record_list(wall().tagged(tag), page_number, "/tag/" + tag, {})


func _pilot(id: int) -> void:
	_section = "recent"
	record = wall().get_record(id)
	if record.is_empty():
		page_title = "%s - Not found" % SITE_NAME
		main.add_child(NetUI.text("No pilot with that registry number", &"NetMemTitle", true))
		main.add_child(NetUI.text("The record may have been removed, or the address may be wrong.", &"NetMemBody", true))
		main.add_child(_link("Back to Recently Lost", url("/recent")))
		return
	page_title = "%s - %s" % [SITE_NAME, str(record.callsign)]
	main.add_child(_record_head())
	var words := str(record.get("last_words", ""))
	if words != "":
		main.add_child(_heading("Last words"))
		main.add_child(_quote(words))
	main.add_child(_heading("Cause"))
	main.add_child(NetUI.text(plain(cause_line(record)), &"NetMemBody", true))
	main.add_child(_heading("Last known build"))
	main.add_child(_build_table())
	if record.get("named", false):
		main.add_child(_heading("Tribute"))
		var tribute := _body(wall().tribute_of(record))
		tribute.set_meta("tribute", true)
		main.add_child(tribute)
	var comments := wall().visible_comments(record)
	main.add_child(_heading("Messages (%d)" % comments.size()))
	if comments.is_empty():
		main.add_child(NetUI.text("No messages yet.", &"NetMemMeta"))
	var rows := NetUI.vbox(&"NetZeroStack")
	for i in comments.size():
		rows.add_child(_message(i + 1, comments[i], i % 2 == 1))
	main.add_child(rows)
	main.add_child(_message_form())


func _about() -> void:
	_section = "about"
	page_title = "%s - About" % SITE_NAME
	main.add_child(_heading("About the Wall"))
	main.add_child(_body(wall().site_text("about")))
	main.add_child(NetUI.text("Posted by %s, moderator" % plain(wall().site_text("moderator")), &"NetMemMeta", true))
	main.add_child(NetUI.text("Pilots registered: %s" % BbsText.thousands(wall().registry_total()), &"NetMemBright"))


func _submit() -> void:
	_section = "submit"
	page_title = "%s - Submit a Pilot" % SITE_NAME
	main.add_child(_heading("Submit a pilot"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.theme_type_variation = &"NetMemGrid"
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	for field_name in SUBMIT_FIELDS:
		var label := NetUI.text(str(field_name) + ":", &"NetMemBody")
		label.custom_minimum_size.x = 120
		grid.add_child(label)
		var field := _field("")
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(field)
	main.add_child(grid)
	var row := NetUI.hbox(&"NetMemToolbar")
	var submit := _pill("Submit", func(): pass)
	submit.disabled = true
	submit.set_meta("submit", true)
	row.add_child(submit)
	var note := NetUI.text(SUBMIT_NOTE, &"NetMemMeta", true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	main.add_child(row)


func _not_found() -> void:
	page_title = "%s - Not found" % SITE_NAME
	main.add_child(NetUI.text("Page not found", &"NetMemTitle"))
	main.add_child(NetUI.text("The page may have moved, or the address may be wrong.", &"NetMemBody", true))
	main.add_child(_link("Go to the Memorial Wall home page", url("/")))


# Cards for list, page_number's PER_PAGE of them, then the paging links.
func _record_list(list: Array, page_number: int, list_path: String, list_query: Dictionary) -> void:
	var pages := maxi(1, ceili(list.size() / float(PER_PAGE)))
	var shown := clampi(page_number, 1, pages)
	var from := (shown - 1) * PER_PAGE
	set_meta("page", shown)
	set_meta("pages", pages)
	if list.is_empty():
		main.add_child(NetUI.text(NO_RECORDS, &"NetMemMeta"))
		return
	main.add_child(NetUI.text("Pilots %d-%d of %s" % [from + 1, mini(from + PER_PAGE, list.size()), BbsText.thousands(list.size())],
			&"NetMemMeta"))
	for entry in list.slice(from, from + PER_PAGE):
		main.add_child(_card(entry))
	if pages > 1:
		main.add_child(_paging(shown, pages, list_path, list_query))


# "« Prev 1 2 3 ... 9 Next »": the open page bright, the others links.
func _paging(shown: int, pages: int, list_path: String, list_query: Dictionary) -> HBoxContainer:
	var row := NetUI.hbox(&"NetMemToolbar")
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var page_url := func(n: int) -> String:
		var page_query: Dictionary = list_query.duplicate()
		page_query["page"] = str(n)
		return url(list_path, page_query)
	if shown > 1:
		row.add_child(_link("« Prev", page_url.call(shown - 1)))
	else:
		row.add_child(NetUI.text("« Prev", &"NetMemMeta"))
	var numbers := [1, pages]
	for n in range(shown - PAGE_LINKS, shown + PAGE_LINKS + 1):
		if n >= 1 and n <= pages and not n in numbers:
			numbers.append(n)
	numbers.sort()
	var last := 0
	for n in numbers:
		if n - last > 1:
			row.add_child(NetUI.text("...", &"NetMemMeta"))
		if n == shown:
			row.add_child(NetUI.text(str(n), &"NetMemBright"))
		else:
			row.add_child(_link(str(n), page_url.call(n)))
		last = n
	if shown < pages:
		row.add_child(_link("Next »", page_url.call(shown + 1)))
	else:
		row.add_child(NetUI.text("Next »", &"NetMemMeta"))
	return row


# ---- a record ---------------------------------------------------------------------

func _card(entry: Dictionary) -> PanelContainer:
	var row := NetUI.hbox(&"NetMemColumns")
	row.add_child(_tile(str(entry.callsign)))
	var words := NetUI.vbox(&"NetMemTight")
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HFlowContainer.new()
	name_row.theme_type_variation = &"NetMemCloud"
	name_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var link := _link(str(entry.callsign), record_url(int(entry.id)))
	link.theme_type_variation = &"NetMemCallsign"
	name_row.add_child(link)
	if str(entry.squad_tag) != "":
		var tag := NetUI.text("[%s]" % plain(str(entry.squad_tag)), &"NetMemMeta")
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_row.add_child(tag)
	words.add_child(name_row)
	words.add_child(NetUI.text(lost_line(entry), &"NetMemBody", true))
	words.add_child(NetUI.text(plain(MemorialWall.cause_text(entry)), &"NetMemMeta", true))
	row.add_child(words)
	var right := NetUI.vbox(&"NetMemTight")
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var candles := NetUI.hbox(&"NetMemToolbar")
	candles.alignment = BoxContainer.ALIGNMENT_END
	candles.add_child(MemorialCandle.new(false))
	var count := NetUI.text(BbsText.thousands(MemorialWall.candle_count(entry)), &"NetMemBright")
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	candles.add_child(count)
	right.add_child(candles)
	var messages := wall().visible_comments(entry).size()
	var messages_link := _link("%d message%s »" % [messages, "" if messages == 1 else "s"], record_url(int(entry.id)))
	messages_link.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(messages_link)
	row.add_child(right)
	var card := NetUI.panel(&"NetMemCard", row)
	card.set_meta("record", int(entry.id))
	return card


func _tile(callsign: String) -> PanelContainer:
	var initials := NetUI.text(initials_of(callsign), &"NetMemInitials")
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tile := NetUI.panel(&"NetMemTile", initials)
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return tile


# The registry number, the callsign and where it was lost; the candle, its
# button and the count on the right.
func _record_head() -> HBoxContainer:
	var row := NetUI.hbox(&"NetMemColumns")
	row.add_child(_tile(str(record.callsign)))
	var words := NetUI.vbox(&"NetMemTight")
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(NetUI.text(registry_number(record), &"NetMemRegistry"))
	words.add_child(NetUI.text(str(record.callsign), &"NetMemTitle", true))
	if str(record.squad_tag) != "":
		words.add_child(NetUI.text("Squad: [%s]" % plain(str(record.squad_tag)), &"NetMemMeta"))
	words.add_child(NetUI.text(lost_line(record), &"NetMemBody", true))
	row.add_child(words)
	var light := NetUI.vbox(&"NetMemTight")
	candle = MemorialCandle.new(true)
	light.add_child(candle)
	var lit: bool = record.get("player_candle", false)
	candle_button = MechUI.button(LIT_TEXT if lit else LIGHT_TEXT, &"NetMemPill")
	candle_button.disabled = lit
	candle_button.pressed.connect(func(): light_candle())
	light.add_child(candle_button)
	candle_count_label = NetUI.text(candles_text(MemorialWall.candle_count(record)), &"NetMemMeta")
	candle_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	light.add_child(candle_count_label)
	row.add_child(light)
	return row


# The last words between large quote marks.
func _quote(text: String) -> PanelContainer:
	var row := NetUI.hbox(&"NetMemToolbar")
	var open_mark := NetUI.text("“", &"NetMemQuoteMark")
	open_mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(open_mark)
	var line := NetUI.text(plain(text), &"NetMemBright", true)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	var close_mark := NetUI.text("”", &"NetMemQuoteMark")
	close_mark.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(close_mark)
	var box := NetUI.panel(&"NetMemQuote", row)
	box.set_meta("last_words", text)
	return box


# Slot, part (a link to its Steelapedia article) and maker, in striped rows.
func _build_table() -> VBoxContainer:
	var table := NetUI.vbox(&"NetZeroStack")
	var head := NetUI.hbox(&"NetMemToolbar")
	head.add_child(_cell(NetUI.text("Slot", &"NetMemBright"), SLOT_WIDTH))
	head.add_child(_cell(NetUI.text("Part", &"NetMemBright"), 0))
	head.add_child(_cell(NetUI.text("Maker", &"NetMemBright"), MAKER_WIDTH))
	table.add_child(NetUI.panel(&"NetMemTableHead", head))
	var count := 0
	var build: Dictionary = record.get("build", {})
	for entry in MemorialWall.BUILD_SLOTS:
		var slot: String = entry[1]
		if not build.has(slot):
			continue
		var part_type: String = entry[2]
		var part_id := str(build[slot])
		var line := NetUI.hbox(&"NetMemToolbar")
		line.add_child(_cell(NetUI.text(str(entry[0]), &"NetMemMeta"), SLOT_WIDTH))
		line.add_child(_cell(_rich(_link_code(Store.part_name(part_type, part_id), NetSites.wiki_url(part_id))), 0))
		line.add_child(_cell(NetUI.text(plain(Manufacturers.display_name(Store.maker_of(part_type, part_id))), &"NetMemBody", true),
				MAKER_WIDTH))
		var row := NetUI.panel(&"NetMemRowAlt" if count % 2 == 1 else &"NetMemRow", line)
		row.set_meta("net_part", [part_type, part_id])
		table.add_child(row)
		count += 1
	if count == 0:
		table.add_child(NetUI.panel(&"NetMemRow", NetUI.text("No build on record.", &"NetMemMeta")))
	table.set_meta("rows", count)
	return table


func _cell(content: Control, width: int) -> Control:
	if width > 0:
		content.custom_minimum_size.x = width
	else:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return content


# "#n", the message, and "posted by <author> on 15 Jan 2035 at 03:14".
func _message(number: int, comment: Dictionary, alt: bool) -> PanelContainer:
	var row := NetUI.hbox(&"NetMemColumns")
	var label := NetUI.text("#%d" % number, &"NetMemNumber")
	label.custom_minimum_size.x = NUMBER_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	var words := NetUI.vbox(&"NetMemTight")
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(NetUI.text(plain(str(comment.text)), &"NetMemBright", true))
	words.add_child(NetUI.text("posted by %s on %s at %s" % [plain(_author(str(comment.author))), PilotNet.long_date(int(comment.day)),
			str(comment.time)], &"NetMemMeta", true))
	row.add_child(words)
	var panel := NetUI.panel(&"NetMemRowAlt" if alt else &"NetMemRow", row)
	panel.set_meta("comment", number)
	return panel


func _author(author: String) -> String:
	return PlayerProgress.get_callsign() if author == MemorialWall.PLAYER_AUTHOR else author


# The player's one message: a field and Post, or a line once it's posted.
func _message_form() -> Control:
	if wall().has_player_message(int(record.id)):
		return NetUI.text("You left a message for %s." % str(record.callsign), &"NetMemMeta", true)
	var column := NetUI.vbox(&"NetMemTight")
	column.add_child(NetUI.text("Leave a message", &"NetMemHeading"))
	var row := NetUI.hbox(&"NetMemToolbar")
	message_field = _field("Your message (%d characters)" % MemorialWall.MESSAGE_LENGTH)
	message_field.max_length = MemorialWall.MESSAGE_LENGTH
	message_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_field.text_submitted.connect(func(text: String): post_message(text))
	row.add_child(message_field)
	row.add_child(_pill("Post", func(): post_message(message_field.text)))
	column.add_child(row)
	column.add_child(NetUI.text("Posting as %s" % PlayerProgress.get_callsign(), &"NetMemMeta"))
	return column


# ---- the frame ----------------------------------------------------------------------

func _build() -> void:
	var ground := NetUI.panel(&"NetMemPage")
	ground.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ground)
	var centre := NetUI.hbox(&"NetZeroRow")
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	ground.add_child(centre)
	var frame := NetUI.panel(&"NetMemColumn")
	frame.custom_minimum_size.x = COLUMN_WIDTH
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	centre.add_child(frame)
	var column := NetUI.vbox(&"NetZeroStack")
	frame.add_child(column)
	column.add_child(_header())
	column.add_child(_nav())
	var body := NetUI.hbox(&"NetMemColumns")
	body.add_child(main)
	side = _side_column()
	body.add_child(side)
	column.add_child(NetUI.panel(&"NetMemContent", body))
	column.add_child(_footer())


func _header() -> PanelContainer:
	var row := NetUI.hbox(&"NetMemToolbar")
	row.add_child(NetUI.text(SITE_NAME, &"NetMemLogo"))
	var badge := NetUI.panel(&"NetMemBadge", NetUI.text("BETA", &"NetMemBadgeText"))
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	return NetUI.panel(&"NetMemGlossy", row)


# The tagline, then the tabs; the open section's tab joins the page.
func _nav() -> PanelContainer:
	var column := NetUI.vbox(&"NetMemLines")
	column.add_child(NetUI.text(TAGLINE, &"NetMemMeta"))
	var tabs := NetUI.hbox(&"NetMemTabs")
	for tab in TABS:
		var button := MechUI.button(str(tab[0]), &"NetMemTabActive" if tab[2] == _section else &"NetMemTab")
		var target := url(str(tab[1]))
		button.set_meta("url", target)
		button.pressed.connect(follow.bind(target))
		button.mouse_entered.connect(hover.bind(target))
		button.mouse_exited.connect(hover.bind(""))
		tabs.add_child(button)
	column.add_child(tabs)
	return NetUI.panel(&"NetMemNav", column)


func _side_column() -> VBoxContainer:
	var column := NetUI.vbox(&"NetMemStack")
	column.custom_minimum_size.x = SIDE_WIDTH
	if _section != "search":
		var row := NetUI.hbox(&"NetMemToolbar")
		search_field = _field("Callsign, site, part")
		search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search_field.text_submitted.connect(_submit_search)
		row.add_child(search_field)
		row.add_child(_pill("Go", func(): _submit_search(search_field.text)))
		column.add_child(_side_box("Search", row))

	var week := wall().this_week()
	var lost := NetUI.vbox(&"NetMemTight")
	for entry in week.slice(0, BOX_COUNT):
		lost.add_child(_link(str(entry.callsign), record_url(int(entry.id))))
		lost.add_child(NetUI.text("%s · %s" % [PilotNet.long_date(int(entry.day)), plain(str(entry.site))], &"NetMemMeta", true))
	if week.is_empty():
		lost.add_child(NetUI.text("No pilots lost this week.", &"NetMemMeta", true))
	else:
		lost.add_child(_link("All %d this week »" % week.size(), url("/recent")))
	column.add_child(_side_box("This week", lost))

	var remembered := NetUI.vbox(&"NetMemTight")
	for entry in wall().most_remembered(BOX_COUNT):
		remembered.add_child(_link(str(entry.callsign), record_url(int(entry.id))))
		var messages := wall().visible_comments(entry).size()
		remembered.add_child(NetUI.text("%s · %d message%s" % [candles_text(MemorialWall.candle_count(entry)), messages,
				"" if messages == 1 else "s"], &"NetMemMeta", true))
	if wall().records.is_empty():
		remembered.add_child(NetUI.text(NO_RECORDS, &"NetMemMeta"))
	column.add_child(_side_box("Most remembered", remembered))

	var notice := wall().player_notice_lines()
	if not notice.is_empty():
		var lines := NetUI.vbox(&"NetMemTight")
		lines.add_child(NetUI.text(plain(str(notice[0])), &"NetMemBright", true))
		if str(notice[1]) != "":
			lines.add_child(NetUI.text(str(notice[1]), &"NetMemMeta", true))
		var box := NetUI.panel(&"NetMemNotice", lines)
		box.set_meta("player_notice", notice[0])
		column.add_child(box)

	column.add_child(_side_box("Causes and regions", _cloud()))

	var stats := NetUI.vbox(&"NetMemTight")
	stats.add_child(NetUI.text("Pilots registered: %s" % BbsText.thousands(wall().registry_total()), &"NetMemBody", true))
	stats.add_child(NetUI.text("Lost this week: %s" % BbsText.thousands(week.size()), &"NetMemBody", true))
	stats.add_child(NetUI.text("Candles lit: %s" % BbsText.thousands(wall().candles_lit()), &"NetMemBody", true))
	column.add_child(_side_box("Registry", stats))
	return column


func _side_box(title: String, body: Control) -> VBoxContainer:
	var box := NetUI.vbox(&"NetZeroStack")
	box.add_child(NetUI.panel(&"NetMemSideHead", NetUI.text(title, &"NetMemHeading")))
	box.add_child(NetUI.panel(&"NetMemSideBody", body))
	return box


# Every cause and site on the Wall, in A-Z order, sized by count.
func _cloud() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.theme_type_variation = &"NetMemCloud"
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	var counts := wall().tag_counts()
	var tags := counts.keys()
	tags.sort_custom(func(a, b): return MemorialWall.tag_name(str(a)).naturalnocasecmp_to(MemorialWall.tag_name(str(b))) < 0)
	var least := 0
	var most := 0
	for tag in tags:
		var count := int(counts[tag])
		least = count if least == 0 else mini(least, count)
		most = maxi(most, count)
	for tag in tags:
		var label := plain(MemorialWall.tag_name(str(tag)))
		var level := fitting_level(label, cloud_level(int(counts[tag]), least, most))
		var link := _link(label, tag_url(str(tag)))
		link.theme_type_variation = TAG_STYLES[level]
		link.set_meta("tag_level", level)
		flow.add_child(link)
	return flow


## A tag's size in the cloud, 0 to TAG_STYLES.size() - 1: where its count
## sits between the least and the most on a log scale, so one big tag
## doesn't shrink all the others; 1 when every tag has the same count.
static func cloud_level(count: int, least: int, most: int) -> int:
	if most <= least or count <= 0:
		return 1
	var share := (log(float(count)) - log(float(maxi(least, 1)))) / (log(float(most)) - log(float(maxi(least, 1))))
	return clampi(floori(share * TAG_STYLES.size()), 0, TAG_STYLES.size() - 1)


## level, or the biggest size under it whose text fits the side column.
static func fitting_level(label: String, level: int) -> int:
	var shown := level
	while shown > 0:
		var style: StringName = TAG_STYLES[shown]
		if theme_font(style).get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, theme_font_size(style)).x <= SIDE_INNER:
			break
		shown -= 1
	return shown


## A variation's font, looked up through its base types.
static func theme_font(type: StringName) -> Font:
	var look := type
	while look != &"":
		if THEME.has_font("font", look):
			return THEME.get_font("font", look)
		look = THEME.get_type_variation_base(look)
	return THEME.default_font


static func theme_font_size(type: StringName) -> int:
	var look := type
	while look != &"":
		if THEME.has_font_size("font_size", look):
			return THEME.get_font_size("font_size", look)
		look = THEME.get_type_variation_base(look)
	return THEME.default_font_size


func _footer() -> PanelContainer:
	var column := NetUI.vbox(&"NetMemLines")
	var links := NetUI.hbox(&"NetMemToolbar")
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in TABS.size():
		if i > 0:
			links.add_child(NetUI.text("|", &"NetMemMeta"))
		links.add_child(_link(str(TABS[i][0]), url(str(TABS[i][1]))))
	column.add_child(links)
	var small := NetUI.text(SMALL_PRINT, &"NetMemMeta")
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(small)
	var badges := NetUI.hbox(&"NetMemToolbar")
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in WEB_BADGES:
		badges.add_child(_web_badge(str(entry[0]), str(entry[1])))
	column.add_child(badges)
	var counter := NetUI.hbox(&"NetMemToolbar")
	counter.alignment = BoxContainer.ALIGNMENT_CENTER
	var visitors := NetUI.text("Visitors:", &"NetMemMeta")
	visitors.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	counter.add_child(visitors)
	counter.add_child(_hit_counter(hits()))
	column.add_child(counter)
	return NetUI.panel(&"NetMemFooter", column)


# An 80 x 15 web badge: two words in two bordered blocks.
func _web_badge(left: String, right: String) -> PanelContainer:
	var row := NetUI.hbox(&"NetZeroRow")
	row.add_child(NetUI.panel(&"NetMemWebBadgeLeft", NetUI.text(left, &"NetMemWebBadgeText")))
	var words := NetUI.text(right, &"NetMemWebBadgeSub")
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var right_part := NetUI.panel(&"NetMemWebBadgeRight", words)
	right_part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_part)
	var badge := NetUI.panel(&"NetMemWebBadge", row)
	badge.custom_minimum_size = WEB_BADGE_SIZE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.set_meta("web_badge", "%s %s" % [left, right])
	return badge


# The visitor count in small boxed digits.
func _hit_counter(count: int) -> PanelContainer:
	var row := NetUI.hbox(&"NetCounterRow")
	var shown := str(count).pad_zeros(COUNTER_DIGITS)
	for ch in shown:
		row.add_child(NetUI.panel(&"NetCounterDigit", NetUI.text(ch, &"NetMemBright")))
	var node := NetUI.panel(&"NetCounter", row)
	node.set_meta("digits", shown)
	return node


# ---- pieces -------------------------------------------------------------------------

func _heading(text: String) -> VBoxContainer:
	var column := NetUI.vbox(&"NetMemTight")
	column.add_child(NetUI.text(text, &"NetMemHeading", true))
	var rule := HSeparator.new()
	rule.theme_type_variation = &"NetMemRule"
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	return column


func _body(text: String) -> Label:
	return NetUI.text(plain(text), &"NetMemBody", true)


func _link(label: String, target: String) -> LinkButton:
	var node := NetUI.link(self, plain(label), target)
	node.theme_type_variation = &"NetMemLink"
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node


func _pill(label: String, action: Callable) -> Button:
	var button := MechUI.button(label, &"NetMemPill")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	return button


func _field(placeholder: String) -> LineEdit:
	var field := NetUI.input(placeholder)
	field.theme_type_variation = &"NetMemInput"
	field.context_menu_enabled = false
	return field


# BBCode in a RichTextLabel whose [url=<address>] links load (and show their
# address while the mouse is over them); it wraps, so a long name never
# widens the page.
func _rich(bbcode: String) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.theme_type_variation = &"NetMemRich"
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.selection_enabled = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.focus_mode = Control.FOCUS_NONE
	node.text = bbcode
	node.meta_clicked.connect(func(meta): follow(str(meta)))
	node.meta_hover_started.connect(func(meta): hover(str(meta)))
	node.meta_hover_ended.connect(func(_meta): hover(""))
	return node


func _link_code(text: String, target: String) -> String:
	var color := "#" + THEME.get_color("font_color", "NetMemLink").to_html(false)
	return "[url=%s][color=%s]%s[/color][/url]" % [target, color, BbsText.esc(plain(text))]


func _submit_search(value: String) -> void:
	if value.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	follow(url("/search", {"q": value.strip_edges()}))
