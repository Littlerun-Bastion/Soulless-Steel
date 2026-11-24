class_name SalvageLoot
extends Resource

# What one kind of salvage source gives (SalvageField). Unlike LootTable,
# there is no tech tier roll: the source shows what it gives, so its loot is
# fixed by kind.
#
# By default each entry rolls on its own, so a bus can give an engine, a
# battery and a wiring harness at once, or only some of them. With pick_one,
# exactly one entry is chosen, each entry's chance being its weight (a
# shipping container holds one bulk item, or a few smaller ones), and then
# its count is rolled.
#
# A rolled count larger than the item's stack size becomes several stacks.

@export var entries: Array[SalvageLootEntry] = []
@export var pick_one := false


func roll(amount: int, rng: RandomNumberGenerator) -> Array:
	var stacks := []
	if pick_one:
		var entry := _pick(rng)
		if entry != null:
			_add(stacks, entry, entry.roll_count_always(amount, rng))
		return stacks
	for entry in entries:
		if entry != null:
			_add(stacks, entry, entry.roll_count(amount, rng))
	return stacks


func _pick(rng: RandomNumberGenerator) -> SalvageLootEntry:
	var total := 0.0
	for entry in entries:
		if entry != null and entry.item != null:
			total += maxf(entry.chance, 0.0)
	if total <= 0.0:
		return null
	var at := rng.randf() * total
	for entry in entries:
		if entry == null or entry.item == null:
			continue
		at -= maxf(entry.chance, 0.0)
		if at < 0.0:
			return entry
	return null


func _add(stacks: Array, entry: SalvageLootEntry, n: int) -> void:
	var per_stack := maxi(1, entry.item.max_stack) if entry.item != null else 1
	while n > 0:
		var q := mini(n, per_stack)
		var stack := item_stack.from_generic(entry.item, q)
		if stack != null:
			stacks.append(stack)
		n -= q
