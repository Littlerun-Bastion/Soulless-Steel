extends Node

# PlayerProgress owns everything the player has earned or built up:
#   - money          : credits, spent in the Store and earned from matches
#   - current mecha  : the design dictionary the player pilots
#   - stash          : the hangar grid inventory (bought and looted parts/items)
#   - mech cargo     : the grid inventory carried inside the mecha
#
# Story position lives in StoryDirector; settings live in Profile.
# Profile only packs/unpacks this data into the save file under "progress".
#
# Part helpers (add_part, remove_part, count_part, get_owned_parts) treat the
# stash as the single source of owned-but-unequipped parts. part_type is always
# a PartManager key: "head", "core", "arm_weapon", "shoulder_weapon", etc.
#
# Anything that changes progress saves the profile unless should_save = false
# (use that to batch several changes, then save once).
#
# Testing: game/test/PlayerProgressTest.tscn runs self-checks (F6 in the
# editor) with autosave off, restoring the real progress afterwards.

signal money_changed(new_amount)
signal mecha_changed(design)

const DEFAULT_MECHA := {
	"head": "MSV-L3J-H", "core": "MSV-L3J-C", "shoulders": "MSV-L3J-SG",
	"generator": "type_1_gen", "chipset": "type_2_chip", "chassis": "MSV-L3J-L",
	"thruster": "type_1_thruster",
	"arm_weapon_left": "MA-L127", "arm_weapon_right": "MA-L127",
	"shoulder_weapon_left": false, "shoulder_weapon_right": false,
}
const STASH_SIZE := Vector2i(8, 20)

var money: float = 0.0
var current_mecha: Dictionary = DEFAULT_MECHA.duplicate()
var stash_inventory: Inventory = null
var mech_inventory: Inventory = null

var autosave := true  # tests turn this off so the real profile isn't written


# ---- Money ----

func get_money() -> float:
	return money


func can_afford(amount: float) -> bool:
	return money >= amount


func add_money(amount: float, should_save := true) -> void:
	_set_money(money + amount, should_save)


# Returns false (and changes nothing) when the player can't afford it.
func spend_money(amount: float, should_save := true) -> bool:
	if not can_afford(amount):
		return false
	_set_money(money - amount, should_save)
	return true


func _set_money(value: float, should_save: bool) -> void:
	money = value
	_log("money = " + str(money))
	money_changed.emit(money)
	if should_save:
		_save()


# ---- Current mecha ----

func get_current_mecha() -> Dictionary:
	return current_mecha


func set_current_mecha(design: Dictionary, should_save := true) -> void:
	current_mecha = design
	mecha_changed.emit(current_mecha)
	if should_save:
		_save()


# ---- Inventories ----

func get_stash_inventory() -> Inventory:
	if stash_inventory == null:
		stash_inventory = Inventory.new()
		stash_inventory.initialize_grid(STASH_SIZE.x, STASH_SIZE.y)
	return stash_inventory


func set_stash_inventory(inv: Inventory) -> void:
	stash_inventory = inv


# Cargo is sized by the core, so a fresh one is left uninitialised for the
# Hangar to size (see HangarScreen._ready).
func get_mech_inventory() -> Inventory:
	if mech_inventory == null:
		mech_inventory = Inventory.new()
	return mech_inventory


func set_mech_inventory(inv: Inventory) -> void:
	mech_inventory = inv


# ---- Parts in the stash ----

# Returns false when the stash has no room; nothing is added in that case.
func add_part(part_type: String, part_id: String, should_save := true) -> bool:
	var stack := item_stack.new()
	stack.kind = item_stack.ItemKind.PART
	stack.item_category = "part"
	stack.item_type = part_type
	stack.item_id = part_id
	if not get_stash_inventory().add_stack_to_first_available_slot(stack):
		return false
	if should_save:
		_save()
	return true


# Removes one copy. Returns false when the stash doesn't have it.
func remove_part(part_type: String, part_id: String, should_save := true) -> bool:
	for stack in _get_stash_stacks():
		if stack.kind == item_stack.ItemKind.PART and stack.item_type == part_type and stack.item_id == part_id:
			if stack.quantity > 1:
				stack.quantity -= 1
			else:
				get_stash_inventory().remove_item_stack(stack)
			if should_save:
				_save()
			return true
	return false


func count_part(part_type: String, part_id: String) -> int:
	return int(get_owned_parts(part_type).get(part_id, 0))


# {part_id: count} of parts in the stash, optionally only of one part_type.
func get_owned_parts(part_type := "") -> Dictionary:
	var owned := {}
	for stack in _get_stash_stacks():
		if stack.kind != item_stack.ItemKind.PART:
			continue
		if part_type != "" and stack.item_type != part_type:
			continue
		owned[stack.item_id] = owned.get(stack.item_id, 0) + stack.quantity
	return owned


func _get_stash_stacks() -> Array:
	var stacks := []
	var inv := get_stash_inventory()
	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell = inv.grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				stacks.append(cell["stack"])
	return stacks


# ---- Save / load ----

func reset() -> void:
	money = 0.0
	current_mecha = DEFAULT_MECHA.duplicate()
	stash_inventory = null
	mech_inventory = null
	money_changed.emit(money)
	mecha_changed.emit(current_mecha)


func get_save_data() -> Dictionary:
	return {
		"money": money,
		"current_mecha": current_mecha,
		"stash_inventory": _inventory_to_dict(stash_inventory),
		"mech_inventory": _inventory_to_dict(mech_inventory),
	}


func set_save_data(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = float(data.get("money", 0.0))
	current_mecha = _with_default_slots(data.get("current_mecha"))
	stash_inventory = _inventory_from_dict(data.get("stash_inventory"))
	mech_inventory = _inventory_from_dict(data.get("mech_inventory"))
	money_changed.emit(money)
	mecha_changed.emit(current_mecha)


# Saves from before PlayerProgress kept money and the mecha in "stats" and the
# inventories at the top level. Builds the "progress" dictionary from those.
func migrate_legacy_save(data: Dictionary) -> Dictionary:
	var stats = data.get("stats", {})
	if typeof(stats) != TYPE_DICTIONARY:
		stats = {}
	return {
		"money": stats.get("money", 0.0),
		"current_mecha": stats.get("current_mecha"),
		"stash_inventory": data.get("stash_inventory"),
		"mech_inventory": data.get("mech_inventory"),
	}


# Fills slots added to DEFAULT_MECHA since the design was saved.
func _with_default_slots(design) -> Dictionary:
	if typeof(design) != TYPE_DICTIONARY:
		return DEFAULT_MECHA.duplicate()
	for slot in DEFAULT_MECHA:
		if not design.has(slot):
			design[slot] = DEFAULT_MECHA[slot]
	return design


func _inventory_to_dict(inv: Inventory) -> Dictionary:
	if inv == null:
		return {}  # represent "no inventory" as empty dict

	var items: Array = []
	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell = inv.grid[y][x]
			var stack: item_stack = cell["stack"]
			# Only serialize origin cells
			if stack == null or cell["origin_x"] != x or cell["origin_y"] != y:
				continue

			var entry := {
				"x": x,
				"y": y,
				"quantity": stack.quantity,
				"rotated": stack.rotated,
				"kind": stack.kind,
			}
			if stack.kind == item_stack.ItemKind.PART:
				entry["part_type"] = stack.item_type
				entry["part_name"] = stack.item_id
			else:
				var path := ""
				if stack.item != null and stack.item.resource_path != "":
					path = stack.item.resource_path
				entry["item_path"] = path
			items.append(entry)

	return {
		"grid_width": inv.grid_width,
		"grid_height": inv.grid_height,
		"items": items,
	}


func _inventory_from_dict(data) -> Inventory:
	# Be defensive: old saves might have wrong types here.
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return null

	var inv := Inventory.new()
	var w: int = int(data.get("grid_width", 0))
	var h: int = int(data.get("grid_height", 0))
	if w <= 0 or h <= 0:
		return inv
	inv.initialize_grid(w, h)

	for entry in data.get("items", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var stack := item_stack.new()
		stack.quantity = int(entry.get("quantity", 1))
		stack.rotated = bool(entry.get("rotated", false))
		stack.kind = int(entry.get("kind", 0)) as item_stack.ItemKind

		if stack.kind == item_stack.ItemKind.PART:
			stack.item_category = "part"
			stack.item_type = str(entry.get("part_type", ""))
			stack.item_id = str(entry.get("part_name", ""))
			# The old Profile loader wrote to non-existent fields, so parts
			# re-saved by it lost their identity. Nothing to restore from them.
			if stack.item_type == "" or stack.item_id == "":
				push_warning("PlayerProgress: dropping saved part with no type/id at %s,%s" % [entry.get("x"), entry.get("y")])
				continue
		else:
			var item_path: String = entry.get("item_path", "")
			if item_path != "":
				var res = load(item_path)
				if res != null:
					stack.item = res

		inv.place_item(stack, int(entry.get("x", 0)), int(entry.get("y", 0)))

	return inv


func _save() -> void:
	if autosave:
		FileManager.save_profile()


func _log(text: String) -> void:
	if Debug.get_setting("verbose_logging"):
		print("[PlayerProgress] ", text)
