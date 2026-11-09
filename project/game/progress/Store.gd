class_name Store
extends RefCounted

# The regional store, sold through amazing.com on the NET (NetWindow). It
# sells Standard parts at their price.
#
# A part is listed (is_listed) when it is real (not "Null"), has a price, has
# a maker that isn't the test maker, has store_listed on (off keeps secret
# parts out of the store and out of the Compare window's STORE list) and is
# no higher tech than MAX_TECH_TIER.
#
# The cart lasts for the session and is never saved: one [part_type, part_id]
# entry per copy. Checkout delivers each entry (deliver), charges only for the
# ones that arrived, leaves the rest in the cart and spends the money once.
#
# Related parts: Hardware parts come in frames (their `frame`, frame_of), and
# a part's frame_mates are the rest of it on sale. similar() ranks the listed
# parts by the tags they share with one.

## Part types in shop order.
const CATEGORIES := ["head", "core", "shoulders", "chassis", "generator", "chipset", "thruster",
		"internal", "arm_weapon", "shoulder_weapon"]
## The shop's departments, named like the Equipment window's tabs.
const GROUPS := [
	{"id": "hardware", "name": "HARDWARE", "types": ["head", "core", "shoulders", "chassis"]},
	{"id": "wetware", "name": "WETWARE", "types": ["generator", "chipset", "thruster", "internal"]},
	{"id": "weapons", "name": "WEAPONS", "types": ["arm_weapon", "shoulder_weapon"]},
]
const TYPE_NAMES := {
	"head": ["Head", "Heads"], "core": ["Core", "Cores"], "shoulders": ["Shoulders", "Shoulders"],
	"chassis": ["Chassis", "Chassis"], "generator": ["Generator", "Generators"],
	"chipset": ["Chipset", "Chipsets"], "thruster": ["Thruster", "Thrusters"],
	"internal": ["Internal", "Internals"], "arm_weapon": ["Arm weapon", "Arm weapons"],
	"shoulder_weapon": ["Shoulder weapon", "Shoulder weapons"],
}
## The highest tech tier on sale.
const MAX_TECH_TIER := item_data.TechTier.HIGH
## The part types that come in frames (frame_of).
const FRAME_TYPES := ["head", "core", "shoulders", "chassis"]
## The most parts similar() gives.
const SIMILAR_MAX := 5
const ORDER_PREFIX := "AMZ"
const FIRST_ORDER := 4217

## Statics can't have signals, so the store keeps one object that does.
class Feed extends RefCounted:
	signal cart_changed
	signal delivered(part_type: String, part_id: String)

static var feed := Feed.new()
static var cart: Array = []
## The last checkout's result (checkout), {} before the first.
static var last_order: Dictionary = {}
static var _orders := 0


# ---- what the store lists ------------------------------------------------

static func is_listed(part_type: String, part_id: String) -> bool:
	var part := get_part(part_type, part_id)
	if part == null:
		return false
	var price_value = part.get("price")
	if not (price_value is float or price_value is int) or price_value <= 0:
		return false
	var maker := Manufacturers.of_part(part)
	if maker == "" or Manufacturers.is_test(maker):
		return false
	if part.get("store_listed") == false:
		return false
	var tier = part.get("tech_tier")
	return tier is int and tier <= MAX_TECH_TIER


## The part, or null if there is no such part of a store category.
static func get_part(part_type: String, part_id: String) -> Object:
	if not part_type in CATEGORIES or part_id == "" or part_id == "Null":
		return null
	var parts: Dictionary = PartManager.get_parts(part_type)
	return parts.get(part_id)


## The listed part ids of one type, by price, then name.
static func catalogue(part_type: String) -> Array:
	if not part_type in CATEGORIES:
		return []
	var ids: Array = PartManager.get_parts(part_type).keys().filter(func(id): return is_listed(part_type, id))
	ids.sort_custom(func(a, b):
		var pa := price(part_type, a)
		var pb := price(part_type, b)
		if pa != pb:
			return pa < pb
		var na := part_name(part_type, a)
		var nb := part_name(part_type, b)
		if na != nb:
			return na.naturalnocasecmp_to(nb) < 0
		return a < b)
	return ids


## [part_type, part_id] pairs of the maker's listed parts, in shop order.
static func catalogue_of_maker(maker_id: String) -> Array:
	var result := []
	for part_type in CATEGORIES:
		for part_id in catalogue(part_type):
			if maker_of(part_type, part_id) == maker_id:
				result.append([part_type, part_id])
	return result


## [part_type, part_id] pairs whose part name, maker or id contains the text,
## ignoring case, in shop order.
static func search(text: String) -> Array:
	var wanted := text.strip_edges().to_lower()
	if wanted == "":
		return []
	var result := []
	for part_type in CATEGORIES:
		for part_id in catalogue(part_type):
			var maker := maker_of(part_type, part_id)
			var part := get_part(part_type, part_id)
			var haystack := [part_name(part_type, part_id), str(part_id), str(part.get("manufacturer_name")),
					Manufacturers.display_name(maker), Manufacturers.short_name(maker)]
			if haystack.any(func(s): return wanted in str(s).to_lower()):
				result.append([part_type, part_id])
	return result


## The store sells Standard grade only, at the part's price.
static func price(part_type: String, part_id: String) -> int:
	var part := get_part(part_type, part_id)
	var value = part.get("price") if part != null else null
	return int(roundf(value)) if value is float or value is int else 0


static func part_name(part_type: String, part_id: String) -> String:
	var part := get_part(part_type, part_id)
	var value = part.get("part_name") if part != null else null
	return str(value) if value != null and str(value) != "" else part_id


static func maker_of(part_type: String, part_id: String) -> String:
	return Manufacturers.of_part(get_part(part_type, part_id))


## "Head" (one=true) or "Heads".
static func type_name(part_type: String, one := true) -> String:
	var names: Array = TYPE_NAMES.get(part_type, [part_type, part_type])
	return names[0] if one else names[1]


## The group a part type belongs to, {} for none.
static func group_of(part_type: String) -> Dictionary:
	for group in GROUPS:
		if part_type in group.types:
			return group
	return {}


static func group_by_id(group_id: String) -> Dictionary:
	for group in GROUPS:
		if group.id == group_id:
			return group
	return {}


# ---- related parts ------------------------------------------------------

## The frame a Hardware part belongs to (its `frame`), "" for none.
static func frame_of(part_type: String, part_id: String) -> String:
	if not part_type in FRAME_TYPES:
		return ""
	var part := get_part(part_type, part_id)
	var value = part.get("frame") if part != null else null
	return str(value).strip_edges() if value != null else ""


## The other listed parts of a Hardware part's frame, in shop order; [] when
## it has no frame or is the only part of it on sale.
static func frame_mates(part_type: String, part_id: String) -> Array:
	var frame := frame_of(part_type, part_id)
	var mates := []
	if frame == "":
		return mates
	for other_type in FRAME_TYPES:
		for other_id in catalogue(other_type):
			if not (other_type == part_type and other_id == part_id) and frame_of(other_type, other_id) == frame:
				mates.append([other_type, other_id])
	return mates


## Up to SIMILAR_MAX listed parts that share tags with the part: the most
## tags in common first, then the same type, the same maker, the nearest
## price and the name.
static func similar(part_type: String, part_id: String) -> Array:
	var tags := _tags_of(part_type, part_id)
	var maker := maker_of(part_type, part_id)
	var here := price(part_type, part_id)
	var scored := []
	for other_type in CATEGORIES:
		for other_id in catalogue(other_type):
			if other_type == part_type and other_id == part_id:
				continue
			var shared := 0
			for tag in _tags_of(other_type, other_id):
				if tag in tags:
					shared += 1
			if shared == 0:
				continue
			scored.append({"entry": [other_type, other_id], "shared": shared, "same_type": other_type == part_type,
					"same_maker": maker_of(other_type, other_id) == maker,
					"gap": absi(price(other_type, other_id) - here), "name": part_name(other_type, other_id)})
	scored.sort_custom(func(a, b):
		if a.shared != b.shared:
			return a.shared > b.shared
		if a.same_type != b.same_type:
			return a.same_type
		if a.same_maker != b.same_maker:
			return a.same_maker
		if a.gap != b.gap:
			return a.gap < b.gap
		return str(a.name).naturalnocasecmp_to(b.name) < 0)
	return scored.slice(0, SIMILAR_MAX).map(func(s): return s.entry)


static func _tags_of(part_type: String, part_id: String) -> Array:
	var part := get_part(part_type, part_id)
	var tags = part.get("tags") if part != null else null
	return tags if tags is Array else []


# ---- the cart -----------------------------------------------------------

## Adds one copy; false (and nothing added) for a part that isn't listed.
static func add_to_cart(part_type: String, part_id: String) -> bool:
	if not is_listed(part_type, part_id):
		return false
	cart.append([part_type, part_id])
	feed.cart_changed.emit()
	return true


static func remove_from_cart(index: int) -> void:
	if index < 0 or index >= cart.size():
		return
	cart.remove_at(index)
	feed.cart_changed.emit()


static func clear_cart() -> void:
	cart.clear()
	feed.cart_changed.emit()


static func cart_total() -> int:
	var total := 0
	for entry in cart:
		total += price(entry[0], entry[1])
	return total


static func cart_count() -> int:
	return cart.size()


# ---- checkout -----------------------------------------------------------

## Why the player can't buy the cart right now; "" when they can.
static func block_reason() -> String:
	if cart.is_empty():
		return "CART IS EMPTY"
	if PlayerProgress.is_in_expedition():
		return "OFFLINE DURING EXPEDITIONS"
	if PlayerProgress.is_in_debt():
		return "ACCOUNT IN DEBT"
	if not PlayerProgress.can_afford(cart_total()):
		return "INSUFFICIENT FUNDS"
	return ""


## Buys the cart. Each entry goes through deliver(); only the ones that
## arrive are charged, and the ones that don't stay in the cart. The money
## is spent once at the end (which saves). Returns
## {"bought": [...], "left": [...], "spent": int, "order": String}; the order
## number is "" when nothing could be bought.
static func checkout() -> Dictionary:
	var reason := block_reason()
	if reason != "":
		return {"bought": [], "left": cart.duplicate(), "spent": 0, "order": "", "reason": reason}
	var bought := []
	var left := []
	var spent := 0
	for entry in cart:
		if deliver(entry[0], entry[1]):
			bought.append(entry)
			spent += price(entry[0], entry[1])
		else:
			left.append(entry)
	cart = left
	var order := ""
	if not bought.is_empty():
		PlayerProgress.spend_money(spent)
		order = _next_order_number()
		var text := "Order %s: %d item%s, %d CT" % [order, bought.size(), "" if bought.size() == 1 else "s", spent]
		if not left.is_empty():
			text += "; %d left in the cart (stash full)" % left.size()
		MechLog.write("NET", text, MechLog.Kind.LOOT)
	else:
		MechLog.write("NET", "Order failed: stash full", MechLog.Kind.SYSTEM, true)
	last_order = {"bought": bought, "left": left.duplicate(), "spent": spent, "order": order}
	feed.cart_changed.emit()
	return last_order.duplicate()


## The one place a purchase arrives: today straight into the stash (without
## saving; checkout saves once). False when it doesn't fit.
static func deliver(part_type: String, part_id: String) -> bool:
	if not PlayerProgress.add_part(part_type, part_id, false):
		return false
	feed.delivered.emit(part_type, part_id)
	return true


## Where deliveries go, for the receipt.
static func delivery_place() -> String:
	return "STASH"


## "AMZ-04217-31": a running number and two check digits.
static func _next_order_number() -> String:
	var serial := FIRST_ORDER + _orders
	_orders += 1
	var check := (serial * 37 + 11) % 97
	return "%s-%05d-%02d" % [ORDER_PREFIX, serial, check]
