extends MechWindow
class_name InventoryWindow

## A wreck's loot window also lists the parts it shed (Wreck.unsalvageable)
## under the grid, under an UNSALVAGEABLE heading: each with its sprite
## crossed out, its slot and name struck through, and an UNSALVAGEABLE tag.
## They aren't items: nothing there can be dragged or taken. The list follows
## the wreck (Wreck.unsalvageable_changed), so a part a Coyote carries off
## leaves it.

const UNSALVAGEABLE := "UNSALVAGEABLE"
## The crossed-out sprite's box, and how bright the sprite and the cross are.
const ICON_SIZE := Vector2(48, 40)
const ICON_TINT := Color(1, 1, 1, 0.45)
const STRIKE_WIDTH := 2.0

var inventory_grid: InventoryGrid = null
var target_inventory: Inventory = null

var _wreck: Wreck = null
var _unsalvageable_box: VBoxContainer = null

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


## Lists `wreck`'s unsalvageable parts under the grid, and keeps the list up
## to date; null (or anything not a Wreck) clears it.
func show_unsalvageable(wreck) -> void:
	if is_instance_valid(_wreck) and _wreck.unsalvageable_changed.is_connected(_fill_unsalvageable):
		_wreck.unsalvageable_changed.disconnect(_fill_unsalvageable)
	_wreck = wreck if wreck is Wreck else null
	if _wreck != null:
		_wreck.unsalvageable_changed.connect(_fill_unsalvageable)
	_fill_unsalvageable()


## The rows shown, "<slot> · <name>" each (tests).
func get_unsalvageable_rows() -> Array[String]:
	var rows: Array[String] = []
	if _unsalvageable_box == null or not _unsalvageable_box.visible:
		return rows
	for row in _unsalvageable_box.get_children():
		if row.has_meta("part_text"):
			rows.append(str(row.get_meta("part_text")))
	return rows


func _fill_unsalvageable() -> void:
	var entries: Array = _wreck.unsalvageable if is_instance_valid(_wreck) else []
	if _unsalvageable_box == null:
		if entries.is_empty():
			return
		_unsalvageable_box = MechUI.vbox(&"TightStack")
		var column: Node = $Content/VBox
		column.add_child(_unsalvageable_box)
		column.move_child(_unsalvageable_box, inventory_grid.get_index() + 1)
	MechUI.clear(_unsalvageable_box)
	_unsalvageable_box.visible = not entries.is_empty()
	if entries.is_empty():
		return
	_unsalvageable_box.add_child(HSeparator.new())
	_unsalvageable_box.add_child(MechUI.label(&"LabelMetaBright", UNSALVAGEABLE))
	for entry in entries:
		_unsalvageable_box.add_child(_unsalvageable_row(entry))
	size.y = maxf(size.y, get_combined_minimum_size().y)


func _unsalvageable_row(entry: Dictionary) -> HBoxContainer:
	var row := MechUI.hbox(&"BarRow")
	var text := "%s · %s" % [entry.get("label", ""), entry.get("name", "")]
	row.set_meta("part_text", text)
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = entry.get("texture")
	icon.modulate = ICON_TINT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name_label := MechUI.label(&"LabelDim", text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var tag := MechUI.label(&"LabelMetaBright", UNSALVAGEABLE)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tag)
	# Drawn after each node's own drawing (the draw signal), so over it, in
	# the name's colour.
	icon.draw.connect(_draw_cross.bind(icon, name_label))
	name_label.draw.connect(_draw_strike.bind(name_label))
	return row


# An X corner to corner over the sprite's box.
func _draw_cross(icon: TextureRect, name_label: Label) -> void:
	var colour := name_label.get_theme_color("font_color")
	var box := Rect2(Vector2.ZERO, icon.size).grow(-4.0)
	icon.draw_line(box.position, box.end, colour, STRIKE_WIDTH)
	icon.draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), colour, STRIKE_WIDTH)


# A line through the middle of the text, as long as the text (or the label).
func _draw_strike(label: Label) -> void:
	var colour := label.get_theme_color("font_color")
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := minf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, label.size.x)
	var y := floorf(label.size.y * 0.5) + 1.0
	label.draw_line(Vector2(0.0, y), Vector2(width, y), colour, STRIKE_WIDTH)


func _register_with_drag_manager() -> void:
	if inventory_grid == null:
		return
	MechOS.drag_manager.register_grid(inventory_grid, self)


func _exit_tree() -> void:
	# Clean up when window is closed/freed
	if inventory_grid != null:
		MechOS.drag_manager.unregister_grid(inventory_grid)
	if is_instance_valid(_wreck) and _wreck.unsalvageable_changed.is_connected(_fill_unsalvageable):
		_wreck.unsalvageable_changed.disconnect(_fill_unsalvageable)
