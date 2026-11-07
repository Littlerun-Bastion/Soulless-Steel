extends TestSuite

# NetStoreTest: the NET browser, amazing.com and Compare to...
#   - Manufacturers: every part resolves to a maker, one Martel
#   - Store: what's listed (not test parts, Null, store_listed off, no price,
#     too high tech), the catalogue's order, search, the cart, each checkout
#     block in order, a checkout with a full stash
#   - addresses (one canonical form, planned and unknown sites), history,
#     the jittery load bar and its timing, cached pages, instant loads
#   - Compare to... in the stash, the cargo and a filled slot (not salvage
#     or an empty slot), the OWNED and STORE lists, PartCompare's numbers
#     with grades, weapon damage and AP from the projectile
#   - NET only in the Hangar (not the field, not after leaving), the title
#     Store button opening it at amazing.com
#   - every amazing.com page opening without errors, a product page for
#     every part type, the cart, checkout and receipt
# Loads are instant (NetWindow.load_time_scale 0) except in the load cases.

const HANGAR := preload("res://game/ui/HangarScreen.tscn")
const START_MENU := preload("res://game/start_menu/StartMenu.tscn")
const SALVAGE := preload("res://database/items/salvage/wiring_loom.tres")
const HEAD := "MSV-M2-H"
const OTHER_HEAD := "O10-Head"
const CARGO_HEAD := "Percival-Head"
const CHASSIS := "MSV-L3J-L"
const WEAPON := "MA-L127"
# Test parts made real for a moment, so every type has a product page.
const MAKE_REAL := [["chipset", "type_1_chip"], ["thruster", "type_1_thruster"], ["internal", "WD-2"]]


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("every part has a maker; one Martel", _test_manufacturers)
	await case("what the store lists", _test_listing)
	await case("the catalogue's order and search", _test_catalogue)
	await case("the cart", _test_cart)
	await case("what stops a checkout, in order", _test_block_reasons)
	await case("checkout with a full stash", _test_checkout)
	await case("addresses", _test_addresses)
	await case("history", _test_history)
	await case("the load plan", _test_load_plan)
	await case("the load bar in the window", _test_load_bar)
	await case("cached, instant and stopped loads", _test_load_kinds)
	await case("the frame: title, status, favorites, balance", _test_frame)
	await case("Compare to... where it shows", _test_compare_menu)
	await case("the Compare window's lists", _test_compare_lists)
	await case("PartCompare numbers", _test_part_compare)
	await case("NET in the Hangar only", _test_availability)
	await case("the title Store button", _test_store_button)
	await case("every amazing.com page opens", _test_pages)
	await case("a product page for every part type", _test_product_pages)
	await case("buying on amazing.com", _test_buying)
	NetWindow.load_time_scale = 1.0


func before_each() -> void:
	PlayerProgress.reset()
	Store.clear_cart()
	Store.last_order = {}
	NetWindow.load_time_scale = 0.0
	MechOS.close_all()


# ---- helpers --------------------------------------------------------------

func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


func _part_stack(part_type: String, part_id: String, grade := Grades.STANDARD) -> item_stack:
	var stack := item_stack.new()
	stack.kind = item_stack.ItemKind.PART
	stack.item_category = "part"
	stack.item_type = part_type
	stack.item_id = part_id
	stack.grade = grade
	return stack


# Every Label's, Button's and link's text under node.
func _text(node: Node) -> String:
	var bits := []
	for child in node.find_children("*", "", true, false):
		if child.is_queued_for_deletion():
			continue
		if child is Label or child is Button or child is LinkButton:
			bits.append(child.text)
	return "\n".join(bits)


func _find_button(node: Node, label: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if child.text == label and not child.is_queued_for_deletion():
			return child
	return null


func _find_link(node: Node, label: String) -> LinkButton:
	for child in node.find_children("*", "LinkButton", true, false):
		if child.text == label and not child.is_queued_for_deletion():
			return child
	return null


func _net(url := "") -> NetWindow:
	MechOS.set_app_available("net", true)
	var window: NetWindow = MechOS.open_net(url)
	check(window != null, "NET opens")
	return window


func _open_hangar() -> Node:
	var hangar = HANGAR.instantiate()
	add_child(hangar)
	await wait_frames(2)
	return hangar


func _close_hangar(hangar: Node) -> void:
	hangar.queue_free()
	await wait_frames(2)


# ---- Manufacturers --------------------------------------------------------

func _test_manufacturers() -> void:
	var unresolved := []
	for part_type in PlayerProgress.PART_TYPES:
		for part_id in PartManager.get_parts(part_type):
			if part_id == "Null":
				continue
			var part = PartManager.get_part(part_type, part_id)
			if Manufacturers.of_part(part) == "":
				unresolved.append("%s:%s (%s)" % [part_type, part_id, part.get("manufacturer_name")])
			if str(part.get("manufacturer_name")).to_lower().contains("martel"):
				check_eq(Manufacturers.of_part(part), "martel", "%s is a Martel part" % part_id)
				check_eq(str(part.manufacturer_name), Manufacturers.display_name("martel"), "%s names the one Martel in full" % part_id)
	check(unresolved.is_empty(), "every part resolves to a maker (%s)" % str(unresolved))
	check_eq(Manufacturers.of_part({"manufacturer_name": "  orontes CONSTRUCTIONS "}), "orontes", "case and spaces don't matter")
	check_eq(Manufacturers.of_part({"manufacturer_name": "Mil-Grade Imports"}), "", "an unknown maker gives nothing")
	check(Manufacturers.is_test("test") and not Manufacturers.is_test("martel"), "only the test maker is a test")
	check(not "test" in Manufacturers.real_ids() and Manufacturers.real_ids().size() == Manufacturers.ids().size() - 1, "real_ids leaves out only the test maker")
	check_eq(Manufacturers.short_name("pt_gajah_teknis"), "Gajah Teknis", "short names")
	for id in Manufacturers.ids():
		check(Manufacturers.domain_of(id) != "", "%s has a site" % id)
		check_eq(Manufacturers.of_domain(Manufacturers.domain_of(id)), id, "%s's site leads back to it" % id)


# ---- Store ----------------------------------------------------------------

func _test_listing() -> void:
	for entry in [["chipset", "type_1_chip"], ["chipset", "type_2_chip"], ["thruster", "type_1_thruster"], ["internal", "WD-2"]]:
		check(not Store.is_listed(entry[0], entry[1]), "test part %s isn't listed" % entry[1])
	check(not Store.is_listed("core", "Null"), "Null isn't listed")
	check(not Store.is_listed("core", "no_such_core") and not Store.is_listed("salvage", "x"), "nothing that doesn't exist")
	check(Store.is_listed("head", HEAD), "a real head is listed")
	var part = PartManager.get_part("head", HEAD)
	part.store_listed = false
	check(not Store.is_listed("head", HEAD), "store_listed off keeps it out")
	part.store_listed = true
	var price: float = part.price
	part.price = 0.0
	check(not Store.is_listed("head", HEAD), "no price keeps it out")
	part.price = price
	var tier: int = part.tech_tier
	part.tech_tier = Store.MAX_TECH_TIER + 1
	check(not Store.is_listed("head", HEAD), "a tier over MAX_TECH_TIER keeps it out")
	part.tech_tier = tier
	check(Store.is_listed("head", HEAD), "and back on once restored")
	var wrong := []
	for part_type in Store.CATEGORIES:
		for part_id in PartManager.get_parts(part_type):
			var p = PartManager.get_part(part_type, part_id)
			var maker := Manufacturers.of_part(p)
			var expected: bool = part_id != "Null" and float(p.price) > 0.0 and maker != "" \
					and not Manufacturers.is_test(maker) and p.store_listed and p.tech_tier <= Store.MAX_TECH_TIER
			if expected != Store.is_listed(part_type, part_id):
				wrong.append(part_id)
	check(wrong.is_empty(), "every other part is listed (%s)" % str(wrong))
	for part_type in ["chipset", "thruster", "internal"]:
		check(Store.catalogue(part_type).is_empty(), "no %s for sale yet" % part_type)
	check(Store.price("head", HEAD) is int and Store.price("head", HEAD) == int(part.price), "price is the part's, as an int")


func _test_catalogue() -> void:
	for part_type in Store.CATEGORIES:
		var ids := Store.catalogue(part_type)
		for i in range(1, ids.size()):
			var a: String = ids[i - 1]
			var b: String = ids[i]
			var pa := Store.price(part_type, a)
			var pb := Store.price(part_type, b)
			check(pa < pb or (pa == pb and Store.part_name(part_type, a).naturalnocasecmp_to(Store.part_name(part_type, b)) <= 0),
					"%s sorted by price, then name (%s before %s)" % [part_type, a, b])
	var by_name := Store.search("LANCELOT")
	check(by_name.has(["head", "Lancelot-Head"]) and by_name.has(["core", "Lancelot-Core"]), "search finds by name, any case")
	var by_maker := Store.search("claymore")
	check(not by_maker.is_empty() and by_maker.all(func(e): return Store.maker_of(e[0], e[1]) == "claymore"), "search finds by maker")
	check(Store.search("yamaguchi heavy").has(["head", "SAMURAI-Head"]), "by the maker's full name")
	check_eq(Store.search("1cr_core"), [["core", "GTk-1Cr_Core"]], "search finds by id")
	check(Store.search("   ").is_empty() and Store.search("no such thing").is_empty(), "nothing for nothing")
	check(Store.search("test").is_empty(), "never a test part")
	var claymore := Store.catalogue_of_maker("claymore")
	check(not claymore.is_empty() and claymore.all(func(e): return Store.maker_of(e[0], e[1]) == "claymore"), "one maker's catalogue")
	check(Store.catalogue_of_maker("nordomeccanica").is_empty(), "a maker with no stock")


func _test_cart() -> void:
	var changed := [0]
	var on_changed := func(): changed[0] += 1
	Store.feed.cart_changed.connect(on_changed)
	check(Store.add_to_cart("head", HEAD) and Store.add_to_cart("head", HEAD), "the same part twice")
	check(Store.add_to_cart("chassis", CHASSIS), "and another")
	check(not Store.add_to_cart("chipset", "type_1_chip"), "never a part that isn't listed")
	check_eq(Store.cart_count(), 3, "one entry per copy")
	check_eq(Store.cart_total(), Store.price("head", HEAD) * 2 + Store.price("chassis", CHASSIS), "the total")
	Store.remove_from_cart(0)
	check_eq(Store.cart, [["head", HEAD], ["chassis", CHASSIS]], "removing by index")
	Store.remove_from_cart(9)
	check_eq(Store.cart_count(), 2, "a bad index changes nothing")
	Store.clear_cart()
	check_eq(Store.cart_total(), 0, "cleared")
	check_eq(changed[0], 5, "every change is announced (three adds, a remove, a clear)")
	Store.feed.cart_changed.disconnect(on_changed)


func _test_block_reasons() -> void:
	PlayerProgress.in_expedition = true
	PlayerProgress.charge_repairs(5000, false)
	check_eq(Store.block_reason(), "CART IS EMPTY", "an empty cart first")
	Store.add_to_cart("head", HEAD)
	check_eq(Store.block_reason(), "OFFLINE DURING EXPEDITIONS", "then the expedition")
	PlayerProgress.in_expedition = false
	check_eq(Store.block_reason(), "ACCOUNT IN DEBT", "then debt")
	PlayerProgress.add_money(10 - PlayerProgress.get_money(), false)
	check_eq(Store.block_reason(), "INSUFFICIENT FUNDS", "then the money")
	PlayerProgress.add_money(Store.cart_total(), false)
	check_eq(Store.block_reason(), "", "nothing stops it")
	PlayerProgress.in_expedition = true
	var stash_before := PlayerProgress.get_stash_inventory().get_stacks().size()
	var result := Store.checkout()
	check(result.bought.is_empty() and result.reason == "OFFLINE DURING EXPEDITIONS" and Store.cart_count() == 1,
			"a blocked checkout buys nothing")
	check_eq(PlayerProgress.get_stash_inventory().get_stacks().size(), stash_before, "and delivers nothing")
	PlayerProgress.in_expedition = false


func _test_checkout() -> void:
	var size := _part_stack("head", HEAD)
	var stash := Inventory.new()
	stash.initialize_grid(size.width_cells(), size.height_cells())
	PlayerProgress.set_stash_inventory(stash)
	PlayerProgress.add_money(10000, false)
	var start := PlayerProgress.get_money()
	Store.add_to_cart("head", HEAD)
	Store.add_to_cart("head", OTHER_HEAD)
	var delivered := []
	var on_delivered := func(t, id): delivered.append([t, id])
	Store.feed.delivered.connect(on_delivered)
	var money_changes := [0]
	var on_money := func(_m): money_changes[0] += 1
	PlayerProgress.money_changed.connect(on_money)
	DirAccess.remove_absolute(FileManager.profile_path)
	FileManager.profile_loaded = true
	PlayerProgress.autosave = true
	var result := Store.checkout()
	PlayerProgress.autosave = false
	FileManager.profile_loaded = false
	PlayerProgress.money_changed.disconnect(on_money)
	Store.feed.delivered.disconnect(on_delivered)
	check_eq(result.bought, [["head", HEAD]], "what fits is bought")
	check_eq(result.left, [["head", OTHER_HEAD]], "what doesn't is left")
	check_eq(Store.cart, [["head", OTHER_HEAD]], "and stays in the cart")
	check_eq(result.spent, Store.price("head", HEAD), "only what arrived is charged")
	check_eq(PlayerProgress.get_money(), start - Store.price("head", HEAD), "the money is spent")
	check_eq(money_changes[0], 1, "once")
	check(FileAccess.file_exists(FileManager.profile_path), "and saved")
	check_eq(delivered, [["head", HEAD]], "deliver() ran for the delivered part")
	check_eq(PlayerProgress.count_part("head", HEAD), 1, "it's in the stash")
	var order := RegEx.create_from_string("^AMZ-\\d{5}-\\d{2}$")
	check(order.search(str(result.order)) != null, "an order number like AMZ-04217-31 (%s)" % result.order)
	check(MechLog.lines[-1].source == "NET" and str(result.order) in MechLog.lines[-1].text, "one line in the log")
	check_eq(Store.last_order.order, result.order, "kept for the receipt")
	var second := Store.checkout()
	check(second.bought.is_empty() and second.order == "" and Store.cart_count() == 1, "nothing fits: nothing bought, no order")
	check(second.order != result.order, "a different result")


# ---- addresses and history -------------------------------------------------

func _test_addresses() -> void:
	var a := NetSites.parse("HTTP://WWW.Amazing.com/c/head")
	var b := NetSites.parse("amazing.com/c/head")
	check_eq(a.url, b.url, "the same page however it's typed")
	check_eq(a.url, "amazing.com/c/head", "in one form")
	check_eq(a.domain, "amazing.com", "the domain")
	check_eq(a.path, "/c/head", "the path")
	check_eq(NetSites.parse("www.amazing.com/").url, "amazing.com/", "the root")
	check_eq(NetSites.parse("https://amazing.com//c//head/").url, "amazing.com/c/head", "stray slashes")
	check_eq(NetSites.display("amazing.com/c/head"), "http://www.amazing.com/c/head", "shown as http://www.")
	var q := NetSites.parse("amazing.com/search?q=lancelot+head&Sort=name")
	check_eq(q.query, {"q": "lancelot head", "sort": "name"}, "the query")
	check_eq(NetSites.parse(NetSites.search_url("Rangda core")).query.get("q"), "Rangda core", "a search survives its address")
	check_eq(NetSites.parse(NetSites.product_url("arm_weapon", "Kruis_CL157.0")).path, "/p/arm_weapon/Kruis_CL157.0", "a part id keeps its case")
	check_eq(NetSites.kind_of("amazing.com"), NetSites.BUILT, "amazing.com is built")
	check_eq(NetSites.kind_of("fourx.net"), NetSites.PLANNED_SITE, "FourX.net is planned")
	check_eq(NetSites.kind_of("steelapedia.net"), NetSites.BUILT, "Steelapedia is built")
	check_eq(NetSites.kind_of("pilot.net"), NetSites.BUILT, "so is pilot.net")
	check_eq(NetSites.kind_of(Manufacturers.domain_of("claymore")), NetSites.PLANNED_SITE, "a maker's site is planned")
	check_eq(NetSites.kind_of(Manufacturers.domain_of("test")), NetSites.UNKNOWN, "but not the test maker's")
	check_eq(NetSites.kind_of("nowhere.example"), NetSites.UNKNOWN, "anything else is unknown")

	var window := _net()
	window.navigate("HTTP://WWW.Amazing.com/c/head")
	check_eq(window.current_url, "amazing.com/c/head", "the window opens the canonical address")
	check(window.page is AmazingPage, "amazing.com's page")
	check_eq(window.address_field.text, "http://www.amazing.com/c/head", "the address field")
	window.navigate("fourx.net/forum")
	check(window.page is UnderConstructionPage, "a planned site: Under Construction")
	var text := _text(window.page)
	check("UNDER CONSTRUCTION" in text and "FourX.net" in text and UnderConstructionPage.MESSAGE in text,
			"with the site's name and the message")
	check(_find_link(window.page, "Back to the home page") != null, "and a link home")
	window.navigate("nowhere.example/page")
	check(window.page is ServerNotFoundPage, "an unknown domain: Server not found")
	check(ServerNotFoundPage.message("nowhere.example") in _text(window.page), "naming the server")
	check(window.get_status_text().contains("nowhere.example"), "the status says it couldn't be found")
	window.reload()
	check(window.page is ServerNotFoundPage and window.current_url == "nowhere.example/page", "RELOAD tries again")
	_find_link(window.page, "Go to the home page").pressed.emit()
	check_eq(window.current_url, "amazing.com/", "the link goes home")


func _test_history() -> void:
	var window := _net("amazing.com/")
	check(window.back_button.disabled and window.forward_button.disabled, "nothing to go back or forward to")
	window.navigate("amazing.com/hardware")
	window.navigate("amazing.com/wetware")
	check_eq(window.back_history, ["amazing.com/", "amazing.com/hardware"], "the back list")
	check(not window.back_button.disabled and window.forward_button.disabled, "BACK on, FWD off")
	window.go_back()
	check_eq(window.current_url, "amazing.com/hardware", "back")
	window.go_back()
	check_eq(window.current_url, "amazing.com/", "back again")
	check(window.back_button.disabled and not window.forward_button.disabled, "BACK off, FWD on")
	window.go_forward()
	check_eq(window.current_url, "amazing.com/hardware", "forward")
	check_eq(window.forward_history, ["amazing.com/wetware"], "one left to go forward to")
	window.navigate("amazing.com/makers")
	check(window.forward_history.is_empty() and window.forward_button.disabled, "a new page clears the forward list")
	window.reload()
	check_eq(window.current_url, "amazing.com/makers", "RELOAD loads it again")
	check_eq(window.back_history, ["amazing.com/", "amazing.com/hardware"], "without touching the history")
	window.navigate("amazing.com/makers")
	check_eq(window.back_history.size(), 2, "going to the open page is a reload")
	window.go_home()
	check_eq(window.current_url, NetSites.parse(NetWindow.HOME_URL).url, "HOME")


# ---- loading --------------------------------------------------------------

func _test_load_plan() -> void:
	var rng := RandomNumberGenerator.new()
	var long_stalls := 0
	for seed in range(1, 61):
		rng.seed = seed
		var total := rng.randf_range(NetWindow.LOAD_MIN, NetWindow.LOAD_MAX)
		var plan := NetLoad.plan(rng, total)
		var ok := true
		var last_t := 0.0
		var last_p := 0
		var longest := 0.0
		for step in plan.steps:
			ok = ok and step[0] >= last_t - 0.0001 and step[1] >= last_p
			var jump: int = step[1] - last_p
			ok = ok and (jump >= NetLoad.JUMP_MIN or step[1] == 100) and jump <= NetLoad.JUMP_MAX
			if last_p >= NetLoad.LONG_STALL_FROM and last_p <= NetLoad.LONG_STALL_TO:
				longest = maxf(longest, step[0] - last_t)
			last_t = step[0]
			last_p = step[1]
		if longest > 0.0 and plan.steps.size() > 1:
			var typical: float = (plan.steps[-1][0] - plan.steps[0][0]) / (plan.steps.size() - 1)
			if longest > typical * 1.5:
				long_stalls += 1
		check(ok, "seed %d: never goes down, jumps of 3-18 %%" % seed)
		check(last_p == 100 and plan.progress_at(total - 0.0001) == 100 and last_t < total, "seed %d: full before the end" % seed)
		check(plan.progress_at(plan.connect_time - 0.0001) == 0, "seed %d: nothing before the host replies" % seed)
		check(plan.phase_at(0.0) == NetLoad.Phase.LOOKUP and plan.phase_at(total) == NetLoad.Phase.DONE, "seed %d: phases" % seed)
	check(long_stalls >= 30, "most loads have one long stall late on (%d of 60)" % long_stalls)
	rng.seed = 7
	var first := NetLoad.plan(rng, 2.0).steps
	rng.seed = 7
	check_eq(NetLoad.plan(rng, 2.0).steps, first, "a seeded rng gives the same load")
	var failed := NetLoad.plan_failed(1.5)
	check(failed.failed and failed.progress_at(1.4) == 0 and failed.phase_at(1.4) == NetLoad.Phase.LOOKUP, "a failed lookup transfers nothing")


# Steps a load at a steady 60 frames a second, so no long frame skips a
# phase: [[elapsed, progress, status], ...].
func _step_load(window: NetWindow) -> Array:
	window.set_process(false)
	var samples := []
	var frames := 0
	while window.is_loading() and frames < 3000:
		samples.append([window.load_elapsed(), window.load_progress(), window.get_status_text()])
		window._process(1.0 / 60.0)
		frames += 1
	window.set_process(true)
	return samples


# Watches a load on real frames: [[elapsed, progress, status], ...].
func _watch_load(window: NetWindow) -> Array:
	var samples := []
	var frames := 0
	while window.is_loading() and frames < 3000:
		samples.append([window.load_elapsed(), window.load_progress(), window.get_status_text()])
		await get_tree().process_frame
		frames += 1
	return samples


func _test_load_bar() -> void:
	var window := _net("amazing.com/")
	NetWindow.load_time_scale = 1.0
	NetWindow.visited.clear()
	window.rng.seed = 1234
	var old_page := window.page
	window.navigate("amazing.com/makers")
	check(window.is_loading(), "a load takes a while")
	check(window.page == old_page and old_page.visible, "the old page shows while it loads")
	check_eq(window.reload_button.text, "STOP", "RELOAD reads STOP")
	var duration := window.load_duration()
	check(duration >= NetWindow.LOAD_MIN and duration <= NetWindow.LOAD_MAX, "a new page takes %.2f s, within the limits" % duration)
	var samples: Array = _step_load(window)
	check(not window.is_loading() and window.current_url == "amazing.com/makers", "the load ends")
	check(window.page != old_page and window.page.visible, "and the new page shows")
	var never_down := true
	var changes := 0
	var top := 0
	for i in samples.size():
		top = maxi(top, samples[i][1])
		if i > 0:
			never_down = never_down and samples[i][1] >= samples[i - 1][1]
			if samples[i][1] != samples[i - 1][1]:
				changes += 1
	check(never_down, "progress never goes down")
	check(changes > 3 and changes * 3 < samples.size(), "it moves in jumps, not every frame (%d changes in %d frames)" % [changes, samples.size()])
	check_eq(top, 100, "it reaches 100 %")
	check(samples[-1][0] <= duration and samples[-1][0] >= duration * 0.8, "it takes its time")
	var statuses := samples.map(func(s): return s[2])
	for wanted in ["Looking up host: amazing.com...", "Contacting host: amazing.com...", "Host contacted. Waiting for reply..."]:
		check(wanted in statuses, "the status says %s" % wanted)
	check(statuses.any(func(s): return str(s).begins_with("Transferring data from amazing.com... (") and str(s).ends_with("%)")),
			"and the transfer's percent")
	check_eq(window.get_status_text(), NetWindow.DONE_TEXT, "then Document: Done.")
	check_eq(window.load_progress(), 0, "the bar empties")
	check_eq(window.reload_button.text, "RELOAD", "and STOP is RELOAD again")
	var bar := window.load_bar
	bar.progress = 50
	check_eq(bar.lit_blocks(), NetLoadBar.BLOCKS / 2, "half the blocks at 50 %")
	bar.progress = 0


func _test_load_kinds() -> void:
	var window := _net("amazing.com/")
	NetWindow.load_time_scale = 1.0
	NetWindow.visited.clear()
	window.rng.seed = 99
	window.navigate("amazing.com/wetware")
	var first := window.load_duration()
	await _watch_load(window)
	window.reload()
	var cached := window.load_duration()
	check(cached >= NetWindow.CACHED_MIN and cached <= NetWindow.CACHED_MAX, "a cached page takes %.2f s" % cached)
	check(cached < first, "faster than the first time")
	await _watch_load(window)

	var before := window.page
	var history := window.back_history.duplicate()
	window.navigate("amazing.com/weapons")
	await wait_frames(3)
	window.reload_button.pressed.emit()
	check(not window.is_loading(), "STOP stops the load")
	check(window.page == before and window.current_url == "amazing.com/wetware", "the open page stays")
	check_eq(window.back_history, history, "and the history")
	check_eq(window.get_status_text(), NetWindow.STOPPED_TEXT, "Transfer interrupted!")
	check_eq(window.address_field.text, NetSites.display("amazing.com/wetware"), "the address goes back")

	window.navigate("nowhere.example")
	var statuses: Array = (await _watch_load(window)).map(func(s): return s[2])
	check(statuses.all(func(s): return str(s) == "Looking up host: nowhere.example..." or str(s).begins_with("http://")),
			"an unknown server is only looked up")
	check(window.page is ServerNotFoundPage, "then Server not found")

	NetWindow.load_time_scale = 0.0
	window.navigate("amazing.com/makers")
	check(not window.is_loading() and window.current_url == "amazing.com/makers" and window.page is AmazingPage,
			"with load_time_scale 0 a load is instant")


func _test_frame() -> void:
	var window := _net("amazing.com/c/head")
	check_eq(window.get_title_text(), "NET // amazing.com - Heads", "the title is NET // the page's")
	var link := _find_link(window.page, "Cores")
	link.mouse_entered.emit()
	check_eq(window.get_status_text(), "http://www.amazing.com/c/core", "a link's address in the status bar")
	link.mouse_exited.emit()
	check_eq(window.get_status_text(), NetWindow.DONE_TEXT, "and back")
	check_eq(window._favorites["amazing.com"].theme_type_variation, &"NetFavoriteActive", "the open site shows bright")
	check_eq(window._favorites["steelapedia.net"].theme_type_variation, &"NetFavorite", "the others don't")
	window._favorites["steelapedia.net"].pressed.emit()
	check(window.page is SteelapediaPage and window._favorites["steelapedia.net"].theme_type_variation == &"NetFavoriteActive",
			"a favorite opens its site")
	var maker := _action("net_makers", "maker_claymore")
	check(not maker.is_empty() and maker.label == "Claymore International", "the Manufacturers menu lists the makers")
	check(_action("net_makers", "maker_test").is_empty(), "but not the test maker")
	maker.run.call({"window": window})
	check_eq(window.current_url, Manufacturers.domain_of("claymore") + "/", "and opens their sites")
	check(window.page is UnderConstructionPage and window._makers_link.theme_type_variation == &"NetFavoriteActive",
			"under construction, with Manufacturers bright")
	PlayerProgress.add_money(1234, false)
	check_eq(window.balance_label.text, "%d CT" % int(PlayerProgress.get_money()), "BAL follows the money")
	check(window.min_size.x >= 1200 and window.min_size.y >= 820, "about 1200 x 820")
	check(window.min_size.x + 64 <= 1920 and window.min_size.y <= 1080, "which fits beside the sidebar")
	check(window.get_global_rect().position.x >= 64, "opened clear of the sidebar")


# ---- Compare ----------------------------------------------------------------

func _test_compare_menu() -> void:
	var hangar = await _open_hangar()
	var compare := _action("item", "compare")
	check(not compare.is_empty() and compare.label == "Compare to...", "Compare to... on items")
	check(not _action("part", "compare").is_empty(), "and on parts")
	var stash := PlayerProgress.get_stash_inventory()
	var head := _part_stack("head", HEAD)
	stash.add_stack_anywhere(head)
	var cargo: Inventory = MechOS.player_ref.mech_inventory
	var cargo_head := _part_stack("head", CARGO_HEAD)
	cargo.add_stack_anywhere(cargo_head)
	var salvage := item_stack.from_generic(SALVAGE)
	stash.add_stack_anywhere(salvage)
	check(compare.visible_if.call({"type": "item", "stack": head, "inventory": stash}), "for a part in the stash")
	check(compare.visible_if.call({"type": "item", "stack": cargo_head, "inventory": cargo}), "in the cargo")
	check(not compare.visible_if.call({"type": "item", "stack": salvage, "inventory": stash}), "not for salvage")
	var equipment: EquipmentWindow = MechOS.open_windows["equipment"]
	var head_slot: PartSlot = null
	var empty_slot: PartSlot = null
	for slot in equipment.part_slots:
		if slot.part_type == "head":
			head_slot = slot
		if slot.part_type == "shoulder_weapon":
			empty_slot = slot
	var slot_ctx := head_slot.get_context_target(Vector2.ZERO)
	check_eq(slot_ctx, {"type": "part", "part_type": "head", "part_id": PlayerProgress.DEFAULT_MECHA.head,
			"grade": Grades.STANDARD, "slot": "head"}, "a filled slot is a part")
	check(_action("part", "compare").visible_if.call(slot_ctx), "Compare to... on a filled slot")
	check(empty_slot.get_context_target(Vector2.ZERO).is_empty(), "an empty slot is nothing")
	var menu_ids := MechOS._get_context_actions(slot_ctx).map(func(a): return a.id)
	check(not "view_product" in menu_ids and not "add_to_cart" in menu_ids, "no store actions on a slot")
	var store_ctx := {"type": "part", "part_type": "head", "part_id": HEAD, "grade": Grades.STANDARD, "from_store": true}
	menu_ids = MechOS._get_context_actions(store_ctx).map(func(a): return a.id)
	check(menu_ids == ["view_product", "add_to_cart", "compare"], "a store part: View product, Add to cart, Compare to... (%s)" % str(menu_ids))
	_action("part", "add_to_cart").run.call(store_ctx)
	check_eq(Store.cart, [["head", HEAD]], "Add to cart from the menu")
	_action("part", "view_product").run.call(store_ctx)
	check(MechOS.is_app_open("net") and MechOS.open_windows["net"].current_url == NetSites.product_url("head", HEAD),
			"View product opens it on NET")
	compare.run.call({"type": "item", "stack": head, "inventory": stash})
	var window: CompareWindow = MechOS.open_windows.get("compare")
	check(window != null, "Compare to... opens COMPARE")
	if window != null:
		check_eq(window.title_label.text,
				"COMPARE // %s" % PartCompare.display_name({"part_type": "head", "part_id": HEAD}).to_upper(), "titled with the part")
		_action("part", "compare").run.call(slot_ctx)
		check_eq(window.subject.part_id, PlayerProgress.DEFAULT_MECHA.head, "opening it again replaces the subject")
		check(MechOS.open_windows.get("compare") == window, "in the same window")
	await _close_hangar(hangar)


func _test_compare_lists() -> void:
	var hangar = await _open_hangar()
	var stash := PlayerProgress.get_stash_inventory()
	stash.add_stack_anywhere(_part_stack("head", HEAD))
	stash.add_stack_anywhere(_part_stack("head", HEAD))
	stash.add_stack_anywhere(_part_stack("head", OTHER_HEAD, Grades.REFINED))
	var cargo: Inventory = MechOS.player_ref.mech_inventory
	cargo.add_stack_anywhere(_part_stack("head", CARGO_HEAD))
	var secret = PartManager.get_part("head", CARGO_HEAD)
	secret.store_listed = false
	var window: CompareWindow = MechOS.open_compare({"part_type": "head", "part_id": HEAD, "grade": Grades.STANDARD, "place": "stash"})
	var owned := window.get_entries()
	var wheres := owned.map(func(e): return "%s|%s|%s" % [e.part_id, e.grade, e.where])
	check(("%s|standard|FITTED · HEAD" % PlayerProgress.DEFAULT_MECHA.head) in wheres, "OWNED lists the fitted part (%s)" % str(wheres))
	check(("%s|refined|STASH" % OTHER_HEAD) in wheres, "a stash copy, with its grade")
	check(("%s|standard|CARGO" % CARGO_HEAD) in wheres, "a cargo copy")
	check(not owned.any(func(e): return e.part_id == HEAD and e.place == "stash"), "not the subject itself")
	check(owned.any(func(e): return e.part_id == CARGO_HEAD), "a secret part the player owns shows")
	check(window.get_rows().any(func(r): return "Refined" in r and "STASH" in r), "rows show the grade and the place")
	window.select_row(0)
	check(window.compare.get_header_text() != "" and " > " in window.compare.get_header_text(), "picking a row compares")
	window.set_tab(CompareWindow.STORE)
	var store_ids := window.get_entries().map(func(e): return e.part_id)
	check_eq(store_ids, Store.catalogue("head"), "STORE is the catalogue")
	check(not CARGO_HEAD in store_ids, "never a part that isn't listed")
	check(window.get_rows().all(func(r): return " CT" in r), "with prices")
	check(not window._list.find_children("*", "LinkButton", true, false).is_empty(), "and amazing.com links while NET is on")
	secret.store_listed = true

	var other := MechOS.open_compare({"part_type": "head", "part_id": OTHER_HEAD, "grade": Grades.REFINED, "place": "stash"})
	other.set_tab(CompareWindow.OWNED)
	var rows: Array = other.get_entries().map(func(e): return "%s|%s" % [e.part_id, e.where])
	check(("%s|STASH ×2" % HEAD) in rows, "two copies are one row, ×2 (%s)" % str(rows))
	check(not rows.any(func(r): return str(r).begins_with(OTHER_HEAD)), "the subject isn't listed")

	var weapons := MechOS.open_compare({"part_type": "arm_weapon", "part_id": WEAPON, "grade": Grades.STANDARD,
			"place": "slot:arm_weapon_left"})
	weapons.set_tab(CompareWindow.OWNED)
	var weapon_rows: Array = weapons.get_entries().map(func(e): return e.where)
	check_eq(weapon_rows, ["FITTED · R ARM"], "weapons by type: the other arm, with its side")
	check(weapons.compare.is_showing_empty() and weapons.compare.get_empty_text() == PartCompare.EMPTY_TEXT,
			"nothing picked: Pick a part to compare.")
	await _close_hangar(hangar)


func _test_part_compare() -> void:
	var standard := {"part_type": "chassis", "part_id": CHASSIS, "grade": Grades.STANDARD}
	var refined := {"part_type": "chassis", "part_id": CHASSIS, "grade": Grades.REFINED}
	var part = PartManager.get_part("chassis", CHASSIS)
	var speed := float(part.max_speed)
	check(is_equal_approx(PartCompare.difference(standard, refined, "max_speed"), speed * 0.05), "Refined walks 5% faster")
	check(is_equal_approx(PartCompare.difference(standard, refined, "health"), 0.0), "grades don't touch health")
	var view := PartCompare.new()
	add_child(view)
	view.show_compare(standard, refined)
	check_eq(view.get_header_text(), "%s > Refined %s" % [part.part_name, part.part_name], "the header: SUBJECT > CANDIDATE")
	check_eq(view.get_row_text("max_speed"), "%s > %s  +%s" % [MechUI.fmt(speed), MechUI.fmt(speed * 1.05), MechUI.fmt(speed * 0.05)],
			"84 > 102  +18 style")
	check_eq(view.get_row_text("health"), MechUI.fmt(float(part.health)), "an unchanged row shows one number")
	check_eq(view.get_row_text("is_legs"), "YES" if part.is_legs else "NO", "a yes/no field as text")
	check(view._rows["is_legs"].bar == null and view._rows["max_speed"].bar != null, "with no bar")
	check(view._rows["max_speed"].bar.preview_ratio > view._rows["max_speed"].bar.ratio, "a gain hatches the bar")
	var light := {"part_type": "chassis", "part_id": "O10-Chassis15k", "grade": Grades.STANDARD}
	view.show_compare(standard, light)
	check("Lower is better" == view._rows["weight"].bar.get_parent().tooltip_text, "lower_better only adds a tooltip")
	view.show_compare(standard, {})
	check(view.is_showing_empty() and view.get_header_text() == "", "no candidate: Pick a part to compare.")
	view.queue_free()

	var weapon = PartManager.get_part("arm_weapon", WEAPON)
	var projectile: Node = weapon.projectile.instantiate()
	var damage := float(projectile.base_damage)
	var ap := float(projectile.armor_pen)
	projectile.free()
	var spec := {"part_type": "arm_weapon", "part_id": WEAPON, "grade": Grades.STANDARD}
	check_eq(PartCompare.value_of(spec, PartCompare.field_of("arm_weapon", "base_damage")), damage, "damage from the projectile")
	check_eq(PartCompare.value_of(spec, PartCompare.field_of("arm_weapon", "armor_pen")), ap, "AP from the projectile")
	check_eq(weapon.get_aoe_info().blast_radius, weapon.get_aoe_info().blast_radius, "the AoE info still reads")
	check_eq(PartCompare.format_value(null), "-", "a value a part doesn't have is -")
	var missing := []
	for part_type in PartCompare.FIELDS:
		for field in PartCompare.FIELDS[part_type]:
			if field.get("source") == "projectile":
				continue
			var has_it: bool = PartManager.get_parts(part_type).values().any(func(p): return p.get(field.id) != null)
			if not has_it:
				missing.append("%s.%s" % [part_type, field.id])
	check(missing.is_empty(), "every field exists on the part scripts (%s)" % str(missing))


# ---- NET in the game ----------------------------------------------------------

func _test_availability() -> void:
	check(not MechOS.is_app_available("net"), "NET is off outside the Hangar")
	check(MechOS.open_net() == null, "and doesn't open")
	var hangar = await _open_hangar()
	check(MechOS.is_app_available("net"), "on in the Hangar")
	MechOS.toggle_app("net")
	check(MechOS.is_app_open("net"), "the sidebar tile opens it")
	var window: NetWindow = MechOS.open_windows["net"]
	check_eq(window.current_url, NetSites.parse(NetWindow.HOME_URL).url, "at the home page")
	MouseManager.set_aim_available(true)
	await wait_frames(2)
	check(not MechOS.is_app_available("net") and not MechOS.is_app_open("net"), "not in the field")
	MouseManager.reset()
	await wait_frames(2)
	check(MechOS.is_app_available("net"), "back once out of the field")
	await _close_hangar(hangar)
	check(not MechOS.is_app_available("net"), "off after leaving the Hangar")


func _test_store_button() -> void:
	var menu = START_MENU.instantiate()
	add_child(menu)
	await wait_frames()
	TransitionManager.captured.clear()
	menu._on_Store_pressed()
	check_eq(TransitionManager.captured, ["res://game/ui/HangarScreen.tscn"], "Store goes to the Hangar")
	check_eq(HangarScreen.open_net_url, "amazing.com", "to open amazing.com")
	menu.queue_free()
	await wait_frames()
	var hangar = await _open_hangar()
	check(MechOS.is_app_open("net"), "the Hangar opens NET")
	if MechOS.is_app_open("net"):
		check_eq(MechOS.open_windows["net"].current_url, "amazing.com/", "at amazing.com")
	check_eq(HangarScreen.open_net_url, "", "once")
	await _close_hangar(hangar)
	var again = await _open_hangar()
	check(not MechOS.is_app_open("net"), "the next visit doesn't open it")
	await _close_hangar(again)


# ---- amazing.com ---------------------------------------------------------------

func _test_pages() -> void:
	var window := _net("amazing.com/")
	var paths := ["/", "/hardware", "/wetware", "/weapons", "/c/head", "/c/head?sort=name", "/c/head?sort=maker",
			"/c/chipset", "/c/nonsense", "/search?q=lancelot", "/search?q=zzzz", "/search", "/makers",
			"/maker/claymore", "/maker/nordomeccanica", "/maker/nobody", "/cart", "/checkout", "/receipt",
			"/guestbook", "/nonsense", "/p/head/" + HEAD, "/p/head/no_such", "/p/chipset/type_1_chip"]
	for path in paths:
		var visitors := AmazingPage.visitors
		window.navigate("amazing.com" + path)
		check(window.page is AmazingPage and window.page.page_title.begins_with("amazing.com"), "%s opens" % path)
		check_eq(AmazingPage.visitors, visitors + 1, "%s counts a visitor" % path)
		var counter: Array = window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("digits"))
		check(counter.size() == 1 and counter[0].get_meta("digits") == AmazingPage.counter_text(), "%s shows the hit counter" % path)
	window.navigate("amazing.com/")
	var home := _text(window.page)
	check("This Week's Picks!" in home and "SHOP BY PART" in home and "Mil-Grade Imports" in home, "the home page")
	check("Best viewed at 800x600." in home and "Sign our guestbook!" in home and "You are visitor no." in home, "the footer")
	check(AmazingPage.picks.size() >= AmazingPage.PICKS_MIN and AmazingPage.picks.size() <= AmazingPage.PICKS_MAX, "4-6 picks")
	check(AmazingPage.picks.all(func(e): return Store.is_listed(e[0], e[1])) and not AmazingPage.featured.is_empty(), "listed, and a featured part")
	var picks := AmazingPage.picks.duplicate()
	window.reload()
	check_eq(AmazingPage.picks, picks, "the same picks all session")
	check(_text(window.page).contains("FEATURED: " + Store.part_name(AmazingPage.featured[0], AmazingPage.featured[1])), "the featured part")
	var tab := _find_button(window.page, "Home")
	check(tab != null and tab.theme_type_variation == &"NetTabActive", "Home is the active tab")
	window.navigate("amazing.com/c/head")
	check_eq(_find_button(window.page, "Hardware").theme_type_variation, &"NetTabActive", "a hardware category: Hardware")
	check(_text(window.page).contains(Store.part_name("head", Store.catalogue("head")[0])), "the category lists its parts")
	check(_find_button(window.page, "Add to cart") != null, "with Add to cart")
	window.navigate("amazing.com/c/chipset")
	var empty := window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("out_of_stock"))
	check(empty.size() == 1 and "OUT OF STOCK" in _text(window.page), "an empty category: OUT OF STOCK")
	window.navigate("amazing.com/hardware")
	check(_text(window.page).contains("%d items" % Store.catalogue("head").size()), "a group lists its categories' counts")
	window.navigate("amazing.com/makers")
	var makers := _text(window.page)
	check("Claymore International" in makers and not "Nordomeccanica" in makers and not "\nTest\n" in makers, "only makers with stock")
	check(_find_link(window.page, Manufacturers.domain_of("claymore")) != null, "with links to their sites")
	window.navigate("amazing.com/maker/claymore")
	check(_text(window.page).contains("Lancelot-Core") and _text(window.page).contains("CORES"), "a maker's parts by category")
	window.navigate("amazing.com/search?q=lancelot")
	check(_text(window.page).contains("Lancelot-Head") and window.page.find_children("*", "LineEdit", true, false)[0].text == "lancelot",
			"search results, the search kept in the box")
	window.navigate("amazing.com/guestbook")
	check("UNDER CONSTRUCTION" in _text(window.page), "the guestbook is under construction")
	window.navigate("amazing.com/p/chipset/type_1_chip")
	check("Not found" in _text(window.page), "a part that isn't sold has no page")
	window.navigate("amazing.com/")
	var field: LineEdit = window.page.find_children("*", "LineEdit", true, false)[0]
	field.text = "samurai"
	_find_button(window.page, "GO!").pressed.emit()
	check_eq(window.current_url, NetSites.search_url("samurai"), "GO! searches")


func _test_product_pages() -> void:
	var saved := {}
	for entry in MAKE_REAL:
		var part = PartManager.get_part(entry[0], entry[1])
		saved[entry[1]] = part.manufacturer_name
		part.manufacturer_name = Manufacturers.display_name("espada")
	var window := _net("amazing.com/")
	for part_type in Store.CATEGORIES:
		var ids := Store.catalogue(part_type)
		if not check(not ids.is_empty(), "%s has a part to show" % part_type):
			continue
		var part_id: String = ids[0]
		window.navigate(NetSites.product_url(part_type, part_id))
		var page := window.page
		var text := _text(page)
		check(page.page_title.ends_with(Store.part_name(part_type, part_id)), "%s's product page" % part_id)
		check("In your stash:" in text and "Fitted:" in text and "Read more on Steelapedia" in text and "Visit maker's site" in text,
				"%s: stash, fitted and links" % part_id)
		check(_find_button(page, "Add to cart") != null, "%s: Add to cart" % part_id)
		var views := page.find_children("*", "PartCompare", true, false)
		check(views.size() == 1, "%s: a comparison" % part_id)
		if views.is_empty():
			continue
		var view: PartCompare = views[0]
		var fitted := CompareWindow.fitted_parts(part_type)
		if fitted.is_empty():
			check_eq(view.get_empty_text(), AmazingPage.NOTHING_FITTED, "%s: nothing fitted to compare" % part_id)
		else:
			check(view.get_header_text().ends_with("> " + Store.part_name(part_type, part_id).to_upper()) or
					view.get_header_text().ends_with("> " + Store.part_name(part_type, part_id)),
					"%s: compared with the fitted part (%s)" % [part_id, view.get_header_text()])
		if part_type == "arm_weapon" or part_type == "shoulder_weapon":
			check(_find_button(page, "LEFT") != null and _find_button(page, "RIGHT") != null, "%s: LEFT / RIGHT" % part_id)
		var ctx := page.get_context_target(Vector2.ZERO)
		check_eq(ctx, {"type": "part", "part_type": part_type, "part_id": part_id, "grade": Grades.STANDARD, "from_store": true},
				"%s right-clicks as a store part" % part_id)
		var sprite: Array = page.find_children("*", "TextureRect", true, false).filter(func(n): return n.has_meta("sprite"))
		var fallback: Array = page.find_children("*", "Label", true, false).filter(func(n): return n.has_meta("fallback"))
		check(sprite.size() + fallback.size() == 1, "%s: its sprite or its name" % part_id)
		for node in sprite:
			check(node.texture.get_width() <= AmazingPage.SPRITE_BOX.x and node.texture.get_height() <= AmazingPage.SPRITE_BOX.y,
					"%s: a sprite at 1:1 that fits" % part_id)
	window.navigate(NetSites.product_url("arm_weapon", WEAPON))
	var right := _find_button(window.page, "RIGHT")
	right.button_pressed = true
	right.pressed.emit()
	var weapon_view: PartCompare = window.page.find_children("*", "PartCompare", true, false)[0]
	check(weapon_view.get_header_text() != "", "the RIGHT toggle compares the right arm")
	for entry in MAKE_REAL:
		PartManager.get_part(entry[0], entry[1]).manufacturer_name = saved[entry[1]]
	check(not Store.is_listed("chipset", "type_1_chip"), "the test parts are test parts again")


func _test_buying() -> void:
	PlayerProgress.add_money(100000, false)
	var window := _net("amazing.com/c/head")
	var cheapest: String = Store.catalogue("head")[0]
	var rows: Array = window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("net_part"))
	check(not rows.is_empty() and rows[0].get_meta("net_part") == ["head", cheapest], "rows carry their part")
	_find_button(rows[0], "Add to cart").pressed.emit()
	check_eq(Store.cart, [["head", cheapest]], "Add to cart")
	check(_find_button(window.page, "Your cart (1)") != null, "the cart tab counts it")
	window.navigate("amazing.com/cart")
	var text := _text(window.page)
	check(Store.part_name("head", cheapest) in text and "Total:" in text and "Balance after:" in text, "the cart lists it with the sums")
	check(not _find_button(window.page, "Proceed to checkout").disabled, "checkout is on")
	_find_link(window.page, "Remove").pressed.emit()
	check(Store.cart.is_empty() and window.current_url == "amazing.com/cart", "Remove takes it out and reloads the cart")
	var alerts: Array = window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("block_reason"))
	check(alerts.size() == 1 and alerts[0].get_meta("block_reason") == "CART IS EMPTY", "an empty cart says so")
	check(_find_button(window.page, "Proceed to checkout").disabled, "and can't check out")
	Store.add_to_cart("head", cheapest)
	PlayerProgress.charge_repairs(int(PlayerProgress.get_money()) + 50, false)
	window.reload()
	alerts = window.page.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("block_reason"))
	check(alerts.size() == 1 and alerts[0].get_meta("block_reason") == "ACCOUNT IN DEBT", "debt blocks it")
	PlayerProgress.add_money(100050, false)
	window.navigate("amazing.com/checkout")
	check("Purchase 1 item for %d CT?" % Store.price("head", cheapest) in _text(window.page), "checkout asks")
	_find_button(window.page, "Place order").pressed.emit()
	check_eq(window.current_url, "amazing.com/receipt", "Place order shows the receipt")
	text = _text(window.page)
	check(str(Store.last_order.order) in text and "STASH" in text and Store.part_name("head", cheapest) in text,
			"order number, Delivered to: STASH, what came")
	check_eq(PlayerProgress.count_part("head", cheapest), 1, "it's in the stash")
	check(Store.cart.is_empty(), "the cart is empty")
	var tiny := Inventory.new()
	tiny.initialize_grid(1, 1)
	PlayerProgress.set_stash_inventory(tiny)
	Store.add_to_cart("head", cheapest)
	window.navigate("amazing.com/checkout")
	_find_button(window.page, "Place order").pressed.emit()
	text = _text(window.page)
	check("Nothing could be delivered." in text and "STASH FULL — left in your cart" in text, "a full stash on the receipt")
	check_eq(Store.cart_count(), 1, "the part waits in the cart")
