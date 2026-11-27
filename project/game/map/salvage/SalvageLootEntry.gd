class_name SalvageLootEntry
extends Resource

# One item a salvage source can give (see SalvageLoot): with `chance` it is
# there, `count` times (a random number from count.x to count.y). In a
# pick_one table, `chance` is the entry's weight instead.
#
# With per_amount above 0, the count follows the source's amount instead
# (for example intact solar modules): amount / per_amount, at least count.x
# and at most count.y.

@export var item: item_data
@export_range(0.0, 1.0) var chance := 1.0
@export var count := Vector2i(1, 1)
@export var per_amount := 0


func roll_count(amount: int, rng: RandomNumberGenerator) -> int:
	if item == null or rng.randf() >= chance:
		return 0
	return roll_count_always(amount, rng)


# The count, with no chance roll.
func roll_count_always(amount: int, rng: RandomNumberGenerator) -> int:
	if item == null:
		return 0
	if per_amount > 0:
		@warning_ignore("integer_division")
		return clampi(amount / per_amount, count.x, count.y)
	return rng.randi_range(count.x, maxi(count.x, count.y))
