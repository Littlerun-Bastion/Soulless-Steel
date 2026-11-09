extends TestSuite

# SteelapediaTest: Steelapedia's articles (Steelapedia, SteelapediaMarkup)
# and its pages.
#   - every row of the markup table, links to missing articles, brackets
#   - the file header (requires as JSON, infobox order), an article's and a
#     section's requires
#   - generated articles: every listed part and real maker, every Entity
#     species; a secret part once owned; never test parts; a file replacing
#     a generated body but not its infobox; Lorem Ipsum the same per slug
#   - search, random, categories; every page, a missing slug, the redirects;
#     the links between amazing.com, pilot.net and Steelapedia
# Loads are instant (NetWindow.load_time_scale 0).

const LISTED_PART := ["arm_weapon", "MA-L127"]
const SECRET_PART := ["head", "Percival-Head"]


func run_tests() -> void:
	await case("the markup, row by row", _test_markup)
	await case("sections and their requires", _test_sections)
	await case("the file header", _test_header)
	await case("the sample files", _test_files)
	await case("an article's requires", _test_article_requires)
	await case("generated articles", _test_generated)
	await case("a secret part once owned", _test_secret_part)
	await case("a file replaces a generated body, not its data", _test_override)
	await case("Lorem Ipsum", _test_lorem)
	await case("search, random and categories", _test_search)
	await case("what links here, new articles, view source, the logo", _test_helpers)
	await case("every page opens", _test_pages)
	await case("links between the sites", _test_cross_links)
	NetWindow.load_time_scale = 1.0


func before_each() -> void:
	StoryDirector.reset(false)
	PlayerProgress.reset()
	PilotNet.reset(false)
	Steelapedia.reload_articles()
	NetWindow.load_time_scale = 0.0
	MechOS.close_all()


func _exists(slug: String) -> bool:
	return slug == "real" or slug == "martel"


func _title(slug: String) -> String:
	return "Real Article" if slug == "real" else ""


func _bb(text: String) -> String:
	return SteelapediaMarkup.to_bbcode(text, _exists, _title)


func _net(url: String) -> NetWindow:
	MechOS.set_app_available("net", true)
	var window: NetWindow = MechOS.open_net(url)
	check(window != null, "NET opens")
	return window


# ---- markup -----------------------------------------------------------------------

func _test_markup() -> void:
	check_eq(_bb("'''bold'''"), "[b]bold[/b]", "'''bold'''")
	check_eq(_bb("''italic''"), "[i]italic[/i]", "''italic''")
	check_eq(_bb("a '''b''' and ''c'' d"), "a [b]b[/b] and [i]c[/i] d", "both in a line")
	var link := SteelapediaMarkup.link_color()
	check_eq(_bb("[[real]]"), "[url=wiki:real][color=%s]Real Article[/color][/url]" % link, "[[slug]] names the article")
	check_eq(_bb("[[real|the text]]"), "[url=wiki:real][color=%s]the text[/color][/url]" % link, "[[slug|text]]")
	check_eq(_bb("[[Real]]"), "[url=wiki:real][color=%s]Real Article[/color][/url]" % link, "a slug in any case")
	check(link != SteelapediaMarkup.missing_color(), "links and missing links differ")
	var missing := SteelapediaMarkup.missing_color()
	check_eq(_bb("[[nowhere|gone]]"), "[url=wiki:nowhere][color=%s][s]gone[/s][/color][/url]" % missing,
			"a missing article: dim and struck through")
	check_eq(_bb("[[no_such_thing]]"), "[url=wiki:no_such_thing][color=%s][s]no such thing[/s][/color][/url]" % missing,
			"its slug as the text")
	check_eq(_bb("[[net:pilot.net/board/news|the news]]"), "[url=net:pilot.net/board/news][color=%s]the news[/color][/url]" % link,
			"a link to another site")
	check_eq(_bb("* one\n* two"), "[ul]one\ntwo[/ul]", "bullets")
	check_eq(_bb("first\n\nsecond"), "first\n\nsecond", "a blank line is a new paragraph")
	check_eq(_bb("a [b] c"), "a [lb]b[rb] c", "other brackets are made safe")
	check_eq(_bb("text\n* item\nmore"), "text\n[ul]item[/ul]\nmore", "a list between lines")


func _test_sections() -> void:
	var body := "Lead text.\n\n== History ==\nOld.\n\n=== Early ===\nEarlier.\n\n== Secret ==\nrequires: {\"flags\": {\"s\": true}}\nHidden.\n\n=== Inside ===\nAlso hidden.\n\n== After ==\nShown."
	var sections := SteelapediaMarkup.sections(body)
	check_eq(sections.map(func(s): return [s.level, s.title]), [[0, ""], [2, "History"], [3, "Early"], [2, "Secret"], [3, "Inside"], [2, "After"]],
			"== and === headings")
	check_eq(sections[0].text, "Lead text.", "the lead")
	check_eq(sections[3].requires, {"flags": {"s": true}}, "a requires line right after a heading")
	check_eq(sections[3].text, "Hidden.", "isn't text")
	var meets := func(c: Dictionary) -> bool: return StoryDirector.meets(c)
	var shown := SteelapediaMarkup.visible_sections(body, meets).map(func(s): return s.title)
	check_eq(shown, ["", "History", "Early", "After"], "a hidden section hides only itself and its subsections")
	StoryDirector.set_flag("s", true, false)
	check_eq(SteelapediaMarkup.visible_sections(body, meets).size(), 6, "until its conditions pass")


func _test_header() -> void:
	var text := "title: Martel Shipping\nsummary: One line.\nrequires: {\"flags\": {\"met_martel\": true}}\ninfobox.Founded: [YEAR]\ninfobox.Headquarters: [PLACE]\nsee_also: orontes, PT Gajah Teknis\n---\n'''Martel''' is.\n\n== History ==\nText."
	var article := Steelapedia.parse(text, "Martel", "manufacturers")
	check_eq(article.slug, "martel", "the slug from the file name, lower case")
	check_eq(article.title, "Martel Shipping", "title")
	check_eq(article.summary, "One line.", "summary")
	check_eq(article.requires, {"flags": {"met_martel": true}}, "requires as JSON")
	check_eq(article.infobox, [["Founded", "[YEAR]"], ["Headquarters", "[PLACE]"]], "the infobox in file order")
	check_eq(article.see_also, ["orontes", "pt_gajah_teknis"], "see_also as slugs")
	check(article.body.begins_with("'''Martel''' is."), "the body after ---")
	check(article.errors.is_empty(), "no errors")
	var bad := Steelapedia.parse("title: X\ncolour: red\nrequires: not json\nno colon here\n---\nBody.", "x", "misc")
	var problems := " | ".join(bad.errors)
	check("unknown header key 'colour'" in problems and "requires isn't a JSON object" in problems and "isn't 'key: value'" in problems,
			"mistakes are caught (%s)" % problems)
	check("no '---' line" in " ".join(Steelapedia.parse("title: X\nBody.", "x", "misc").errors), "a missing --- too")


func _test_files() -> void:
	check(Steelapedia.load_errors.is_empty(), "every file reads cleanly (%s)" % str(Steelapedia.load_errors))
	for category in ["pilots", "places", "history", "misc"]:
		var dir := DirAccess.open(Steelapedia.ROOT + category)
		check(dir != null and dir.get_files().size() >= 1, "a sample file in %s" % category)
	var sample = Steelapedia.get_article("sample_markup")
	check(sample != null and sample.title.begins_with("[SAMPLE]") and sample.category == "misc", "the markup sample")
	check_eq(sample.infobox, [["Type", "[SAMPLE]"], ["First seen", "Day 1"]], "with its infobox")
	check(Steelapedia.get_article("sample_pilot").title.begins_with("[SAMPLE]"), "the pilot sample")


func _test_article_requires() -> void:
	check(Steelapedia.get_article("sample_history") == null and not Steelapedia.article_exists("sample_history"),
			"an article hidden by its requires")
	check(not Steelapedia.all_articles().any(func(a): return a.slug == "sample_history"), "nowhere in the lists")
	PilotNet.day = 4
	StoryDirector.set_flag("sample_history_unlocked", true, false)
	check(Steelapedia.get_article("sample_history") != null, "shows once it passes")
	check_eq(Steelapedia.last_modified_day("sample_history"), 4, "last modified on the day it first showed")
	check_eq(Steelapedia.last_modified_day("sample_place"), 1, "Day 1 for an article that always showed")


func _test_generated() -> void:
	var missing := []
	for part_type in Store.CATEGORIES:
		for part_id in Store.catalogue(part_type):
			if not Steelapedia.article_exists(part_id):
				missing.append(part_id)
	check(missing.is_empty(), "every listed part has an article (%s)" % str(missing))
	for maker in Manufacturers.real_ids():
		check(Steelapedia.article_exists(maker), "%s has an article" % maker)
	check(not Steelapedia.article_exists("test"), "not the test maker")
	for entry in [["chipset", "type_1_chip"], ["thruster", "type_1_thruster"], ["internal", "WD-2"], ["core", "Null"]]:
		check(not Steelapedia.article_exists(entry[1]), "no article for test part %s" % entry[1])
	PlayerProgress.add_part("chipset", "type_1_chip", false)
	check(not Steelapedia.article_exists("type_1_chip"), "not even once owned")
	for species in ["Coyote", "Coyote Spitter", "Fisher", "Tick Swarm", "Stalker", "Brute"]:
		check(Steelapedia.article_exists(SteelapediaMarkup.slug_of(species)), "the %s has an article" % species)
	var part = Steelapedia.get_article(LISTED_PART[1])
	var labels: Array = part.infobox.map(func(r): return r[0])
	for wanted in ["Maker", "Part type", "Tech tier", "Price", "Weight", "Size", "Damage", "Clip size"]:
		check(wanted in labels, "a part's infobox has %s" % wanted)
	check(part.infobox[0][1].begins_with("[[martel|"), "the maker as a link")
	check(part.body.contains("== Overview ==") and part.body.contains("== Variants =="), "Lorem Ipsum sections")
	check(part.links[0][0] == "Buy on amazing.com" and part.links[0][1] == NetSites.product_url(LISTED_PART[0], LISTED_PART[1]),
			"Buy on amazing.com")
	check(part.categories.has("parts") and part.categories.has("arm_weapons") and part.categories.has("martel"),
			"in Parts, its type and its maker (%s)" % str(part.categories))
	var maker = Steelapedia.get_article("claymore")
	var maker_rows: Dictionary = {}
	for row in maker.infobox:
		maker_rows[row[0]] = row[1]
	check(maker_rows.get("Website") == "[[net:claymore-intl.co.uk|claymore-intl.co.uk]]", "a maker's website as a NET link")
	check_eq(maker_rows.get("Parts in the catalogue"), str(Store.catalogue_of_maker("claymore").size()), "its parts count")
	check(str(maker.extra_sections.get("Products", "")).contains("[[lancelot-core|Lancelot-Core]]"), "a generated product list")
	var entity = Steelapedia.get_article("coyote")
	check(entity.infobox == [["Species", "Coyote"], ["Classification", "[CLASSIFICATION]"]], "an Entity's infobox")
	check(entity.body.contains("== Description ==") and entity.body.contains("== Encounters =="), "and its sections")


func _test_secret_part() -> void:
	var part = PartManager.get_part(SECRET_PART[0], SECRET_PART[1])
	part.store_listed = false
	Steelapedia.known_parts.clear()
	check(not Steelapedia.article_exists(SECRET_PART[1]), "a secret part has no article")
	PlayerProgress.add_part(SECRET_PART[0], SECRET_PART[1], false)
	check(Steelapedia.article_exists(SECRET_PART[1]), "until the player owns one")
	PlayerProgress.remove_part(SECRET_PART[0], SECRET_PART[1], false)
	check(Steelapedia.article_exists(SECRET_PART[1]), "and it stays after")
	var data: Dictionary = JSON.parse_string(JSON.stringify(Steelapedia.get_save_data()))
	Steelapedia.set_save_data({})
	check(not Steelapedia.article_exists(SECRET_PART[1]), "(forgotten without the save)")
	Steelapedia.set_save_data(data)
	check(Steelapedia.article_exists(SECRET_PART[1]), "saved")
	part.store_listed = true


func _test_override() -> void:
	var file := Steelapedia.parse("summary: Yosqi's summary.\ninfobox.Nickname: Old Reliable\n---\nYosqi's own text.\n\n== Products ==\nHand-written.",
			"martel", "manufacturers")
	Steelapedia._files["martel"] = file
	var article = Steelapedia.get_article("martel")
	Steelapedia._files.erase("martel")
	check_eq(article.body, file.body, "the file's body replaces the Lorem Ipsum")
	check_eq(article.summary, "Yosqi's summary.", "and its summary")
	check_eq(article.title, Manufacturers.display_name("martel"), "the title stays the maker's")
	var labels: Array = article.infobox.map(func(r): return r[0])
	check(labels.has("Website") and labels.has("Parts in the catalogue"), "the generated infobox stays")
	check_eq(labels[-1], "Nickname", "with the file's rows after it")
	check(str(article.extra_sections.get("Products", "")).contains("[["), "and the generated product list")


func _test_lorem() -> void:
	check_eq(Steelapedia.lorem("martel", 2), Steelapedia.lorem("martel", 2), "the same for the same slug")
	check(Steelapedia.lorem("martel", 1) != Steelapedia.lorem("orontes", 1), "different for another")
	check_eq(Steelapedia.lorem("x", 3).split("\n\n").size(), 3, "paragraphs")
	check(Steelapedia.get_article("martel").body == Steelapedia.get_article("martel").body, "an article's prose is stable")


func _test_search() -> void:
	var found := Steelapedia.search("martel")
	check(not found.is_empty() and found[0].slug == "martel", "a title match first (%s)" % str(found.map(func(article): return article.slug).slice(0, 3)))
	var by_text := Steelapedia.search("Hand-written nowhere")
	check(by_text.is_empty(), "nothing for nothing")
	check(Steelapedia.exact_title("martel shipping and sav manufacturing").slug == "martel", "an exact title, any case")
	check(Steelapedia.random_article() != null, "a random article")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var a = Steelapedia.random_article(rng)
	rng.seed = 3
	check_eq(Steelapedia.random_article(rng).slug, a.slug, "random from a seeded rng is repeatable")
	var listed := 0
	for part_type in Store.CATEGORIES:
		listed += Store.catalogue(part_type).size()
	check_eq(Steelapedia.articles_in("parts").size(), listed, "Parts holds every listed part")
	check_eq(Steelapedia.articles_in("heads").size(), Store.catalogue("head").size(), "a part type's category")
	check_eq(Steelapedia.articles_in("claymore").size(), Store.catalogue_of_maker("claymore").size(), "a maker's category")
	var titles: Array = Steelapedia.articles_in("manufacturers").map(func(x): return x.title)
	var sorted := titles.duplicate()
	sorted.sort_custom(func(x, y): return str(x).naturalnocasecmp_to(str(y)) < 0)
	check_eq(titles, sorted, "A-Z")
	check_eq(Steelapedia.category_name("arm_weapons"), "Arm weapons", "category names")
	check_eq(Steelapedia.category_name("martel"), "Martel", "a maker's short name")


func _test_helpers() -> void:
	var linking: Array = Steelapedia.links_to("martel").map(func(a): return a.slug)
	check(linking.has("sample_markup"), "a [[link]] in the text links")
	check(linking.has("ma-l127"), "a part links to its maker")
	check(Steelapedia.links_to("ma-l127").map(func(a): return a.slug).has("martel"), "and the maker to its parts")
	check(Steelapedia.links_to("no_such_article").map(func(a): return a.slug).has("sample_markup"), "a red link links too")
	check_eq(Steelapedia.recent_articles(3).size(), 3, "new articles")
	PilotNet.day = 7
	StoryDirector.set_flag("sample_history_unlocked", true, false)
	check_eq(Steelapedia.last_modified_day("sample_history"), 7, "an article that shows on day 7")
	check_eq(Steelapedia.recent_articles(1)[0].slug, "sample_history", "the last article to show comes first")
	var source := Steelapedia.source_of(Steelapedia.get_article("sample_markup"))
	check(source.begins_with("title: [SAMPLE] Markup sample") and "\n---\n" in source and "== Lorem ipsum ==" in source,
			"a file's source: its header, then its sections")
	check(not "Nemo enim ipsam" in source and not "requires:" in source, "without a hidden section or requires lines")
	StoryDirector.set_flag("sample_steelapedia_section", true, false)
	check("Nemo enim ipsam" in Steelapedia.source_of(Steelapedia.get_article("sample_markup")), "the section once it shows")
	var made := Steelapedia.source_of(Steelapedia.get_article("ma-l127"))
	check(made.begins_with("title: " + Store.part_name("arm_weapon", "MA-L127")) and "infobox.Maker:" in made,
			"a generated article's source is its data")
	var picture := SteelapediaLogo.picture()
	var side := SteelapediaLogo.DIAMETER + 2
	check_eq(picture.get_size(), Vector2(side, side), "the logo is drawn at its size")
	var image := picture.get_image()
	var holes := 0
	var tones := {}
	for y in side:
		for x in side:
			var inside := Vector2(x + 0.5 - side / 2.0, y + 0.5 - side / 2.0).length() < SteelapediaLogo.DIAMETER / 2.0 - 2.0
			var colour := image.get_pixel(x, y)
			if inside and colour.a == 0.0:
				holes += 1
			elif colour.a > 0.0:
				tones[colour.to_html()] = true
	check(holes > 20, "one plate is missing (%d clear pixels)" % holes)
	check(tones.size() >= 3 and tones.size() <= 7, "the globe uses the theme greys (%d)" % tones.size())


# ---- pages ------------------------------------------------------------------------

func _test_pages() -> void:
	var window := _net("steelapedia.net/")
	var page: SteelapediaPage = window.page
	var text := page.get_text()
	check(SteelapediaPage.WELCOME in text and "Today's featured article" in text and "In the news" in text
			and "Did you know..." in text and "Portals:" in text and "New articles" in text, "the Main Page")
	check(SteelapediaPage.LOGO in text and SteelapediaPage.MOTTO in text and "Random article" in text
			and "navigation" in text and "search" in text and "toolbox" in text, "the sidebar")
	check(not page.find_children("*", "SteelapediaLogo", true, false).is_empty(), "the logo")
	check("Today's featured picture" in text or SteelapediaPage.featured_picture().is_empty(), "the featured picture")
	check(SteelapediaPage.LICENSE in text and not "last modified" in text, "the footer, without a date on the Main Page")
	var featured := SteelapediaPage.featured_slug
	window.reload()
	check_eq(SteelapediaPage.featured_slug, featured, "the same featured article all session")
	for path in ["/wiki/martel", "/wiki/MA-L127", "/wiki/coyote", "/wiki/sample_markup", "/wiki/sample_pilot",
			"/wiki/martel?action=edit", "/wiki/martel?action=history", "/wiki/martel?action=talk", "/?action=talk",
			"/category/parts", "/category/heads", "/category/martel", "/category/places", "/special/all",
			"/special/categories", "/special/whatlinkshere/martel", "/special/specialpages", "/special/nothing",
			"/search?q=lorem", "/search?q=lorem&fulltext=1", "/search?q=zzzz", "/search", "/wiki/no_such_article", "/nonsense"]:
		window.navigate("steelapedia.net" + path)
		check(window.page is SteelapediaPage and window.page.page_title.begins_with("Steelapedia"), "%s opens" % path)
	window.navigate("steelapedia.net/wiki/MA-L127")
	page = window.page
	text = page.get_text()
	check(page.article.slug == "ma-l127" and SteelapediaPage.FROM in text, "an article")
	check(not page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("infobox")).is_empty(), "with an infobox")
	check(not page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("contents")).is_empty(),
			"a contents box (4 sections)")
	check(not page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("categories")).is_empty()
			and "Categories" in text and "Martel" in text, "the category bar")
	check("This page was last modified on %s." % PilotNet.long_date(1) in text, "last modified")
	check("Buy on amazing.com" in text, "the amazing.com link")
	var tabs := page.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("url") and not b is LinkButton)
	check_eq(tabs.map(func(b): return b.text), ["article", "discussion", "view source", "history"], "the tabs")
	check(tabs[0].theme_type_variation == &"NetWikiTabActive" and tabs[1].theme_type_variation == &"NetWikiTab", "the open tab")
	var links: Array = page.find_children("*", "LinkButton", true, false).map(func(l): return str(l.get_meta("url", "")))
	check(links.has("steelapedia.net/wiki/ma-l127?action=edit"), "[edit] links to view source")
	check(links.has("steelapedia.net/special/whatlinkshere/ma-l127"), "the toolbox's What links here")

	window.navigate("steelapedia.net/wiki/martel")
	text = window.page.get_text()
	var symbol := FourX.symbol_of_maker("martel")
	check(symbol != "" and ("FourX: " + symbol) in text, "a maker's infobox names its FourX stock")
	window.navigate("steelapedia.net/special/whatlinkshere/martel")
	text = window.page.get_text()
	check("[SAMPLE] Markup sample" in text and Store.part_name("arm_weapon", "MA-L127") in text, "what links to Martel")
	window.navigate("steelapedia.net/wiki/sample_markup?action=edit")
	text = window.page.get_text()
	check(SteelapediaPage.PROTECTED in text and "== Lorem ipsum ==" in text and "[[martel]]" in text, "view source shows the markup")
	check(not "Nemo enim ipsam" in text and not "requires:" in text, "but not a hidden section or a requires line")
	window.navigate("steelapedia.net/wiki/ma-l127?action=history")
	check("Revision history" in window.page.get_text() and SteelapediaPage.EDITOR in window.page.get_text(), "history")
	window.navigate("steelapedia.net/wiki/ma-l127?action=talk")
	check(SteelapediaPage.NO_TALK in window.page.get_text(), "the discussion")
	window.navigate("steelapedia.net/wiki/sample_markup")
	text = window.page.get_text()
	check(not "Nemo enim ipsam" in text and "Neque porro quisquam" in text, "a hidden section isn't shown, the others are")
	check("See also" in text, "See also")
	StoryDirector.set_flag("sample_steelapedia_section", true, false)
	window.reload()
	check("Nemo enim ipsam" in window.page.get_text(), "it shows once it passes")
	window.navigate("steelapedia.net/wiki/sample_place")
	check(window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("contents")).is_empty(),
			"no contents box under three sections")
	window.navigate("steelapedia.net/wiki/no_such_article")
	text = window.page.get_text()
	check(SteelapediaPage.MISSING in text and "Search for \"no such article\"" in text and "Main Page" in text, "a missing slug")
	window.navigate("steelapedia.net/special/random")
	await wait_frames(2)
	check(window.current_url.begins_with("steelapedia.net/wiki/"), "Random goes to an article (%s)" % window.current_url)
	window.navigate("steelapedia.net/search?q=Martel%20Shipping%20and%20SAV%20Manufacturing")
	await wait_frames(2)
	check_eq(window.current_url, "steelapedia.net/wiki/martel", "one exact title match goes straight to it")
	window.navigate("steelapedia.net/search?q=lorem")
	await wait_frames(2)
	check(window.current_url.begins_with("steelapedia.net/search"), "a search with no exact match stays")
	check("result" in window.page.get_text(), "and lists the results")


func _test_cross_links() -> void:
	var window := _net("amazing.com/p/arm_weapon/MA-L127")
	var links: Array = window.page.find_children("*", "LinkButton", true, false).map(func(l): return str(l.get_meta("url", "")))
	check(links.has(NetSites.wiki_url("MA-L127")), "amazing.com's Read more on Steelapedia goes to the article")
	window.navigate("amazing.com/maker/martel")
	links = window.page.find_children("*", "LinkButton", true, false).map(func(l): return str(l.get_meta("url", "")))
	check(links.has(NetSites.wiki_url("martel")), "a maker page links to the maker's article")
	PilotNet.post({"id": "wiki_news", "board": "news", "title": "Fresh news", "body": "Body."})
	window.navigate("steelapedia.net/")
	links = window.page.find_children("*", "LinkButton", true, false).map(func(l): return str(l.get_meta("url", "")))
	check(links.has("pilot.net/post/wiki_news"), "In the news links back to pilot.net posts")
	window.navigate(NetSites.wiki_url("martel"))
	var body: Array = window.page.find_children("*", "RichTextLabel", true, false).map(func(r): return r.text)
	check(" ".join(body).contains("[url=net:claymore-intl.co.uk]") or " ".join(body).contains("[url=net:martel-sav.com]"),
			"an article's NET links")
