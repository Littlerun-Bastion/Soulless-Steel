extends Resource
class_name MaterialData

# A crafting material that salvage is recycled into (Hangar). Items list
# what they break into in item_data.composition, keyed by this id.
# All materials are registered in Materials.ALL.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
