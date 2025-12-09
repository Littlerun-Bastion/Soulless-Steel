extends Resource
class_name inventory

@export var grid_width: int = 0
@export var grid_height: int = 0
@export var max_slots: int = 30  # Not strictly needed for grid, but you had it

# Each cell is a Dictionary:
# {
#   "stack": item_stack or null,
#   "origin_x": int,
#   "origin_y": int
# }
var grid: Array = []

const EMPTY_CELL := {
	"stack": null,
	"origin_x": -1,
	"origin_y": -1
}


func initialize_grid(width: int, height: int):
	grid_width = width
	grid_height = height
	grid.clear()
	grid.resize(height)

	for y in range(height):
		grid[y] = []
		grid[y].resize(width)
		for x in range(width):
			grid[y][x] = EMPTY_CELL.duplicate()


func resize_and_migrate(new_width: int, new_height: int):
	var old_items: Array = []

	# Collect item stacks from origin cells only
	for y in range(grid_height):
		for x in range(grid_width):
			var cell = grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				old_items.append(cell["stack"])

	# Create new grid
	initialize_grid(new_width, new_height)

	# Try to reinsert items
	for stack in old_items:
		add_stack_to_first_available_slot(stack)


func add_stack_to_first_available_slot(stack: item_stack) -> bool:
	for y in range(grid_height):
		for x in range(grid_width):
			if place_item(stack, x, y):
				return true
	return false


func get_current_weight() -> float:
	var total := 0.0
	for y in range(grid_height):
		for x in range(grid_width):
			var cell = grid[y][x]
			var stack: item_stack = cell["stack"]
			if stack and stack.item:
				total += stack.item.weight * stack.quantity
	return total


func add_item(item: item_data, quantity := 1) -> bool:
	var stack := item_stack.new()
	stack.item = item
	stack.quantity = quantity

	for y in range(grid_height):
		for x in range(grid_width):
			if place_item(stack, x, y):
				return true

	return false


func remove_item(item: item_data, quantity: int = 1) -> bool:
	var remaining = quantity
	for y in range(grid_height):
		for x in range(grid_width):
			var cell = grid[y][x]
			var stack: item_stack = cell["stack"]
			if stack and stack.item == item:
				if stack.quantity > remaining:
					stack.quantity -= remaining
					return true
				else:
					remaining -= stack.quantity
					remove_item_stack(stack)
				if remaining <= 0:
					return true
	return remaining <= 0


func item_fits_at(stack: item_stack, start_x: int, start_y: int) -> bool:
	var w = stack.width_cells()
	var h = stack.height_cells()

	# Bounds check
	if start_x + w > grid_width:
		return false
	if start_y + h > grid_height:
		return false

	# Check occupancy
	for y in range(start_y, start_y + h):
		for x in range(start_x, start_x + w):
			if grid[y][x]["stack"] != null:
				return false

	return true



func place_item(stack: item_stack, start_x: int, start_y: int) -> bool:
	if not item_fits_at(stack, start_x, start_y):
		return false

	var w = stack.width_cells()
	var h = stack.height_cells()

	for y in range(start_y, start_y + h):
		for x in range(start_x, start_x + w):
			grid[y][x]["stack"] = stack
			grid[y][x]["origin_x"] = start_x
			grid[y][x]["origin_y"] = start_y

	return true



func remove_item_stack(stack: item_stack) -> void:
	var origin_x := -1
	var origin_y := -1

	# Find origin cell
	for y in range(grid_height):
		for x in range(grid_width):
			if grid[y][x]["stack"] == stack:
				origin_x = grid[y][x]["origin_x"]
				origin_y = grid[y][x]["origin_y"]
				break

	if origin_x == -1:
		return

	var w = stack.width_cells()
	var h = stack.height_cells()

	for y in range(origin_y, origin_y + h):
		for x in range(origin_x, origin_x + w):
			grid[y][x]["stack"] = null
			grid[y][x]["origin_x"] = -1
			grid[y][x]["origin_y"] = -1
