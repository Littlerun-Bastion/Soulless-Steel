class_name SteelapediaMarkup
extends RefCounted

## Steelapedia's wiki markup, turned into BBCode for a RichTextLabel. The one
## place the markup is read (the writing guide is database/steelapedia/README.md):
##
##   == Heading ==            a section (it goes into the contents box)
##   === Subheading ===       a subsection
##   requires: {...}          right after a heading: the section shows only
##                            while StoryDirector.meets() it
##   '''bold'''  ''italic''
##   [[slug]]  [[slug|text]]  a link to an article; dim and struck through
##                            when there's no such article (a "red link")
##   [[net:pilot.net/board/news|text]]   a link to another NET site
##   * item                   a bullet
##   a blank line             a new paragraph
##
## Links come out as [url=wiki:<slug>] and [url=net:<address>] in the
## theme's link colour (NetWikiLink, NetWikiLinkMissing); the page follows
## them (meta_clicked).

const WIKI := "wiki:"
const NET := "net:"
const THEME := preload("res://game/ui/mech_os/MechTheme.tres")

static var _heading := RegEx.create_from_string("^(={2,3})\\s*(.+?)\\s*\\1\\s*$")
static var _requires := RegEx.create_from_string("^requires:\\s*(\\{.*\\})\\s*$")
static var _link := RegEx.create_from_string("\\[\\[([^\\[\\]|]+)(?:\\|([^\\[\\]]*))?\\]\\]")
static var _bold := RegEx.create_from_string("'''(.+?)'''")
static var _italic := RegEx.create_from_string("''(.+?)''")


## The body split at its headings: [{"level": 0 (the lead) / 2 / 3, "title",
## "requires": {}, "text"}], in order. A requires line right after a heading
## goes into that section's "requires".
static func sections(body: String) -> Array:
	var result := [{"level": 0, "title": "", "requires": {}, "text": ""}]
	var lines := body.replace("\r\n", "\n").split("\n")
	var just_headed := false
	var text_lines := []
	for line in lines:
		var heading := _heading.search(line.strip_edges())
		if heading != null:
			result[-1].text = "\n".join(text_lines).strip_edges()
			text_lines = []
			result.append({"level": heading.get_string(1).length(), "title": heading.get_string(2),
					"requires": {}, "text": ""})
			just_headed = true
			continue
		if just_headed:
			var found := _requires.search(line.strip_edges())
			if found != null:
				var conditions = parse_json(found.get_string(1))
				result[-1].requires = conditions if conditions is Dictionary else {"_bad": found.get_string(1)}
				just_headed = false
				continue
			if line.strip_edges() == "":
				continue
		just_headed = false
		text_lines.append(line)
	result[-1].text = "\n".join(text_lines).strip_edges()
	return result


## The sections that show now: a section whose requires fails is left out,
## and so are the subsections under a level-2 section that's left out.
static func visible_sections(body: String, meets: Callable) -> Array:
	var shown := []
	var skipping := false
	for section in sections(body):
		if section.level == 2:
			skipping = not meets.call(section.requires)
		elif section.level == 3 and not skipping:
			if not meets.call(section.requires):
				continue
		if skipping and section.level != 0:
			continue
		shown.append(section)
	return shown


## A block of markup (no headings) as BBCode: paragraphs, bullets, bold,
## italic and links. exists(slug) -> bool styles missing links; title(slug)
## -> String names [[slug]] links without text.
static func to_bbcode(text: String, exists: Callable, title: Callable = Callable()) -> String:
	var out := []
	var bullets := []
	for raw_line in text.replace("\r\n", "\n").split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("* "):
			bullets.append(inline(line.substr(2), exists, title))
			continue
		if not bullets.is_empty():
			out.append("[ul]" + "\n".join(bullets) + "[/ul]")
			bullets = []
		out.append(inline(line, exists, title))
	if not bullets.is_empty():
		out.append("[ul]" + "\n".join(bullets) + "[/ul]")
	var joined := "\n".join(out)
	while "\n\n\n" in joined:
		joined = joined.replace("\n\n\n", "\n\n")
	return joined.strip_edges()


## One line: bold, italic and links, with any other [ ] made safe.
static func inline(line: String, exists: Callable, title: Callable = Callable()) -> String:
	var links := []
	var text := line
	for found in _link.search_all(line):
		links.append(_link_code(found.get_string(1).strip_edges(), found.get_string(2), exists, title))
		text = text.replace(found.get_string(), "\u0001%d\u0002" % (links.size() - 1))
	text = text.replace("[", "\u0003").replace("]", "[rb]").replace("\u0003", "[lb]")
	text = _bold.sub(text, "[b]$1[/b]", true)
	text = _italic.sub(text, "[i]$1[/i]", true)
	for i in links.size():
		text = text.replace("\u0001%d\u0002" % i, links[i])
	return text


static func _link_code(target: String, label: String, exists: Callable, title: Callable) -> String:
	if target.begins_with(NET):
		var address := target.substr(NET.length())
		return "[url=%s%s][color=%s]%s[/color][/url]" % [NET, address, link_color(), _safe(label if label != "" else address)]
	var slug := slug_of(target)
	var shown := label
	if shown == "":
		shown = str(title.call(slug)) if title.is_valid() else ""
		if shown == "":
			shown = target.replace("_", " ")
	if exists.call(slug):
		return "[url=%s%s][color=%s]%s[/color][/url]" % [WIKI, slug, link_color(), _safe(shown)]
	return "[url=%s%s][color=%s][s]%s[/s][/color][/url]" % [WIKI, slug, missing_color(), _safe(shown)]


## The slugs a piece of markup links to ([[slug]], [[slug|text]]; not net:
## links), in order.
static func link_targets(text: String) -> Array:
	var found := []
	for match_data in _link.search_all(text):
		var target := match_data.get_string(1).strip_edges()
		if not target.begins_with(NET):
			found.append(slug_of(target))
	return found


## JSON text as data, or null when it doesn't parse (without an error: a
## writer's mistake shows in SteelapediaTest, not as an engine error).
static func parse_json(text: String):
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## How an article name is written as a slug: lower case, spaces as _.
static func slug_of(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "_")


## A link's colour: NetWikiLink's.
static func link_color() -> String:
	return "#" + THEME.get_color("font_color", "NetWikiLink").to_html(false)


## A red link's colour: NetWikiLinkMissing's.
static func missing_color() -> String:
	return "#" + THEME.get_color("font_color", "NetWikiLinkMissing").to_html(false)


static func _safe(text: String) -> String:
	return text.replace("[", "\u0003").replace("]", "[rb]").replace("\u0003", "[lb]")
