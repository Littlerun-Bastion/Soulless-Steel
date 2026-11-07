class_name PilotNetSite
extends RefCounted

## What pilot.net shows, whichever look draws it: PilotNetPage (the
## text-mode board) and PilotNetPortalPage (the web portal) lay out the same
## picks from here. The data itself is PilotNet's (and FourX's, Steelapedia's
## and the Store's for the front page).

const DOMAIN := "pilot.net"
const RANKS := [[10, "Ace"], [5, "Veteran"], [2, "Pilot"], [0, "Rookie"]]
const SYSOP := "SYSOP"
const NO_POSTS := "(nothing here yet)"
## The gig buttons' actions.
const ACCEPT := "accept"
const ACCEPT_POST := "accept_post"
const ABANDON := "abandon"
## The In memoriam box: the Memorial Wall's newest records.
const MEMORIAL_COUNT := 3
const MEMORIAL_NAME := "Memorial Wall"


static func url(page_path: String, page_query := {}) -> String:
	return NetSites.make_url(DOMAIN, page_path, page_query)


static func post_url(id: String) -> String:
	return url("/post/" + id)


static func pilot_url(callsign: String) -> String:
	return url("/pilot/" + callsign)


# ---- the front page -----------------------------------------------------------

## The top story: the first pinned news post, else the newest; {} for none.
static func top_story() -> Dictionary:
	var pinned := PilotNet.visible_posts(PilotNet.NEWS_BOARD).filter(func(p): return p.pinned)
	if not pinned.is_empty():
		return pinned[0]
	var news := PilotNet.latest(PilotNet.NEWS_BOARD, 1)
	return news[0] if not news.is_empty() else {}


## The newest news posts after the top story, count at most.
static func headlines(count: int) -> Array:
	var top := top_story()
	return PilotNet.latest(PilotNet.NEWS_BOARD, count + 1).filter(func(p): return p.id != top.get("id", "")).slice(0, count)


## The newest posts on the boards that aren't news or gigs, count at most.
static func hot_topics(count: int) -> Array:
	var talk := PilotNet.visible_posts().filter(func(p): return not p.board in [PilotNet.NEWS_BOARD, PilotNet.GIGS_BOARD])
	talk.sort_custom(func(a, b): return PilotNet.first_seen_day(a.id) > PilotNet.first_seen_day(b.id))
	return talk.slice(0, count)


## What complete gigs will pay at home.
static func pay_waiting() -> int:
	var pay := 0
	for gig in PilotNet.complete_gigs():
		pay += int(gig.reward)
	return pay


## The first paragraph of a post's body, tags filled.
static func teaser(post_data: Dictionary) -> String:
	return PilotNet.fill_tags(str(post_data.get("body", ""))).strip_edges().split("\n\n")[0]


# ---- pilots -------------------------------------------------------------------

## Who's online: the player, the pilots met last, and regulars made by the
## callsign generator from the day.
static func online() -> Array:
	var names := [PlayerProgress.get_callsign().to_upper()]
	var met_names: Array = PilotNet.met.keys()
	met_names.sort_custom(func(a, b): return PilotNet.last_seen(str(a)) > PilotNet.last_seen(str(b)))
	for callsign in met_names.slice(0, 4):
		if not str(callsign) in names:
			names.append(str(callsign))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("online:%d" % PilotNet.day).hash()
	var taken := {}
	for callsign in names:
		taken[callsign] = true
	for i in rng.randi_range(3, 6):
		var callsign := CallsignGenerator.generate(rng, taken)
		taken[callsign] = true
		names.append(callsign)
	return names


## Guests online, picked by the day.
static func guests() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("guests:%d" % PilotNet.day).hash()
	return rng.randi_range(2, 12)


## Every pilot with a profile or met in the field, A-Z, one entry a callsign
## (any case); letter "" for all.
static func directory(letter: String) -> Array:
	var seen := {}
	var out := []
	for callsign in PilotNet.visible_pilots() + PilotNet.met.keys():
		var key := str(callsign).to_lower()
		if seen.has(key) or (letter != "" and not str(callsign).to_upper().begins_with(letter)):
			continue
		seen[key] = true
		out.append(str(callsign))
	out.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return out


## A pilot's rank from their posts ("You" for the player, "Sysop").
static func rank(callsign: String) -> String:
	if callsign.to_lower() == PlayerProgress.get_callsign().to_lower():
		return "You"
	if callsign == SYSOP:
		return "Sysop"
	var count := PilotNet.post_count(callsign)
	for entry in RANKS:
		if count >= int(entry[0]):
			return str(entry[1])
	return ""


## Whether a callsign has a page: a profile, met in the field, or the player.
static func is_known(callsign: String) -> bool:
	return not PilotNet.pilot_profile(callsign).is_empty() or PilotNet.is_met(callsign) \
			or callsign.to_lower() == PlayerProgress.get_callsign().to_lower()


## The author of a post or a reply, tags filled.
static func author_of(entry: Dictionary) -> String:
	return PilotNet.author_name(entry) if entry.has("title") else PilotNet.fill_tags(str(entry.get("author", "")))


# ---- forums -------------------------------------------------------------------

## The section a board belongs to in the nav: "NEWS", "GIGS" or "FORUMS".
static func section_of(board_id: String) -> String:
	if board_id == PilotNet.NEWS_BOARD:
		return "NEWS"
	if board_id == PilotNet.GIGS_BOARD:
		return "GIGS"
	return "FORUMS"


## The newest post of a list (by the day it appeared), {} for none.
static func newest(posts: Array) -> Dictionary:
	var best: Dictionary = {}
	for post_data in posts:
		if best.is_empty() or PilotNet.first_seen_day(post_data.id) > PilotNet.first_seen_day(best.id):
			best = post_data
	return best


## Each visible board with its figures: [{"board", "topics", "posts",
## "unread", "last" (a post or {})}].
static func forum_rows() -> Array:
	var rows := []
	for board in PilotNet.visible_boards():
		var posts := PilotNet.visible_posts(str(board.id))
		var replies := 0
		for post_data in posts:
			replies += PilotNet.visible_replies(post_data.id).size()
		rows.append({"board": board, "topics": posts.size(), "posts": posts.size() + replies,
				"unread": posts.any(func(p): return PilotNet.is_new(p.id)), "last": newest(posts)})
	return rows


## {"topics", "posts", "pilots", "newest"} for the forum index.
static func stats() -> Dictionary:
	var topics := 0
	var posts := 0
	for row in forum_rows():
		topics += int(row.topics)
		posts += int(row.posts)
	var newest_name := ""
	var newest_day := -1
	for callsign in PilotNet.met:
		if PilotNet.last_seen(str(callsign)) > newest_day:
			newest_day = PilotNet.last_seen(str(callsign))
			newest_name = str(callsign)
	return {"topics": topics, "posts": posts, "pilots": directory("").size() + 1,
			"newest": newest_name if newest_name != "" else PlayerProgress.get_callsign().to_upper()}


## Whether a post offers a gig (it is a gig, or names a template).
static func has_gig(post_data: Dictionary) -> bool:
	return post_data.get("source") == "gig" or str(post_data.get("gig", "")) != ""


## A reply's time of day, made from the post and the reply's place.
static func reply_time(post_id: String, index: int) -> String:
	return PilotNet.post_time("%s/%d" % [post_id, index])


# ---- gigs ---------------------------------------------------------------------

## What a post offers: {"kind": "gig" (a gig, accept with ACCEPT), "taken"
## (the gig taken from it), "offer" (its template's terms, accept with
## ACCEPT_POST)} with "gig" or "template"; {} for nothing.
static func gig_offer(post_id: String, post_data: Dictionary) -> Dictionary:
	if post_data.get("source") == "gig":
		var gig := PilotNet.get_gig(str(post_data.gig_id))
		return {"kind": "gig", "gig": gig} if not gig.is_empty() else {}
	if str(post_data.get("gig", "")) == "":
		return {}
	var taken := PilotNet.gig_of_post(post_id)
	if not taken.is_empty():
		return {"kind": "taken", "gig": taken}
	var template := PilotNet.get_template(str(post_data.gig))
	if template.is_empty() or not PilotNet.meets(template.get("requires", {})):
		return {}
	return {"kind": "offer", "template": template}


## A template's title with its ranges in: "Clear 4-8 Coyotes".
static func offer_title(template: Dictionary) -> String:
	return str(template.get("title", "")).replace("{count}", range_text(template.get("count", 1))) \
			.replace("{kind_plural}", PilotNet.kind_plural(template)).replace("{kind}", PilotNet.kind_name(template)) \
			.replace("{item}", PilotNet.item_name(template))


## "Reward: 300 CT   Reputation: +1   Posted: 02/01/2035   By: KESTREL"
static func gig_terms(gig: Dictionary) -> String:
	return "Reward: %d CT   Reputation: +%d   Posted: %s   By: %s" % [int(gig.reward), int(gig.reputation),
			PilotNet.short_date(int(gig.posted)), str(gig.poster)]


## The In memoriam box's records: the Memorial Wall's newest.
static func in_memoriam(count := MEMORIAL_COUNT) -> Array:
	PilotNet.memorial.ensure_started()
	return PilotNet.memorial.newest(count)


## The Memorial Wall's record of a callsign (a profile or a met pilot that
## was lost), {} for none.
static func memorial_record(callsign: String) -> Dictionary:
	return PilotNet.memorial.record_of(callsign)


## "† Lost 15 Jan 2035", for the line that links a lost pilot to the Wall.
static func lost_text(record: Dictionary) -> String:
	return "† Lost %s" % PilotNet.long_date(int(record.get("day", 1)))


## "Reward: 300-600 CT   Reputation: +1"
static func offer_terms(template: Dictionary) -> String:
	return "Reward: %s CT   Reputation: +%d" % [range_text(template.get("reward", 0)), int(template.get("reputation", 0))]


## "2 days": how long an open gig stays on the board.
static func expires_text(gig: Dictionary) -> String:
	var left := int(gig.posted) + PilotNet.GIG_LIFETIME_DAYS - PilotNet.day
	return "%d day%s" % [maxi(left, 1), "" if left <= 1 else "s"]


static func range_text(value) -> String:
	if value is Array and value.size() >= 2:
		return "%d-%d" % [int(value[0]), int(value[1])] if int(value[0]) != int(value[1]) else str(int(value[0]))
	return str(int(value))


## Runs a gig button: ACCEPT (a gig id), ACCEPT_POST (a post id) or ABANDON;
## true when it worked. Plays the confirm or deny sound.
static func act(action_name: String, target: String) -> bool:
	var done := false
	if action_name == ACCEPT:
		done = PilotNet.accept_gig(target)
	elif action_name == ACCEPT_POST:
		done = PilotNet.accept_post_gig(target)
	elif action_name == ABANDON:
		PilotNet.abandon_gig(target)
		done = true
	AudioManager.play_sfx("confirm" if done else "deny_softer")
	return done
