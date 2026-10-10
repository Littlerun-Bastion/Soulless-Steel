extends Node

# PlayerProgress owns everything the player has earned or built up:
#   - money          : credits, spent in the Store and earned from matches
#   - current mecha  : the design dictionary the player pilots
#   - stash          : the hangar grid inventory (bought and looted parts/items)
#   - mech cargo     : the grid inventory carried inside the mecha
#   - materials      : crafting materials from recycling salvage (Materials)
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
# Expedition stakes (begin/extract/lose_expedition): Expedition is hardcore.
# The equipped mecha and its cargo go out with the player and are lost unless
# they extract; the stash and money at home are always safe. The in-expedition
# flag is saved, so a crash or closing the game mid-run counts as abandoning
# it — FileManager resolves that on the next boot.
#
# Testing: game/test/PlayerProgressTest.tscn runs self-checks (F6 in the
# editor) with autosave off, restoring the real progress afterwards.

signal money_changed(new_amount)
signal mecha_changed(design)
signal expedition_lost(report)
signal materials_changed(materials)

# Why an expedition was lost (the "reason" in a loss report).
const LOSS_DESTROYED := "destroyed"   # the player's mecha was destroyed
const LOSS_ABANDONED := "abandoned"   # quit, closed the game or crashed mid-run

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
var materials: Dictionary = {}  # material id -> amount
var in_expedition := false
# What the last lost expedition cost, until something shows it to the player
# (game-over screen or main menu). Saved, so it survives a crash.
var pending_loss_report: Dictionary = {}

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


# ---- Materials and recycling ----

# A copy; change counts through add_materials / recycling.
func get_materials() -> Dictionary:
	return materials.duplicate()


func get_material_count(material_id: String) -> int:
	return int(materials.get(material_id, 0))


func add_materials(amounts: Dictionary, should_save := true) -> void:
	for material_id in amounts:
		var amount := int(amounts[material_id])
		if amount != 0:
			materials[material_id] = get_material_count(material_id) + amount
	_log("materials = " + str(materials))
	materials_changed.emit(get_materials())
	if should_save:
		_save()


# Salvage with a composition can be recycled — at home only: recycling
# mid-run would turn loot into materials that can't be lost.
func can_recycle(stack: item_stack) -> bool:
	return not in_expedition and not recycle_value(stack).is_empty()


# What recycling the whole stack yields: material id -> amount.
func recycle_value(stack: item_stack) -> Dictionary:
	var value := {}
	if stack == null or stack.kind != item_stack.ItemKind.GENERIC or stack.item == null:
		return value
	var composition = stack.item.get("composition")
	if not composition is Dictionary:
		return value
	for material_id in composition:
		var amount := int(composition[material_id]) * stack.quantity
		if amount > 0:
			value[material_id] = amount
	return value


# Removes the stack from inv and adds its materials. Returns what was gained
# ({} if it can't be recycled).
func recycle_stack(inv: Inventory, stack: item_stack, should_save := true) -> Dictionary:
	if inv == null or not can_recycle(stack) or not inv.get_stacks().has(stack):
		return {}
	var gained := recycle_value(stack)
	inv.remove_item_stack(stack)
	add_materials(gained, should_save)
	return gained


# Recycles every recyclable stack in inv (parts and the rest stay). Saves once.
func recycle_all(inv: Inventory) -> Dictionary:
	var gained := {}
	if inv == null:
		return gained
	for stack in inv.get_stacks():
		var got := recycle_stack(inv, stack, false)
		for material_id in got:
			gained[material_id] = int(gained.get(material_id, 0)) + int(got[material_id])
	if not gained.is_empty():
		_save()
	return gained


# ---- Expedition stakes ----

func begin_expedition() -> void:
	in_expedition = true
	_log("expedition started")
	_save()


func is_in_expedition() -> bool:
	return in_expedition


# Cargo already lives in mech_inventory, so extracting only has to end the
# run and save what the player brought back.
func extract_expedition() -> void:
	if not in_expedition:
		return
	in_expedition = false
	_log("expedition extracted")
	_save()


# Loses everything that went out: the cargo is emptied and the player starts
# over in DEFAULT_MECHA. Stash and money are untouched. Returns the loss
# report (also kept as pending until take_loss_report), or {} when no
# expedition is running — so dying after extracting costs nothing.
func lose_expedition(reason: String) -> Dictionary:
	if not in_expedition:
		return {}
	var report := {
		"reason": reason,
		"mecha": _describe_mecha(current_mecha),
		"cargo": _describe_inventory(mech_inventory),
	}
	in_expedition = false
	pending_loss_report = report
	mech_inventory = null  # the next core to be equipped sizes a fresh one
	set_current_mecha(DEFAULT_MECHA.duplicate(), false)
	_log("expedition lost (%s)" % reason)
	_save()
	expedition_lost.emit(report)
	return report


# Called once the profile is loaded at boot: a run that was still going when
# the game closed is lost.
func resolve_abandoned_expedition() -> bool:
	if not in_expedition:
		return false
	lose_expedition(LOSS_ABANDONED)
	return true


func has_loss_report() -> bool:
	return not pending_loss_report.is_empty()


# Returns the pending loss report and clears it, so it's only shown once.
func take_loss_report() -> Dictionary:
	var report := pending_loss_report
	if report.is_empty():
		return report
	pending_loss_report = {}
	_save()
	return report


# Player-facing lines for a loss report (game-over screen, main menu).
func format_loss_report(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var lines := []
	var mecha: Array = report.get("mecha", [])
	var cargo: Array = report.get("cargo", [])
	lines.append("Mecha lost: " + (", ".join(mecha) if not mecha.is_empty() else "none"))
	lines.append("Cargo lost: " + (", ".join(cargo) if not cargo.is_empty() else "empty"))
	lines.append("Your stash and credits are safe. A standard mecha has been issued.")
	return "\n".join(lines)


# "Name" / "Name x3" for everything in the mech cargo (extraction summary).
func describe_cargo() -> Array:
	return _describe_inventory(mech_inventory)


# Part names of every equipped part, in DEFAULT_MECHA slot order.
func _describe_mecha(design: Dictionary) -> Array:
	var names := []
	for slot in DEFAULT_MECHA:
		var part_id = design.get(slot)
		if typeof(part_id) == TYPE_STRING and part_id != "":
			names.append(_part_display_name(_part_type_for_slot(slot), part_id))
	return names


# "Name" or "Name x3" for every stack in an inventory.
func _describe_inventory(inv: Inventory) -> Array:
	var names := []
	if inv == null:
		return names
	for y in range(inv.grid_height):
		for x in range(inv.grid_width):
			var cell = inv.grid[y][x]
			var stack: item_stack = cell["stack"]
			if stack == null or cell["origin_x"] != x or cell["origin_y"] != y:
				continue
			var item_name := "?"
			if stack.kind == item_stack.ItemKind.PART:
				item_name = _part_display_name(stack.item_type, stack.item_id)
			elif stack.item != null and stack.item.get("display_name"):
				item_name = stack.item.display_name
			names.append(item_name if stack.quantity <= 1 else "%s x%d" % [item_name, stack.quantity])
	return names


# Design slots name the side ("arm_weapon_left"); PartManager wants the type.
func _part_type_for_slot(slot: String) -> String:
	if "arm_weapon" in slot:
		return "arm_weapon"
	if "shoulder_weapon" in slot:
		return "shoulder_weapon"
	return slot


func _part_display_name(part_type: String, part_id: String) -> String:
	if PartManager.get_parts(part_type) is Dictionary and PartManager.is_valid_part(part_type, part_id):
		var part_name = PartManager.get_part(part_type, part_id).get("part_name")
		if typeof(part_name) == TYPE_STRING and part_name != "":
			return part_name
	return part_id


# ---- Save / load ----

func reset() -> void:
	money = 0.0
	current_mecha = DEFAULT_MECHA.duplicate()
	stash_inventory = null
	mech_inventory = null
	materials = {}
	in_expedition = false
	pending_loss_report = {}
	money_changed.emit(money)
	mecha_changed.emit(current_mecha)
	materials_changed.emit(get_materials())


func get_save_data() -> Dictionary:
	return {
		"money": money,
		"current_mecha": current_mecha,
		"stash_inventory": _inventory_to_dict(stash_inventory),
		"mech_inventory": _inventory_to_dict(mech_inventory),
		"materials": materials,
		"in_expedition": in_expedition,
		"pending_loss_report": pending_loss_report,
	}


func set_save_data(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = float(data.get("money", 0.0))
	current_mecha = _with_default_slots(data.get("current_mecha"))
	stash_inventory = _inventory_from_dict(data.get("stash_inventory"))
	mech_inventory = _inventory_from_dict(data.get("mech_inventory"))
	materials = {}
	var saved_materials = data.get("materials", {})
	if typeof(saved_materials) == TYPE_DICTIONARY:
		for material_id in saved_materials:
			materials[str(material_id)] = int(saved_materials[material_id])  # JSON numbers load as floats
	in_expedition = bool(data.get("in_expedition", false))
	var report = data.get("pending_loss_report", {})
	pending_loss_report = report if typeof(report) == TYPE_DICTIONARY else {}
	money_changed.emit(money)
	mecha_changed.emit(current_mecha)
	materials_changed.emit(get_materials())


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
