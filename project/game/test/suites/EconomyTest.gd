extends TestSuite

# EconomyTest: credits and what feeds them. Selling (PlayerProgress and the
# Hangar's right-click Sell / Sell all salvage): an item sells for SELL_RATE
# of its value, whole stacks at once, at home only; parts and weapons sell one
# at a time; big sales ask first. What the cargo would sell for (the debrief
# shows it).
# Each case starts from fresh progress (PlayerProgress.reset).

const PLATE := preload("res://database/items/salvage/armor_plate_fragment.tres")  # price 10
const ENGINE := preload("res://database/items/salvage/damaged_nt_engine.tres")   # price 220
const BIG_CORE := "Lancelot-Core"  # price 3200: a sale over SELL_CONFIRM_OVER


func run_tests() -> void:
	await case("an item sells for half its value", _test_sell_value)
	await case("selling pays and removes the stack", _test_sell_stack)
	await case("no selling mid-run", _test_no_selling_in_expedition)
	await case("things with no value can't be sold", _test_no_value)
	await case("sell all salvage leaves parts", _test_sell_all)
	await case("what the cargo would sell for", _test_cargo_value)
	await case("sell menu actions", _test_sell_actions)


func before_each() -> void:
	PlayerProgress.reset()


func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


func _stack(item: Resource, quantity := 1) -> item_stack:
	var stack := item_stack.from_generic(item)
	stack.quantity = quantity
	return stack


# A weapon as it drops from a wreck.
func _weapon_stack() -> item_stack:
	var entry := LootEntry.new()
	entry.part_type = "arm_weapon"
	entry.part_id = "MA-L127"
	return entry.make_stack()


# The cargo is sized by the core in the Hangar; give the fresh one a grid.
func _cargo() -> Inventory:
	var cargo := PlayerProgress.get_mech_inventory()
	cargo.initialize_grid(8, 8)
	return cargo


func _part_stack(part_type: String, part_id: String) -> item_stack:
	PlayerProgress.add_part(part_type, part_id, false)
	for stack in PlayerProgress.get_stash_inventory().get_stacks():
		if stack.is_part() and stack.item_id == part_id:
			return stack
	return null


func _test_sell_value() -> void:
	check_eq(PlayerProgress.SELL_RATE, 0.5, "the Store sells at full value and buys back at half")
	check_eq(PlayerProgress.sell_value(_stack(ENGINE)), 110, "a 220 ct engine sells for 110")
	check_eq(PlayerProgress.sell_value(_stack(PLATE, 3)), 15, "a stack sells as a whole (3 x 10 ct -> 15)")
	check_eq(PlayerProgress.sell_value(_stack(PLATE)), 5, "one 10 ct plate -> 5")
	var core := _part_stack("core", BIG_CORE)
	check(core != null, "a part in the stash")
	check_eq(PlayerProgress.sell_value(core), 1600, "a part sells for half its price (3200 -> 1600)")
	var gun_price: float = PartManager.get_part("arm_weapon", "MA-L127").price
	check_eq(PlayerProgress.sell_value(_weapon_stack()), int(floor(gun_price * 0.5)), "weapons too")
	check_eq(PlayerProgress.sell_value(null), 0, "nothing sells for nothing")


func _test_sell_stack() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	var plates := _stack(PLATE, 4)
	stash.add_stack_anywhere(plates)
	var changes := []
	var on_change := func(amount): changes.append(amount)
	PlayerProgress.money_changed.connect(on_change)
	check(PlayerProgress.can_sell(plates), "salvage can be sold at home")
	check_eq(PlayerProgress.sell_stack(stash, plates, false), 20, "selling returns what it paid")
	PlayerProgress.money_changed.disconnect(on_change)
	check_eq(PlayerProgress.get_money(), 20.0, "the credits are added")
	check(changes == [20.0], "money_changed tells the Hangar")
	check(stash.is_empty(), "the stack is gone")
	check_eq(PlayerProgress.sell_stack(stash, plates, false), 0, "a stack that's already gone can't be sold again")
	var elsewhere := _stack(PLATE)
	check_eq(PlayerProgress.sell_stack(stash, elsewhere, false), 0, "only stacks in that inventory sell")
	check_eq(PlayerProgress.get_money(), 20.0, "and nothing was paid for them")


func _test_no_selling_in_expedition() -> void:
	var cargo := _cargo()
	var engine := _stack(ENGINE)
	check(cargo.add_stack_anywhere(engine), "salvage in the cargo")
	PlayerProgress.begin_expedition()
	check(not PlayerProgress.can_sell(engine), "nothing sells mid-run (loot would become safe credits)")
	check_eq(PlayerProgress.sell_stack(cargo, engine, false), 0, "sell_stack refuses")
	check_eq(PlayerProgress.sell_all_salvage(cargo), 0, "so does Sell all salvage")
	check(cargo.get_stacks().has(engine) and PlayerProgress.get_money() == 0.0, "the cargo and credits are untouched")
	PlayerProgress.extract_expedition()
	check(PlayerProgress.can_sell(engine), "back home it sells")


func _test_no_value() -> void:
	var worthless := item_data.new()
	worthless.id = "worthless"
	worthless.display_name = "Worthless"
	var stack := item_stack.from_generic(worthless)
	check_eq(PlayerProgress.sell_value(stack), 0, "no price, no value")
	check(not PlayerProgress.can_sell(stack), "so it can't be sold")
	var stash := PlayerProgress.get_stash_inventory()
	stash.add_stack_anywhere(stack)
	check_eq(PlayerProgress.sell_stack(stash, stack, false), 0, "sell_stack refuses it")
	check(stash.get_stacks().has(stack), "and it stays")


func _test_sell_all() -> void:
	var stash := PlayerProgress.get_stash_inventory()
	stash.add_stack_anywhere(_stack(PLATE, 2))
	stash.add_stack_anywhere(_stack(ENGINE))
	var core := _part_stack("core", BIG_CORE)
	check_eq(PlayerProgress.salvage_sell_value(stash), 120, "the preview counts salvage only (10 + 110)")
	check_eq(PlayerProgress.sell_all_salvage(stash), 120, "Sell all salvage pays for every piece")
	check_eq(PlayerProgress.get_money(), 120.0, "credits added")
	check_eq(stash.get_stacks(), [core], "the part stays: parts sell one at a time")
	check_eq(PlayerProgress.sell_all_salvage(stash), 0, "nothing left to sell")


func _test_cargo_value() -> void:
	check_eq(PlayerProgress.cargo_sell_value(), 0, "an empty cargo is worth nothing")
	var cargo := _cargo()
	var gun := _weapon_stack()
	for stack in [_stack(ENGINE), _stack(PLATE, 3), gun]:
		check(cargo.add_stack_anywhere(stack), "packed into the cargo")
	var expected := 110 + 15 + PlayerProgress.sell_value(gun)
	check_eq(PlayerProgress.cargo_sell_value(), expected, "everything in the cargo counts, parts too")


func _test_sell_actions() -> void:
	var sell := _action("item", "sell")
	var sell_all := _action("inventory", "sell_all")
	check(not sell.is_empty() and not sell_all.is_empty() and not _action("item", "sell_all").is_empty(),
			"sell actions registered")
	var stash := PlayerProgress.get_stash_inventory()
	var engine := _stack(ENGINE)
	stash.add_stack_anywhere(engine)

	var ctx := {"type": "item", "stack": engine, "inventory": stash}
	check(not sell["visible_if"].call(ctx), "hidden where selling isn't allowed (Mech OS mid-run)")
	ctx["recycle_allowed"] = true
	check(sell["visible_if"].call(ctx), "shown in the Hangar")
	check(sell["enabled_if"].call(ctx) == "", "enabled on things with a value")
	check_eq(sell["label"].call(ctx), "Sell (110 ct)", "the label says what it pays")
	check_eq(sell["confirm"].call(ctx), "", "a small sale goes straight through")
	var ids := MechOS._get_context_actions(ctx).map(func(a): return a["id"])
	check("recycle" in ids and "sell" in ids, "offered next to Recycle")

	var worthless := item_data.new()
	worthless.id = "worthless"
	var nothing_ctx := {"type": "item", "stack": item_stack.from_generic(worthless), "inventory": stash, "recycle_allowed": true}
	check_eq(sell["enabled_if"].call(nothing_ctx), "NO VALUE", "greyed out on things worth nothing")
	check_eq(sell["label"].call(nothing_ctx), "Sell", "with no price in the label")

	var core := _part_stack("core", BIG_CORE)
	var core_ctx := {"type": "item", "stack": core, "inventory": stash, "recycle_allowed": true}
	check_eq(sell["confirm"].call(core_ctx), "Confirm: sell for 1600 ct?", "a big sale asks first")

	sell["run"].call(ctx)
	check_eq(PlayerProgress.get_money(), 110.0, "Sell sells it")
	check(not stash.get_stacks().has(engine), "and takes it out of the stash")

	var inv_ctx := {"type": "inventory", "inventory": stash, "recycle_allowed": true}
	check_eq(sell_all["enabled_if"].call(inv_ctx), "NO SALVAGE", "Sell all salvage is greyed out with only parts left")
	stash.add_stack_anywhere(_stack(PLATE, 2))
	check_eq(sell_all["enabled_if"].call(inv_ctx), "", "and enabled once there's salvage")
	check_eq(sell_all["label"].call(inv_ctx), "Sell all salvage (10 ct)", "its label previews the total")
	check_eq(sell_all["confirm"].call(inv_ctx), "", "a small total doesn't ask")
	sell_all["run"].call(inv_ctx)
	check_eq(PlayerProgress.get_money(), 120.0, "Sell all salvage sells the salvage")
	check_eq(stash.get_stacks(), [core], "and leaves the part")
	check(not sell_all["visible_if"].call({"type": "inventory", "inventory": Inventory.new(), "recycle_allowed": true}),
			"no Sell all on an empty inventory")
