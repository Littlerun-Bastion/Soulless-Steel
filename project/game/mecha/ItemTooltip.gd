extends Panel
class_name ItemTooltip

@onready var name_label: Label          = $MarginContainer/VBoxContainer/NameLabel
@onready var type_label: Label          = $MarginContainer/VBoxContainer/TypeLabel
@onready var stats_label: Label         = $MarginContainer/VBoxContainer/StatsLabel
@onready var description_label: RichTextLabel   = $MarginContainer/VBoxContainer/DescriptionLabel

func _ready() -> void:
	visible = false
	z_index = 999                # make sure it draws above other stuff
	set_process(true)            # ensure _process() runs every frame

func show_item(stack: item_stack) -> void:
	if stack == null or stack.item == null:
		hide()
		return

	var item = stack.item

	# --- Name (robust) ---
	var name_val = item.get("item_name")
	if name_val == null or str(name_val) == "":
		name_val = item.get("part_name")
	if name_val == null or str(name_val) == "":
		name_val = item.get("display_name")
	name_label.text = str(name_val if name_val != null else "UNKNOWN ITEM")

	# --- Type / tags ---
	var tags = item.get("tags")
	if tags is Array and tags.size() > 0:
		type_label.text = ", ".join(tags)
	else:
		type_label.text = ""

	# --- Stats: weight, size, value ---
	var lines: Array[String] = []

	var weight = item.get("weight")
	if typeof(weight) == TYPE_FLOAT or typeof(weight) == TYPE_INT:
		lines.append("Weight: %s" % weight)

	var w := stack.width_cells()
	var h := stack.height_cells()
	lines.append("Size: %sx%s" % [w, h])

	var price = item.get("price")
	if typeof(price) == TYPE_FLOAT or typeof(price) == TYPE_INT:
		lines.append("Value: %s" % price)

	if lines.is_empty():
		stats_label.text = ""
	else:
		stats_label.text = "  • " + "\n  • ".join(lines)

	# --- Description ---
	var desc = item.get("description")
	description_label.text = str(desc if desc != null else "")

	reset_size()
	visible = true
	_update_position()   # position immediately on first show

func _process(_delta: float) -> void:
	if visible:
		_update_position()

func _update_position() -> void:
	var global_mouse := get_viewport().get_mouse_position()
	var parent := get_parent() as Control
	if parent == null:
		return

	var parent_rect := parent.get_global_rect()
	var local := global_mouse - parent_rect.position + Vector2(24, 24)

	var max_x = max(parent.size.x - size.x, 0.0)
	var max_y = max(parent.size.y - size.y, 0.0)
	local.x = clamp(local.x, 0.0, max_x)
	local.y = clamp(local.y, 0.0, max_y)

	position = local
