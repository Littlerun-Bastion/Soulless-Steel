extends TestSuite

# FourXTest: FourX.net's market (FourX) and its pages (FourXPage).
#   - market.json is valid, and the checks catch mistakes
#   - the instruments: a stock per real maker, a quote per salvage item (bio
#     ones in their group), the indexes and the file's instruments; symbols
#   - the market: HISTORY_DAYS of prices, one step a day, the same for the
#     same seed, an index as its members' mean, the price floor and ceiling,
#     events moving only their targets
#   - a new profile starts with no market; save and load
#   - the formats and the trend line; every page, the lookup redirect, the two
#     inverted blocks, pilot.net's widget linking to quotes
# Loads are instant (NetWindow.load_time_scale 0).

const SEED := 4217


func run_tests() -> void:
	await case("market.json is valid", _test_content)
	await case("the checks catch mistakes", _test_checks_catch)
	await case("the instruments", _test_instruments)
	await case("symbols", _test_symbols)
	await case("the market moves once a day", _test_days)
	await case("the same seed, the same market", _test_seed)
	await case("indexes, floor and ceiling", _test_indexes)
	await case("events move their targets", _test_events)
	await case("a new profile, save and load", _test_save)
	await case("formats and the trend line", _test_formats)
	await case("every page opens", _test_pages)
	NetWindow.load_time_scale = 1.0


func before_each() -> void:
	StoryDirector.reset(false)
	PlayerProgress.reset()
	PilotNet.reset(false)
	FourX.reload_content()
	FourX.market_seed = SEED
	MechOS.close_all()
	MechOS.set_app_available("net", false)
	NetWindow.load_time_scale = 0.0


func _net(url: String) -> NetWindow:
	MechOS.set_app_available("net", true)
	var window: NetWindow = MechOS.open_net(url)
	check(window != null, "NET opens")
	return window


func _prices() -> Dictionary:
	var out := {}
	for entry in FourX.instruments():
		out[entry.symbol] = FourX.quote(entry.symbol).prices
	return out


# ---- content ------------------------------------------------------------------

func _test_content() -> void:
	var errors := FourX.check_content()
	check(errors.is_empty(), "no problems in market.json (%s)" % "; ".join(errors))


func _test_checks_catch() -> void:
	var bad := {
		"oops": 1,
		"groups": [{"id": "other", "name": "OTHER", "speed": 2}],
		"symbols": {"nobody": "lower", "martel": "FXC"},
		"instruments": [{"symbol": "TOOLONG", "name": "", "group": "nowhere", "base": 0, "requires": {"when": 1}},
				{"symbol": "DUPE", "name": "One", "group": "other", "base": 5}, {"symbol": "DUPE", "name": "Two", "group": "other", "base": 5}],
		"events": [{"id": "e", "targets": ["group:nowhere", "NOPE"], "requires": [], "drift": 0.1, "size": 1},
				{"id": "f", "targets": []}],
	}
	var errors := " | ".join(FourX.check_data(bad))
	for wanted in ["unknown key 'oops'", "unknown key 'speed'", "'nobody' is not a maker or item id",
			"'lower' for 'nobody' is not 1-5 capitals", "'FXC' is used twice", "the symbol is not 1-5 capitals",
			"no name", "base must be a number above 0", "group 'nowhere' is not a group", "unknown condition 'when'",
			"instrument 'DUPE': the symbol is used twice", "target 'group:nowhere'", "target 'NOPE'",
			"requires is not an object", "unknown key 'size'", "event 'f': no targets"]:
		check(wanted in errors, "catches: %s" % wanted)


# ---- instruments --------------------------------------------------------------

func _test_instruments() -> void:
	var all := FourX.instruments()
	var symbols := {}
	for entry in all:
		check(not symbols.has(entry.symbol), "%s is used once" % entry.symbol)
		symbols[entry.symbol] = true
	for maker in Manufacturers.real_ids():
		var symbol := FourX.symbol_of_maker(maker)
		check(symbol != "" and FourX.get_instrument(symbol).group == FourX.MAKER_GROUP, "%s has a stock (%s)" % [maker, symbol])
	check_eq(FourX.symbol_of_maker(Manufacturers.TEST), "", "the test maker has none")
	var items := FourX.salvage_items()
	var test_ids := []
	for file_name in DirAccess.get_files_at(FourX.ITEMS_DIR + "test/"):
		var file := str(file_name).trim_suffix(".remap")
		if file.ends_with(".tres"):
			var item = load(FourX.ITEMS_DIR + "test/" + file)
			if item != null:
				test_ids.append(str(item.get("id")))
	check(not items.is_empty() and not items.any(func(i): return i.id in test_ids), "salvage items, no test items")
	for item in items:
		var entry := FourX.get_instrument(FourX.symbol_of_item(item.id))
		var group := FourX.BIO_GROUP if FourX.BIO_TAG in item.tags else FourX.SALVAGE_GROUP
		check(not entry.is_empty() and entry.group == group and is_equal_approx(float(entry.base), float(item.price)),
				"%s is quoted in %s at its price" % [item.id, group])
	var composite := FourX.get_instrument(FourX.COMPOSITE)
	check(composite.is_index and composite.members.size() == Manufacturers.real_ids().size(), "the composite holds every maker")
	var salvage := FourX.get_instrument(FourX.SALVAGE_INDEX)
	check(salvage.is_index and salvage.members.size() == items.size(), "the salvage index holds every item")
	check(not FourX.get_instrument("SMPL").is_empty(), "market.json's sample instrument")
	check_eq(FourX.instruments(FourX.INDEX_GROUP).map(func(e): return e.symbol), [FourX.COMPOSITE, FourX.SALVAGE_INDEX], "the indexes")
	var base := FourX.maker_base("martel")
	check(base >= FourX.MAKER_BASE_MIN and base <= FourX.MAKER_BASE_MAX, "a maker's base price is in range (%.2f)" % base)
	var group_ids: Array = FourX.groups().map(func(g): return g.id)
	check(group_ids.has(FourX.MAKER_GROUP) and group_ids.has(FourX.SALVAGE_GROUP) and group_ids.has(FourX.BIO_GROUP), "the groups")


func _test_symbols() -> void:
	check_eq(FourX.make_symbol("Martel", {}), "MRTL", "one word: its first letter and consonants")
	check_eq(FourX.make_symbol("Acid Gland", {}), "AGLN", "more words: their first letters, then consonants")
	check_eq(FourX.make_symbol("ARACo", {}), "ARC", "three letters when that's all there is")
	check_eq(FourX.make_symbol("Martel", {"MRTL": true}), "MRT2", "a taken symbol ends in a digit")
	check_eq(FourX.make_symbol("!!", {}), "X", "a name with no letters")
	var regex := RegEx.create_from_string(FourX.SYMBOL_PATTERN)
	check(FourX.instruments().all(func(e): return regex.search(e.symbol) != null), "every symbol is 1-5 capitals or digits")
	check(FourX.search("mrtl").size() >= 1 and FourX.search("mrtl")[0].symbol == "MRTL", "lookup finds a symbol in any case")
	check(FourX.search("gland").any(func(e): return e.item == "acid_gland"), "and a name")


# ---- the market ---------------------------------------------------------------

func _test_days() -> void:
	var first := _prices()
	check(first.values().all(func(p): return p.size() == FourX.HISTORY_DAYS), "%d prices each" % FourX.HISTORY_DAYS)
	check_eq(FourX.day(), PilotNet.day, "the market is at PilotNet's day")
	PilotNet.advance_day()
	check_eq(FourX.last_day, PilotNet.day, "a day passes: the market closes it")
	var second := _prices()
	for symbol in ["MRTL", FourX.symbol_of_item("acid_gland")]:
		check_eq(second[symbol].slice(0, FourX.HISTORY_DAYS - 1), first[symbol].slice(1), "%s's history moves on one day" % symbol)
		check_eq(second[symbol].size(), FourX.HISTORY_DAYS, "and keeps its length")
	var shown := FourX.quote("MRTL")
	check(is_equal_approx(shown.prev, float(first["MRTL"][-1])) and is_equal_approx(shown.change, shown.last - shown.prev), "the change is on the day before")
	PilotNet.day += 3
	check_eq(FourX.day(), PilotNet.day, "missed days are closed when next looked at")


func _test_seed() -> void:
	var first := _prices()
	FourX.reset()
	FourX.market_seed = SEED
	check_eq(_prices(), first, "the same seed makes the same market")
	FourX.reset()
	FourX.market_seed = SEED + 1
	check(_prices() != first, "another seed another")


func _test_indexes() -> void:
	var composite := FourX.get_instrument(FourX.COMPOSITE)
	var total := 0.0
	for symbol in composite.members:
		total += FourX.quote(symbol).last / float(FourX.get_instrument(symbol).base)
	check(is_equal_approx(snappedf(FourX.INDEX_BASE * total / composite.members.size(), 0.01), FourX.quote(FourX.COMPOSITE).last),
			"an index is its members' mean over base, times %d" % int(FourX.INDEX_BASE))
	for entry in FourX.instruments():
		var shown := FourX.quote(entry.symbol)
		if not entry.is_index:
			check(shown.low >= entry.base * FourX.MIN_FACTOR - 0.01 and shown.high <= entry.base * FourX.MAX_FACTOR + 0.01,
					"%s stays within its floor and ceiling" % entry.symbol)
	check(is_equal_approx(FourX.price_factor("MRTL"), FourX.quote("MRTL").last / float(FourX.get_instrument("MRTL").base)), "price_factor")
	check_eq(FourX.price_factor("NOPE"), 1.0, "1 for no such instrument")


func _test_events() -> void:
	FourX.ensure_ready()
	var saved := FourX.get_save_data()
	PilotNet.advance_day()
	var calm := _prices()
	FourX.set_save_data(JSON.parse_string(JSON.stringify(saved)))
	PilotNet.day -= 1
	check(FourX.active_events().is_empty(), "the sample event waits for its flag")
	StoryDirector.set_flag("sample_bio_rally", true, false)
	check_eq(FourX.active_events().size(), 1, "the sample event passes")
	PilotNet.advance_day()
	var stormy := _prices()
	var lift := 0.0
	var bio := FourX.instruments(FourX.BIO_GROUP)
	for entry in bio:
		lift += log(float(stormy[entry.symbol][-1]) / float(calm[entry.symbol][-1]))
	check(lift / bio.size() > 0.0, "it lifts its targets on average (%.3f)" % (lift / bio.size()))
	for entry in FourX.instruments(FourX.MAKER_GROUP):
		check_eq(stormy[entry.symbol], calm[entry.symbol], "%s isn't a target" % entry.symbol)


func _test_save() -> void:
	PilotNet.reset(false)
	check_eq(FourX.last_day, 0, "a new profile has no market")
	PilotNet.advance_day()
	check_eq(FourX.last_day, 0, "and doesn't make one when the day passes")
	FourX.market_seed = SEED
	var before := _prices()
	check(FourX.last_day == PilotNet.day, "until it's looked at")
	var data = JSON.parse_string(JSON.stringify(PilotNet.get_save_data()))
	check(data.has("fourx"), "saved with pilot.net's data")
	PilotNet.reset(false)
	PilotNet.set_save_data(data)
	check_eq(FourX.market_seed, SEED, "the seed comes back")
	check_eq(_prices(), before, "and the prices")
	var trimmed: Dictionary = data.fourx.duplicate(true)
	trimmed.history.erase("MRTL")
	trimmed.history["GONE"] = [1.0, 2.0]
	FourX.set_save_data(trimmed)
	check_eq(FourX.quote("MRTL").prices.size(), FourX.HISTORY_DAYS, "an instrument missing from the save gets a history")
	check(not FourX.history.has("GONE"), "one no longer in the market is dropped")


func _test_formats() -> void:
	check_eq(FourX.format_price(1234.5), "1,234.50", "a price")
	check_eq(FourX.format_price(999.999), "1,000.00", "rounded up")
	check_eq(FourX.format_change(-0.8), "-0.80", "a fall")
	check_eq(FourX.format_change(12.0), "+12.00", "a rise")
	check_eq(FourX.format_pct(1.237), "+1.24%", "a percentage")
	var line := FourX.sparkline("MRTL", 12)
	check_eq(line.length(), 12, "a trend line as wide as asked")
	var known := true
	for c in line:
		known = known and c in FourX.SPARK
	check(known, "made of the trend characters (%s)" % line)
	check_eq(BbsText.thousands(1234567), "1,234,567", "thousands")
	check_eq(BbsText.cut("abcdef", 4), "abc" + BbsText.CUT, "cutting text")
	check_eq(BbsText.wrap("one two three", 7), ["one two", "three"], "wrapping")
	check_eq(BbsText.bar(3, 6, 10), "[#####.....]", "a progress bar")


# ---- pages --------------------------------------------------------------------

func _test_pages() -> void:
	var window := _net("fourx.net/")
	var page: FourXPage = window.page
	var text := page.get_text()
	check("FOURX.NET" in text and "INDEXES" in text and "TOP GAINERS" in text and "TOP LOSERS" in text and "GROUPS" in text,
			"the markets page")
	check(FourXPage.NOTICE in text, "trading isn't open yet")
	check(page.get_code().count("[bgcolor=") <= 2, "two inverted blocks at most")
	check(page.get_links().has(NetSites.quote_url(FourX.COMPOSITE)), "the ticker links to quotes")
	var maker_symbol := FourX.symbol_of_maker("martel")
	for path in ["/", "/group/makers", "/group/salvage", "/group/bio", "/group/other", "/group/index", "/group/nothing",
			"/q/" + FourX.COMPOSITE, "/q/" + maker_symbol, "/q/" + maker_symbol.to_lower(), "/q/NOPE",
			"/search?q=gland", "/search?q=zzzz", "/search", "/nonsense"]:
		window.navigate("fourx.net" + path)
		check(window.page is FourXPage and window.page.page_title.begins_with("FourX.net"), "%s opens" % path)
		var widths: Array = Array(window.page.screen.get_parsed_text().split("\n")).map(func(l): return str(l).length())
		check(widths.max() <= FourXPage.WIDTH, "%s fits the layout (%d)" % [path, widths.max()])
	window.navigate("fourx.net/q/" + maker_symbol)
	text = window.page.get_text()
	check("30-DAY CHART" in text and "KEY FIGURES" in text and Manufacturers.display_name("martel") in text, "a quote")
	check(window.page.get_links().has(NetSites.wiki_url("martel")) and window.page.get_links().has(NetSites.maker_url("martel")),
			"linked to the maker on Steelapedia and amazing.com")
	window.navigate("fourx.net/q/NOPE")
	check("404" in window.page.get_text(), "no such symbol")
	window.navigate("fourx.net/search?q=" + maker_symbol.to_lower())
	await wait_frames(2)
	check_eq(window.current_url, NetSites.quote_url(maker_symbol), "an exact symbol goes straight to its quote")
	window.navigate("fourx.net/search?q=gland")
	await wait_frames(2)
	check(window.current_url.begins_with("fourx.net/search") and "match" in window.page.get_text(), "a name search lists matches")
	(window.page as FourXPage).lookup_field.text_submitted.emit("salvage")
	check_eq(window.current_url, "fourx.net/search?q=salvage", "the lookup box looks up")
	window.navigate("pilot.net/")
	check(window.page.get_links().has(NetSites.quote_url(FourX.COMPOSITE)), "pilot.net's market widget links to quotes")
