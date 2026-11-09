class_name FourXPage
extends NetPage

## FourX.net, the regional exchange, as a quote terminal: black with VT323
## like pilot.net, but a market screen in ASCII (BbsText): a title bar, a
## ticker line, function keys, tables of quotes. Its data is FourX's. Paths:
##   /               the markets: the indexes, today's movers, the groups
##   /group/<id>     every instrument in a group, by symbol
##   /q/<symbol>     a quote: the 30-day chart, key figures, and links to the
##                   maker on Steelapedia, amazing.com and its own site
##   /search?q=      symbol lookup; an exact symbol goes straight to its quote
## The title bar and the open section's key are the page's two inverted
## blocks. FourX only quotes so far; the footer says trading isn't open.

const DOMAIN := "fourx.net"
const NAME := "FOURX.NET"
const TAGLINE := "REGIONAL EXCHANGE"
const WIDTH := 108
const CHAR_WIDTH := 10
const CHART_ROWS := 12
const CHART_DAY := 3
const CHART_LABEL := 10
const MOVER_COUNT := 5
const MARKETS := "MARKETS"
const LOOKUP := "LOOKUP"
const NOTICE := "TRADING ACCOUNTS ARE NOT OPEN YET. QUOTES ARE FOR INFORMATION ONLY."
const QUOTE_COLUMNS := [{"title": "SYMBOL", "width": 6}, {"title": "NAME", "width": 25},
		{"title": "LAST", "width": 11, "align": "right"}, {"title": "CHG", "width": 9, "align": "right"},
		{"title": "CHG%", "width": 8, "align": "right"}, {"title": "30-DAY TREND", "width": 30}]

var screen: RichTextLabel
var header: RichTextLabel
var lookup_field: LineEdit = null
## Where a redirect (an exact lookup) goes, "" for none (tests).
var redirect := ""
var _lines: Array = []
var _section := ""


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	var segments := Array(page_path.split("/", false))
	var first: String = str(segments[0]).to_lower() if not segments.is_empty() else ""
	page_title = "FourX.net"
	if first == "":
		_markets()
	elif first == "group" and segments.size() == 2:
		_group(str(segments[1]).to_lower())
	elif first == "q" and segments.size() == 2:
		_quote(str(segments[1]).to_upper())
	elif first == "search":
		_lookup(str(page_query.get("q", "")))
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


## Every address the page links to (tests).
func get_links() -> Array:
	var regex := RegEx.create_from_string("\\[url=([^\\]]+)\\]")
	return regex.search_all(get_code()).map(func(m): return m.get_string(1))


# ---- pages ------------------------------------------------------------------------

func _markets() -> void:
	_section = MARKETS
	page_title = "FourX.net - Markets"
	_add(BbsText.spread(BbsText.bright("MARKETS"), BbsText.dim("%d instruments · %s close" % [FourX.instruments().size(),
			PilotNet.short_date(FourX.day())]), WIDTH))
	_add(BbsText.Seg.new())
	_add(BbsText.bright("INDEXES"))
	_add_all(_quote_table(FourX.instruments(FourX.INDEX_GROUP)))
	_add(BbsText.Seg.new())
	var moves := FourX.movers(MOVER_COUNT)
	_add_all(BbsText.beside([BbsText.box("TOP GAINERS", 53, _mover_lines(moves.gainers, 49)),
			BbsText.box("TOP LOSERS", 53, _mover_lines(moves.losers, 49))], [53, 53], 2))
	_add(BbsText.Seg.new())
	_add(BbsText.bright("GROUPS"))
	var rows := []
	for group in FourX.groups():
		if group.id == FourX.INDEX_GROUP:
			continue
		var members := FourX.instruments(str(group.id))
		var up := 0
		var down := 0
		var total := 0.0
		for entry in members:
			var shown := FourX.quote(entry.symbol)
			total += float(shown.change_pct)
			if shown.change > 0.0:
				up += 1
			elif shown.change < 0.0:
				down += 1
		var mean := total / members.size() if not members.is_empty() else 0.0
		rows.append([BbsText.cell(str(group.name), 59, "", NetSites.fourx_url("/group/" + str(group.id))),
				str(members.size()), str(up), str(down), BbsText.cell(FourX.format_pct(mean), 10, _move_style(mean), "", "right")])
	_add_all(BbsText.table([{"title": "GROUP", "width": 59}, {"title": "INSTRUMENTS", "width": 11, "align": "right"},
			{"title": "UP", "width": 6, "align": "right"}, {"title": "DOWN", "width": 6, "align": "right"},
			{"title": "AVG CHG%", "width": 10, "align": "right"}], rows))


func _mover_lines(quotes: Array, width: int) -> Array:
	var lines := []
	for shown in quotes:
		lines.append(BbsText.join([BbsText.cell(str(shown.symbol), 6, "", NetSites.quote_url(str(shown.symbol))),
				BbsText.cell(str(shown.name), width - 6 - 11 - 9, "dim"),
				BbsText.cell(FourX.format_price(float(shown.last)), 11, "", "", "right"),
				BbsText.cell(FourX.format_pct(float(shown.change_pct)), 9, _move_style(float(shown.change_pct)), "", "right")]))
	if lines.is_empty():
		lines.append(BbsText.dim("No moves today."))
	return lines


func _group(group: String) -> void:
	var members := FourX.instruments(group)
	if members.is_empty():
		_not_found()
		return
	_section = group
	var title := FourX.group_name(group)
	page_title = "FourX.net - %s" % title.capitalize()
	_add(BbsText.spread(BbsText.bright(title), BbsText.dim("%d instrument%s · %s close" % [members.size(),
			"" if members.size() == 1 else "s", PilotNet.short_date(FourX.day())]), WIDTH))
	_add(BbsText.Seg.new())
	members.sort_custom(func(a, b): return a.symbol < b.symbol)
	_add_all(_quote_table(members))


func _quote(symbol: String) -> void:
	var shown := FourX.quote(symbol)
	if shown.is_empty():
		_not_found()
		return
	var entry := FourX.get_instrument(symbol)
	_section = str(entry.group)
	page_title = "FourX.net - %s" % symbol
	_add(BbsText.spread(BbsText.join([BbsText.bright(symbol), BbsText.dim(" · "), BbsText.plain(BbsText.cut(str(entry.name), 70))]),
			BbsText.link(FourX.group_name(str(entry.group)), NetSites.fourx_url("/group/" + str(entry.group)))
			if entry.group != FourX.INDEX_GROUP else BbsText.dim(FourX.group_name(FourX.INDEX_GROUP)), WIDTH))
	var pct := float(shown.change_pct)
	_add(BbsText.spread(BbsText.join([BbsText.plain("LAST "), BbsText.bright(FourX.format_price(float(shown.last))),
			BbsText.plain("   "), BbsText.cell("%s (%s)" % [FourX.format_change(float(shown.change)), FourX.format_pct(pct)], 24,
			_move_style(pct))]), BbsText.dim("%s CLOSE" % PilotNet.short_date(FourX.day())), WIDTH))
	_add(BbsText.Seg.new())
	_add_all(BbsText.box("30-DAY CHART", WIDTH, _chart(shown.prices)))
	_add(BbsText.Seg.new())
	var first := float(shown.first)
	var figures := [
		BbsText.pair("Previous close", FourX.format_price(float(shown.prev)), 49),
		BbsText.pair("30-day high", FourX.format_price(float(shown.high)), 49),
		BbsText.pair("30-day low", FourX.format_price(float(shown.low)), 49),
		BbsText.pair("30-day change", FourX.format_pct((float(shown.last) - first) / first * 100.0 if first > 0.0 else 0.0), 49),
		BbsText.pair("Base price", FourX.format_price(float(shown.base)), 49),
		BbsText.pair("Volatility", "%.1f%%" % (float(entry.volatility) * 100.0), 49),
	]
	_add_all(BbsText.beside([BbsText.box("KEY FIGURES", 53, figures), BbsText.box("ABOUT", 53, _about(entry))], [53, 53], 2))


# The chart: CHART_DAY columns a day, the close as "#" over ":" down to the
# axis, the range on the left, the days under it.
func _chart(prices: Array) -> Array:
	var low := float(prices[0])
	var high := float(prices[0])
	for value in prices:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	var levels := []
	for value in prices:
		levels.append(0 if high <= low else int(roundf((float(value) - low) / (high - low) * (CHART_ROWS - 1))))
	var lines := []
	@warning_ignore("integer_division")
	var middle_row := (CHART_ROWS - 1) / 2
	for row in range(CHART_ROWS - 1, -1, -1):
		var label := ""
		if row == CHART_ROWS - 1:
			label = FourX.format_price(high)
		elif row == 0:
			label = FourX.format_price(low)
		elif row == middle_row:
			label = FourX.format_price((high + low) / 2.0)
		var runs := [BbsText.cell(label, CHART_LABEL, "dim", "", "right"), BbsText.dim(" |")]
		for level in levels:
			if level == row:
				runs.append(BbsText.bright("#".repeat(CHART_DAY)))
			elif level > row:
				runs.append(BbsText.dim(":".repeat(CHART_DAY)))
			else:
				runs.append(BbsText.space(CHART_DAY))
		lines.append(BbsText.join(runs))
	var axis_width := prices.size() * CHART_DAY
	lines.append(BbsText.dim(" ".repeat(CHART_LABEL + 1) + "+" + "-".repeat(axis_width)))
	var start := "%d DAYS AGO" % (prices.size() - 1)
	var end := "TODAY (%s)" % PilotNet.short_date(FourX.day())
	lines.append(BbsText.dim(" ".repeat(CHART_LABEL + 2) + start + " ".repeat(maxi(axis_width - start.length() - end.length(), 1)) + end))
	return lines


func _about(entry: Dictionary) -> Array:
	var lines := []
	if entry.is_index:
		lines.append(BbsText.dim("%d members, %s at base:" % [entry.members.size(), BbsText.thousands(int(FourX.INDEX_BASE))]))
		var row := []
		var used := 0
		for symbol in entry.members:
			if used + str(symbol).length() + 1 > 49:
				lines.append(BbsText.join(row))
				row = []
				used = 0
			row.append(BbsText.link(str(symbol), NetSites.quote_url(str(symbol))))
			row.append(BbsText.space(1))
			used += str(symbol).length() + 1
		if not row.is_empty():
			lines.append(BbsText.join(row))
	if entry.maker != "":
		lines.append(BbsText.link("%s on Steelapedia »" % BbsText.cut(Manufacturers.short_name(entry.maker), 30), NetSites.wiki_url(entry.maker)))
		lines.append(BbsText.link("Their parts on amazing.com »", NetSites.maker_url(entry.maker)))
		lines.append(BbsText.link("%s »" % Manufacturers.domain_of(entry.maker), Manufacturers.domain_of(entry.maker)))
	if entry.item != "":
		lines.append(BbsText.dim("Item value: %s CT. Selling pays %d%%." % [FourX.format_price(float(entry.base)),
				int(roundf(PlayerProgress.SELL_RATE * 100.0))]))
		lines.append(BbsText.dim("FourX prices don't change sell prices yet."))
	if str(entry.steelapedia) != "" and entry.maker == "":
		lines.append(BbsText.link("On Steelapedia »", NetSites.wiki_url(str(entry.steelapedia))))
	if lines.is_empty():
		lines.append(BbsText.dim("-"))
	return lines


func _lookup(text: String) -> void:
	_section = LOOKUP
	page_title = "FourX.net - Lookup"
	var wanted := text.strip_edges()
	_add(BbsText.bright("SYMBOL LOOKUP"))
	_add(BbsText.Seg.new())
	if wanted == "":
		_add(BbsText.dim("Type a symbol or a name in the box above and press Enter."))
		return
	var exact := FourX.get_instrument(wanted)
	if not exact.is_empty():
		_add(BbsText.dim("Going to %s..." % exact.symbol))
		redirect = NetSites.quote_url(exact.symbol)
		follow.call_deferred(redirect)
		return
	var found := FourX.search(wanted)
	_add(BbsText.dim("%d match%s for \"%s\"" % [found.size(), "" if found.size() == 1 else "es", BbsText.cut(wanted, 60)]))
	if not found.is_empty():
		_add_all(_quote_table(found))


func _not_found() -> void:
	page_title = "FourX.net - Not found"
	_add(BbsText.bright("404 -- NO SUCH PAGE ON FOURX.NET"))
	_add(BbsText.link("[F1] MARKETS", NetSites.fourx_url()))


# ---- pieces -----------------------------------------------------------------------

func _quote_table(entries: Array) -> Array:
	var rows := []
	for entry in entries:
		var shown := FourX.quote(entry.symbol)
		var pct := float(shown.change_pct)
		rows.append([BbsText.cell(entry.symbol, 6, "", NetSites.quote_url(entry.symbol)), str(entry.name),
				FourX.format_price(float(shown.last)), BbsText.cell(FourX.format_change(float(shown.change)), 9, _move_style(pct), "", "right"),
				BbsText.cell(FourX.format_pct(pct), 8, _move_style(pct), "", "right"),
				BbsText.cell(FourX.sparkline(entry.symbol, 30), 30, "dim")])
	return BbsText.table(QUOTE_COLUMNS, rows)


# Rises bright, falls dim.
func _move_style(change: float) -> String:
	return "bright" if change >= 0.0 else "dim"


func _build(search_text: String) -> void:
	var page := NetUI.panel(&"NetBbsPage")
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)
	var column := NetUI.vbox(&"NetZeroStack")
	page.add_child(column)
	header = _screen(_header_lines())
	column.add_child(header)
	column.add_child(_lookup_row(search_text))
	screen = _screen([BbsText.rule(WIDTH)] + _lines + [BbsText.Seg.new(), BbsText.rule(WIDTH),
			BbsText.spread(BbsText.dim(NOTICE), BbsText.dim("Quotes: %s close" % PilotNet.short_date(FourX.day())), WIDTH)])
	column.add_child(screen)


func _screen(lines: Array) -> RichTextLabel:
	var node := BbsText.screen(lines)
	node.meta_clicked.connect(func(meta): follow(str(meta)))
	node.meta_hover_started.connect(func(meta): hover(str(meta)))
	node.meta_hover_ended.connect(func(_meta): hover(""))
	return node


func _header_lines() -> Array:
	var title := " %s · %s" % [NAME, TAGLINE]
	var stamp := "%s CLOSE " % PilotNet.short_date(FourX.day())
	var bar := title + " ".repeat(maxi(WIDTH - title.length() - stamp.length(), 1)) + stamp
	var keys := [["F1", MARKETS, NetSites.fourx_url()]]
	for group in FourX.groups():
		if group.id != FourX.INDEX_GROUP:
			keys.append(["F%d" % (keys.size() + 1), str(group.name), NetSites.fourx_url("/group/" + str(group.id)), str(group.id)])
	keys.append(["F%d" % (keys.size() + 1), LOOKUP, NetSites.fourx_url("/search"), LOOKUP])
	var nav := []
	for key in keys:
		var label := "[%s] %s" % [key[0], key[1]]
		var id: String = key[3] if key.size() > 3 else MARKETS
		if not nav.is_empty():
			nav.append(BbsText.space(2))
		nav.append(BbsText.inverted(label, key[2]) if id == _section else BbsText.link(label, key[2]))
	return [BbsText.inverted(bar), _ticker(), BbsText.rule(WIDTH, "="), BbsText.join(nav), BbsText.rule(WIDTH)]


# The ticker: the indexes, then every maker, while they fit.
func _ticker() -> BbsText.Seg:
	var runs := []
	var used := 0
	var entries := FourX.instruments(FourX.INDEX_GROUP) + FourX.instruments(FourX.MAKER_GROUP)
	for entry in entries:
		var shown := FourX.quote(entry.symbol)
		var price := FourX.format_price(float(shown.last))
		var pct := FourX.format_pct(float(shown.change_pct))
		var cell_width: int = entry.symbol.length() + 1 + price.length() + 1 + pct.length() + 3
		if used + cell_width > WIDTH:
			break
		runs.append(BbsText.link(entry.symbol, NetSites.quote_url(entry.symbol)))
		runs.append(BbsText.plain(" " + price + " "))
		runs.append(BbsText.cell(pct, pct.length(), _move_style(float(shown.change_pct))))
		runs.append(BbsText.space(3))
		used += cell_width
	return BbsText.join(runs)


func _lookup_row(text: String) -> HBoxContainer:
	var row := NetUI.hbox(&"NetToolbar")
	row.custom_minimum_size.x = WIDTH * CHAR_WIDTH
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(NetUI.text("SYMBOL LOOKUP>", &"NetBbsLink"))
	lookup_field = NetUI.input("a symbol or a name")
	lookup_field.theme_type_variation = &"NetBbsInput"
	lookup_field.text = text
	lookup_field.context_menu_enabled = false
	lookup_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lookup_field.text_submitted.connect(_submit)
	row.add_child(lookup_field)
	var go := MechUI.button("[GO]", &"NetBbsButton")
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func(): _submit(lookup_field.text))
	row.add_child(go)
	return row


func _submit(value: String) -> void:
	if value.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	follow(NetSites.fourx_url("/search", {"q": value.strip_edges()}))


func _add(line: BbsText.Seg) -> void:
	_lines.append(line)


func _add_all(lines: Array) -> void:
	_lines.append_array(lines)
