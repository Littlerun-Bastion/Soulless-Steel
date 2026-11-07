class_name CallsignGenerator
extends RefCounted

## NPC callsigns as internet handles ("netizen" names), from
## database/npcs/callsigns.json. A style is picked by the file's weights:
##   word      a name from "words"                          Kestrel
##   myth      a folklore creature or spirit from "myth"    Inkanyamba
##   gamer     a word or myth name with 1-2 decorations: a prefix (one in
##             "gamer_pairs" brings its matching suffix), a suffix, light
##             leetspeak on one or two letters, odd capitals    x_Inkanyamba
##   compound  "compound_a" then "compound_b"               GreyWake
##   realname  a first and a family name in a handle's shape    AlexNorris2023
##   numbered  a lower-case word with a number or ".exe"    kestrel_04
## A callsign is at most MAX_LENGTH characters of ASCII letters, digits, "_",
## "." and "-", and has no "blocklist" word in it (any case, with leetspeak
## read back, with and without its separators). It is never one in
## `exclude` (any case), a named NPC's name, the player's callsign or a
## callsign retired on the Memorial Wall (reserved). A roll that breaks a rule
## is rolled again; after MAX_ROLLS, the last roll that was only taken gets a
## number on the end.

const DATA_PATH := "res://database/npcs/callsigns.json"
const MAX_LENGTH := 16
const MAX_ROLLS := 10
const STYLES := ["word", "myth", "gamer", "compound", "realname", "numbered"]
## The lists the generator reads; each must be a list with names.
const POOLS := ["words", "myth", "compound_a", "compound_b", "gamer_prefixes", "gamer_suffixes", "first_names",
		"last_names", "blocklist"]
const LEET := {"a": "4", "e": "3", "o": "0", "i": "1", "s": "5"}
const UNLEET := {"4": "a", "3": "e", "0": "o", "1": "i", "5": "s"}
const YEARS := [1985, 2034]
const VALID_PATTERN := "^[A-Za-z0-9_.\\-]+$"
const SEPARATORS := ["_", ".", "-"]
const TEST_NPC := "Test Dummy"
const FALLBACK := "Pilot"

## The style of the last name generate() gave (tests).
static var last_style := ""
static var _data: Dictionary = {}
static var _valid: RegEx = null
static var _shared: RandomNumberGenerator = null


## The data file, read once (a file that doesn't parse gives {}).
static func data() -> Dictionary:
	if _data.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(DATA_PATH)) == OK and json.data is Dictionary:
			_data = json.data
	return _data


## Uses `custom` instead of the file until reload_data() (tests).
static func use_data(custom: Dictionary) -> void:
	_data = custom


static func reload_data() -> void:
	_data = {}
	data()


## One callsign that breaks no rule and isn't in exclude (keys, any case).
static func generate(rng: RandomNumberGenerator, exclude: Dictionary) -> String:
	var taken := {}
	for key in exclude:
		taken[str(key).to_lower()] = true
	var spare := ""
	for i in MAX_ROLLS:
		var style := pick_style(rng)
		var name := roll(rng, style)
		if not is_allowed(name):
			continue
		if not taken.has(name.to_lower()) and not is_reserved(name):
			last_style = style
			return name
		spare = name
	if spare == "":
		spare = _pick(rng, "words")
		if not is_allowed(spare):
			spare = FALLBACK
	last_style = "numbered"
	for attempt in 1000:
		var number := str(rng.randi_range(2, 999) if attempt < 900 else rng.randi_range(1000, 999999))
		var name := spare.substr(0, MAX_LENGTH - number.length()) + number
		if is_allowed(name) and not taken.has(name.to_lower()) and not is_reserved(name):
			return name
	return FALLBACK + str(rng.randi())


## A callsign from a randomised generator of its own, for code with no rng
## (Enemy's internal name).
static func random(exclude := {}) -> String:
	if _shared == null:
		_shared = RandomNumberGenerator.new()
		_shared.randomize()
	return generate(_shared, exclude)


## A style, by the file's weights.
static func pick_style(rng: RandomNumberGenerator) -> String:
	var found = data().get("weights", {})
	var weights: Dictionary = found if found is Dictionary else {}
	var total := 0.0
	for style in STYLES:
		total += maxf(float(weights.get(style, 0)), 0.0)
	if total <= 0.0:
		return "word"
	var at := rng.randf() * total
	for style in STYLES:
		at -= maxf(float(weights.get(style, 0)), 0.0)
		if at < 0.0:
			return style
	return STYLES[-1]


## One name in a style, with no rules checked.
static func roll(rng: RandomNumberGenerator, style: String) -> String:
	if style == "myth":
		return _pick(rng, "myth")
	if style == "gamer":
		return _gamer(rng)
	if style == "compound":
		return _pick(rng, "compound_a") + _pick(rng, "compound_b")
	if style == "realname":
		return _realname(rng)
	if style == "numbered":
		var word := _pick(rng, "words").to_lower()
		var shape := rng.randi_range(0, 2)
		if shape == 0:
			return "%s_%02d" % [word, rng.randi_range(0, 99)]
		if shape == 1:
			return word + str(rng.randi_range(YEARS[0], YEARS[1]))
		return word + ".exe"
	return _pick(rng, "words")


static func _gamer(rng: RandomNumberGenerator) -> String:
	var name := _pick(rng, "myth" if rng.randf() < 0.35 else "words")
	var decorations := ["prefix", "suffix", "leet", "caps"]
	var chosen := []
	for i in rng.randi_range(1, 2):
		var left := decorations.filter(func(d): return not d in chosen)
		chosen.append(left[rng.randi_range(0, left.size() - 1)])
	if "leet" in chosen:
		name = _leet(rng, name)
	if "caps" in chosen:
		name = _odd_caps(rng, name)
	var pairs = data().get("gamer_pairs", {})
	if "prefix" in chosen:
		var prefix := _pick(rng, "gamer_prefixes")
		if prefix.ends_with("_") and prefix == prefix.to_lower() and rng.randf() < 0.5:
			name = name.to_lower()
		name = prefix + name
		if pairs is Dictionary and pairs.has(prefix) and not "suffix" in chosen:
			name += str(pairs[prefix])
	if "suffix" in chosen:
		name += _pick(rng, "gamer_suffixes")
	return name


# One or two letters swapped for the digits that look like them.
static func _leet(rng: RandomNumberGenerator, name: String) -> String:
	var spots := []
	for i in name.length():
		if LEET.has(name[i].to_lower()):
			spots.append(i)
	var out := name
	for i in mini(rng.randi_range(1, 2), spots.size()):
		var at: int = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		out = out.substr(0, at) + str(LEET[out[at].to_lower()]) + out.substr(at + 1)
	return out


# Odd capitals: the first letter and some others upper case ("ShADoW").
static func _odd_caps(rng: RandomNumberGenerator, name: String) -> String:
	var out := ""
	for i in name.length():
		var ch := name[i]
		out += ch.to_upper() if i == 0 or rng.randf() < 0.4 else ch.to_lower()
	return out


static func _realname(rng: RandomNumberGenerator) -> String:
	var first := _pick(rng, "first_names")
	var last := _pick(rng, "last_names")
	var shape := rng.randi_range(0, 5)
	if shape == 0:
		return first + last + _number(rng)
	if shape == 1:
		return "%s.%s" % [first.to_lower(), last.to_lower()]
	if shape == 2:
		return (first + last.substr(0, 1)).to_lower()
	if shape == 3:
		return first.substr(0, 1) + last
	if shape == 4:
		return "%s_%s_" % [first.to_lower(), last.to_lower()]
	return (first + last).to_lower() + "%02d" % rng.randi_range(0, 99)


# A year (YEARS) or two or three digits.
static func _number(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.5:
		return str(rng.randi_range(YEARS[0], YEARS[1]))
	return str(rng.randi_range(10, 999))


static func _pick(rng: RandomNumberGenerator, pool: String) -> String:
	var list = data().get(pool, [])
	if not list is Array or list.is_empty():
		return FALLBACK
	return str(list[rng.randi_range(0, list.size() - 1)])


# ---- rules ------------------------------------------------------------------

## Whether a name keeps the shape rules: 1 to MAX_LENGTH valid characters and
## no blocklist word.
static func is_allowed(name: String) -> bool:
	if name.is_empty() or name.length() > MAX_LENGTH:
		return false
	if _valid == null:
		_valid = RegEx.create_from_string(VALID_PATTERN)
	if _valid.search(name) == null:
		return false
	return not is_blocked(name)


## Whether a blocklist word is in the name: any case, leetspeak read back,
## with and without the separators.
static func is_blocked(name: String) -> bool:
	var plain := ""
	for ch in name.to_lower():
		plain += str(UNLEET.get(ch, ch))
	var joined := plain
	for separator in SEPARATORS:
		joined = joined.replace(separator, "")
	var blocklist = data().get("blocklist", [])
	if not blocklist is Array:
		return false
	for word in blocklist:
		var bad := str(word).to_lower()
		if bad != "" and (bad in plain or bad in joined):
			return true
	return false


## Whether a name is kept from the generator wherever it is used: a named
## NPC's, the player's callsign, or retired on the Memorial Wall (any case).
static func is_reserved(name: String) -> bool:
	var lower := name.to_lower()
	if lower == PlayerProgress.get_callsign().to_lower():
		return true
	for npc in NPCManager.SPECIAL_NPCS:
		if npc != null and str(npc.get("mecha_name")).to_lower() == lower:
			return true
	var wall = PilotNet.get("memorial")
	return wall != null and wall.is_retired(name)


## Every problem in the data file (CallsignTest fails on any).
static func check_content() -> Array:
	var errors := []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(DATA_PATH)) != OK or not json.data is Dictionary:
		return ["%s: not a JSON object" % DATA_PATH]
	var file: Dictionary = json.data
	for pool in POOLS:
		var list = file.get(pool)
		if not list is Array or list.is_empty():
			errors.append("%s: '%s' is missing or empty" % [DATA_PATH, pool])
			continue
		for entry in list:
			if not entry is String or str(entry).is_empty():
				errors.append("%s: '%s' has an entry that isn't a name" % [DATA_PATH, pool])
			elif _valid_shape(str(entry)) == false and pool != "blocklist":
				errors.append("%s: '%s' has '%s', which isn't ASCII letters, digits, _ . or -" % [DATA_PATH, pool, entry])
	var weights = file.get("weights")
	if not weights is Dictionary:
		errors.append("%s: 'weights' is missing" % DATA_PATH)
	else:
		for style in STYLES:
			if not weights.has(style):
				errors.append("%s: no weight for '%s'" % [DATA_PATH, style])
	var pairs = file.get("gamer_pairs", {})
	if not pairs is Dictionary:
		errors.append("%s: 'gamer_pairs' isn't an object" % DATA_PATH)
	return errors


static func _valid_shape(name: String) -> bool:
	if _valid == null:
		_valid = RegEx.create_from_string(VALID_PATTERN)
	return _valid.search(name) != null
