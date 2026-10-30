extends MechWindow
class_name MaterialsWindow

## MAT: the player's crafting materials (Hangar only), grouped by tech tier
## with a total per tier. Zero counts are dim; a material nothing in the game
## recycles into reads NO KNOWN SOURCE. Hovering a row shows its description
## and what to recycle for it. Counts follow PlayerProgress.materials_changed,
## so recycling updates the window live.

const DETAIL_HINT := "Hover a material to read about it."
const SALVAGE_DIR := "res://database/items/salvage/"
const WEAPON_TYPES := ["arm_weapon", "shoulder_weapon"]

var _counts: Dictionary = {}       # material id -> count Label
var _names: Dictionary = {}        # material id -> name Label
var _totals: Dictionary = {}       # tier -> total Label
var _detail_title: Label
var detail_label: Label            # the description (HangarTest reads it)
var _detail_sources: Label

# material id -> ["Armor Plate Fragment", ...]; built once per session.
static var _sources_cache: Dictionary = {}


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	_build()
	PlayerProgress.materials_changed.connect(_on_materials_changed)
	_on_materials_changed(PlayerProgress.get_materials())


func get_count_text(material_id: String) -> String:
	return _counts[material_id].text if _counts.has(material_id) else ""


## Display names of what recycles into this material (salvage and weapons).
static func get_sources(material_id: String) -> Array:
	if _sources_cache.is_empty():
		_build_sources()
	return _sources_cache.get(material_id, [])


# ---- building -----------------------------------------------------------

func _build() -> void:
	var column := MechUI.vbox(&"PaneStack")
	content.add_child(column)

	var area := MechUI.scroll_box(&"StatsColumn")
	column.add_child(area[0])
	var groups: VBoxContainer = area[1]
	for tier in Materials.TIERS:
		groups.add_child(_make_group(tier))

	var detail := MechUI.vbox(&"TightStack")
	_detail_title = MechUI.label(&"LabelMeta")
	detail_label = MechUI.label(&"LabelBody", "", true)
	_detail_sources = MechUI.label(&"LabelMeta", "", true)
	detail.add_child(_detail_title)
	detail.add_child(detail_label)
	detail.add_child(_detail_sources)
	var footer := MechUI.pane(&"PaneFooter", detail)
	footer.custom_minimum_size.y = 150
	column.add_child(footer)
	_show_detail(null)


func _make_group(tier) -> VBoxContainer:
	var group := MechUI.vbox(&"StatGroup")
	var heading := MechUI.hbox()
	heading.add_child(MechUI.label(&"LabelMetaBright", "%s TECH" % Materials.tier_name(tier).to_upper()))
	heading.add_child(MechUI.spacer())
	var total := MechUI.label(&"LabelMetaBright")
	heading.add_child(total)
	_totals[tier] = total
	group.add_child(heading)
	group.add_child(HSeparator.new())
	for material in Materials.of_tier(tier):
		group.add_child(_make_row(material))
	return group


func _make_row(material: MaterialData) -> Control:
	var row := MechUI.hbox()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(_show_detail.bind(material))
	row.mouse_exited.connect(_show_detail.bind(null))
	var name_label := MechUI.label(&"LabelBody", material.display_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := MechUI.label(&"LabelBody")
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	row.add_child(count)
	_names[material.id] = name_label
	_counts[material.id] = count
	return row


# ---- behaviour ----------------------------------------------------------

func _on_materials_changed(materials: Dictionary) -> void:
	for tier in Materials.TIERS:
		var total := 0
		for material in Materials.of_tier(tier):
			var amount := int(materials.get(material.id, 0))
			total += amount
			var count: Label = _counts[material.id]
			var has_any := amount > 0
			# No count to show and nothing gives it: say so instead of "0".
			var no_source := not has_any and get_sources(material.id).is_empty()
			count.text = "NO KNOWN SOURCE" if no_source else str(amount)
			count.theme_type_variation = &"LabelMeta" if no_source else (&"LabelBody" if has_any else &"LabelDim")
			_names[material.id].theme_type_variation = &"LabelBody" if has_any else &"LabelDim"
		_totals[tier].text = str(total)


func _show_detail(material: MaterialData) -> void:
	if material == null:
		_detail_title.text = "DETAIL"
		detail_label.text = DETAIL_HINT
		_detail_sources.text = ""
		return
	_detail_title.text = "%s · %s TECH" % [material.display_name.to_upper(),
			Materials.tier_name(material.tech_tier).to_upper()]
	detail_label.text = material.description
	var sources := get_sources(material.id)
	_detail_sources.text = "SOURCES: " + (", ".join(sources) if not sources.is_empty() else "none known")


# Every salvage item (database/items/salvage) and weapon with a composition.
static func _build_sources() -> void:
	_sources_cache = {"_built": []}
	var dir := DirAccess.open(SALVAGE_DIR)
	if dir != null:
		for file in dir.get_files():
			file = file.trim_suffix(".remap")  # exported builds
			if not file.ends_with(".tres"):
				continue
			var item = load(SALVAGE_DIR + file)
			if item != null:
				_add_sources(item, str(item.get("display_name")))
	for part_type in WEAPON_TYPES:
		for part_id in PartManager.get_parts(part_type):
			var part = PartManager.get_part(part_type, part_id)
			if part != null:
				var part_name = part.get("part_name")
				_add_sources(part, str(part_name) if part_name else str(part_id))


static func _add_sources(source: Object, display_name: String) -> void:
	var composition = source.get("composition")
	if not composition is Dictionary:
		return
	for material_id in composition:
		if not _sources_cache.has(material_id):
			_sources_cache[material_id] = []
		if not display_name in _sources_cache[material_id]:
			_sources_cache[material_id].append(display_name)
