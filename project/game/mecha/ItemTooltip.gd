extends Panel
class_name ItemTooltip

@onready var name_label: Label              = $MarginContainer/VBoxContainer/NameLabel
@onready var type_label: Label              = $MarginContainer/VBoxContainer/TypeLabel
@onready var stats_label: Label             = $MarginContainer/VBoxContainer/StatsLabel
@onready var description_label: RichTextLabel = $MarginContainer/VBoxContainer/DescriptionLabel

func _ready() -> void:
	visible = false
	z_index = 999
	set_process(true)


func show_item(stack: item_stack) -> void:
	if stack == null:
		hide()
		return

	# --- Resolve the underlying resource (works for both items *and* parts) ---
	var res = null

	if stack.has_method("get_resource"):
		res = stack.get_resource()   # e.g. item_data.tres or part scene/resource
	if res == null:
		# Fallback for old generic items that still live in stack.item
		res = stack.item

	if res == null:
		hide()
		return

	# From here on we only talk to `res`, regardless of whether it's an item_data
	# or a part scene/resource.

	# --- Name (robust) ---
	var name_val = res.get("item_name")
	if name_val == null or str(name_val) == "":
		name_val = res.get("part_name")
	if name_val == null or str(name_val) == "":
		name_val = res.get("display_name")
	if name_val == null or str(name_val) == "":
		name_val = res.get("name")

	name_label.text = str(name_val if name_val != null else "UNKNOWN ITEM")

	# --- Type / tags ---
	var tags_text := ""
	var tags_val = res.get("tags")
	if tags_val is Array and tags_val.size() > 0:
		tags_text = ", ".join(tags_val)
	else:
		# Optional: for part stacks, fall back to part_type if no tags
		if stack.kind == item_stack.ItemKind.PART and stack.part_type != "":
			tags_text = str(stack.part_type).to_upper()

	type_label.text = tags_text

	# --- Stats: weight, size, value ---
	var lines: Array[String] = []

	var weight_val = res.get("weight")
	if typeof(weight_val) == TYPE_FLOAT or typeof(weight_val) == TYPE_INT:
		lines.append("Weight: %s" % weight_val)

	var w := stack.width_cells()
	var h := stack.height_cells()
	lines.append("Size: %sx%s" % [w, h])

	var price_val = res.get("price")
	if typeof(price_val) == TYPE_FLOAT or typeof(price_val) == TYPE_INT:
		lines.append("Value: %s" % price_val)

	if lines.is_empty():
		stats_label.text = ""
	else:
		stats_label.text = "  • " + "\n  • ".join(lines)

	# --- Description ---
	var desc_val = res.get("description")
	description_label.text = str(desc_val if desc_val != null else "")

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
