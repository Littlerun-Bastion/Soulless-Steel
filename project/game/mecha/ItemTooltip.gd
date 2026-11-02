extends Panel
class_name ItemTooltip

@onready var name_label: Label              = $MarginContainer/VBoxContainer/NameLabel
@onready var type_label: Label              = $MarginContainer/VBoxContainer/TypeLabel
@onready var stats_label: Label             = $MarginContainer/VBoxContainer/StatsLabel
@onready var description_label: Label        = $MarginContainer/VBoxContainer/DescriptionLabel

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
	var graded := stack.is_part()
	if graded:
		name_label.text = Grades.label(stack.grade, name_label.text)

	# --- Type / tags ---
	var tags_text := ""
	var tags_val = res.get("tags")
	if tags_val is Array and tags_val.size() > 0:
		tags_text = ", ".join(tags_val)
	else:
		# Optional: for part stacks, fall back to part_type if no tags
		if stack.kind == item_stack.ItemKind.PART and stack.item_type != "":
			tags_text = str(stack.item_type).to_upper()

	type_label.text = tags_text

	# --- Stats: weight, size, value ---
	var lines: Array[String] = []

	if graded:
		lines.append("Grade: %s" % _grade_text(stack.grade))
		var progress := PlayerProgress.blueprint_progress(stack.item_type, stack.item_id)
		if progress >= PlayerProgress.BLUEPRINT_COPIES:
			lines.append("Blueprint: known (FAB can build it)")
		elif progress > 0:
			lines.append("Blueprint: %d/%d recycled" % [progress, PlayerProgress.BLUEPRINT_COPIES])

	var weight_val = res.get("weight")
	if typeof(weight_val) == TYPE_FLOAT or typeof(weight_val) == TYPE_INT:
		lines.append("Weight: %s" % weight_val)

	var w := stack.width_cells()
	var h := stack.height_cells()
	lines.append("Size: %sx%s" % [w, h])

	# Parts without a price yet show none rather than "Value: 0".
	var price_val = res.get("price")
	if (typeof(price_val) == TYPE_FLOAT or typeof(price_val) == TYPE_INT) and price_val > 0:
		lines.append("Value: %d ct" % int(price_val * Grades.value_mult(stack.grade)))

	# Salvage: tech tier and what recycling it yields (per item).
	var tier_val = res.get("tech_tier")
	if typeof(tier_val) == TYPE_INT and tier_val != item_data.TechTier.NONE:
		lines.append("Tech: %s" % str(item_data.TechTier.keys()[tier_val]).capitalize())
	var composition_val = res.get("composition")
	if composition_val is Dictionary and not composition_val.is_empty():
		# A part's grade scales what it gives (one part per stack).
		var yields: Dictionary = PlayerProgress.recycle_value(stack) if graded else composition_val
		lines.append("Recycles into: %s" % (Materials.describe(yields) if not yields.is_empty() else "nothing"))

	if lines.is_empty():
		stats_label.text = ""
	else:
		stats_label.text = "  • " + "\n  • ".join(lines)

	# --- Description ---
	var desc_val = res.get("description")
	description_label.text = str(desc_val if desc_val != null else "")
	description_label.visible = description_label.text != ""
	type_label.visible = type_label.text != ""

	# The panel doesn't size itself to its content, so fit it to the margin
	# box (keeps the background behind the text and the clamp on screen).
	var content := $MarginContainer as Control
	content.reset_size()
	size = content.get_combined_minimum_size()
	content.size = size
	visible = true
	_update_position()   # position immediately on first show


# "Refined (+5% capacity, stability, accuracy, speed)": the stats grades
# scale (Grades.GRADED_STATS); just "Standard" for Standard.
static func _grade_text(grade: String) -> String:
	var mult: float = Grades.DATA[Grades.of(grade)].stats
	if is_equal_approx(mult, 1.0):
		return Grades.display_name(grade)
	return "%s (%+d%% capacity, stability, accuracy, speed)" % [Grades.display_name(grade), roundi((mult - 1.0) * 100.0)]


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
