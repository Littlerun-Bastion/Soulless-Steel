class_name Steelapedia
extends RefCounted

## Steelapedia, the in-world encyclopedia: its articles. The page that shows
## them is game/ui/net/sites/steelapedia/; the writing guide is
## database/steelapedia/README.md.
##
## Articles are text files, database/steelapedia/<category>/<slug>.txt: a
## header of "key: value" lines, a line "---", then the body in
## SteelapediaMarkup. The game also makes articles from its data, with Lorem
## Ipsum prose (lorem()):
##   parts          every part the Store lists, and a secret one (not
##                  listed) once the player has owned it; never test parts
##   manufacturers  every maker but the test one
##   entities       every Entity species with a scene in game/entities/
## A file with the same slug replaces such an article's prose; its data (the
## infobox, the maker's product list, the amazing.com link) stays generated.
##
## Slugs are lower case ("ma-l127"), so a link or file name in any case finds
## the article. Each article is a Dictionary:
##   slug, title, summary, category, categories (category ids), requires,
##   infobox ([[label, markup]]), see_also (slugs), body (markup),
##   generated (bool), file (path or ""), links ([[text, net address]]),
##   extra_sections ({section title: markup added under it}).
## requires is checked every time an article is read, so story changes show
## at once.

const ROOT := "res://database/steelapedia/"
const CATEGORIES := ["parts", "manufacturers", "entities", "pilots", "places", "history", "misc"]
const CATEGORY_NAMES := {
	"parts": "Parts", "manufacturers": "Manufacturers", "entities": "Entities", "pilots": "Pilots",
	"places": "Places", "history": "History", "misc": "Misc",
}
const HEADER_KEYS := ["title", "summary", "requires", "see_also", "categories"]
const PART_SECTIONS := ["Overview", "Design", "Service history", "Variants"]
const MAKER_SECTIONS := ["History", "Products", "Corporate affairs"]
const ENTITY_SECTIONS := ["Description", "Behaviour", "Encounters"]
const ENTITIES_DIR := "res://game/entities/"
const CLASSIFICATION := "[CLASSIFICATION]"
const LOREM := ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
		"eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim", "ad",
		"minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "aliquip", "ex",
		"ea", "commodo", "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate", "velit",
		"esse", "cillum", "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat", "cupidatat", "non",
		"proident", "sunt", "culpa", "qui", "officia", "deserunt", "mollit", "anim", "id", "est", "laborum"]

## The day each article with a requires first showed (slug -> day). Saved
## with PilotNet's data.
static var first_visible: Dictionary = {}
## Secret parts the player has owned ("type:id"): their articles stay.
static var known_parts: Dictionary = {}
## Problems found reading the files (SteelapediaTest reports them).
static var load_errors: Array = []

static var _files: Dictionary = {}       # slug -> article from a file
static var _generated: Dictionary = {}   # slug -> article made from data
static var _files_read := false
static var _generated_built := false


# ---- loading ------------------------------------------------------------------

## Reads the files and builds the generated articles, once. (The generated
## ones load the Entity scenes, so they wait until an article is wanted.)
static func ensure_loaded() -> void:
	_ensure_files()
	if not _generated_built:
		_generated_built = true
		_generated.clear()
		_build_generated()


## Reads every file again (the debug reload: F9 with pilot.net's).
static func reload_articles() -> void:
	_files_read = false
	_generated_built = false
	ensure_loaded()


static func _ensure_files() -> void:
	if _files_read:
		return
	_files_read = true
	load_errors.clear()
	_files.clear()
	for category in CATEGORIES:
		var dir := DirAccess.open(ROOT + category)
		if dir == null:
			continue
		var names := Array(dir.get_files())
		names.sort()
		for file_name in names:
			var name := str(file_name).trim_suffix(".remap")
			if not name.ends_with(".txt"):
				continue
			var path: String = ROOT + str(category) + "/" + name
			var article := parse(FileAccess.get_file_as_string(path), name.get_basename(), category)
			article.file = path
			if _files.has(article.slug):
				load_errors.append("%s: slug '%s' is already used by %s" % [path, article.slug, _files[article.slug].file])
				continue
			for error in article.get("errors", []):
				load_errors.append("%s: %s" % [path, error])
			_files[article.slug] = article


## An article from a file's text. Header keys it doesn't know go in "errors".
static func parse(text: String, slug: String, category: String) -> Dictionary:
	var article := _new_article(SteelapediaMarkup.slug_of(slug), category)
	var lines := text.replace("\r\n", "\n").split("\n")
	var cut := lines.find("---")
	if cut < 0:
		article.errors.append("no '---' line between the header and the body")
		cut = -1
	for i in range(0, maxi(cut, 0)):
		var line := lines[i].strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var colon := line.find(":")
		if colon <= 0:
			article.errors.append("header line '%s' isn't 'key: value'" % line)
			continue
		var key := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		if key.begins_with("infobox."):
			article.infobox.append([key.substr(8).strip_edges(), value])
		elif key == "title":
			article.title = value
		elif key == "summary":
			article.summary = value
		elif key == "requires":
			var conditions = SteelapediaMarkup.parse_json(value)
			if conditions is Dictionary:
				article.requires = conditions
			else:
				article.errors.append("requires isn't a JSON object: %s" % value)
		elif key == "see_also":
			article.see_also = _list(value).map(func(s): return SteelapediaMarkup.slug_of(s))
		elif key == "categories":
			for extra in _list(value):
				if not extra in article.categories:
					article.categories.append(SteelapediaMarkup.slug_of(extra))
		else:
			article.errors.append("unknown header key '%s'" % key)
	article.body = "\n".join(lines.slice(cut + 1)).strip_edges()
	if article.title == "":
		article.title = slug.replace("_", " ").capitalize()
	return article


static func _list(value: String) -> Array:
	return Array(value.split(",", false)).map(func(s): return str(s).strip_edges()).filter(func(s): return s != "")


static func _new_article(slug: String, category: String) -> Dictionary:
	return {"slug": slug, "title": "", "summary": "", "category": category, "categories": [category],
			"requires": {}, "infobox": [], "see_also": [], "body": "", "generated": false, "file": "",
			"links": [], "extra_sections": {}, "errors": [], "data": {}}


# ---- generated articles ---------------------------------------------------------

static func _build_generated() -> void:
	for part_type in Store.CATEGORIES:
		for part_id in PartManager.get_parts(part_type):
			if part_id == "Null":
				continue
			var maker := Manufacturers.of_part(PartManager.get_part(part_type, part_id))
			if Manufacturers.is_test(maker):
				continue
			var article := _new_article(SteelapediaMarkup.slug_of(part_id), "parts")
			article.generated = true
			article.title = Store.part_name(part_type, part_id)
			article.categories = ["parts", type_category(part_type)]
			if maker != "":
				article.categories.append(maker)
			article.data = {"kind": "part", "part_type": part_type, "part_id": part_id, "maker": maker}
			article.body = _lorem_body(article.slug, PART_SECTIONS)
			article.summary = lorem_sentence(article.slug)
			article.links = [["Buy on amazing.com", NetSites.product_url(part_type, part_id)]]
			_generated[article.slug] = article
	for maker in Manufacturers.real_ids():
		var article := _new_article(maker, "manufacturers")
		article.generated = true
		article.title = Manufacturers.display_name(maker)
		article.data = {"kind": "maker", "maker": maker}
		article.body = _lorem_body(maker, MAKER_SECTIONS)
		article.summary = lorem_sentence(maker)
		article.links = [["This maker's stock on amazing.com", NetSites.maker_url(maker)]]
		_generated[maker] = article
	for species in entity_species():
		var slug := SteelapediaMarkup.slug_of(species)
		var article := _new_article(slug, "entities")
		article.generated = true
		article.title = species
		article.data = {"kind": "entity", "species": species}
		article.body = _lorem_body(slug, ENTITY_SECTIONS)
		article.summary = lorem_sentence(slug)
		article.infobox = [["Species", species], ["Classification", CLASSIFICATION]]
		_generated[slug] = article


## Every Entity species with a scene under game/entities/ (its "species").
static func entity_species() -> Array:
	var found := []
	_scan_species(ENTITIES_DIR, found)
	found.sort()
	return found


static func _scan_species(path: String, found: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan_species(path.path_join(sub), found)
	for file_name in dir.get_files():
		var name := str(file_name).trim_suffix(".remap")
		if not name.ends_with(".tscn"):
			continue
		var scene = load(path.path_join(name))
		if not scene is PackedScene:
			continue
		var state: SceneState = scene.get_state()
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == "species":
				var species := str(state.get_node_property_value(0, i))
				if species != "" and not species in found:
					found.append(species)


static func _lorem_body(slug: String, titles: Array) -> String:
	var parts := []
	for i in titles.size():
		parts.append("== %s ==\n%s" % [titles[i], lorem("%s/%d" % [slug, i], 2)])
	return "\n\n".join(parts)


## "heads", "arm_weapons": the category of a part type.
static func type_category(part_type: String) -> String:
	return SteelapediaMarkup.slug_of(Store.type_name(part_type, false))


# ---- reading ----------------------------------------------------------------------

## The article as it shows now, or null when there's none or it's hidden.
## with_data false leaves the generated infobox and lists out (quicker, for
## lists and search).
static func get_article(slug: String, with_data := true):
	ensure_loaded()
	slug = SteelapediaMarkup.slug_of(slug)
	var base: Dictionary = _generated.get(slug, {})
	var file: Dictionary = _files.get(slug, {})
	if base.is_empty() and file.is_empty():
		return null
	if not base.is_empty() and not _generated_visible(base):
		return null
	var article: Dictionary = (base if not base.is_empty() else file).duplicate(true)
	if not base.is_empty() and not file.is_empty():
		article.body = file.body
		article.file = file.file
		article.requires = file.requires
		article.see_also = file.see_also
		if file.title != "" and file.title != slug.replace("_", " ").capitalize():
			article.title = file.title
		if file.summary != "":
			article.summary = file.summary
		for extra in file.categories:
			if not extra in article.categories:
				article.categories.append(extra)
	if not StoryDirector.meets(article.requires):
		return null
	if not base.is_empty() and with_data:
		_add_data(article)
	if not file.is_empty() and not base.is_empty():
		article.infobox.append_array(file.infobox)
	return article


static func article_exists(slug: String) -> bool:
	ensure_loaded()
	slug = SteelapediaMarkup.slug_of(slug)
	var base: Dictionary = _generated.get(slug, {})
	var file: Dictionary = _files.get(slug, {})
	if base.is_empty() and file.is_empty():
		return false
	if not base.is_empty() and not _generated_visible(base):
		return false
	return StoryDirector.meets(file.requires if not file.is_empty() else base.requires)


## The article's title, "" when it doesn't show.
static func title_of(slug: String) -> String:
	var article = get_article(slug, false)
	return article.title if article != null else ""


## Every article that shows, A-Z by title (without the generated data).
static func all_articles() -> Array:
	ensure_loaded()
	var slugs := {}
	for slug in _generated:
		slugs[slug] = true
	for slug in _files:
		slugs[slug] = true
	var result := []
	for slug in slugs:
		var article = get_article(slug, false)
		if article != null:
			result.append(article)
	result.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
	return result


## The articles in a category ("parts", "heads", "martel"...), A-Z.
static func articles_in(category: String) -> Array:
	return all_articles().filter(func(a): return category in a.categories)


## Every category that has an article, with its count: {id: count}.
static func category_counts() -> Dictionary:
	var counts := {}
	for article in all_articles():
		for category in article.categories:
			counts[category] = int(counts.get(category, 0)) + 1
	return counts


static func category_name(category: String) -> String:
	if CATEGORY_NAMES.has(category):
		return CATEGORY_NAMES[category]
	if Manufacturers.is_valid(category):
		return Manufacturers.short_name(category)
	for part_type in Store.CATEGORIES:
		if type_category(part_type) == category:
			return Store.type_name(part_type, false)
	return category.replace("_", " ").capitalize()


## Articles whose title contains the text first, then those whose summary or
## body does, any case.
static func search(text: String) -> Array:
	var wanted := text.strip_edges().to_lower()
	if wanted == "":
		return []
	var by_title := []
	var by_text := []
	for article in all_articles():
		if wanted in article.title.to_lower():
			by_title.append(article)
		elif wanted in article.summary.to_lower() or wanted in article.body.to_lower():
			by_text.append(article)
	return by_title + by_text


## The visible article whose title is the text (any case), or null.
static func exact_title(text: String):
	for article in all_articles():
		if article.title.to_lower() == text.strip_edges().to_lower():
			return article
	return null


static func random_article(rng: RandomNumberGenerator = null):
	var all := all_articles()
	if all.is_empty():
		return null
	return all[rng.randi_range(0, all.size() - 1) if rng != null else randi() % all.size()]


## The day the article first showed (Day 1 for one that always has).
static func last_modified_day(slug: String) -> int:
	return int(first_visible.get(SteelapediaMarkup.slug_of(slug), 1))


## Records the day each file article with a requires first shows (PilotNet
## calls it whenever the story moves).
static func note_visible(day: int) -> void:
	_ensure_files()
	for slug in _files:
		var article: Dictionary = _files[slug]
		if article.requires.is_empty() or first_visible.has(slug):
			continue
		if StoryDirector.meets(article.requires):
			first_visible[slug] = day


static func _generated_visible(article: Dictionary) -> bool:
	var data: Dictionary = article.data
	if data.get("kind") != "part":
		return true
	var part_type: String = data.part_type
	var part_id: String = data.part_id
	if Store.is_listed(part_type, part_id):
		return true
	var key := "%s:%s" % [part_type, part_id]
	if known_parts.has(key):
		return true
	if player_has_owned(part_type, part_id):
		known_parts[key] = true
		return true
	return false


## Whether the player has (or had, by its blueprint) this part: in the stash,
## the cargo or fitted, or recycled at least once.
static func player_has_owned(part_type: String, part_id: String) -> bool:
	if PlayerProgress.count_part(part_type, part_id) > 0 or PlayerProgress.blueprint_progress(part_type, part_id) > 0:
		return true
	var design := PlayerProgress.get_current_mecha()
	for slot in design:
		if str(design[slot]) == part_id and (slot == part_type or str(slot).begins_with(part_type)):
			return true
	var cargo := PlayerProgress.get_mech_inventory()
	if cargo != null and not cargo.grid.is_empty():
		for stack in cargo.get_stacks():
			if stack.is_part() and stack.item_type == part_type and stack.item_id == part_id:
				return true
	return false


# The data parts of a generated article, made fresh: the infobox, the maker's
# product list.
static func _add_data(article: Dictionary) -> void:
	var data: Dictionary = article.data
	if data.get("kind") == "part":
		article.infobox = part_infobox(data.part_type, data.part_id)
	elif data.get("kind") == "maker":
		var maker: String = data.maker
		var products := Store.catalogue_of_maker(maker)
		article.infobox = [["Name", Manufacturers.display_name(maker)], ["Short name", Manufacturers.short_name(maker)],
				["Website", "[[net:%s|%s]]" % [Manufacturers.domain_of(maker), Manufacturers.domain_of(maker)]],
				["Parts in the catalogue", str(products.size())]]
		var lines := products.map(func(e): return "* [[%s|%s]] (%s)" % [SteelapediaMarkup.slug_of(e[1]),
				Store.part_name(e[0], e[1]), Store.type_name(e[0])])
		article.extra_sections = {"Products": "\n".join(lines) if not lines.is_empty() else "''No parts in the catalogue.''"}


## A part's infobox: its maker, type, tier, price, weight, size, then the
## PartCompare stats for its type.
static func part_infobox(part_type: String, part_id: String) -> Array:
	var part = PartManager.get_part(part_type, part_id)
	var maker := Manufacturers.of_part(part)
	var rows := []
	rows.append(["Maker", "[[%s|%s]]" % [maker, Manufacturers.display_name(maker)] if maker != "" else "-"])
	rows.append(["Part type", Store.type_name(part_type)])
	var tier = part.get("tech_tier")
	rows.append(["Tech tier", Materials.tier_name(tier) if tier is int and tier != item_data.TechTier.NONE else "-"])
	rows.append(["Price", "%d CT" % Store.price(part_type, part_id)])
	rows.append(["Weight", MechUI.fmt(float(part.get("weight")))])
	var size = part.get("item_size")
	if size is Array and size.size() >= 2:
		rows.append(["Size", "%d × %d" % [int(size[0]), int(size[1])]])
	var spec := {"part_type": part_type, "part_id": part_id, "grade": Grades.STANDARD}
	for field in PartCompare.FIELDS.get(part_type, []):
		if field.id == "price" or field.id == "weight":
			continue
		rows.append([str(field.label), PartCompare.format_value(PartCompare.value_of(spec, field))])
	return rows


# ---- Lorem Ipsum ------------------------------------------------------------------

## Lorem Ipsum for a slug: paragraphs of it, always the same for the same
## slug. All of Steelapedia's (and pilot.net's) placeholder prose comes from
## here.
static func lorem(slug: String, paragraphs := 1) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = slug.hash()
	var out := []
	for p in paragraphs:
		var sentences := []
		for s in rng.randi_range(3, 5):
			sentences.append(_sentence(rng))
		out.append(" ".join(sentences))
	return "\n\n".join(out)


## One Lorem Ipsum sentence for a slug.
static func lorem_sentence(slug: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("summary:" + slug).hash()
	return _sentence(rng)


static func _sentence(rng: RandomNumberGenerator) -> String:
	var words := []
	for w in rng.randi_range(6, 14):
		words.append(LOREM[rng.randi_range(0, LOREM.size() - 1)])
	var text := " ".join(words)
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


# ---- save -------------------------------------------------------------------------

static func get_save_data() -> Dictionary:
	return {"first_visible": first_visible.duplicate(), "known_parts": known_parts.keys()}


static func set_save_data(data) -> void:
	first_visible = {}
	known_parts = {}
	if not data is Dictionary:
		return
	var seen = data.get("first_visible", {})
	if seen is Dictionary:
		for slug in seen:
			first_visible[str(slug)] = int(seen[slug])
	for key in data.get("known_parts", []):
		known_parts[str(key)] = true
