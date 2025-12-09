extends Resource
class_name item_stack

@export var item: item_data
@export var quantity: int = 1

var rotated: bool = false

func is_full() -> bool:
	return quantity >= item.max_stack


func width_cells() -> int:
	if rotated:
		return item.height()
	return item.width()

func height_cells() -> int:
	if rotated:
		return item.width()
	return item.height()
