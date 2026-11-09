extends Node

## pilot.net's data (autoload "PilotNet"): posts, boards, world status, gigs,
## the pilots the player has met, the day, and what the player has read. It
## draws nothing: the pages (game/ui/net/sites/pilotnet/) read it and follow
## its signals. The content guide is database/pilotnet/README.md.
##
## Ways in, all ending in the same post shape:
##   A. data files: database/pilotnet/posts/*.json. A post shows while
##      StoryDirector.meets(requires) and goes away once meets(hidden_if).
##      They are checked again on every StoryDirector.state_changed.
##   B. code: post(), show_post(), hide_post(), reply().
##   C. story effects: {"pilotnet": {"show": [ids], "hide": [ids], "post": {}}}
##      in anything that goes through StoryDirector.apply_effects().
##   D. map triggers: "story:pilotnet=<id>" shows that post.
##   E. world status: database/pilotnet/world.json names story flags; the
##      front page shows their values as text.
##
## A post with "notify" that the player hasn't opened is unread: the NET tile
## counts those, and one MechLog line says it appeared. Other posts never
## count. Posts from files aren't saved (an edited file shows its new text in
## an old save); only their read state and first-seen day are.
##
## The day starts at 1 and goes up by one each time an expedition ends,
## extracted or lost. Posts are stamped with the day they first appear.
##
## Gigs are small jobs from database/pilotnet/gigs.json, apart from
## MissionManager: GIG_BOARD_SIZE open at once (rolled by weight, gone after
## GIG_LIFETIME_DAYS unless accepted), MAX_ACTIVE_GIGS accepted. Progress made
## during a run counts only once the run ends in an extraction, and adds up
## across runs. A complete gig pays when the player is next at home.
##
## The site has two looks (look()): LOOK_BBS, the text-mode board, and
## LOOK_PORTAL, the web portal. database/pilotnet/site.json's "new_look"
## conditions switch the site to the portal while they pass; look_override
## (Shift+F9 while the game runs) sets one for a test.
##
## The calendar: Day 1 is CALENDAR_START, Day n is n - 1 days later. NET
## pages show dates (date_text, short_date, stamp) where they would show a
## day number; the day stays the number underneath.
##
## The Memorial Wall's registry (memorial, a MemorialWall) lives here so it
## shares the day and the save; pilot_lost says when a record goes up.

signal posts_changed
## A post became visible for the first time.
signal post_appeared(post: Dictionary)
signal unread_changed(total: int)
signal gigs_changed
## A Memorial Wall record went up (a MemorialWall record Dictionary).
@warning_ignore("unused_signal")
signal pilot_lost(record: Dictionary)

const DATA_DIR := "res://database/pilotnet/"
const POSTS_DIR := DATA_DIR + "posts/"
const BOARDS_PATH := DATA_DIR + "boards.json"
const WORLD_PATH := DATA_DIR + "world.json"
const GIGS_PATH := DATA_DIR + "gigs.json"
const PILOTS_PATH := DATA_DIR + "pilots.json"
const SITE_PATH := DATA_DIR + "site.json"
const ITEMS_DIR := "res://database/items/"
const DIRECTOR_PATH := "res://game/expedition/ExpeditionDirector.gd"

const NEWS_BOARD := "news"
const GIGS_BOARD := "gigs"
const GIG_BOARD_SIZE := 5
const GIG_LIFETIME_DAYS := 3
const MAX_ACTIVE_GIGS := 3
const GIG_LIMIT_REASON := "GIG LIMIT REACHED (%d)"
## Kinds a kill gig may name when ExpeditionDirector can't be read.
const FALLBACK_KINDS := ["mech", "Coyote", "Coyote Spitter", "Fisher", "Tick Swarm"]
const DEBUG_ACTION := "debug_8"
const DEBUG_KEY := KEY_F9

const POST_KEYS := ["id", "board", "author", "title", "body", "requires", "hidden_if", "notify",
		"pinned", "order", "on_read", "replies", "gig"]
const REPLY_KEYS := ["author", "body", "requires"]
const CONDITION_KEYS := ["reached", "not_reached", "flags", "manual"]
const STORY_EFFECT_KEYS := ["flags", "advance"]
const EFFECT_KEY := "pilotnet"
const EFFECT_VALUE_KEYS := ["show", "hide", "post"]
const BOARD_KEYS := ["id", "name", "blurb", "requires"]
const WORLD_KEYS := ["label", "values", "default", "requires"]
const GIG_KEYS := ["id", "title", "type", "kind", "kind_plural", "item", "item_name", "count", "reward",
		"reputation", "weight", "requires", "poster"]
const GIG_TYPES := ["kill", "extract", "extract_with"]
const GIG_TITLE_TAGS := ["count", "kind", "kind_plural", "item"]
const PILOT_KEYS := ["affiliation", "bio", "requires", "steelapedia"]
const SITE_KEYS := ["new_look"]
const NEW_LOOK_KEYS := ["requires", "notice"]
const LOOK_BBS := "bbs"
const LOOK_PORTAL := "portal"
## Day 1's date (YYYY-MM-DD).
const CALENDAR_START := "2035-01-01"
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const SECONDS_PER_DAY := 86400

var day := 1
## The Memorial Wall's registry.
var memorial := MemorialWall.new()
var autosave := true
## site.json: which look the site has.
var site: Dictionary = {}
## A look that replaces site.json's choice ("" for none). Not saved.
var look_override := ""
## Draws every gig roll; tests seed it.
var rng := RandomNumberGenerator.new()

var boards: Array = []
var world: Dictionary = {}       # flag -> {label, values, default, requires}
var gig_templates: Array = []
var pilots: Dictionary = {}      # callsign -> profile
## Problems found while loading the data files (PilotNetTest reports them).
var load_errors: Array = []

var _file_posts: Dictionary = {}  # id -> post, in file order
var _pushed: Dictionary = {}      # id -> post from post()
var _shown: Dictionary = {}       # id -> true (show_post)
var _hidden: Dictionary = {}      # id -> true (hide_post)
var _extra_replies: Dictionary = {}  # post id -> [reply] from reply()
var _first_seen: Dictionary = {}  # id -> day
var _read: Dictionary = {}        # id -> true
var _visible: Dictionary = {}     # id -> true, as of the last refresh
var _unread := 0
var _loaded := false

var gigs: Array = []              # open, active and complete gigs (Dictionaries)
var gigs_completed := 0
var _gig_serial := 0
var _post_gigs: Dictionary = {}   # post id -> gig id taken from that post
var _run_progress: Dictionary = {}  # gig id -> progress this run, not yet kept
var _kinds: Array = []
var _item_names: Dictionary = {}
var _board_filled := false

var met: Dictionary = {}          # callsign -> the day last seen


func _ready() -> void:
	rng.randomize()
	_ensure_debug_action()
	ensure_loaded()
	StoryDirector.register_effect(EFFECT_KEY, apply_effect)
	StoryDirector.state_changed.connect(_on_story_changed)
	PlayerProgress.expedition_started.connect(_on_expedition_started)
	PlayerProgress.expedition_extracted.connect(_on_expedition_extracted)
	PlayerProgress.expedition_lost.connect(_on_expedition_lost)
	_refresh(false)


## F9: reads pilot.net's, Steelapedia's and FourX's files again (so an edited
## file shows without a restart) and prints every post, shown or not, and why.
## Shift+F9: the next look override instead (none, portal, bbs, none...).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(DEBUG_ACTION):
		if event is InputEventKey and event.shift_pressed:
			cycle_look_override()
			return
		reload_content()
		Steelapedia.reload_articles()
		FourX.reload_content()
		memorial.reload_content()
		_refresh()
		print(get_debug_text())


# ---- loading --------------------------------------------------------------

## Loads the data files once (also on first use, before _ready).
func ensure_loaded() -> void:
	if not _loaded:
		reload_content()


## Reads every data file again (posts, boards, world, gigs, pilots).
func reload_content() -> void:
	_loaded = true
	load_errors.clear()
	_file_posts.clear()
	for path in post_files():
		var data = read_json(path)
		var list = data.get("posts", []) if data is Dictionary else data
		if not list is Array:
			load_errors.append("%s: no list of posts" % path)
			continue
		for raw in list:
			if not raw is Dictionary or str(raw.get("id", "")) == "":
				load_errors.append("%s: a post without an id" % path)
				continue
			var entry := _normal_post(raw, "file")
			if _file_posts.has(entry.id):
				load_errors.append("%s: post id '%s' is used twice" % [path, entry.id])
				continue
			entry["file"] = path.get_file()
			_file_posts[entry.id] = entry
	var board_data = read_json(BOARDS_PATH)
	boards = board_data.get("boards", []) if board_data is Dictionary else []
	var world_data = read_json(WORLD_PATH)
	world = {}
	if world_data is Dictionary:
		for key in world_data:
			if not str(key).begins_with("_") and world_data[key] is Dictionary:
				world[key] = world_data[key]
	var gig_data = read_json(GIGS_PATH)
	gig_templates = gig_data.get("gigs", []) if gig_data is Dictionary else []
	var pilot_data = read_json(PILOTS_PATH)
	pilots = {}
	if pilot_data is Dictionary:
		for key in pilot_data:
			if not str(key).begins_with("_") and pilot_data[key] is Dictionary:
				pilots[key] = pilot_data[key]
	var site_data = read_json(SITE_PATH)
	site = site_data if site_data is Dictionary else {}


## Every .json file in the posts folder, A-Z.
func post_files() -> Array:
	var files := []
	var dir := DirAccess.open(POSTS_DIR)
	if dir == null:
		return files
	for file_name in dir.get_files():
		var entry := str(file_name).trim_suffix(".remap")
		if entry.ends_with(".json"):
			files.append(POSTS_DIR + entry)
	files.sort()
	return files


## A JSON file's data, or null when it is missing or doesn't parse.
func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		load_errors.append("%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _normal_post(raw: Dictionary, source: String) -> Dictionary:
	var entry := raw.duplicate(true)
	entry["id"] = str(raw.get("id", ""))
	entry["board"] = str(raw.get("board", ""))
	entry["author"] = str(raw.get("author", ""))
	entry["title"] = str(raw.get("title", ""))
	entry["body"] = str(raw.get("body", ""))
	for key in ["requires", "hidden_if", "on_read"]:
		if not entry.get(key) is Dictionary:
			entry[key] = {}
	if not entry.get("replies") is Array:
		entry["replies"] = []
	entry["notify"] = bool(raw.get("notify", false))
	entry["pinned"] = bool(raw.get("pinned", false))
	entry["order"] = int(raw.get("order", 0))
	entry["gig"] = str(raw.get("gig", ""))
	entry["source"] = source
	return entry


# ---- posts ------------------------------------------------------------------

## A post by id, visible or not ({} if there's none). Gigs are posts too
## ("gig:<gig id>" on the GIGS board); the board lists only the open ones.
func get_post(id: String) -> Dictionary:
	ensure_loaded()
	if _pushed.has(id):
		return _pushed[id]
	if _file_posts.has(id):
		return _file_posts[id]
	if id.begins_with("gig:"):
		var gig := get_gig(id.substr(4))
		if not gig.is_empty():
			return _gig_post(gig)
	return {}


func post_exists(id: String) -> bool:
	return not get_post(id).is_empty()


## Every post id, files first (in file order), then posts from code, then
## open gigs.
func all_ids() -> Array:
	ensure_loaded()
	var ids: Array = _file_posts.keys()
	for id in _pushed:
		if not _file_posts.has(id):
			ids.append(id)
	for gig in gigs:
		if gig.state == "open":
			ids.append("gig:" + gig.id)
	return ids


func is_post_visible(id: String) -> bool:
	return why_hidden(id) == ""


## "" when the post shows, else why not (for the debug list).
func why_hidden(id: String) -> String:
	var post_data := get_post(id)
	if post_data.is_empty():
		return "no such post"
	if _hidden.has(id):
		return "hidden by hide_post"
	if not post_data.hidden_if.is_empty() and StoryDirector.meets(post_data.hidden_if):
		return "hidden_if passes %s" % JSON.stringify(post_data.hidden_if)
	if not _shown.has(id) and not meets(post_data.requires):
		return "requires fails %s" % JSON.stringify(post_data.requires)
	if post_data.source == "file" and not board_visible(post_data.board):
		return "board '%s' is hidden" % post_data.board
	return ""


## StoryDirector.meets, except that {"manual": true} never passes by itself
## (only show_post shows such a post).
func meets(conditions: Dictionary) -> bool:
	if conditions.get("manual", false):
		return false
	return StoryDirector.meets(conditions)


## The visible posts of a board ("" = every board): pinned first, then the
## newest first-seen day, then "order"; posts added later before earlier
## ones on a tie.
func visible_posts(board_id := "") -> Array:
	var ids := all_ids()
	var result := []
	for i in ids.size():
		var entry := get_post(ids[i])
		if (board_id == "" or entry.board == board_id) and is_post_visible(ids[i]):
			result.append({"post": entry, "seq": i})
	result.sort_custom(func(a, b):
		if a.post.pinned != b.post.pinned:
			return a.post.pinned
		var da := first_seen_day(a.post.id)
		var db := first_seen_day(b.post.id)
		if da != db:
			return da > db
		if a.post.order != b.post.order:
			return a.post.order < b.post.order
		return a.seq > b.seq)
	return result.map(func(e): return e.post)


## The newest visible posts of a board, not counting pinned ones first.
func latest(board_id: String, count: int) -> Array:
	var posts := visible_posts(board_id)
	posts.sort_custom(func(a, b):
		var da := first_seen_day(a.id)
		var db := first_seen_day(b.id)
		if da != db:
			return da > db
		return a.order < b.order)
	return posts.slice(0, count)


## Visible posts whose title or body contain text, any case.
func search(text: String) -> Array:
	var wanted := text.strip_edges().to_lower()
	if wanted == "":
		return []
	return visible_posts().filter(func(p):
		return wanted in fill_tags(p.title).to_lower() or wanted in fill_tags(p.body).to_lower())


## The visible posts by a pilot (by callsign; "{player}" posts are the
## player's).
func posts_by(callsign: String) -> Array:
	return visible_posts().filter(func(p): return author_name(p).to_lower() == callsign.to_lower())


## How many visible posts and replies the pilot wrote.
func post_count(callsign: String) -> int:
	var wanted := callsign.to_lower()
	var total := 0
	for post_data in visible_posts():
		if author_name(post_data).to_lower() == wanted:
			total += 1
		for reply_data in visible_replies(post_data.id):
			if fill_tags(str(reply_data.get("author", ""))).to_lower() == wanted:
				total += 1
	return total


## The author's callsign as shown, with {player} filled in.
func author_name(post_data: Dictionary) -> String:
	var author := str(post_data.get("author", ""))
	return fill_tags(author) if author != "" else "SYSOP"


## The day the post first appeared (the current day if it hasn't yet).
func first_seen_day(id: String) -> int:
	return int(_first_seen.get(id, day))


## A time of day made from the id ("03:14"), the same every time.
func post_time(id: String) -> String:
	var h := absi(id.hash())
	@warning_ignore("integer_division")
	return "%02d:%02d" % [h % 24, (h / 24) % 60]


## The post's replies the story allows now: its own, then those from reply().
func visible_replies(id: String) -> Array:
	var all: Array = get_post(id).get("replies", []).duplicate()
	all.append_array(_extra_replies.get(id, []))
	return all.filter(func(r): return r is Dictionary and meets(r.get("requires", {})))


# ---- ways in (B and C) ---------------------------------------------------------

## Adds a post at run time (the post schema; saved). The same id again
## replaces it.
func post(new_post: Dictionary) -> void:
	ensure_loaded()
	if str(new_post.get("id", "")) == "":
		push_error("PilotNet.post: a post needs an id")
		return
	var post_data := _normal_post(new_post, "code")
	_pushed[post_data.id] = post_data
	_hidden.erase(post_data.id)
	_changed()


## Shows a post even when its requires doesn't pass (saved).
func show_post(id: String) -> void:
	if not post_exists(id):
		push_warning("PilotNet.show_post: no post '%s'" % id)
	_shown[id] = true
	_hidden.erase(id)
	_changed()


## Hides any post (saved).
func hide_post(id: String) -> void:
	_hidden[id] = true
	_changed()


## Adds a reply to a thread (saved): {"author", "body", "requires"}.
func reply(post_id: String, new_reply: Dictionary) -> void:
	if not _extra_replies.has(post_id):
		_extra_replies[post_id] = []
	_extra_replies[post_id].append(new_reply.duplicate(true))
	_changed()


## The "pilotnet" story effect: {"show": [ids], "hide": [ids], "post": {}},
## or a post id (from a "story:pilotnet=<id>" map trigger) to show.
func apply_effect(value) -> void:
	if value is String:
		show_post(value)
		return
	if not value is Dictionary:
		push_error("PilotNet: the pilotnet effect wants a Dictionary or a post id, got %s" % str(value))
		return
	for id in value.get("show", []):
		show_post(str(id))
	for id in value.get("hide", []):
		hide_post(str(id))
	if value.get("post") is Dictionary:
		post(value.post)


# ---- reading ------------------------------------------------------------------

## The player opened a post: it's read, and its on_read effects run (once).
func open_post(id: String) -> void:
	if _read.has(id) or not post_exists(id):
		return
	_read[id] = true
	var effects: Dictionary = get_post(id).get("on_read", {})
	if not effects.is_empty():
		StoryDirector.apply_effects(effects)
	_changed()


func is_read(id: String) -> bool:
	return _read.has(id)


## Unread: a visible notify post the player hasn't opened.
func unread_count() -> int:
	return _unread


## *NEW*: a visible post the player hasn't opened.
func is_new(id: String) -> bool:
	return not _read.has(id)


# ---- boards and world ---------------------------------------------------------

func get_board(id: String) -> Dictionary:
	ensure_loaded()
	for board in boards:
		if board is Dictionary and str(board.get("id")) == id:
			return board
	return {}


func board_visible(id: String) -> bool:
	var board := get_board(id)
	return not board.is_empty() and meets(board.get("requires", {}))


func visible_boards() -> Array:
	ensure_loaded()
	return boards.filter(func(b): return b is Dictionary and meets(b.get("requires", {})))


## The WORLD STATUS lines that show: [{"flag", "label", "text"}].
func world_lines() -> Array:
	ensure_loaded()
	var lines := []
	for flag in world:
		var entry: Dictionary = world[flag]
		if meets(entry.get("requires", {})):
			lines.append({"flag": flag, "label": str(entry.get("label", flag)), "text": world_text(flag)})
	return lines


## A world-status flag's value as text: its entry's text for the value, or
## the raw value when there's none.
func world_text(flag: String) -> String:
	ensure_loaded()
	var entry: Dictionary = world.get(flag, {})
	var key := value_key(StoryDirector.get_flag(flag, entry.get("default", null)))
	var values: Dictionary = entry.get("values", {})
	return str(values[key]) if values.has(key) else key


## A flag value as a world.json key: true -> "true", 2.0 -> "2".
static func value_key(value) -> String:
	if value == null:
		return ""
	if value is bool:
		return "true" if value else "false"
	if value is float and is_equal_approx(value, roundf(value)):
		return str(int(value))
	return str(value)


# ---- text tags ----------------------------------------------------------------

## Fills {player}, {day}, {date}, {flag:name} and {world:name}; any other
## {tag} stays.
func fill_tags(text: String) -> String:
	if not "{" in text:
		return text
	var out := text.replace("{player}", PlayerProgress.get_callsign()).replace("{day}", str(day)) \
			.replace("{date}", date_text(day))
	var regex := RegEx.create_from_string("\\{(flag|world):([^{}\\s]+)\\}")
	for found in regex.search_all(out):
		var kind := found.get_string(1)
		var tag_name := found.get_string(2)
		var filled := value_key(StoryDirector.get_flag(tag_name)) if kind == "flag" else world_text(tag_name)
		out = out.replace(found.get_string(), filled)
	return out


## The {tags} in text that fill_tags doesn't know.
func unknown_tags(text: String) -> Array:
	var unknown := []
	var regex := RegEx.create_from_string("\\{([^{}\\s]*)\\}")
	for found in regex.search_all(text):
		var tag := found.get_string(1)
		if tag == "player" or tag == "day" or tag == "date" or tag.begins_with("flag:") or tag.begins_with("world:"):
			continue
		unknown.append(found.get_string())
	return unknown


# ---- the calendar -------------------------------------------------------------

## A day's date: {"year", "month", "day", "weekday" (0 = Sunday)}.
static func date_of(day_number: int) -> Dictionary:
	var start := Time.get_unix_time_from_datetime_string(CALENDAR_START)
	return Time.get_datetime_dict_from_unix_time(start + (day_number - 1) * SECONDS_PER_DAY)


## "Mon 15 Jan 2035"
func date_text(day_number: int) -> String:
	var date := date_of(day_number)
	return "%s %d %s %d" % [WEEKDAYS[int(date.weekday)], int(date.day), MONTHS[int(date.month) - 1], int(date.year)]


## "15/01/2035"
func short_date(day_number: int) -> String:
	var date := date_of(day_number)
	return "%02d/%02d/%d" % [int(date.day), int(date.month), int(date.year)]


## "15 Jan 2035"
func long_date(day_number: int) -> String:
	var date := date_of(day_number)
	return "%d %s %d" % [int(date.day), MONTHS[int(date.month) - 1], int(date.year)]


## "15 Jan 2035 · 03:14": a date and a time of day, as the early-2000s
## pages print them.
func stamp(day_number: int, time: String) -> String:
	return "%s · %s" % [long_date(day_number), time]


# ---- the look -----------------------------------------------------------------

## The site's look now: look_override when it's set, else LOOK_PORTAL while
## site.json's "new_look" conditions pass, else LOOK_BBS.
func look() -> String:
	if look_override == LOOK_BBS or look_override == LOOK_PORTAL:
		return look_override
	ensure_loaded()
	var new_look = site.get("new_look")
	if new_look is Dictionary:
		var conditions = new_look.get("requires", {})
		if conditions is Dictionary and meets(conditions):
			return LOOK_PORTAL
	return LOOK_BBS


## The new look's notice line (site.json), tags filled; "" for none.
func look_notice() -> String:
	var new_look = site.get("new_look")
	return fill_tags(str(new_look.get("notice", ""))) if new_look is Dictionary else ""


## The next look override: none, the portal, the board, none... and prints
## the look (Shift+F9).
func cycle_look_override() -> void:
	var order := ["", LOOK_PORTAL, LOOK_BBS]
	look_override = order[(order.find(look_override) + 1) % order.size()]
	print("pilot.net look: %s (%s)" % [look(), "forced" if look_override != "" else "from site.json"])


# ---- refresh and unread -------------------------------------------------------

func _on_story_changed() -> void:
	_refresh()


func _changed() -> void:
	_refresh()
	_save()


# Works out which posts show. A post seen for the first time gets the day
# (and, with announce, post_appeared and a MechLog line if it notifies).
func _refresh(announce := true) -> void:
	ensure_loaded()
	var now_visible := {}
	for id in all_ids():
		if is_post_visible(id):
			now_visible[id] = true
			if announce and not _first_seen.has(id):
				_first_seen[id] = day
				var post_data := get_post(id)
				post_appeared.emit(post_data)
				if post_data.notify:
					MechLog.write("NET", "New on pilot.net: %s" % fill_tags(post_data.title))
	var changed := now_visible.hash() != _visible.hash()
	_visible = now_visible
	_update_unread()
	Steelapedia.note_visible(day)
	if changed:
		posts_changed.emit()


func _update_unread() -> void:
	var total := 0
	for id in _visible:
		if get_post(id).get("notify", false) and not _read.has(id):
			total += 1
	if total != _unread:
		_unread = total
		unread_changed.emit(total)
	if is_instance_valid(MechOS) and MechOS.get("taskbar") != null:
		MechOS.taskbar.set_badge("net", total)


# ---- the day ------------------------------------------------------------------

## One day passes: old open gigs go, new ones fill the board, the Memorial
## Wall puts up the day's losses, FourX closes the day.
func advance_day() -> void:
	day += 1
	expire_gigs()
	fill_board()
	memorial.on_new_day(day)
	_refresh()
	FourX.note_day(day)


func _on_expedition_started() -> void:
	_run_progress.clear()
	memorial.note_deployed()


func _on_expedition_extracted() -> void:
	for gig in active_gigs():
		var progress := int(gig.progress) + int(_run_progress.get(gig.id, 0))
		if gig.type == "extract":
			progress += 1
		elif gig.type == "extract_with":
			progress = maxi(progress, cargo_count(str(gig.item)))
		gig.progress = mini(progress, int(gig.count))
		if gig.progress >= int(gig.count):
			gig.state = "complete"
			MechLog.write("NET", "Gig complete: %s" % gig.title, MechLog.Kind.LOOT)
	_run_progress.clear()
	advance_day()
	gigs_changed.emit()
	pay_completed()
	_save()


func _on_expedition_lost(_report) -> void:
	_run_progress.clear()
	memorial.note_player_lost()
	advance_day()
	gigs_changed.emit()
	_save()


# ---- gigs ---------------------------------------------------------------------

func get_gig(id: String) -> Dictionary:
	for gig in gigs:
		if gig.id == id:
			return gig
	return {}


## The open gigs. The board is first filled here, not at start-up: rolling
## reads ExpeditionDirector (spawnable_kinds), which loads Entity scenes.
func open_gigs() -> Array:
	if not _board_filled:
		_board_filled = true
		fill_board()
	return gigs.filter(func(g): return g.state == "open")


func active_gigs() -> Array:
	return gigs.filter(func(g): return g.state == "active")


## Complete, waiting to be paid when the player is next at home.
func complete_gigs() -> Array:
	return gigs.filter(func(g): return g.state == "complete")


func get_template(id: String) -> Dictionary:
	ensure_loaded()
	for template in gig_templates:
		if template is Dictionary and str(template.get("id")) == id:
			return template
	return {}


## Why the player can't accept another gig now; "" when they can.
func accept_block_reason() -> String:
	if active_gigs().size() >= MAX_ACTIVE_GIGS:
		return GIG_LIMIT_REASON % MAX_ACTIVE_GIGS
	return ""


func accept_gig(id: String) -> bool:
	var gig := get_gig(id)
	if gig.is_empty() or gig.state != "open" or accept_block_reason() != "":
		return false
	gig.state = "active"
	MechLog.write("NET", "Gig accepted: %s" % gig.title)
	gigs_changed.emit()
	_changed()
	return true


## Takes up the gig a post offers ("gig": template id): a gig is rolled from
## the template and accepted at once. Once per post.
func accept_post_gig(post_id: String) -> bool:
	var post_data := get_post(post_id)
	var template := get_template(str(post_data.get("gig", "")))
	if template.is_empty() or _post_gigs.has(post_id) or accept_block_reason() != "":
		return false
	var gig := roll_gig(template)
	gig.state = "active"
	gig["post"] = post_id
	gigs.append(gig)
	_post_gigs[post_id] = gig.id
	MechLog.write("NET", "Gig accepted: %s" % gig.title)
	gigs_changed.emit()
	_changed()
	return true


## The gig taken from a post, {} if none.
func gig_of_post(post_id: String) -> Dictionary:
	return get_gig(str(_post_gigs.get(post_id, "")))


## Drops an accepted gig, with no penalty.
func abandon_gig(id: String) -> void:
	var gig := get_gig(id)
	if gig.is_empty() or gig.state != "active":
		return
	gigs.erase(gig)
	_run_progress.erase(id)
	MechLog.write("NET", "Gig abandoned: %s" % gig.title)
	gigs_changed.emit()
	_changed()


## Open gigs older than GIG_LIFETIME_DAYS go.
func expire_gigs() -> void:
	gigs = gigs.filter(func(g): return g.state != "open" or day - int(g.posted) < GIG_LIFETIME_DAYS)


## Fills the board up to GIG_BOARD_SIZE open gigs, rolled from the templates
## the story allows by weight, a template not already open first.
func fill_board() -> void:
	ensure_loaded()
	_board_filled = true
	var added := false
	while open_gigs().size() < GIG_BOARD_SIZE:
		var template := _pick_template()
		if template.is_empty():
			break
		gigs.append(roll_gig(template))
		added = true
	if added:
		gigs_changed.emit()
		_refresh()


func offerable_templates() -> Array:
	var kinds := spawnable_kinds()
	return gig_templates.filter(func(t):
		return t is Dictionary and str(t.get("type")) in GIG_TYPES and meets(t.get("requires", {})) \
				and (t.type != "kill" or str(t.get("kind")) in kinds))


func _pick_template() -> Dictionary:
	var pool := offerable_templates()
	if pool.is_empty():
		return {}
	var open_ids := open_gigs().map(func(g): return g.template)
	var fresh := pool.filter(func(t): return not t.id in open_ids)
	if not fresh.is_empty():
		pool = fresh
	var total := 0.0
	for template in pool:
		total += maxf(float(template.get("weight", 1.0)), 0.0)
	var pick := rng.randf() * total
	for template in pool:
		pick -= maxf(float(template.get("weight", 1.0)), 0.0)
		if pick < 0.0:
			return template
	return pool[-1]


## A new open gig from a template: count and reward rolled once, the reward
## rounded to the nearest 10.
func roll_gig(template: Dictionary) -> Dictionary:
	_gig_serial += 1
	var count := _roll_int(template.get("count", 1))
	var reward := int(roundf(_roll_float(template.get("reward", 0)) / 10.0) * 10.0)
	var poster := str(template.get("poster", ""))
	if poster == "":
		poster = CallsignGenerator.generate(rng, {})
	var gig := {
		"id": "g%d" % _gig_serial, "template": str(template.get("id", "")), "type": str(template.get("type", "kill")),
		"kind": str(template.get("kind", "")), "item": str(template.get("item", "")),
		"count": maxi(count, 1), "reward": reward, "reputation": int(template.get("reputation", 0)),
		"poster": poster, "posted": day, "state": "open", "progress": 0,
	}
	gig["noun"] = _gig_noun(template, gig)
	gig["title"] = _gig_title(template, gig)
	return gig


func _roll_int(value) -> int:
	if value is Array and value.size() >= 2:
		return rng.randi_range(int(value[0]), int(value[1]))
	return int(value)


func _roll_float(value) -> float:
	if value is Array and value.size() >= 2:
		return rng.randf_range(float(value[0]), float(value[1]))
	return float(value)


func _gig_title(template: Dictionary, gig: Dictionary) -> String:
	return str(template.get("title", gig.id)).replace("{count}", str(gig.count)) \
			.replace("{kind_plural}", kind_plural(template)).replace("{kind}", kind_name(template)) \
			.replace("{item}", item_name(template))


func _gig_noun(template: Dictionary, gig: Dictionary) -> String:
	if gig.type == "kill":
		return kind_plural(template)
	if gig.type == "extract":
		return "extractions"
	return item_name(template)


## "Coyote", or "mech" as "mech".
func kind_name(template: Dictionary) -> String:
	return str(template.get("kind", ""))


func kind_plural(template: Dictionary) -> String:
	if template.has("kind_plural"):
		return str(template.kind_plural)
	return kind_name(template) + "s"


## The item's name for a gig: "item_name", else the item's display name, else
## the item or tag as written.
func item_name(template: Dictionary) -> String:
	if template.has("item_name"):
		return str(template.item_name)
	var item := str(template.get("item", ""))
	if _item_names.is_empty():
		_item_names = _read_item_names(ITEMS_DIR)
	return str(_item_names.get(item, item))


static func _read_item_names(path: String) -> Dictionary:
	var names := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return names
	for sub in dir.get_directories():
		names.merge(_read_item_names(path.path_join(sub)))
	for file_name in dir.get_files():
		var entry := str(file_name).trim_suffix(".remap")
		if entry.ends_with(".tres"):
			var res = load(path.path_join(entry))
			if res is item_data and res.id != "":
				names[res.id] = res.display_name
	return names


## "3/6 Coyotes".
func progress_text(gig: Dictionary) -> String:
	return "%d/%d %s" % [int(gig.progress), int(gig.count), gig.noun]


## The kinds a kill gig may name: "mech" and the species ExpeditionDirector
## spawns (read off its scenes), else FALLBACK_KINDS.
func spawnable_kinds() -> Array:
	if not _kinds.is_empty():
		return _kinds
	var script = load(DIRECTOR_PATH) if ResourceLoader.exists(DIRECTOR_PATH) else null
	if script is Script:
		_kinds = ["mech"]
		var constants: Dictionary = script.get_script_constant_map()
		for key in constants:
			var scene = constants[key]
			if not scene is PackedScene:
				continue
			var state: SceneState = scene.get_state()
			for i in state.get_node_property_count(0):
				if state.get_node_property_name(0, i) == "species":
					var species := str(state.get_node_property_value(0, i))
					if not species in _kinds:
						_kinds.append(species)
	if _kinds.size() <= 1:
		_kinds = FALLBACK_KINDS.duplicate()
	return _kinds


## CombatScene: the player killed this (a mecha or an Entity). Counts toward
## active kill gigs of its kind, kept only if the run ends in an extraction.
func report_kill(victim: Object) -> void:
	report_kind(ContactStore.kind_of(victim))


func report_kind(kind: String) -> void:
	if not PlayerProgress.is_in_expedition():
		return
	for gig in active_gigs():
		if gig.type == "kill" and gig.kind == kind:
			_run_progress[gig.id] = int(_run_progress.get(gig.id, 0)) + 1


## This run's progress on a gig, not kept until extraction.
func run_progress(id: String) -> int:
	return int(_run_progress.get(id, 0))


## How many of an item (id or tag) the mech cargo holds.
func cargo_count(item: String) -> int:
	var count := 0
	var cargo := PlayerProgress.get_mech_inventory()
	if cargo == null or cargo.grid.is_empty():
		return 0
	for stack in cargo.get_stacks():
		var res = stack.get_resource()
		var tags = res.get("tags") if res != null else null
		var res_id = res.get("id") if res != null else null
		if str(res_id) == item or str(stack.item_id) == item or str(stack.item_id).get_file().get_basename() == item \
				or (tags is Array and item in tags):
			count += stack.quantity
	return count


## Pays every complete gig, when the player is at home (the Hangar).
func pay_completed() -> void:
	if not is_at_home():
		return
	var paid := false
	for gig in complete_gigs():
		gigs.erase(gig)
		gigs_completed += 1
		PlayerProgress.add_money(int(gig.reward), false)
		PlayerProgress.add_reputation(int(gig.reputation), false)
		MechLog.write("NET", "Gig paid: %s, %d CT" % [gig.title, int(gig.reward)], MechLog.Kind.LOOT)
		post({"id": "paid_" + str(gig.id), "board": GIGS_BOARD, "author": gig.poster,
				"title": "Payment sent: %d CT" % int(gig.reward), "body": Steelapedia.lorem("paid_" + str(gig.id), 1),
				"notify": true})
		paid = true
	if paid:
		gigs_changed.emit()
		_changed()


## At home: in the Hangar, where NET runs.
func is_at_home() -> bool:
	return MechOS.is_app_available("net") and not PlayerProgress.is_in_expedition()


# An open gig as a post on the GIGS board.
func _gig_post(gig: Dictionary) -> Dictionary:
	return {
		"id": "gig:" + str(gig.id), "board": GIGS_BOARD, "author": gig.poster, "title": gig.title,
		"body": Steelapedia.lorem("gig_" + str(gig.template), 1), "requires": {}, "hidden_if": {},
		"notify": false, "pinned": false, "order": 0, "on_read": {}, "replies": [], "gig": "",
		"gig_id": gig.id, "source": "gig",
	}


# ---- pilots -------------------------------------------------------------------

## A pilot's profile from pilots.json ({} if there's none, or it's hidden).
func pilot_profile(callsign: String) -> Dictionary:
	ensure_loaded()
	var key := _pilot_key(callsign)
	if key == "" or not meets(pilots[key].get("requires", {})):
		return {}
	var profile: Dictionary = pilots[key].duplicate(true)
	profile["callsign"] = key
	return profile


func _pilot_key(callsign: String) -> String:
	if pilots.has(callsign):
		return callsign
	for key in pilots:
		if str(key).to_lower() == callsign.to_lower():
			return key
	return ""


## The profiles that show, A-Z.
func visible_pilots() -> Array:
	ensure_loaded()
	var names := pilots.keys().filter(func(k): return meets(pilots[k].get("requires", {})))
	names.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return names


## LocalPilots: a pilot joined Local in the player's expedition.
func note_met(callsign: String) -> void:
	if callsign == "" or callsign == PlayerProgress.get_callsign():
		return
	met[callsign] = day
	_save()


func is_met(callsign: String) -> bool:
	return met.has(callsign) or met.has(_pilot_key(callsign))


func last_seen(callsign: String) -> int:
	return int(met.get(callsign, met.get(_pilot_key(callsign), 0)))


## A named NPC's frame: [[slot label, part type, part id]] from its
## special_npc resource, [] if it isn't one.
func known_build(callsign: String) -> Array:
	var slots := [["Head", "head", "head"], ["Core", "core", "core"], ["Shoulders", "shoulders", "shoulders"],
			["Chassis", "chassis", "chassis"], ["Generator", "generator", "generator"],
			["Chipset", "chipset", "chipset"], ["Thruster", "thruster", "thruster"],
			["L arm", "arm_weapon_left", "arm_weapon"], ["R arm", "arm_weapon_right", "arm_weapon"],
			["L shoulder", "shoulder_weapon_left", "shoulder_weapon"],
			["R shoulder", "shoulder_weapon_right", "shoulder_weapon"], ["Internal", "internal", "internal"]]
	for npc in NPCManager.SPECIAL_NPCS:
		if str(npc.get("mecha_name")).to_lower() != callsign.to_lower():
			continue
		var build := []
		for slot in slots:
			var ids = npc.get(slot[1])
			if ids is Array and not ids.is_empty() and PartManager.is_valid_part(slot[2], str(ids[0])):
				build.append([slot[0], slot[2], str(ids[0])])
		return build
	return []


# ---- debug --------------------------------------------------------------------

## Every post, whether it shows and why not (debug key, F9).
func get_debug_text() -> String:
	var lines := ["[PilotNet] day %d, %d unread, %d gigs (%d open, %d active)" % [day, _unread, gigs.size(),
			open_gigs().size(), active_gigs().size()]]
	for id in all_ids():
		var why := why_hidden(id)
		var post_data := get_post(id)
		lines.append("  %s %-28s %-8s %s%s" % ["+" if why == "" else "-", id, post_data.board,
				fill_tags(post_data.title), "" if why == "" else "   (%s)" % why])
	for error in load_errors:
		lines.append("  ! " + error)
	return "\n".join(lines)


func _ensure_debug_action() -> void:
	if InputMap.has_action(DEBUG_ACTION):
		return
	InputMap.add_action(DEBUG_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = DEBUG_KEY
	InputMap.action_add_event(DEBUG_ACTION, key)


# ---- save / reset -------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {
		"day": day,
		"read": _read.keys(),
		"first_seen": _first_seen.duplicate(),
		"pushed": _pushed.values().map(func(p): return _strip_post(p)),
		"shown": _shown.keys(),
		"hidden": _hidden.keys(),
		"replies": _extra_replies.duplicate(true),
		"gigs": gigs.duplicate(true),
		"gig_serial": _gig_serial,
		"gigs_completed": gigs_completed,
		"post_gigs": _post_gigs.duplicate(),
		"met": met.duplicate(),
		"steelapedia": Steelapedia.get_save_data(),
		"fourx": FourX.get_save_data(),
		"memorial": memorial.get_save_data(),
	}


## A save without the Memorial Wall (from before it) starts one, with the
## backfill before Day 1.
func set_save_data(data) -> void:
	ensure_loaded()
	_clear()
	if not data is Dictionary:
		memorial.start()
		_refresh(false)
		return
	day = maxi(int(data.get("day", 1)), 1)
	for id in data.get("read", []):
		_read[str(id)] = true
	var seen = data.get("first_seen", {})
	if seen is Dictionary:
		for id in seen:
			_first_seen[str(id)] = int(seen[id])
	for raw in data.get("pushed", []):
		if raw is Dictionary and str(raw.get("id", "")) != "":
			var post_data := _normal_post(raw, "code")
			_pushed[post_data.id] = post_data
	for id in data.get("shown", []):
		_shown[str(id)] = true
	for id in data.get("hidden", []):
		_hidden[str(id)] = true
	var replies = data.get("replies", {})
	if replies is Dictionary:
		_extra_replies = replies.duplicate(true)
	for raw in data.get("gigs", []):
		if raw is Dictionary:
			var gig: Dictionary = raw.duplicate(true)
			for key in ["count", "reward", "reputation", "posted", "progress"]:
				gig[key] = int(gig.get(key, 0))
			gigs.append(gig)
	_gig_serial = int(data.get("gig_serial", gigs.size()))
	gigs_completed = int(data.get("gigs_completed", 0))
	var post_gigs = data.get("post_gigs", {})
	if post_gigs is Dictionary:
		_post_gigs = post_gigs.duplicate()
	var met_data = data.get("met", {})
	if met_data is Dictionary:
		for callsign in met_data:
			met[str(callsign)] = int(met_data[callsign])
	Steelapedia.set_save_data(data.get("steelapedia", {}))
	FourX.set_save_data(data.get("fourx", {}))
	if data.get("memorial") is Dictionary:
		memorial.set_save_data(data.memorial)
	else:
		memorial.start()
	_refresh(false)
	gigs_changed.emit()


## A new profile: day 1, nothing read, a fresh gig board, no market yet, a
## Memorial Wall with its backfill.
func reset(should_save := true) -> void:
	ensure_loaded()
	_clear()
	Steelapedia.set_save_data({})
	FourX.reset()
	memorial.start()
	_refresh(false)
	gigs_changed.emit()
	if should_save:
		_save()


func _clear() -> void:
	day = 1
	_board_filled = false
	_pushed.clear()
	_shown.clear()
	_hidden.clear()
	_extra_replies.clear()
	_first_seen.clear()
	_read.clear()
	_visible.clear()
	gigs.clear()
	gigs_completed = 0
	_gig_serial = 0
	_post_gigs.clear()
	_run_progress.clear()
	met.clear()


func _strip_post(post_data: Dictionary) -> Dictionary:
	var copy := post_data.duplicate(true)
	copy.erase("source")
	return copy


func _save() -> void:
	if autosave:
		FileManager.save_profile()


# ---- content checks -----------------------------------------------------------

## Every problem in the data files (PilotNetTest fails on any).
func check_content() -> Array:
	ensure_loaded()
	var errors: Array = load_errors.duplicate()
	var board_ids := boards.map(func(b): return str(b.get("id")) if b is Dictionary else "")
	for board in boards:
		if not board is Dictionary:
			errors.append("boards.json: a board that isn't an object")
			continue
		_check_keys(errors, "board %s" % board.get("id"), board, BOARD_KEYS)
		_check_conditions(errors, "board %s requires" % board.get("id"), board.get("requires", {}))
	var template_ids := gig_templates.map(func(t): return str(t.get("id")) if t is Dictionary else "")
	for post_data in _file_posts.values():
		var where := "post %s" % post_data.id
		_check_keys(errors, where, post_data, POST_KEYS + ["source", "file"])
		if not post_data.board in board_ids:
			errors.append("%s: board '%s' doesn't exist" % [where, post_data.board])
		if post_data.title == "" or post_data.body == "":
			errors.append("%s: needs a title and a body" % where)
		_check_conditions(errors, where + " requires", post_data.requires)
		_check_conditions(errors, where + " hidden_if", post_data.hidden_if)
		_check_effects(errors, where + " on_read", post_data.on_read)
		for text in [post_data.title, post_data.body, post_data.author]:
			for tag in unknown_tags(text):
				errors.append("%s: unknown tag %s" % [where, tag])
		for reply_data in post_data.replies:
			if not reply_data is Dictionary:
				errors.append("%s: a reply that isn't an object" % where)
				continue
			_check_keys(errors, where + " reply", reply_data, REPLY_KEYS)
			_check_conditions(errors, where + " reply requires", reply_data.get("requires", {}))
			for tag in unknown_tags(str(reply_data.get("body", ""))) + unknown_tags(str(reply_data.get("author", ""))):
				errors.append("%s: unknown tag %s in a reply" % [where, tag])
		if post_data.gig != "" and not post_data.gig in template_ids:
			errors.append("%s: gig '%s' isn't a template" % [where, post_data.gig])
	for flag in world:
		var entry: Dictionary = world[flag]
		_check_keys(errors, "world %s" % flag, entry, WORLD_KEYS)
		_check_conditions(errors, "world %s requires" % flag, entry.get("requires", {}))
		var values = entry.get("values", {})
		if not values is Dictionary:
			errors.append("world %s: values isn't an object" % flag)
		else:
			for key in values:
				if not values[key] is String:
					errors.append("world %s: the text for '%s' isn't a string" % [flag, key])
		if entry.has("default") and not entry.default is String:
			errors.append("world %s: default isn't a string" % flag)
	var seen_templates := {}
	for template in gig_templates:
		if not template is Dictionary:
			errors.append("gigs.json: a template that isn't an object")
			continue
		var where := "gig %s" % template.get("id")
		if seen_templates.has(template.get("id")):
			errors.append("%s: id used twice" % where)
		seen_templates[template.get("id")] = true
		_check_keys(errors, where, template, GIG_KEYS)
		_check_conditions(errors, where + " requires", template.get("requires", {}))
		if not str(template.get("type")) in GIG_TYPES:
			errors.append("%s: type '%s' isn't one of %s" % [where, template.get("type"), str(GIG_TYPES)])
		if template.get("type") == "extract_with" and str(template.get("item", "")) == "":
			errors.append("%s: extract_with needs an item" % where)
		for tag in RegEx.create_from_string("\\{([^{}\\s]*)\\}").search_all(str(template.get("title", ""))):
			if not tag.get_string(1) in GIG_TITLE_TAGS:
				errors.append("%s: unknown tag %s in the title" % [where, tag.get_string()])
	for callsign in pilots:
		_check_keys(errors, "pilot %s" % callsign, pilots[callsign], PILOT_KEYS)
		_check_conditions(errors, "pilot %s requires" % callsign, pilots[callsign].get("requires", {}))
	errors.append_array(check_site(site))
	return errors


## Every problem in site.json's data: unknown keys, "new_look" that isn't an
## object, its conditions, unknown tags in its notice.
func check_site(data: Dictionary) -> Array:
	var errors := []
	_check_keys(errors, "site.json", data, SITE_KEYS)
	if not data.has("new_look"):
		return errors
	var new_look = data.new_look
	if not new_look is Dictionary:
		errors.append("site.json new_look: isn't an object")
		return errors
	_check_keys(errors, "site.json new_look", new_look, NEW_LOOK_KEYS)
	_check_conditions(errors, "site.json new_look requires", new_look.get("requires", {}))
	for tag in unknown_tags(str(new_look.get("notice", ""))):
		errors.append("site.json new_look notice: unknown tag %s" % tag)
	return errors


func _check_keys(errors: Array, where: String, data: Dictionary, known: Array) -> void:
	for key in data:
		if not key in known and not str(key).begins_with("_"):
			errors.append("%s: unknown key '%s'" % [where, key])


func _check_conditions(errors: Array, where: String, conditions) -> void:
	if not conditions is Dictionary:
		errors.append("%s: isn't an object" % where)
		return
	for key in conditions:
		if not key in CONDITION_KEYS:
			errors.append("%s: unknown condition '%s'" % [where, key])
	if conditions.has("flags") and not conditions.flags is Dictionary:
		errors.append("%s: flags isn't an object" % where)


func _check_effects(errors: Array, where: String, effects) -> void:
	if not effects is Dictionary:
		errors.append("%s: isn't an object" % where)
		return
	for key in effects:
		if not key in STORY_EFFECT_KEYS and not StoryDirector.has_effect(key):
			errors.append("%s: unknown effect '%s'" % [where, key])
	var value = effects.get(EFFECT_KEY)
	if value is Dictionary:
		for key in value:
			if not key in EFFECT_VALUE_KEYS:
				errors.append("%s: unknown pilotnet key '%s'" % [where, key])
		for key in ["show", "hide"]:
			for id in value.get(key, []):
				if not _file_posts.has(str(id)):
					errors.append("%s: %s names no post '%s'" % [where, key, id])
	elif value is String and not _file_posts.has(value):
		errors.append("%s: pilotnet names no post '%s'" % [where, value])
