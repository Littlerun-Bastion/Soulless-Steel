extends MechWindow
class_name MaterialsWindow

# The player's crafting materials (Hangar, MAT on the taskbar), grouped by
# tech tier. Hovering a material shows its description underneath. Counts
# follow PlayerProgress.materials_changed, so recycling updates it live.

const DIM := Color(1, 1, 1, 0.35)
const DETAIL_HINT := "Hover a material to read about it."

var _counts: Dictionary = {}  # material id -> count Label
var _rows: Dictionary = {}    # material id -> row

@onready var list: VBoxContainer = $Content/VBox/Scroll/List
@onready var detail_label: Label = $Content/VBox/DetailLabel


func _ready() -> void:
	super()
	_build()
	PlayerProgress.materials_changed.connect(_on_materials_changed)
	_on_materials_changed(PlayerProgress.get_materials())


func get_count_text(material_id: String) -> String:
	return _counts[material_id].text if _counts.has(material_id) else ""


func _build() -> void:
	for tier in Materials.TIERS:
		var header := Label.new()
		header.text = "%s TECH" % Materials.tier_name(tier).to_upper()
		header.modulate = Color(1, 1, 1, 0.6)
		list.add_child(header)
		for material in Materials.of_tier(tier):
			list.add_child(_make_row(material))
	detail_label.text = DETAIL_HINT


func _make_row(material: MaterialData) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(_show_detail.bind(material))
	row.mouse_exited.connect(_show_detail.bind(null))
	var name_label := Label.new()
	name_label.text = "  " + material.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var count := Label.new()
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	_counts[material.id] = count
	_rows[material.id] = row
	return row


func _on_materials_changed(materials: Dictionary) -> void:
	for material_id in _counts:
		var amount := int(materials.get(material_id, 0))
		_counts[material_id].text = str(amount)
		_rows[material_id].modulate = Color.WHITE if amount > 0 else DIM


func _show_detail(material: MaterialData) -> void:
	if material == null:
		detail_label.text = DETAIL_HINT
	else:
		detail_label.text = "%s  (%s tech)\n%s" % [material.display_name.to_upper(),
				Materials.tier_name(material.tech_tier), material.description]
