class_name SalvageSource
extends LootContainer

# The searchable node of one SalvageField source near the player: a loot
# container (Search opens the loot window), made and freed by the field. Its
# inventory belongs to the field, so the source keeps what is left when the
# node is freed and made again.

## The field's index of the source this node stands for.
var source_index := -1
