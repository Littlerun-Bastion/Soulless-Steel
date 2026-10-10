extends Resource
class_name LootTable

# Rolls salvage by tech tier: first a tier (weighted, so high tech is rare),
# then one of this table's entries of that tier, all equally likely.
#
# Entries without a tier (parts, items with tech_tier NONE) are skipped by
# rolls. If the rolled tier has no entries, the roll steps down a tier
# (high -> mid -> low), then up, so a table with gaps still hands something out.
#
# Every roll takes an optional RandomNumberGenerator so tests can seed it;
# without one it uses the global random functions.

@export var entries: Array[LootEntry] = []

@export_group("Tier weights")
@export var low_weight: float = 70.0
@export var mid_weight: float = 25.0
@export var high_weight: float = 5.0

const ROLLED_TIERS := [item_data.TechTier.LOW, item_data.TechTier.MID, item_data.TechTier.HIGH]


func get_tier_weight(tier: int) -> float:
	match tier:
		item_data.TechTier.LOW:
			return maxf(low_weight, 0.0)
		item_data.TechTier.MID:
			return maxf(mid_weight, 0.0)
		item_data.TechTier.HIGH:
			return maxf(high_weight, 0.0)
	return 0.0


# Chance (0..1) of each tier being rolled, before falling back for empty tiers.
func get_tier_chances() -> Dictionary:
	var total := 0.0
	for tier in ROLLED_TIERS:
		total += get_tier_weight(tier)
	var chances := {}
	for tier in ROLLED_TIERS:
		chances[tier] = get_tier_weight(tier) / total if total > 0.0 else 0.0
	return chances


func get_entries_of_tier(tier: int) -> Array:
	var result := []
	for entry in entries:
		if entry != null and entry.is_valid() and entry.get_tech_tier() == tier:
			result.append(entry)
	return result


func roll_tier(rng: RandomNumberGenerator = null) -> int:
	var total := 0.0
	for tier in ROLLED_TIERS:
		total += get_tier_weight(tier)
	if total <= 0.0:
		return item_data.TechTier.LOW
	var pick := _randf(rng) * total
	for tier in ROLLED_TIERS:
		pick -= get_tier_weight(tier)
		if pick < 0.0:
			return tier
	return ROLLED_TIERS[-1]


# null when the table has no rollable entries at all.
func roll_entry(rng: RandomNumberGenerator = null) -> LootEntry:
	var tier := roll_tier(rng)
	for candidate_tier in _fallback_order(tier):
		var pool := get_entries_of_tier(candidate_tier)
		if not pool.is_empty():
			return pool[_randi_range(rng, 0, pool.size() - 1)]
	return null


func roll_stack(rng: RandomNumberGenerator = null) -> item_stack:
	var entry := roll_entry(rng)
	return entry.make_stack() if entry != null else null


# count rolls; empty when the table has nothing to give.
func roll_stacks(count: int, rng: RandomNumberGenerator = null) -> Array:
	var stacks := []
	for _i in count:
		var stack := roll_stack(rng)
		if stack != null:
			stacks.append(stack)
	return stacks


# The rolled tier first, then lower tiers, then higher ones.
func _fallback_order(tier: int) -> Array:
	var order := [tier]
	for t in range(tier - 1, item_data.TechTier.LOW - 1, -1):
		order.append(t)
	for t in range(tier + 1, item_data.TechTier.HIGH + 1):
		order.append(t)
	return order


func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()


func _randi_range(rng: RandomNumberGenerator, from: int, to: int) -> int:
	return rng.randi_range(from, to) if rng != null else randi_range(from, to)
