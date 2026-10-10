extends Resource
class_name LootEntry

# One thing a LootContainer or LootTable can hand out: either a generic item
# (item) or a mech part (part_type + part_id). Set one or the other.
#
# Parts are for weapon drops later. part_type is a PartManager key
# ("arm_weapon", "shoulder_weapon", "head", ...), the same as the stash uses.

@export var item: item_data
@export var quantity: int = 1

@export_group("Part")
@export var part_type: String = ""
@export var part_id: String = ""


func is_part() -> bool:
	return part_type != "" and part_id != ""


func is_valid() -> bool:
	if quantity <= 0:
		return false
	if is_part():
		return PartManager.get_parts(part_type) is Dictionary \
				and PartManager.is_valid_part(part_type, part_id)
	return item != null


# Parts have no tier; they never come out of a tier roll.
func get_tech_tier() -> int:
	if is_part() or item == null:
		return item_data.TechTier.NONE
	return item.tech_tier


# A fresh stack each call, so several containers can share one entry.
func make_stack() -> item_stack:
	if not is_valid():
		return null
	if is_part():
		# Same shape as PlayerProgress.add_part: item stays null and is
		# resolved through PartManager when needed.
		var stack := item_stack.new()
		stack.kind = item_stack.ItemKind.PART
		stack.item_category = "part"
		stack.item_type = part_type
		stack.item_id = part_id
		stack.quantity = quantity
		return stack
	return item_stack.from_generic(item, quantity)
