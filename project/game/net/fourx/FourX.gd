class_name FourX
extends RefCounted

## FourX.net's market: the regional exchange's instruments and one closing
## price a day for each. The site is game/ui/net/sites/fourx/; the data guide
## is database/fourx/README.md.
##
## The instruments:
##   makers    a stock for every maker but the test one; its base price is the
##             mean price of the maker's catalogue / MAKER_DIVISOR
##   salvage   a quote for every item with a price under database/items/ (not
##             the test folder); items tagged "bio" go in the group "bio". The
##             base price is the item's price
##   the file  market.json "instruments"
##   indexes   COMPOSITE (the makers) and SALVAGE_INDEX (salvage and bio):
##             INDEX_BASE times the members' mean price over their base
## Symbols are made from the names (make_symbol); market.json "symbols" sets
## one for a maker or item id.
##
## The day is PilotNet's (one per expedition end). Each day every price takes
## one step in log terms: its drift, a pull back toward its base (reversion)
## and its volatility times a normal draw. The draw is seeded by the market's
## seed, the symbol and the day, so a profile's market is always the same.
## Events in market.json add drift and volatility to their targets while
## their story conditions pass. HISTORY_DAYS closing prices are kept for each
## instrument. A new market, or an instrument added later, starts with that
## many days made up (after BURN_IN_DAYS more that aren't kept, without events).
##
## FourX only quotes: nothing trades yet. price_factor() is the hook for a
## system that should follow the market (a sell price, say).

const DATA_PATH := "res://database/fourx/market.json"
const ITEMS_DIR := "res://database/items/"
const SKIPPED_ITEM_DIRS := ["test"]
const HISTORY_DAYS := 30
const BURN_IN_DAYS := 10
const INDEX_BASE := 1000.0
const MIN_FACTOR := 0.1
const MAX_FACTOR := 10.0
const MAKER_DIVISOR := 20.0
const MAKER_BASE_MIN := 5.0
const MAKER_BASE_MAX := 500.0
const MAKER_BASE_DEFAULT := 50.0
const INDEX_GROUP := "index"
const MAKER_GROUP := "makers"
const SALVAGE_GROUP := "salvage"
const BIO_GROUP := "bio"
const BIO_TAG := "bio"
const COMPOSITE := "FXC"
const COMPOSITE_NAME := "FourX Composite"
const SALVAGE_INDEX := "SALV"
const SALVAGE_INDEX_NAME := "Salvage Index"
const DEFAULT_GROUPS := [
	{"id": INDEX_GROUP, "name": "INDEXES"},
	{"id": MAKER_GROUP, "name": "MAKERS", "volatility": 0.025, "reversion": 0.04},
	{"id": SALVAGE_GROUP, "name": "SALVAGE", "volatility": 0.05, "reversion": 0.08},
	{"id": BIO_GROUP, "name": "BIO", "volatility": 0.07, "reversion": 0.1},
]
const DEFAULT_VOLATILITY := 0.03
const DEFAULT_REVERSION := 0.05
const FILE_KEYS := ["groups", "symbols", "instruments", "events"]
const GROUP_KEYS := ["id", "name", "volatility", "reversion", "drift"]
const INSTRUMENT_KEYS := ["symbol", "name", "group", "base", "volatility", "reversion", "drift", "requires", "steelapedia"]
const EVENT_KEYS := ["id", "requires", "targets", "drift", "volatility"]
const CONDITION_KEYS := ["reached", "not_reached", "flags"]
const GROUP_TARGET := "group:"
const SYMBOL_PATTERN := "^[A-Z0-9]{1,5}$"
## The trend line's characters, low to high.
const SPARK := ["_", ".", "-", "^"]

## The market's seed (0 until the market first starts; saved).
static var market_seed := 0
## The day of the last closing price (0: no market yet).
static var last_day := 0
## symbol -> closing prices, oldest first; the last is last_day's.
static var history: Dictionary = {}
## Problems found reading market.json.
static var load_errors: Array = []

static var _groups: Array = []
static var _symbols: Dictionary = {}       # maker or item id -> symbol (market.json)
static var _file_instruments: Array = []
static var _events: Array = []
static var _instruments: Array = []        # every instrument, indexes first
static var _by_symbol: Dictionary = {}
static var _built := false
static var _synced := false


# ---- loading ------------------------------------------------------------------

## Reads market.json and makes the instruments, once.
static func ensure_built() -> void:
	if _built:
		return
	_built = true
	_synced = false
	_read_file()
	_make_instruments()


## Reads market.json again and makes the instruments again (the debug reload:
## F9 with pilot.net's). The prices made so far stay.
static func reload_content() -> void:
	_built = false
	ensure_built()


static func _read_file() -> void:
	load_errors.clear()
	_groups = DEFAULT_GROUPS.duplicate(true)
	_symbols = {}
	_file_instruments = []
	_events = []
	var data = read_data()
	if not data is Dictionary:
		return
	var raw_groups = data.get("groups", [])
	if raw_groups is Array and not raw_groups.is_empty():
		_groups = raw_groups.filter(func(g): return g is Dictionary and str(g.get("id", "")) != "")
		for fallback in DEFAULT_GROUPS:
			if not _groups.any(func(g): return str(g.id) == fallback.id):
				_groups.append(fallback.duplicate())
	var symbols = data.get("symbols", {})
	if symbols is Dictionary:
		for key in symbols:
			if not str(key).begins_with("_"):
				_symbols[str(key)] = str(symbols[key]).to_upper()
	var listed = data.get("instruments", [])
	if listed is Array:
		_file_instruments = listed.filter(func(i): return i is Dictionary)
	var events = data.get("events", [])
	if events is Array:
		_events = events.filter(func(e): return e is Dictionary)


## market.json as data, or null (with the problem in load_errors).
static func read_data():
	if not FileAccess.file_exists(DATA_PATH):
		load_errors.append("%s: missing" % DATA_PATH)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(DATA_PATH)) != OK:
		load_errors.append("%s: line %d: %s" % [DATA_PATH, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		load_errors.append("%s: not a JSON object" % DATA_PATH)
		return null
	return json.data


static func _make_instruments() -> void:
	_instruments.clear()
	_by_symbol.clear()
	var taken := {COMPOSITE: true, SALVAGE_INDEX: true}
	var from_file := []
	for raw in _file_instruments:
		var symbol := str(raw.get("symbol", "")).to_upper()
		if symbol == "" or taken.has(symbol):
			continue
		taken[symbol] = true
		from_file.append(_instrument(symbol, str(raw.get("name", symbol)), str(raw.get("group", "other")),
				float(raw.get("base", 100.0)), raw))
	var makers := []
	for maker in Manufacturers.real_ids():
		var symbol := _claim(str(_symbols.get(maker, "")), Manufacturers.short_name(maker), taken)
		var entry := _instrument(symbol, Manufacturers.display_name(maker), MAKER_GROUP, maker_base(maker), {})
		entry.maker = maker
		entry.steelapedia = maker
		makers.append(entry)
	var salvage := []
	for item in salvage_items():
		var group := BIO_GROUP if BIO_TAG in item.tags else SALVAGE_GROUP
		var symbol := _claim(str(_symbols.get(item.id, "")), str(item.name), taken)
		var entry := _instrument(symbol, str(item.name), group, float(item.price), {})
		entry.item = item.id
		salvage.append(entry)
	var composite := _instrument(COMPOSITE, COMPOSITE_NAME, INDEX_GROUP, INDEX_BASE, {})
	composite.is_index = true
	composite.members = makers.map(func(e): return e.symbol)
	var salvage_index := _instrument(SALVAGE_INDEX, SALVAGE_INDEX_NAME, INDEX_GROUP, INDEX_BASE, {})
	salvage_index.is_index = true
	salvage_index.members = salvage.map(func(e): return e.symbol)
	for entry in [composite, salvage_index] + makers + salvage + from_file:
		_instruments.append(entry)
		_by_symbol[entry.symbol] = entry


static func _instrument(symbol: String, label: String, group: String, base: float, raw: Dictionary) -> Dictionary:
	var settings := group_settings(group)
	var conditions = raw.get("requires", {})
	return {
		"symbol": symbol, "name": label, "group": group, "base": maxf(base, 0.01),
		"volatility": float(raw.get("volatility", settings.get("volatility", DEFAULT_VOLATILITY))),
		"reversion": float(raw.get("reversion", settings.get("reversion", DEFAULT_REVERSION))),
		"drift": float(raw.get("drift", settings.get("drift", 0.0))),
		"requires": conditions if conditions is Dictionary else {},
		"steelapedia": str(raw.get("steelapedia", "")),
		"maker": "", "item": "", "members": [], "is_index": false,
	}


# The symbol market.json sets (when it's free), else one made from the name.
static func _claim(wanted: String, label: String, taken: Dictionary) -> String:
	var symbol := wanted if wanted != "" and not taken.has(wanted) else make_symbol(label, taken)
	taken[symbol] = true
	return symbol


## A maker's base price: the mean price of its catalogue / MAKER_DIVISOR,
## kept between MAKER_BASE_MIN and MAKER_BASE_MAX.
static func maker_base(maker: String) -> float:
	var products := Store.catalogue_of_maker(maker)
	if products.is_empty():
		return MAKER_BASE_DEFAULT
	var total := 0.0
	for entry in products:
		total += Store.price(entry[0], entry[1])
	return cents(clampf(total / products.size() / MAKER_DIVISOR, MAKER_BASE_MIN, MAKER_BASE_MAX))


## Every item FourX quotes: [{"id", "name", "price", "tags"}] for each item
## with a price under ITEMS_DIR (not SKIPPED_ITEM_DIRS), by id.
static func salvage_items() -> Array:
	var found := []
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return found
	for sub in dir.get_directories():
		if sub in SKIPPED_ITEM_DIRS:
			continue
		var folder := ITEMS_DIR + sub + "/"
		for file_name in DirAccess.get_files_at(folder):
			var file := str(file_name).trim_suffix(".remap")
			if not file.ends_with(".tres"):
				continue
			var item = load(folder + file)
			if item == null:
				continue
			var id = item.get("id")
			var price = item.get("price")
			if id == null or str(id) == "" or not (price is int or price is float) or price <= 0:
				continue
			var shown = item.get("display_name")
			var tags = item.get("tags")
			found.append({"id": str(id), "name": str(shown) if shown != null and str(shown) != "" else str(id),
					"price": float(price), "tags": Array(tags) if tags != null else []})
	found.sort_custom(func(a, b): return a.id < b.id)
	return found


## A three- or four-letter symbol for a name. One word gives its first letter
## and the consonants after it ("Martel": MRTL); more words give their first
## letters, then the consonants of the last word ("Acid Gland": AGLN). When
## that symbol is taken, the fourth letter becomes a digit.
static func make_symbol(label: String, taken: Dictionary) -> String:
	var words := []
	var word := ""
	for ch in label.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			word += ch
		elif word != "":
			words.append(word)
			word = ""
	if word != "":
		words.append(word)
	if words.is_empty():
		words = ["X"]
	var symbol := ""
	if words.size() == 1:
		symbol = str(words[0]).substr(0, 1) + _consonants(str(words[0]).substr(1))
	else:
		for w in words.slice(0, 4):
			symbol += str(w).substr(0, 1)
		symbol += _consonants(str(words[-1]).substr(1))
	if symbol.length() < 3:
		symbol += "".join(words).substr(1)
	symbol = symbol.substr(0, 4)
	if not taken.has(symbol):
		return symbol
	for digit in range(2, 10):
		var other := symbol.substr(0, 3) + str(digit)
		if not taken.has(other):
			return other
	var serial := 10
	while taken.has(symbol.substr(0, 2) + str(serial)):
		serial += 1
	return symbol.substr(0, 2) + str(serial)


static func _consonants(text: String) -> String:
	var out := ""
	for ch in text:
		if not ch in "AEIOU0123456789":
			out += ch
	return out


## A group's settings from market.json, {} for an unknown group.
static func group_settings(group: String) -> Dictionary:
	for entry in _groups:
		if str(entry.get("id")) == group:
			return entry
	return {}


# ---- the market ------------------------------------------------------------------

## Makes the instruments and brings the market up to PilotNet's day (a
## market with no prices yet, or one ahead of the day, starts again).
static func ensure_ready() -> void:
	ensure_built()
	var today := maxi(int(PilotNet.day), 1)
	if last_day <= 0 or market_seed == 0 or last_day > today or history.is_empty():
		_start(today)
		return
	if not _synced:
		_sync_instruments()
	while last_day < today:
		_step(last_day + 1)


## A day has passed (PilotNet calls this). A market that has started takes
## the day's step now, with the events that pass now; one that hasn't starts
## when it's first looked at.
static func note_day(_day: int) -> void:
	if last_day > 0:
		ensure_ready()


static func _start(today: int) -> void:
	if market_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		market_seed = rng.randi_range(1, 0x7fffffff)
	history = {}
	last_day = today
	for entry in _instruments:
		if not entry.is_index:
			history[entry.symbol] = _made_up_history(entry, today)
	_update_indexes()
	_synced = true


# Saved prices against the instruments as made now: an instrument that's gone
# loses its prices, a new one gets a made-up history, and every history is
# HISTORY_DAYS long.
static func _sync_instruments() -> void:
	_synced = true
	for symbol in history.keys():
		if not _by_symbol.has(symbol):
			history.erase(symbol)
	for entry in _instruments:
		if entry.is_index:
			continue
		var prices: Array = history.get(entry.symbol, [])
		if prices.is_empty():
			history[entry.symbol] = _made_up_history(entry, last_day)
			continue
		while prices.size() < HISTORY_DAYS:
			prices.push_front(prices[0])
		history[entry.symbol] = prices.slice(prices.size() - HISTORY_DAYS)
	_update_indexes()


static func _made_up_history(entry: Dictionary, end_day: int) -> Array:
	var price: float = entry.base
	var prices := []
	for step_day in range(end_day - HISTORY_DAYS - BURN_IN_DAYS + 1, end_day + 1):
		price = _next_price(entry, price, step_day, [])
		if step_day > end_day - HISTORY_DAYS:
			prices.append(price)
	return prices


static func _step(step_day: int) -> void:
	var events := active_events()
	for entry in _instruments:
		if entry.is_index:
			continue
		var prices: Array = history[entry.symbol]
		prices.append(_next_price(entry, float(prices[-1]), step_day, events))
		while prices.size() > HISTORY_DAYS:
			prices.pop_front()
	last_day = step_day
	_update_indexes()


static func _next_price(entry: Dictionary, price: float, step_day: int, events: Array) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s:%d" % [market_seed, entry.symbol, step_day]).hash()
	var drift: float = entry.drift
	var volatility: float = entry.volatility
	for event in events:
		if _targets(event, entry):
			drift += float(event.get("drift", 0.0))
			volatility += float(event.get("volatility", 0.0))
	var base: float = entry.base
	var pull: float = float(entry.reversion) * (log(base) - log(maxf(price, 0.0001)))
	var step := drift + pull + volatility * rng.randfn(0.0, 1.0)
	return cents(clampf(price * exp(step), base * MIN_FACTOR, base * MAX_FACTOR))


## The value to the cent, as the float that "%.2f" text reads back as, so a
## price saved as JSON loads as the same price.
static func cents(value: float) -> float:
	return ("%.2f" % value).to_float()


static func _update_indexes() -> void:
	for entry in _instruments:
		if not entry.is_index:
			continue
		var prices := []
		for i in HISTORY_DAYS:
			var total := 0.0
			var count := 0
			for symbol in entry.members:
				var values: Array = history.get(symbol, [])
				var at: int = values.size() - HISTORY_DAYS + i
				if at >= 0 and at < values.size():
					total += float(values[at]) / float(_by_symbol[symbol].base)
					count += 1
			prices.append(cents(INDEX_BASE * (total / count if count > 0 else 1.0)))
		history[entry.symbol] = prices


## The market.json events whose story conditions pass now.
static func active_events() -> Array:
	ensure_built()
	return _events.filter(func(e):
		var conditions = e.get("requires", {})
		return StoryDirector.meets(conditions if conditions is Dictionary else {}))


static func _targets(event: Dictionary, entry: Dictionary) -> bool:
	for target in event.get("targets", []):
		var text := str(target)
		if text.begins_with(GROUP_TARGET) and entry.group == text.substr(GROUP_TARGET.length()):
			return true
		if text.to_upper() == entry.symbol:
			return true
	return false


# ---- reading ------------------------------------------------------------------

## The instruments that show (their requires passes): a group's, or all of
## them, indexes first.
static func instruments(group := "") -> Array:
	ensure_ready()
	return _instruments.filter(func(e): return (group == "" or e.group == group) and _shows(e))


static func _shows(entry: Dictionary) -> bool:
	return entry.requires.is_empty() or StoryDirector.meets(entry.requires)


## The instrument with this symbol (any case), {} when there's none or it
## doesn't show.
static func get_instrument(symbol: String) -> Dictionary:
	ensure_ready()
	var entry: Dictionary = _by_symbol.get(symbol.strip_edges().to_upper(), {})
	return entry if not entry.is_empty() and _shows(entry) else {}


## The instrument's quote: {"symbol", "name", "group", "base", "is_index",
## "last", "prev", "change", "change_pct", "high", "low", "first", "prices"}
## (prices oldest first), {} for none.
static func quote(symbol: String) -> Dictionary:
	var entry := get_instrument(symbol)
	if entry.is_empty():
		return {}
	var prices: Array = history.get(entry.symbol, [entry.base])
	var last := float(prices[-1])
	var prev := float(prices[-2]) if prices.size() >= 2 else last
	var high := float(prices[0])
	var low := float(prices[0])
	for value in prices:
		high = maxf(high, float(value))
		low = minf(low, float(value))
	return {"symbol": entry.symbol, "name": entry.name, "group": entry.group, "base": entry.base,
			"is_index": entry.is_index, "last": last, "prev": prev, "change": last - prev,
			"change_pct": (last - prev) / prev * 100.0 if prev > 0.0 else 0.0,
			"high": high, "low": low, "first": float(prices[0]), "prices": prices.duplicate()}


## The groups with instruments that show, in market.json order: [{id, name}].
static func groups() -> Array:
	ensure_ready()
	var shown := []
	for entry in _groups:
		if not instruments(str(entry.id)).is_empty():
			shown.append({"id": str(entry.id), "name": str(entry.get("name", str(entry.id).to_upper()))})
	return shown


static func group_name(group: String) -> String:
	var entry := group_settings(group)
	return str(entry.get("name", group.to_upper())) if not entry.is_empty() else group.to_upper()


## Today's biggest moves among the instruments that aren't indexes:
## {"gainers": [quote], "losers": [quote]}, count of each at most.
static func movers(count: int) -> Dictionary:
	var quotes := []
	for entry in instruments():
		if not entry.is_index:
			quotes.append(quote(entry.symbol))
	quotes.sort_custom(func(a, b): return a.change_pct > b.change_pct)
	var gainers := quotes.filter(func(q): return q.change_pct > 0.0)
	var losers := quotes.filter(func(q): return q.change_pct < 0.0)
	losers.reverse()
	return {"gainers": gainers.slice(0, count), "losers": losers.slice(0, count)}


## The instruments whose symbol or name contains the text (any case): an
## exact symbol first, then symbols that start with it, then the rest.
static func search(text: String) -> Array:
	var wanted := text.strip_edges().to_upper()
	if wanted == "":
		return []
	var exact := []
	var starts := []
	var rest := []
	for entry in instruments():
		if entry.symbol == wanted:
			exact.append(entry)
		elif entry.symbol.begins_with(wanted):
			starts.append(entry)
		elif wanted in str(entry.name).to_upper() or wanted in entry.symbol:
			rest.append(entry)
	return exact + starts + rest


## The maker's stock symbol, "" for none.
static func symbol_of_maker(maker: String) -> String:
	ensure_built()
	for entry in _instruments:
		if entry.maker == maker and maker != "":
			return entry.symbol
	return ""


## The item's symbol, "" for none.
static func symbol_of_item(item_id: String) -> String:
	ensure_built()
	for entry in _instruments:
		if entry.item == item_id and item_id != "":
			return entry.symbol
	return ""


## The last price over the base price (1.0 at base; 1.0 for no such
## instrument). The hook for a system that should follow the market.
static func price_factor(symbol: String) -> float:
	var shown := quote(symbol)
	return shown.last / shown.base if not shown.is_empty() and shown.base > 0.0 else 1.0


## The last width closing prices as a line of SPARK characters, low to high
## between the lowest and highest of them.
static func sparkline(symbol: String, width: int) -> String:
	var shown := quote(symbol)
	if shown.is_empty() or width <= 0:
		return ""
	var prices: Array = shown.prices.slice(maxi(shown.prices.size() - width, 0))
	var low := float(prices[0])
	var high := float(prices[0])
	for value in prices:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	var line := ""
	for value in prices:
		var level := 0 if high <= low else int(roundf((float(value) - low) / (high - low) * (SPARK.size() - 1)))
		line += SPARK[level]
	return line


## The day of the last close.
static func day() -> int:
	ensure_ready()
	return last_day


## "1,234.56"
static func format_price(value: float) -> String:
	var whole := int(absf(value))
	var fraction := int(roundf((absf(value) - whole) * 100.0))
	if fraction >= 100:
		whole += 1
		fraction -= 100
	var digits := str(whole)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return "%s%s%s.%02d" % ["-" if value < 0.0 else "", digits, grouped, fraction]


## "+12.34" or "-0.80"
static func format_change(value: float) -> String:
	return ("+" if value >= 0.0 else "-") + format_price(absf(value))


## "+1.24%"
static func format_pct(value: float) -> String:
	return "%s%.2f%%" % ["+" if value >= 0.0 else "-", absf(value)]


# ---- save -------------------------------------------------------------------------

## The seed, the day and every price but the indexes' (they're made again).
static func get_save_data() -> Dictionary:
	var prices := {}
	for symbol in history:
		var entry: Dictionary = _by_symbol.get(symbol, {})
		if not entry.is_empty() and entry.is_index:
			continue
		prices[symbol] = history[symbol].duplicate()
	return {"seed": market_seed, "day": last_day, "history": prices}


static func set_save_data(data) -> void:
	reset()
	if not data is Dictionary:
		return
	market_seed = int(data.get("seed", 0))
	last_day = int(data.get("day", 0))
	var saved = data.get("history", {})
	if saved is Dictionary:
		for symbol in saved:
			if saved[symbol] is Array and not saved[symbol].is_empty():
				history[str(symbol)] = saved[symbol].map(func(p): return float(p))
	if market_seed == 0 or history.is_empty():
		last_day = 0


## A new profile: no market until it's first looked at.
static func reset() -> void:
	market_seed = 0
	last_day = 0
	history = {}
	_synced = false


# ---- content checks -----------------------------------------------------------

## Every problem in market.json (FourXTest fails on any).
static func check_content() -> Array:
	load_errors.clear()
	var data = read_data()
	var errors: Array = load_errors.duplicate()
	if data is Dictionary:
		errors.append_array(check_data(data))
	return errors


## Every problem in market.json's data: unknown keys, bad symbols and
## groups, a base that isn't above 0, events without known targets,
## conditions with unknown keys.
static func check_data(data: Dictionary) -> Array:
	var errors := []
	var where := DATA_PATH.get_file()
	for key in data:
		if not str(key).begins_with("_") and not key in FILE_KEYS:
			errors.append("%s: unknown key '%s'" % [where, key])
	var group_ids := DEFAULT_GROUPS.map(func(g): return g.id)
	for entry in data.get("groups", []):
		if not entry is Dictionary or str(entry.get("id", "")) == "":
			errors.append("%s: a group without an id" % where)
			continue
		_check_keys(errors, "%s group '%s'" % [where, entry.id], entry, GROUP_KEYS)
		group_ids.append(str(entry.id))
	var regex := RegEx.create_from_string(SYMBOL_PATTERN)
	var ids := {}
	for maker in Manufacturers.real_ids():
		ids[maker] = true
	for item in salvage_items():
		ids[item.id] = true
	var symbols = data.get("symbols", {})
	var seen := {COMPOSITE: "an index", SALVAGE_INDEX: "an index"}
	if symbols is Dictionary:
		for key in symbols:
			if str(key).begins_with("_"):
				continue
			var symbol := str(symbols[key])
			if not ids.has(str(key)):
				errors.append("%s symbols: '%s' is not a maker or item id" % [where, key])
			if regex.search(symbol) == null:
				errors.append("%s symbols: '%s' for '%s' is not 1-5 capitals or digits" % [where, symbol, key])
			if seen.has(symbol):
				errors.append("%s symbols: '%s' is used twice" % [where, symbol])
			seen[symbol] = key
	var file_symbols := {}
	for entry in data.get("instruments", []):
		if not entry is Dictionary:
			errors.append("%s: an instrument that isn't an object" % where)
			continue
		var symbol := str(entry.get("symbol", ""))
		var place := "%s instrument '%s'" % [where, symbol]
		_check_keys(errors, place, entry, INSTRUMENT_KEYS)
		if regex.search(symbol) == null:
			errors.append("%s: the symbol is not 1-5 capitals or digits" % place)
		if seen.has(symbol) or file_symbols.has(symbol):
			errors.append("%s: the symbol is used twice" % place)
		file_symbols[symbol] = true
		if str(entry.get("name", "")) == "":
			errors.append("%s: no name" % place)
		var base = entry.get("base")
		if not (base is float or base is int) or base <= 0:
			errors.append("%s: base must be a number above 0" % place)
		var group := str(entry.get("group", "other"))
		if group == INDEX_GROUP or not group in group_ids:
			errors.append("%s: group '%s' is not a group in the file" % [place, group])
		_check_conditions(errors, place, entry.get("requires", {}))
	var targets := {}
	for id in group_ids:
		targets[GROUP_TARGET + str(id)] = true
	for symbol in file_symbols:
		targets[symbol] = true
	ensure_built()
	for entry in _instruments:
		targets[entry.symbol] = true
	for entry in data.get("events", []):
		if not entry is Dictionary:
			errors.append("%s: an event that isn't an object" % where)
			continue
		var place := "%s event '%s'" % [where, str(entry.get("id", ""))]
		_check_keys(errors, place, entry, EVENT_KEYS)
		var list = entry.get("targets", [])
		if not list is Array or list.is_empty():
			errors.append("%s: no targets" % place)
		else:
			for target in list:
				var text := str(target)
				if not targets.has(text) and not targets.has(text.to_upper()):
					errors.append("%s: target '%s' is not a symbol or group:<id>" % [place, text])
		_check_conditions(errors, place, entry.get("requires", {}))
	return errors


static func _check_keys(errors: Array, where: String, data: Dictionary, known: Array) -> void:
	for key in data:
		if not str(key).begins_with("_") and not key in known:
			errors.append("%s: unknown key '%s'" % [where, key])


static func _check_conditions(errors: Array, where: String, conditions) -> void:
	if not conditions is Dictionary:
		errors.append("%s: requires is not an object" % where)
		return
	for key in conditions:
		if not key in CONDITION_KEYS:
			errors.append("%s: unknown condition '%s'" % [where, key])
