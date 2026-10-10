extends Resource
class_name Inventory

@export var grid_width: int = 0
@export var grid_height: int = 0

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


# Returns the stacks that no longer fit (empty if everything did). Callers
# decide where those go — they used to be dropped silently.
func resize_and_migrate(new_width: int, new_height: int) -> Array:
	var old_items: Array = []

	# Collect item stacks from origin cells only
	for y in range(grid_height):
		for x in range(grid_width):
			var cell = grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				old_items.append(cell["stack"])

	# Create new grid
	initialize_grid(new_width, new_height)

	# Try to reinsert items (turned, if that's the only way they fit)
	var overflow: Array = []
	for stack in old_items:
		if not add_stack_anywhere(stack):
			overflow.append(stack)
	return overflow


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
			if stack and cell["origin_x"] == x and cell["origin_y"] == y:
				total += stack.get_unit_weight() * stack.quantity
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
			
			
# Takes an array of item_stacks, places as many as possible, returns an array of stacks that didn't fit.
func add_stacks_bulk(stacks: Array) -> Array:
	var overflow: Array = []
	for stack in stacks:
		if stack == null:
			continue
		if not add_stack_to_first_available_slot(stack):
			overflow.append(stack)
	return overflow
	
# ---- Moving stacks between inventories (looting) ----

# Every stack, once each (origin cells only).
func get_stacks() -> Array:
	var stacks: Array = []
	for y in range(grid_height):
		for x in range(grid_width):
			var cell = grid[y][x]
			if cell["stack"] != null and cell["origin_x"] == x and cell["origin_y"] == y:
				stacks.append(cell["stack"])
	return stacks


func is_empty() -> bool:
	return get_stacks().is_empty()


# First free spot for the stack as it's currently rotated, or (-1, -1).
func find_free_slot(stack: item_stack) -> Vector2i:
	for y in range(grid_height):
		for x in range(grid_width):
			if item_fits_at(stack, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# Whether the stack fits somewhere, either way round. Changes nothing.
func has_room_for(stack: item_stack) -> bool:
	if find_free_slot(stack).x >= 0:
		return true
	stack.rotated = not stack.rotated
	var fits := find_free_slot(stack).x >= 0
	stack.rotated = not stack.rotated
	return fits


# Like add_stack_to_first_available_slot, but turns the stack if that's the
# only way it fits.
func add_stack_anywhere(stack: item_stack) -> bool:
	if add_stack_to_first_available_slot(stack):
		return true
	stack.rotated = not stack.rotated
	if add_stack_to_first_available_slot(stack):
		return true
	stack.rotated = not stack.rotated
	return false


# Moves one stack from this inventory into target. Leaves it where it was
# (same spot, same rotation) when target has no room.
func transfer_stack_to(stack: item_stack, target: Inventory) -> bool:
	var origin := _find_origin(stack)
	if origin.x < 0 or target == null:
		return false
	var was_rotated := stack.rotated
	remove_item_stack(stack)  # before rotating: removal uses the current size
	if target.add_stack_anywhere(stack):
		return true
	stack.rotated = was_rotated
	place_item(stack, origin.x, origin.y)
	return false


# Moves every stack that fits into target; returns how many moved.
func transfer_all_to(target: Inventory) -> int:
	var moved := 0
	for stack in get_stacks():
		if transfer_stack_to(stack, target):
			moved += 1
	return moved


func _find_origin(stack: item_stack) -> Vector2i:
	for y in range(grid_height):
		for x in range(grid_width):
			var cell = grid[y][x]
			if cell["stack"] == stack:
				return Vector2i(cell["origin_x"], cell["origin_y"])
	return Vector2i(-1, -1)


# Convenience version that takes item_data + quantity pairs
# Each entry: { "item": item_data, "quantity": int }
func add_items_bulk(entries: Array) -> Array:
	var stacks: Array = []
	for entry in entries:
		var item = entry.get("item")
		var qty: int = int(entry.get("quantity", 1))
		if item == null:
			continue
		var stack := item_stack.new()
		stack.item = item
		stack.quantity = qty
		stacks.append(stack)
	return add_stacks_bulk(stacks)
