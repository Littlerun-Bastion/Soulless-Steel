extends Resource
class_name item_data

# How advanced a piece of salvage is. LootTable uses it to make higher tech
# rarer. NONE is for anything that isn't salvage (it never comes out of a
# loot table roll).
enum TechTier { NONE, LOW, MID, HIGH }

## An item tagged this is money: it sells and recycles 1 to 1 into credits,
## at its price (PlayerProgress.is_currency).
const CURRENCY_TAG := "currency"

@export var id: String
@export var display_name: String
@export var description: String
@export var icon: Texture2D
## Tonnes, for one item.
@export var weight: float = 0.0
## Credits. For salvage it is what its composition is worth (Materials.value_of).
@export var price: int = 0
@export var tags: Array[String] = []
@export var item_size := [1,1]

# If this item represents a mech part:
@export var part_scene: PackedScene

# Fields for stackable items
@export var max_stack := 1

@export var tech_tier: TechTier = TechTier.NONE
# What recycling one of this item yields in the Hangar: material id
# (see Materials) -> amount in the material's stored unit. Empty = can't be
# recycled (currency recycles into credits instead).
@export var composition: Dictionary[String, int] = {}


func width() -> int:
	return item_size[0]

func height() -> int:
	return item_size[1]


## "Low", "Mid", "High" (for any TechTier, items and parts alike).
static func tier_name(tier: int) -> String:
	return str(TechTier.keys()[tier]).capitalize()
