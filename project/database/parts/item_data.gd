extends Resource
class_name item_data

# How advanced a piece of salvage is. LootTable uses it to make higher tech
# rarer. NONE is for anything that isn't salvage (it never comes out of a
# loot table roll).
enum TechTier { NONE, LOW, MID, HIGH }

@export var id: String
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var weight: float = 0.0
@export var price: int = 0
@export var tags: Array[String] = []
@export var item_size := [1,1]

# If this item represents a mech part:
@export var part_scene: PackedScene

# Fields for stackable items
@export var max_stack := 1

@export var tech_tier: TechTier = TechTier.NONE
# Later: a composition (what recycling this yields in the Hangar) goes here,
# next to tech_tier. Not designed yet.


func width() -> int:
	return item_size[0]

func height() -> int:
	return item_size[1]
