class_name AmazingPage
extends NetPage

## amazing.com, the regional store (Store), "A+B 2 · Grey bars": a dithered
## banner with the logo and a search box, a grey tab strip, a SHOP BY PART
## box on the left and a footer with the hit counter. Paths:
##   /                         This Week's Picks (chosen once a session) and a featured part
##   /hardware /wetware /weapons  the group's categories with their item counts
##   /c/<type>?sort=           a category table (sort: price, name, maker)
##   /p/<type>/<id>            a product page, compared with what's fitted
##   /search?q=                search results
##   /makers  /maker/<id>      makers A-Z, one maker's parts by category
##   /cart  /checkout  /receipt   buying (Store.checkout)
##   /guestbook                under construction
## The hit counter starts at VISITOR_START and goes up by one each time a
## page opens (not saved). A part row or a product page right-clicks as a
## store "part" (NetPage).

const LOGO := "amazing.com"
const TAGLINE := "the region's general store, est. 1994"
const VISITOR_START := 4216
const PICKS_MIN := 4
const PICKS_MAX := 6
const LEFT_WIDTH := 190
const SPRITE_BOX := Vector2(360, 420)
const FEATURE_BOX := Vector2(210, 210)
const OUT_OF_STOCK := "OUT OF STOCK. Check back after the next shipment."
const NOTHING_FITTED := "Nothing fitted to compare."
const TABS := [["Home", "/"], ["Hardware", "/hardware"], ["Wetware", "/wetware"],
		["Weapons", "/weapons"], ["Makers A-Z", "/makers"]]
const TAB_CART := 5
const SORTS := [["Price", "price"], ["Name", "name"], ["Maker", "maker"]]

static var visitors := VISITOR_START
static var picks: Array = []
static var featured: Array = []
static var _rng: RandomNumberGenerator = null

var main: VBoxContainer
var _cart_tab: Button
var _compare: PartCompare = null
var _compare_side := "left"


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	visitors += 1
	var segments := Array(page_path.split("/", false))
	var first: String = str(segments[0]).to_lower() if not segments.is_empty() else ""
	var active := _active_tab(first, segments)
	add_child(NetUI.banner(LOGO, TAGLINE, _search_box()))
	add_child(_tabs(active))
	var body := NetUI.panel(&"NetContent")
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var columns := NetUI.hbox(&"NetColumns")
	body.add_child(columns)
	columns.add_child(_left_column())
	main = NetUI.vbox(&"NetStack")
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(main)
	page_title = LOGO
	if first == "":
		_home()
	elif first in ["hardware", "wetware", "weapons"] and segments.size() == 1:
		_group(first)
	elif first == "c" and segments.size() == 2:
		_category(_part_type(segments[1]))
	elif first == "p" and segments.size() == 3:
		_product(_part_type(segments[1]), str(segments[2]))
	elif first == "search":
		_search(str(page_query.get("q", "")))
	elif first == "makers" and segments.size() == 1:
		_makers()
	elif first == "maker" and segments.size() == 2:
		_maker(str(segments[1]).to_lower())
	elif first == "cart":
		_cart()
	elif first == "checkout":
		_checkout()
	elif first == "receipt":
		_receipt()
	elif first == "guestbook":
		_guestbook()
	else:
		_not_found()
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(filler)
	main.add_child(_footer())
	Store.feed.cart_changed.connect(_on_cart_changed)


## The counter's six digits as shown (tests).
static func counter_text() -> String:
	return str(visitors).pad_zeros(NetUI.COUNTER_DIGITS)


## The week's picks, chosen once a session from everything listed.
static func ensure_picks() -> void:
	var listed := []
	for part_type in Store.CATEGORIES:
		for part_id in Store.catalogue(part_type):
			listed.append([part_type, part_id])
	picks = picks.filter(func(e): return Store.is_listed(e[0], e[1]))
	if not picks.is_empty() or listed.is_empty():
		return
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	var pool := listed.duplicate()
	var count := mini(_rng.randi_range(PICKS_MIN, PICKS_MAX), pool.size())
	for i in count:
		picks.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
	featured = pool[_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else picks[0]


# ---- the frame --------------------------------------------------------------

func _search_box() -> HBoxContainer:
	var row := NetUI.hbox(&"NetToolbar")
	row.add_child(NetUI.text("Search:"))
	var field := NetUI.input("", 200)
	field.text = str(query.get("q", "")) if path.to_lower() == "/search" else ""
	row.add_child(field)
	var go := NetUI.button("GO!")
	row.add_child(go)
	field.text_submitted.connect(func(text): _submit_search(text))
	go.pressed.connect(func(): _submit_search(field.text))
	return row


func _submit_search(text: String) -> void:
	if text.strip_edges() == "":
		AudioManager.play_sfx("deny_softer")
		return
	follow(NetSites.search_url(text.strip_edges()))


func _tabs(active: int) -> PanelContainer:
	var tabs := TABS.map(func(t): return [t[0], NetSites.store_url(t[1])])
	var strip := NetUI.tab_strip(self, tabs, [[_cart_label(), NetSites.store_url("/cart")]], active)
	for node in strip.find_children("*", "Button", true, false):
		if node.get_meta("url", "") == NetSites.store_url("/cart"):
			_cart_tab = node
	return strip


func _cart_label() -> String:
	return "Your cart (%d)" % Store.cart_count()


func _active_tab(first: String, segments: Array) -> int:
	if first == "":
		return 0
	if first in ["cart", "checkout", "receipt"]:
		return TAB_CART
	if first in ["makers", "maker"]:
		return 4
	var group_id := first
	if (first == "c" or first == "p") and segments.size() >= 2:
		group_id = str(Store.group_of(_part_type(segments[1])).get("id", ""))
	for i in TABS.size():
		if TABS[i][1] == "/" + group_id:
			return i
	return -1


func _left_column() -> VBoxContainer:
	var column := NetUI.vbox(&"NetStack")
	column.custom_minimum_size.x = LEFT_WIDTH
	var links := NetUI.vbox(&"NetTightStack")
	for part_type in Store.CATEGORIES:
		var link := NetUI.link(self, Store.type_name(part_type, false), NetSites.category_url(part_type))
		link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		links.add_child(link)
	column.add_child(NetUI.box("SHOP BY PART", NetUI.panel(&"NetBoxBody", links)))
	column.add_child(NetUI.construction(["UNDER CONSTRUCTION", "Mil-Grade Imports"]))
	return column


func _footer() -> HBoxContainer:
	var row := NetUI.hbox(&"NetToolbar")
	row.add_child(NetUI.text("You are visitor no.", &"NetMeta"))
	row.add_child(NetUI.hit_counter(visitors))
	row.add_child(MechUI.spacer())
	row.add_child(NetUI.text("Best viewed at 800x600.", &"NetMeta"))
	row.add_child(NetUI.link(self, "Sign our guestbook!", NetSites.store_url("/guestbook")))
	return row


func _on_cart_changed() -> void:
	if is_instance_valid(_cart_tab):
		_cart_tab.text = _cart_label()


# ---- pages ------------------------------------------------------------------

func _home() -> void:
	page_title = "%s - Home" % LOGO
	ensure_picks()
	main.add_child(NetUI.heading("This Week's Picks!"))
	if picks.is_empty():
		main.add_child(NetUI.text(OUT_OF_STOCK, &"NetMeta"))
		return
	main.add_child(_part_table(picks, true))
	if featured.is_empty():
		return
	var part_type: String = featured[0]
	var part_id: String = featured[1]
	var part := Store.get_part(part_type, part_id)
	var row := NetUI.hbox(&"NetColumns")
	row.set_meta("net_part", featured)
	row.add_child(NetUI.sprite(part.get("image"), FEATURE_BOX, Store.part_name(part_type, part_id)))
	var info := NetUI.vbox(&"NetTightStack")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(NetUI.text("FEATURED: %s" % Store.part_name(part_type, part_id), &"NetBodyBright"))
	info.add_child(_by_maker(part_type, part_id))
	var blurb := str(part.get("tagline")) if str(part.get("tagline")) != "" else _first_sentence(str(part.get("description")))
	if blurb != "":
		info.add_child(NetUI.text(blurb, &"NetBody", true))
	info.add_child(NetUI.text("%s · %d CT" % [Store.type_name(part_type), Store.price(part_type, part_id)], &"NetMeta"))
	var links := NetUI.hbox(&"NetToolbar")
	links.add_child(NetUI.link(self, "View product", NetSites.product_url(part_type, part_id)))
	links.add_child(NetUI.text("|", &"NetMeta"))
	links.add_child(NetUI.link(self, "Read more on Steelapedia", _steelapedia_url(part_id)))
	links.add_child(NetUI.text("|", &"NetMeta"))
	links.add_child(NetUI.link(self, "Visit maker's site", Manufacturers.domain_of(Store.maker_of(part_type, part_id))))
	info.add_child(links)
	row.add_child(info)
	main.add_child(row)


func _group(group_id: String) -> void:
	var group := Store.group_by_id(group_id)
	page_title = "%s - %s" % [LOGO, str(group.name).capitalize()]
	main.add_child(NetUI.heading(str(group.name).capitalize()))
	var rows := []
	for part_type in group.types:
		var count := Store.catalogue(part_type).size()
		rows.append([NetUI.link(self, Store.type_name(part_type, false), NetSites.category_url(part_type)),
				NetUI.text("%d item%s" % [count, "" if count == 1 else "s"] if count > 0 else "OUT OF STOCK", &"NetMeta")])
	main.add_child(NetUI.table([{"title": "Department"}, {"title": "In stock", "width": 160, "align": "right"}], rows))


func _category(part_type: String) -> void:
	if part_type == "":
		_not_found()
		return
	page_title = "%s - %s" % [LOGO, Store.type_name(part_type, false)]
	main.add_child(NetUI.heading(Store.type_name(part_type, false)))
	var ids := Store.catalogue(part_type)
	if ids.is_empty():
		main.add_child(NetUI.construction(["OUT OF STOCK", "Check back after the next shipment."]))
		main.get_child(-1).set_meta("out_of_stock", true)
		return
	var sort := str(query.get("sort", "price")).to_lower()
	var sorts := NetUI.hbox(&"NetToolbar")
	sorts.add_child(NetUI.text("Sort by:", &"NetMeta"))
	for entry in SORTS:
		var url := NetSites.store_url("/c/" + part_type, {"sort": entry[1]})
		if entry[1] == sort:
			sorts.add_child(NetUI.text(entry[0], &"NetBodyBright"))
		else:
			sorts.add_child(NetUI.link(self, entry[0], url))
	main.add_child(sorts)
	var entries: Array = ids.map(func(id): return [part_type, id])
	main.add_child(_part_table(sort_entries(entries, sort), false))


func _search(text: String) -> void:
	page_title = "%s - Search" % LOGO
	main.add_child(NetUI.heading("Search results"))
	if text.strip_edges() == "":
		main.add_child(NetUI.text("Type the name of a part or a maker in the box above, then press GO!", &"NetMeta", true))
		return
	var found := Store.search(text)
	main.add_child(NetUI.text("%d result%s for \"%s\"" % [found.size(), "" if found.size() == 1 else "s", text], &"NetMeta"))
	if found.is_empty():
		main.add_child(NetUI.text("No parts matched. Check the spelling or try fewer words.", &"NetBody", true))
		return
	main.add_child(_part_table(found, false))


func _makers() -> void:
	page_title = "%s - Makers A-Z" % LOGO
	main.add_child(NetUI.heading("Makers A-Z"))
	var rows := []
	for maker_id in Manufacturers.real_ids():
		var stock := Store.catalogue_of_maker(maker_id).size()
		if stock == 0:
			continue
		rows.append([NetUI.link(self, Manufacturers.display_name(maker_id), NetSites.maker_url(maker_id)),
				NetUI.text("%d item%s" % [stock, "" if stock == 1 else "s"], &"NetMeta"),
				NetUI.link(self, Manufacturers.domain_of(maker_id), Manufacturers.domain_of(maker_id), true)])
	if rows.is_empty():
		main.add_child(NetUI.text(OUT_OF_STOCK, &"NetMeta"))
		return
	main.add_child(NetUI.table([{"title": "Maker"}, {"title": "Stock", "width": 110},
			{"title": "Their site", "width": 260}], rows))


func _maker(maker_id: String) -> void:
	if not Manufacturers.is_valid(maker_id) or Manufacturers.is_test(maker_id):
		_not_found()
		return
	page_title = "%s - %s" % [LOGO, Manufacturers.short_name(maker_id)]
	main.add_child(NetUI.heading(Manufacturers.display_name(maker_id)))
	var site := NetUI.hbox(&"NetToolbar")
	site.add_child(NetUI.text("Their own site:", &"NetMeta"))
	site.add_child(NetUI.link(self, Manufacturers.domain_of(maker_id), Manufacturers.domain_of(maker_id)))
	site.add_child(NetUI.text("|", &"NetMeta"))
	site.add_child(NetUI.link(self, "Read about them on Steelapedia", _steelapedia_url(maker_id)))
	main.add_child(site)
	var entries := Store.catalogue_of_maker(maker_id)
	if entries.is_empty():
		main.add_child(NetUI.text("No stock from this maker right now.", &"NetMeta"))
		return
	for part_type in Store.CATEGORIES:
		var of_type := entries.filter(func(e): return e[0] == part_type)
		if of_type.is_empty():
			continue
		main.add_child(NetUI.text(Store.type_name(part_type, false).to_upper(), &"NetBodyBright"))
		main.add_child(_part_table(of_type, false))


func _product(part_type: String, part_id: String) -> void:
	var part := Store.get_part(part_type, _part_id(part_type, part_id))
	if part == null or not Store.is_listed(part_type, part.part_id):
		_not_found()
		return
	part_id = str(part.part_id)
	page_title = "%s - %s" % [LOGO, Store.part_name(part_type, part_id)]
	set_meta("net_part", [part_type, part_id])
	var top := NetUI.hbox(&"NetColumns")
	top.add_child(NetUI.sprite(part.get("image"), SPRITE_BOX, Store.part_name(part_type, part_id)))
	var info := NetUI.vbox(&"NetStack")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(NetUI.heading(Store.part_name(part_type, part_id)))
	info.add_child(_by_maker(part_type, part_id))
	var tagline := str(part.get("tagline"))
	if tagline != "":
		info.add_child(NetUI.text(tagline, &"NetBodyBright", true))
	var description := str(part.get("description"))
	if description != "":
		info.add_child(NetUI.text(description, &"NetBody", true))
	var facts := NetUI.vbox(&"NetTightStack")
	facts.add_child(_fact("Price", "%d CT" % Store.price(part_type, part_id)))
	facts.add_child(_fact("Part", Store.type_name(part_type)))
	facts.add_child(_fact("Tech tier", _tier(part)))
	var item_size = part.get("item_size")
	if item_size is Array and item_size.size() >= 2:
		facts.add_child(_fact("Size", "%d × %d" % [int(item_size[0]), int(item_size[1])]))
	facts.add_child(_fact("Weight", MechUI.fmt(float(part.get("weight")))))
	facts.add_child(_fact("In your stash", str(PlayerProgress.count_part(part_type, part_id))))
	facts.add_child(_fact("Fitted", _fitted_text(part_type, part_id)))
	info.add_child(facts)
	var buy := NetUI.button("Add to cart")
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	buy.pressed.connect(_add_to_cart.bind(part_type, part_id))
	info.add_child(buy)
	var links := NetUI.hbox(&"NetToolbar")
	links.add_child(NetUI.link(self, "Read more on Steelapedia", _steelapedia_url(part_id)))
	links.add_child(NetUI.text("|", &"NetMeta"))
	links.add_child(NetUI.link(self, "Visit maker's site", Manufacturers.domain_of(Store.maker_of(part_type, part_id))))
	info.add_child(links)
	top.add_child(info)
	main.add_child(top)

	main.add_child(NetUI.rule())
	main.add_child(NetUI.text("COMPARED WITH WHAT YOU HAVE FITTED", &"NetBodyBright"))
	if part_type == "arm_weapon" or part_type == "shoulder_weapon":
		var fitted := CompareWindow.fitted_parts(part_type)
		_compare_side = "left"
		if not fitted.any(func(f): return str(f.slot).ends_with("_left")) and fitted.any(func(f): return str(f.slot).ends_with("_right")):
			_compare_side = "right"
		var sides := NetUI.hbox(&"NetZeroRow")
		var group := ButtonGroup.new()
		for side in ["left", "right"]:
			var toggle := MechUI.button(side.to_upper(), &"NetTab")
			toggle.toggle_mode = true
			toggle.button_group = group
			toggle.button_pressed = side == _compare_side
			toggle.pressed.connect(_set_compare_side.bind(part_type, part_id, side))
			sides.add_child(toggle)
		main.add_child(NetUI.panel(&"NetTabBar", sides))
	_compare = PartCompare.new()
	main.add_child(_compare)
	_fill_compare(part_type, part_id)


func _cart() -> void:
	page_title = "%s - Your cart" % LOGO
	main.add_child(NetUI.heading("Your cart"))
	if Store.cart.is_empty():
		main.add_child(NetUI.text("Your cart is empty. Find something you like and press Add to cart!", &"NetBody", true))
	else:
		var rows := []
		for i in Store.cart.size():
			var entry: Array = Store.cart[i]
			rows.append([NetUI.link(self, Store.part_name(entry[0], entry[1]), NetSites.product_url(entry[0], entry[1])),
					NetUI.text(Store.type_name(entry[0]), &"NetMeta"),
					NetUI.text("%d CT" % Store.price(entry[0], entry[1])),
					_remove_link(i)])
		var table := NetUI.table([{"title": "Item"}, {"title": "Part", "width": 170},
				{"title": "Price", "width": 110, "align": "right"}, {"title": "", "width": 100, "align": "right"}], rows)
		var table_rows := NetUI.table_rows(table)
		for i in Store.cart.size():
			table_rows[i + 1].set_meta("net_part", Store.cart[i])
		main.add_child(table)
	var money := int(PlayerProgress.get_money())
	var total := Store.cart_total()
	var sums := NetUI.vbox(&"NetTightStack")
	sums.add_child(_fact("Total", "%d CT" % total))
	sums.add_child(_fact("Your balance", "%d CT" % money))
	sums.add_child(_fact("Balance after", "%d CT" % (money - total)))
	main.add_child(sums)
	var reason := Store.block_reason()
	if reason != "":
		main.add_child(_alert(reason))
	var proceed := NetUI.button("Proceed to checkout")
	proceed.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	proceed.disabled = reason != ""
	proceed.pressed.connect(follow.bind(NetSites.store_url("/checkout")))
	main.add_child(proceed)


func _checkout() -> void:
	page_title = "%s - Checkout" % LOGO
	main.add_child(NetUI.heading("Checkout"))
	var count := Store.cart_count()
	main.add_child(NetUI.text("Purchase %d item%s for %d CT?" % [count, "" if count == 1 else "s", Store.cart_total()], &"NetBodyBright"))
	main.add_child(NetUI.text("Orders are delivered to your %s at once." % Store.delivery_place().to_lower(), &"NetMeta"))
	var reason := Store.block_reason()
	if reason != "":
		main.add_child(_alert(reason))
	var row := NetUI.hbox(&"NetToolbar")
	var place := NetUI.button("Place order")
	place.disabled = reason != ""
	place.pressed.connect(_place_order)
	row.add_child(place)
	var cancel := NetUI.button("Cancel")
	cancel.pressed.connect(follow.bind(NetSites.store_url("/cart")))
	row.add_child(cancel)
	main.add_child(row)


func _receipt() -> void:
	page_title = "%s - Receipt" % LOGO
	main.add_child(NetUI.heading("Thank you for your order!"))
	var order := Store.last_order
	if order.is_empty():
		main.add_child(NetUI.text("No orders yet.", &"NetMeta"))
		return
	if str(order.order) != "":
		main.add_child(_fact("Order number", str(order.order)))
		main.add_child(_fact("Charged", "%d CT" % int(order.spent)))
		main.add_child(_fact("Delivered to", Store.delivery_place()))
		main.add_child(_entry_list(order.bought))
	else:
		main.add_child(NetUI.text("Nothing could be delivered.", &"NetBody"))
	if not order.left.is_empty():
		main.add_child(NetUI.text("%s FULL — left in your cart" % Store.delivery_place(), &"NetBodyBright"))
		main.add_child(_entry_list(order.left))
	var back := NetUI.link(self, "Back to the shop", NetSites.store_url("/"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	main.add_child(back)


func _guestbook() -> void:
	page_title = "%s - Guestbook" % LOGO
	var box := NetUI.construction(["UNDER CONSTRUCTION", "Guestbook", UnderConstructionPage.MESSAGE])
	main.add_child(box)


func _not_found() -> void:
	page_title = "%s - Not found" % LOGO
	main.add_child(NetUI.heading("Not found"))
	main.add_child(NetUI.text("The page you asked for isn't on this server.", &"NetBody", true))
	main.add_child(NetUI.link(self, "Back to the shop", NetSites.store_url("/")))


# ---- actions ----------------------------------------------------------------

func _add_to_cart(part_type: String, part_id: String) -> void:
	if Store.add_to_cart(part_type, part_id):
		AudioManager.play_sfx("keystrike")
	else:
		AudioManager.play_sfx("deny_softer")


func _place_order() -> void:
	var result := Store.checkout()
	if result.has("reason"):
		AudioManager.play_sfx("deny_softer")
		return
	if result.bought.is_empty():
		AudioManager.play_sfx("deny_softer")
	else:
		AudioManager.play_sfx("confirm")
		MechOS.refresh_inventory_windows()
	follow(NetSites.store_url("/receipt"))


func _set_compare_side(part_type: String, part_id: String, side: String) -> void:
	_compare_side = side
	_fill_compare(part_type, part_id)


func _fill_compare(part_type: String, part_id: String) -> void:
	var fitted := CompareWindow.fitted_parts(part_type)
	if part_type == "arm_weapon" or part_type == "shoulder_weapon":
		fitted = fitted.filter(func(f): return str(f.slot).ends_with("_" + _compare_side))
	var product := {"part_type": part_type, "part_id": part_id, "grade": Grades.STANDARD, "place": "store"}
	if fitted.is_empty():
		_compare.show_compare({}, {})
		_compare.set_empty_text(NOTHING_FITTED)
		return
	var mine: Dictionary = fitted[0]
	_compare.show_compare({"part_type": part_type, "part_id": mine.part_id, "grade": mine.grade,
			"place": "slot:" + str(mine.slot)}, product)


# ---- pieces -----------------------------------------------------------------

## A table of parts: Item, (Part,) Maker, Tier, Price and Add to cart. Each
## row right-clicks as its part.
func _part_table(entries: Array, with_type: bool) -> PanelContainer:
	var columns := [{"title": "Item"}]
	if with_type:
		columns.append({"title": "Part", "width": 160})
	columns.append_array([{"title": "Maker", "width": 150}, {"title": "Tier", "width": 60},
			{"title": "Price", "width": 100, "align": "right"}, {"title": "", "width": 130, "align": "right"}])
	var rows := []
	for entry in entries:
		var part_type: String = entry[0]
		var part_id: String = entry[1]
		var maker := Store.maker_of(part_type, part_id)
		var cells := [NetUI.link(self, Store.part_name(part_type, part_id), NetSites.product_url(part_type, part_id))]
		if with_type:
			cells.append(NetUI.text(Store.type_name(part_type), &"NetMeta"))
		var buy := NetUI.button("Add to cart")
		buy.pressed.connect(_add_to_cart.bind(part_type, part_id))
		cells.append_array([NetUI.link(self, Manufacturers.short_name(maker), NetSites.maker_url(maker)),
				NetUI.text(_tier(Store.get_part(part_type, part_id)), &"NetMeta"),
				NetUI.text("%d CT" % Store.price(part_type, part_id)), buy])
		rows.append(cells)
	var table := NetUI.table(columns, rows)
	var table_rows := NetUI.table_rows(table)
	for i in entries.size():
		table_rows[i + 1].set_meta("net_part", [str(entries[i][0]), str(entries[i][1])])
	return table


## Parts in the order the category's sort link asks for.
static func sort_entries(entries: Array, sort: String) -> Array:
	var sorted := entries.duplicate()
	if sort == "name":
		sorted.sort_custom(func(a, b): return Store.part_name(a[0], a[1]).naturalnocasecmp_to(Store.part_name(b[0], b[1])) < 0)
	elif sort == "maker":
		sorted.sort_custom(func(a, b):
			var ma := Manufacturers.short_name(Store.maker_of(a[0], a[1]))
			var mb := Manufacturers.short_name(Store.maker_of(b[0], b[1]))
			if ma != mb:
				return ma.naturalnocasecmp_to(mb) < 0
			return Store.price(a[0], a[1]) < Store.price(b[0], b[1]))
	return sorted


func _by_maker(part_type: String, part_id: String) -> HBoxContainer:
	var maker := Store.maker_of(part_type, part_id)
	var row := NetUI.hbox(&"NetToolbar")
	row.add_child(NetUI.text("by", &"NetMeta"))
	var link := NetUI.link(self, Manufacturers.display_name(maker), NetSites.maker_url(maker))
	row.add_child(link)
	return row


func _fact(label: String, value: String) -> HBoxContainer:
	var row := NetUI.hbox(&"NetToolbar")
	var name_label := NetUI.text(label + ":", &"NetMeta")
	name_label.custom_minimum_size.x = 140
	row.add_child(name_label)
	row.add_child(NetUI.text(value, &"NetBodyBright"))
	return row


func _alert(reason: String) -> PanelContainer:
	var box := MechUI.pane(&"AlertCritical", MechUI.label(&"AlertCriticalText", "! " + reason))
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.set_meta("block_reason", reason)
	return box


# Takes the entry out of the cart, then loads the cart again.
func _remove_link(index: int) -> LinkButton:
	return NetUI.link(self, "Remove", NetSites.store_url("/cart"), true, func(): Store.remove_from_cart(index))


func _entry_list(entries: Array) -> VBoxContainer:
	var column := NetUI.vbox(&"NetTightStack")
	for entry in entries:
		column.add_child(NetUI.text("· %s (%s) — %d CT" % [Store.part_name(entry[0], entry[1]),
				Store.type_name(entry[0]), Store.price(entry[0], entry[1])]))
	return column


func _fitted_text(part_type: String, part_id: String) -> String:
	var slots := []
	for fitted in CompareWindow.fitted_parts(part_type):
		if fitted.part_id == part_id:
			slots.append(CompareWindow.SLOT_NAMES.get(fitted.slot, fitted.slot))
	return "yes (%s)" % ", ".join(slots) if not slots.is_empty() else "no"


static func _tier(part) -> String:
	var tier = part.get("tech_tier") if part != null else null
	return Materials.tier_name(tier) if tier is int and tier != item_data.TechTier.NONE else "-"


static func _first_sentence(text: String) -> String:
	var cut := text.find(". ")
	return text.substr(0, cut + 1) if cut >= 0 else text


func _steelapedia_url(slug: String) -> String:
	return NetSites.wiki_url(slug)


# A path's part type, matched without case; "" if it isn't one.
func _part_type(segment) -> String:
	var wanted := str(segment).to_lower()
	for part_type in Store.CATEGORIES:
		if part_type == wanted:
			return part_type
	return ""


# A path's part id: exact, else matched without case.
func _part_id(part_type: String, segment: String) -> String:
	if part_type == "":
		return ""
	var parts: Dictionary = PartManager.get_parts(part_type)
	if parts.has(segment):
		return segment
	for id in parts:
		if str(id).to_lower() == segment.to_lower():
			return id
	return segment
