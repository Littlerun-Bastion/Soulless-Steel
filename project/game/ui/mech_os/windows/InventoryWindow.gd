extends MechWindow
class_name InventoryWindow

var inventory_grid: InventoryGrid = null
var target_inventory: Inventory = null

@onready var item_count_label: Label = $Content/VBox/InfoBar/ItemCountLabel
@onready var weight_label: Label = $Content/VBox/InfoBar/WeightLabel


func _ready() -> void:
	super()
	inventory_grid = $Content/VBox/InventoryGrid


func setup(inv: Inventory, title: String = "INVENTORY") -> void:
	target_inventory = inv
	window_title = title
	
	if title_label != null:
		title_label.text = title
	
	if inventory_grid != null:
		inventory_grid.set_inventory(inv)
	
	_register_with_drag_manager()
	update_info()


func update_info() -> void:
	if inventory_grid == null:
		return
	if item_count_label != null:
		item_count_label.text = "Items: %d" % inventory_grid.get_item_count()
	if weight_label != null:
		weight_label.text = "Weight: %.1f" % inventory_grid.get_total_weight()


func refresh() -> void:
	if inventory_grid != null:
		inventory_grid.refresh()
	update_info()


func _register_with_drag_manager() -> void:
	if inventory_grid == null:
		return
	MechOS.drag_manager.register_grid(inventory_grid, self)


func _exit_tree() -> void:
	# Clean up when window is closed/freed
	if inventory_grid != null:
		MechOS.drag_manager.unregister_grid(inventory_grid)
