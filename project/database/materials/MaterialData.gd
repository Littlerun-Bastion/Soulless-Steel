extends Resource
class_name MaterialData

# A crafting material that salvage is recycled into (Hangar). Items list
# what they break into in item_data.composition, keyed by this id, as whole
# numbers of the material's stored unit. The UI shows amounts in the
# display unit (Materials.format_amount). All materials are registered in
# Materials.ALL.

enum Origin { SCRAP, STRANGE }

@export var id: String = ""
@export var display_name: String = ""
## SCRAP: old-world materials. STRANGE: from Entities and AVI.
@export var origin: Origin = Origin.SCRAP
## The unit amounts are stored in: "g", "kg", "mL", "Wh" or "u".
@export var unit: String = "kg"
## The unit the UI shows: "t", "kg", "g", "L", "kWh" or "u". Smaller amounts
## step down a unit (Units.amount).
@export var display_unit: String = "kg"
## The mass of one stored unit, in kg. What an item breaks into is checked
## against its weight with it, and the Fabricator's AVI-Polymer filler goes
## by it.
@export var kg_per_unit: float = 1.0
## What one stored unit is worth, in credits. An item is worth its
## materials: item prices are set from these.
@export var value: float = 0.0
@export_multiline var description: String = ""
@export var icon: Texture2D
