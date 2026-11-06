class_name StatsPanel
extends VBoxContainer

## Mech stats for the Equipment window.
## Reads a build dictionary (part key -> part resource, the same shape as
## Mecha.build) and sums each stat across the parts, like Mecha.get_stat()
## but without the overweight speed penalty: this shows the design's own
## numbers, and the LOAD tile shows whether it is overweight.
##
## Pass a preview build (one part swapped) to show the comparison:
##   "84 > 102 +18" with hatching on the bar for a gain,
##   "310 > 265 -45" with a dashed ghost on the bar for a loss.
## TheJewishBitmap (the summary tiles) has no arrow glyphs, so the text is plain ASCII.
## No armour tiles: the component damage system has no one number for it.

## The stats worked out rather than summed (stat_value): the build's radar
## cross-section from straight ahead over RadarCrossSection.reference_rcs, to 2
## places (lower is better: 1.0 is the default mech), and the shield's
## strength, the average of the core's, the shoulders' and the generator's
## (Mecha.update_shield_strength, all projectors working).
const RCS_FRONT := "rcs_front"
const SHIELD_STRENGTH := "shield_strength_avg"
## Edit these lists to change what the panel shows. "lower_better" only
## changes the tooltip; the marks always follow the number.
const GROUPS := [
	{"title": "MOBILITY", "stats": [
		{"id": "max_speed", "label": "Walk speed"},
		{"id": "thrust_max_speed", "label": "Sprint speed"},
		{"id": "dash_strength", "label": "Dash force"},
		{"id": "dash_cooldown", "label": "Dash cooldown", "lower_better": true},
		{"id": "stability", "label": "Stability"},
	]},
	{"title": "THERMAL", "stats": [
		{"id": "heat_capacity", "label": "Heat capacity"},
		{"id": "heat_dispersion", "label": "Heat dissipation"},
		{"id": "idle_threshold", "label": "Idle threshold"},
		{"id": "move_heat", "label": "Move heat", "lower_better": true},
		{"id": "sprinting_heat", "label": "Sprint heat", "lower_better": true},
		{"id": "dash_heat", "label": "Dash heat", "lower_better": true},
	]},
	{"title": "SHIELD", "stats": [
		{"id": "shield_capacity", "label": "Shield capacity"},
		{"id": SHIELD_STRENGTH, "label": "Shield strength"},
		{"id": "shield_regen_rate", "label": "Shield regen /s"},
	]},
	{"title": "POWER", "stats": [
		{"id": "battery_capacity", "label": "Battery capacity kWh"},
		{"id": "power_output", "label": "Power output kW"},
		{"id": "weapon_power_rating", "label": "Weapon power rating"},
	]},
	{"title": "SENSORS", "stats": [
		{"id": "visual_range", "label": "Visual range m"},
		{"id": "illuminator_angle", "label": "Illuminator angle °"},
		{"id": "ir_sensitivity", "label": "IR sensitivity °C", "lower_better": true},
		{"id": "ir_identification", "label": "IR identification °C", "lower_better": true},
		{"id": "accuracy_modifier", "label": "Accuracy"},
		{"id": "lock_on_speed", "label": "Lock speed"},
		{"id": RCS_FRONT, "label": "RCS (front)", "lower_better": true},
		{"id": "ECM", "label": "ECM"},
		{"id": "sensor_reduction", "label": "Sensor reduction"},
	]},
]

var _rows: Dictionary = {}     # stat id -> {old, value, bar}
var _tiles: Dictionary = {}    # "load" -> {value, note}
var _compare_box: PanelContainer
var _compare_label: Label


func _ready() -> void:
	theme_type_variation = &"StatsColumn"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_compare_line()
	_build_summary()
	_build_groups()


# ---- public -------------------------------------------------------------

## build: the mech's parts now. cargo_weight: what the cargo weighs.
## preview: the build with one part swapped ({} = no comparison).
## header: e.g. "COMPARING CORE  VK-3 > KR-7".
## grades / preview_grades: slot -> part grade for each (Mecha.part_grades).
func show_stats(build: Dictionary, cargo_weight: float,
		preview: Dictionary = {}, header: String = "",
		grades: Dictionary = {}, preview_grades: Dictionary = {}) -> void:
	var comparing := not preview.is_empty()
	_compare_box.visible = comparing
	_compare_label.text = header

	# Summary tiles
	var load_now := sum_stat(build, "weight") + cargo_weight
	var cap_now := sum_stat(build, "weight_capacity", grades)
	var load_new := sum_stat(preview, "weight") + cargo_weight if comparing else load_now
	var cap_new := sum_stat(preview, "weight_capacity", preview_grades) if comparing else cap_now
	_set_tile("load", load_now, load_new, comparing, "OF %s CAPACITY" % _fmt(cap_new))
	if load_new > cap_new and cap_new > 0.0:
		_tiles["load"].note.text = "OVER %s CAPACITY" % _fmt(cap_new)

	# Stat rows
	for group in GROUPS:
		for stat in group.stats:
			var id: String = stat.id
			var cur := stat_value(build, id, grades)
			var new := stat_value(preview, id, preview_grades) if comparing else cur
			var top := maxf(maxf(_max_value(id), cur), maxf(new, 0.0001))
			var row: Dictionary = _rows[id]
			var changed := comparing and not is_equal_approx(cur, new)
			row.old.visible = changed
			row.old.text = "%s >" % _fmt(cur)
			row.value.text = _fmt(new) + ("  %s" % _signed(new - cur) if changed else "")
			row.value.theme_type_variation = &"LabelBodyBright" if changed else &"LabelBody"
			row.bar.ratio = cur / top
			row.bar.preview_ratio = new / top if changed else -1.0


## A stat row's value for a build: RCS_FRONT and SHIELD_STRENGTH worked out,
## any other summed (sum_stat).
static func stat_value(build: Dictionary, stat: String, grades: Dictionary = {}) -> float:
	if stat == RCS_FRONT:
		return snappedf(RadarCrossSection.of_build(build) / RadarCrossSection.reference_rcs(), 0.01)
	if stat == SHIELD_STRENGTH:
		return shield_strength_of(build)
	return sum_stat(build, stat, grades)


## The average shield_strength of the build's core, shoulders and generator
## (those fitted), to 2 places; 0 with no generator.
static func shield_strength_of(build: Dictionary) -> float:
	if not build.get("generator"):
		return 0.0
	var total := 0.0
	var count := 0
	for slot in ["core", "shoulders", "generator"]:
		var part = build.get(slot)
		if part and part.get("shield_strength") != null:
			total += float(part.shield_strength)
			count += 1
	return snappedf(total / count, 0.01) if count > 0 else 0.0


## Sum one stat across a build, the way Mecha.get_stat() does (minus the
## overweight penalty), parts scaled by their grade (slot -> grade; Grades).
## Non-numbers and empty slots count as 0.
static func sum_stat(build: Dictionary, stat: String, grades: Dictionary = {}) -> float:
	var total := 0.0
	for slot in build:
		var part = build[slot]
		if not part:
			continue
		var value = part.get(stat)
		if value is float or value is int:
			total += value * Grades.stat_mult(grades.get(slot), stat)
	if stat == "thrust_max_speed":
		total += sum_stat(build, "max_speed", grades)
	return total


# ---- building -----------------------------------------------------------

func _build_compare_line() -> void:
	_compare_box = PanelContainer.new()
	_compare_box.theme_type_variation = &"AlertNotice"
	_compare_label = Label.new()
	_compare_label.theme_type_variation = &"LabelMetaBright"
	_compare_label.uppercase = true
	_compare_box.add_child(_compare_label)
	_compare_box.visible = false
	add_child(_compare_box)


func _build_summary() -> void:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"StatsTiles"
	add_child(row)
	for key in ["load"]:
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"SummaryTile"
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		var title := Label.new()
		title.theme_type_variation = &"LabelMeta"
		title.text = {"load": "LOAD"}[key]
		var value := Label.new()
		value.theme_type_variation = &"LabelDisplay"
		var note := Label.new()
		note.theme_type_variation = &"LabelMeta"
		box.add_child(title)
		box.add_child(value)
		box.add_child(note)
		tile.add_child(box)
		row.add_child(tile)
		_tiles[key] = {"value": value, "note": note}


func _build_groups() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.theme_type_variation = &"StatsGrid"
	add_child(grid)
	for group in GROUPS:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.theme_type_variation = &"StatGroup"
		var heading := Label.new()
		heading.theme_type_variation = &"LabelMetaBright"
		heading.text = group.title
		box.add_child(heading)
		box.add_child(HSeparator.new())
		for stat in group.stats:
			box.add_child(_build_row(stat))
		grid.add_child(box)


func _build_row(stat: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.theme_type_variation = &"StatRow"
	if stat.get("lower_better", false):
		row.tooltip_text = "Lower is better"
	var line := HBoxContainer.new()
	var name_label := Label.new()
	name_label.theme_type_variation = &"LabelMeta"
	name_label.text = String(stat.label).to_upper()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var old_label := Label.new()
	old_label.theme_type_variation = &"LabelDim"
	old_label.visible = false
	var value_label := Label.new()
	value_label.theme_type_variation = &"LabelBody"
	line.add_child(name_label)
	line.add_child(old_label)
	line.add_child(value_label)
	var bar := StatBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	row.add_child(bar)
	_rows[stat.id] = {"old": old_label, "value": value_label, "bar": bar}
	return row


# ---- helpers ------------------------------------------------------------

func _set_tile(key: String, cur: float, new: float, comparing: bool, note: String) -> void:
	var tile: Dictionary = _tiles[key]
	var changed := comparing and not is_equal_approx(cur, new)
	tile.value.text = (_fmt(cur) + " > " + _fmt(new)) if changed else _fmt(cur)
	tile.note.text = note


func _max_value(stat: String) -> float:
	if stat == RCS_FRONT:
		return RadarCrossSection.MULT_MAX
	if stat == SHIELD_STRENGTH:
		return PartManager.get_max_stat_value("shield_strength") / 3.0
	if PartManager.has_method("get_max_stat_value"):
		var value = PartManager.get_max_stat_value(stat)
		if value is float or value is int:
			return float(value)
	return 0.0


static func _fmt(value: float) -> String:
	return MechUI.fmt(value)


static func _signed(delta: float) -> String:
	return ("+" if delta > 0.0 else "-") + _fmt(absf(delta))
