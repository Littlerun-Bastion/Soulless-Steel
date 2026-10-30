extends MechWindow
class_name DeploymentsWindow

## DEP: pick a site and deploy.
## Sites on the left (only Helwan has signal), the survey in the middle,
## the brief on the right: active contract, loadout check and DEPLOY.
## DEPLOY does what the main menu's Expedition button does, and is
## disabled while a required part is missing or a run is already under way.
##
## The survey grid waits for the chunk map: until a site has survey data,
## the middle column says so.

const SITES := [
	{"name": "HELWAN", "note": "Impact basin", "scene": "res://game/expedition/Expedition.tscn"},
	{"name": "[SITE 2]", "note": ""},
	{"name": "[SITE 3]", "note": ""},
]
const STAKES := "The mecha and its cargo are lost if it goes down. Extract to keep them."

var _site: Dictionary = SITES[0]
var _site_group := ButtonGroup.new()
var _survey_title: Label
var _contract_box: VBoxContainer
var _parts_value: Label
var _weight_value: Label
var _cargo_value: Label
var _blocked_box: PanelContainer
var _blocked_label: Label
var deploy_button: Button


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	_build()
	PlayerProgress.mecha_changed.connect(_refresh.unbind(1))
	MissionManager.mission_started.connect(_refresh.unbind(1))
	_refresh()


## Why DEPLOY is off ("" when it's on).
func get_block_reason() -> String:
	if PlayerProgress.is_in_expedition():
		return "! EXPEDITION ALREADY UNDER WAY"
	var missing := PlayerProgress.missing_parts(PlayerProgress.get_current_mecha())
	if not missing.is_empty():
		return "! NO %s EQUIPPED" % PlayerProgress.describe_missing_parts(missing)
	return ""


# ---- building -----------------------------------------------------------

func _build() -> void:
	var columns := MechUI.hbox(&"PaneRow")
	content.add_child(columns)

	# Sites
	var sites := MechUI.pane(&"PaneDivider")
	sites.custom_minimum_size.x = 280
	columns.add_child(sites)
	var left := MechUI.vbox(&"PaneStack")
	sites.add_child(left)
	left.add_child(MechUI.pane(&"PaneHeader", MechUI.label(&"LabelMeta", "SITES")))
	var back := MechUI.pane(&"ListBack")
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var rows := MechUI.vbox(&"ListRows")
	back.add_child(rows)
	left.add_child(back)
	for site in SITES:
		rows.add_child(_make_site_row(site))

	# Survey
	var survey := MechUI.pane(&"PaneDivider")
	survey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(survey)
	var middle := MechUI.vbox(&"PaneStack")
	survey.add_child(middle)
	_survey_title = MechUI.label(&"LabelMeta")
	middle.add_child(MechUI.pane(&"PaneHeader", _survey_title))
	var survey_area := MarginContainer.new()
	survey_area.theme_type_variation = &"PaneMargin"
	survey_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var no_data := MechUI.pane(&"NoticeDashed", MechUI.label(&"LabelMeta", "NO SURVEY DATA"))
	no_data.size_flags_vertical = Control.SIZE_EXPAND_FILL
	no_data.get_child(0).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_data.get_child(0).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	survey_area.add_child(no_data)
	middle.add_child(survey_area)

	# Brief
	var brief := MechUI.vbox(&"PaneStack")
	brief.custom_minimum_size.x = 380
	columns.add_child(brief)
	var area := MechUI.scroll_box(&"StatsColumn")
	brief.add_child(area[0])
	var sections: VBoxContainer = area[1]

	_contract_box = MechUI.vbox(&"TightStack")
	sections.add_child(_section("CONTRACT", [_contract_box]))

	_parts_value = MechUI.label(&"LabelBody")
	_weight_value = MechUI.label(&"LabelBody")
	_cargo_value = MechUI.label(&"LabelBody")
	sections.add_child(_section("LOADOUT CHECK", [
		_value_row("REQUIRED PARTS", _parts_value),
		_value_row("WEIGHT", _weight_value),
		_value_row("CARGO CARRIED IN", _cargo_value),
		MechUI.label(&"LabelMeta", STAKES, true),
	]))

	var footer := MechUI.vbox(&"ContractStack")
	_blocked_label = MechUI.label(&"AlertCriticalText")
	_blocked_box = MechUI.pane(&"AlertCritical", _blocked_label)
	deploy_button = MechUI.button("DEPLOY", &"ButtonPrimary")
	deploy_button.custom_minimum_size.y = 40
	deploy_button.pressed.connect(_on_deploy_pressed)
	footer.add_child(_blocked_box)
	footer.add_child(deploy_button)
	brief.add_child(MechUI.pane(&"PaneFooter", footer))


func _make_site_row(site: Dictionary) -> Button:
	var has_signal := site.has("scene")
	var row := Button.new()
	row.theme_type_variation = &"ContactRow"
	row.toggle_mode = true
	row.button_group = _site_group
	row.button_pressed = site == _site
	row.disabled = not has_signal
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = 64
	row.pressed.connect(_select_site.bind(site))
	var text := MechUI.vbox()
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 12
	text.offset_right = -12
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_child(MechUI.label(&"LabelBodyBright" if has_signal else &"LabelDim", site.name))
	text.add_child(MechUI.label(&"LabelMeta", site.note.to_upper() if has_signal else "NO SIGNAL"))
	row.add_child(text)
	MechUI.ignore_mouse(text)
	return row


func _section(title: String, rows: Array) -> VBoxContainer:
	var group := MechUI.vbox(&"StatGroup")
	group.add_child(MechUI.label(&"LabelMetaBright", title))
	group.add_child(HSeparator.new())
	for row in rows:
		group.add_child(row)
	return group


func _value_row(title: String, value: Label) -> HBoxContainer:
	var row := MechUI.hbox()
	row.add_child(MechUI.label(&"LabelMeta", title))
	row.add_child(MechUI.spacer())
	row.add_child(value)
	return row


# ---- behaviour ----------------------------------------------------------

func _refresh() -> void:
	_survey_title.text = "SURVEY GRID — %s" % _site.name

	MechUI.clear(_contract_box)
	if MissionManager.has_active_contract():
		var mission = MissionManager.current_mission
		_contract_box.add_child(MechUI.label(&"LabelBodyBright", mission.mission_name, true))
		for obj in mission.objectives:
			_contract_box.add_child(MechUI.label(&"LabelBody", "[ ] " + obj.description, true))
	else:
		_contract_box.add_child(MechUI.label(&"LabelBody", "None"))
		_contract_box.add_child(MechUI.label(&"LabelMeta", "The site's own mission applies.", true))

	var design := PlayerProgress.get_current_mecha()
	var required: int = PlayerProgress.REQUIRED_SLOTS.size()
	var missing := PlayerProgress.missing_parts(design)
	_parts_value.text = "%d / %d" % [required - missing.size(), required]
	_parts_value.theme_type_variation = &"LabelBody" if missing.is_empty() else &"LabelBodyBright"

	var build := _build_from_design(design)
	var cargo: Inventory = PlayerProgress.get_mech_inventory()
	var cargo_weight := cargo.get_current_weight() if cargo != null else 0.0
	var load_now := StatsPanel.sum_stat(build, "weight") + cargo_weight
	var capacity := StatsPanel.sum_stat(build, "weight_capacity")
	_weight_value.text = "%s / %s" % [StatsPanel._fmt(load_now), StatsPanel._fmt(capacity)]
	_weight_value.theme_type_variation = &"LabelBodyBright" if load_now > capacity else &"LabelBody"
	var items := cargo.get_stacks().size() if cargo != null else 0
	_cargo_value.text = "%d ITEM%s" % [items, "" if items == 1 else "S"]

	var reason := get_block_reason()
	_blocked_label.text = reason
	_blocked_box.visible = reason != ""
	deploy_button.disabled = reason != "" or not _site.has("scene")


# Design (slot -> part id) to build (slot -> part), the shape StatsPanel reads.
func _build_from_design(design: Dictionary) -> Dictionary:
	var build := {}
	for slot in design:
		var part_id = design[slot]
		if not part_id:
			continue
		var part_type: String = slot.trim_suffix("_left").trim_suffix("_right")
		var part = PartManager.get_part(part_type, part_id)
		if part != null:
			build[slot] = part
	return build


func _select_site(site: Dictionary) -> void:
	_site = site
	_refresh()


func _on_deploy_pressed() -> void:
	if get_block_reason() != "" or not _site.has("scene"):
		return
	MechLog.write("DEP", "Deploying to %s" % _site.name.capitalize())
	AudioManager.play_sfx("confirm")
	AudioManager.stop_bgm()
	MechOS.close_all()
	TransitionManager.transition_to(_site.scene, "Launching Expedition...")
