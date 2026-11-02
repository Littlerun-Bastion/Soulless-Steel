extends MechWindow
class_name FabricatorWindow

## FAB: builds parts from blueprints (Fabricator). Hangar only.
## Blueprints on the left: known ones first, then the ones still being learned
## ("BLUEPRINT 2/3"). The selected one on the right: what it costs (materials
## had / needed, credits), what comes out, and BUILD, which puts the part in
## the stash. Recycling parts in the Hangar teaches their blueprints.

var build_button: Button
var block_label: Label

var _selected: Array = []  # [part_type, part_id], or [] for none
var _group := ButtonGroup.new()
var _list: VBoxContainer
var _empty: Label
var _title: Label
var _meta: Label
var _cost_box: VBoxContainer
var _output: Label
var _block_box: PanelContainer
var _refresh_queued := false


func _ready() -> void:
	super()
	_build()
	PlayerProgress.blueprints_changed.connect(_queue_refresh)
	PlayerProgress.facilities_changed.connect(_queue_refresh)
	PlayerProgress.materials_changed.connect(_queue_refresh.unbind(1))
	PlayerProgress.money_changed.connect(_queue_refresh.unbind(1))
	refresh()


static func empty_note() -> String:
	return "No blueprints yet. Recycle %d copies of a part, or one Refined or Prototype copy, to learn how to build it." \
			% PlayerProgress.BLUEPRINT_COPIES


## Redraws the list and the selected blueprint.
func refresh() -> void:
	_refresh_queued = false
	var entries := _sorted_blueprints()
	if not _selected.is_empty() and not entries.any(func(e): return e == _selected):
		_selected = []
	if _selected.is_empty() and not entries.is_empty():
		_selected = entries[0]
	MechUI.clear(_list)
	_empty.visible = entries.is_empty()
	for entry in entries:
		_list.add_child(_make_row(entry))
	_fill_detail()


func select(part_type: String, part_id: String) -> void:
	_selected = [part_type, part_id]
	refresh()


func get_selected() -> Array:
	return _selected


## Each row's text, "NAME | META" (tests).
func get_rows() -> Array:
	var rows := []
	for row in _list.get_children():
		if row.is_queued_for_deletion():
			continue
		var labels: Array = row.find_children("*", "Label", true, false)
		rows.append(" | ".join(labels.map(func(l): return l.text)))
	return rows


## Every text on the detail side (tests).
func get_detail_text() -> String:
	var lines := [_title.text, _meta.text, _output.text]
	for label in _cost_box.find_children("*", "Label", true, false):
		if not label.is_queued_for_deletion():
			lines.append(label.text)
	return "\n".join(lines)


# ---- building -----------------------------------------------------------

func _build() -> void:
	var columns := MechUI.hbox(&"PaneRow")
	content.add_child(columns)

	var blueprints := MechUI.pane(&"PaneDivider")
	blueprints.custom_minimum_size.x = 380
	columns.add_child(blueprints)
	var left := MechUI.vbox(&"PaneStack")
	blueprints.add_child(left)
	left.add_child(MechUI.pane(&"PaneHeader", MechUI.label(&"LabelMeta", "BLUEPRINTS")))
	var area := MechUI.scroll_box(&"TightStack")
	left.add_child(area[0])
	var back := MechUI.pane(&"ListBack")
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_list = MechUI.vbox(&"ListRows")
	back.add_child(_list)
	area[1].add_child(back)
	_empty = MechUI.label(&"LabelMeta", empty_note(), true)
	area[1].add_child(_empty)

	var detail := MechUI.vbox(&"PaneStack")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(detail)
	var info_area := MechUI.scroll_box(&"StatsColumn")
	detail.add_child(info_area[0])
	var sections: VBoxContainer = info_area[1]
	_title = MechUI.label(&"LabelBodyBright")
	_meta = MechUI.label(&"LabelMeta")
	var heading := MechUI.vbox(&"TightStack")
	heading.add_child(_title)
	heading.add_child(_meta)
	sections.add_child(heading)
	_cost_box = MechUI.vbox(&"TightStack")
	sections.add_child(_section("COST", _cost_box))
	_output = MechUI.label(&"LabelBody", "", true)
	sections.add_child(_section("OUTPUT", _output))

	var footer := MechUI.vbox(&"ContractStack")
	block_label = MechUI.label(&"AlertCriticalText")
	_block_box = MechUI.pane(&"AlertCritical", block_label)
	build_button = MechUI.button("BUILD", &"ButtonPrimary")
	build_button.custom_minimum_size.y = 40
	build_button.pressed.connect(_on_build_pressed)
	footer.add_child(_block_box)
	footer.add_child(build_button)
	detail.add_child(MechUI.pane(&"PaneFooter", footer))


func _section(title: String, body: Control) -> VBoxContainer:
	var group := MechUI.vbox(&"StatGroup")
	group.add_child(MechUI.label(&"LabelMetaBright", title))
	group.add_child(HSeparator.new())
	group.add_child(body)
	return group


func _make_row(entry: Array) -> Button:
	var known := PlayerProgress.knows_blueprint(entry[0], entry[1])
	var row := Button.new()
	row.theme_type_variation = &"ContactRow"
	row.toggle_mode = true
	row.button_group = _group
	row.button_pressed = entry == _selected
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = 56
	row.pressed.connect(select.bind(entry[0], entry[1]))
	var text := MechUI.vbox()
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 12
	text.offset_right = -12
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_child(MechUI.label(&"LabelBodyBright" if known else &"LabelDim", _part_name(entry)))
	text.add_child(MechUI.label(&"LabelMeta", _row_meta(entry)))
	row.add_child(text)
	MechUI.ignore_mouse(text)
	return row


# ---- behaviour ----------------------------------------------------------

func _fill_detail() -> void:
	MechUI.clear(_cost_box)
	if _selected.is_empty():
		_title.text = "NO BLUEPRINT SELECTED"
		_meta.text = ""
		_output.text = ""
		block_label.text = "! NO BLUEPRINT"
		_block_box.visible = true
		build_button.disabled = true
		return
	var part_type: String = _selected[0]
	var part_id: String = _selected[1]
	_title.text = _part_name(_selected).to_upper()
	_meta.text = _row_meta(_selected)
	var cost := Fabricator.material_cost(part_type, part_id)
	for material_id in Materials.ids():
		if not cost.has(material_id):
			continue
		var have := PlayerProgress.get_material_count(material_id)
		_cost_box.add_child(_cost_row(Materials.display_name(material_id).to_upper(),
				"%d / %d" % [have, cost[material_id]], have >= cost[material_id]))
	var credits := Fabricator.credit_cost(part_type, part_id)
	_cost_box.add_child(_cost_row("CREDITS", "%d / %d CT" % [int(PlayerProgress.get_money()), credits],
			PlayerProgress.can_afford(credits)))
	_output.text = "Into the stash. Fabricator %s: %s." % [Facilities.level_name(Fabricator.level()),
			Facilities.describe(Facilities.FABRICATOR, Fabricator.level())]
	var reason := Fabricator.block_reason(part_type, part_id)
	block_label.text = "! " + reason if reason != "" else ""
	_block_box.visible = reason != ""
	build_button.disabled = reason != ""


func _cost_row(title: String, value: String, enough: bool) -> HBoxContainer:
	var row := MechUI.hbox()
	row.add_child(MechUI.label(&"LabelMeta", title))
	row.add_child(MechUI.spacer())
	row.add_child(MechUI.label(&"LabelBody" if enough else &"Badge", value))
	return row


func _on_build_pressed() -> void:
	if _selected.is_empty():
		return
	var stack := Fabricator.build(_selected[0], _selected[1])
	if stack == null:
		AudioManager.play_sfx("back")
		refresh()
		return
	AudioManager.play_sfx("confirm")
	MechLog.write("FAB", "Built %s" % Grades.label(stack.grade, _part_name(_selected)), MechLog.Kind.LOOT)
	MechOS.refresh_inventory_windows()
	refresh()


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


# Known first, then by how far along, then by name.
func _sorted_blueprints() -> Array:
	var entries: Array = PlayerProgress.get_blueprints().map(func(e): return [str(e[0]), str(e[1])])
	entries = entries.filter(func(e): return Fabricator.get_part(e[0], e[1]) != null)
	entries.sort_custom(func(a, b):
		var pa := PlayerProgress.blueprint_progress(a[0], a[1])
		var pb := PlayerProgress.blueprint_progress(b[0], b[1])
		if pa != pb:
			return pa > pb
		return _part_name(a) < _part_name(b))
	return entries


func _part_name(entry: Array) -> String:
	var part := Fabricator.get_part(entry[0], entry[1])
	var part_name = part.get("part_name") if part != null else null
	return str(part_name) if part_name else str(entry[1])


# "CORE · HIGH TECH · KNOWN" or "... · BLUEPRINT 2/3".
func _row_meta(entry: Array) -> String:
	var part := Fabricator.get_part(entry[0], entry[1])
	var tier = part.get("tech_tier") if part != null else null
	var bits := [str(entry[0]).replace("_", " ").to_upper()]
	if tier is int and tier != item_data.TechTier.NONE:
		bits.append("%s TECH" % Materials.tier_name(tier).to_upper())
	var progress := PlayerProgress.blueprint_progress(entry[0], entry[1])
	bits.append("KNOWN" if progress >= PlayerProgress.BLUEPRINT_COPIES
			else "BLUEPRINT %d/%d" % [progress, PlayerProgress.BLUEPRINT_COPIES])
	return " · ".join(bits)
