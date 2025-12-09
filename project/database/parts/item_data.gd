extends Resource
class_name item_data

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
func width() -> int:
	return item_size[0]

func height() -> int:
	return item_size[1]
