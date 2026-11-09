class_name PartCompare
extends VBoxContainer

## Two parts of one type side by side, for the Compare window and the
## amazing.com product page. A part here is {"part_type", "part_id", "grade"}.
##
## A header "<SUBJECT> > <CANDIDATE>", then one row per stat in
## FIELDS[part_type], in StatsPanel's style: "84 > 102  +18", hatching on the
## bar for a gain and a dashed ghost for a loss (StatBar). The marks follow
## the number; "lower_better" only adds a tooltip. Numbers are scaled by each
## part's grade, as StatsPanel.sum_stat does. Fields with "kind" "flag"
## (yes/no) or "text" show both values as text, with no bar. Fields with
## "source" "projectile" are read off the weapon's projectile scene
## (weapon.get_projectile_stat). A value a part doesn't have shows as "-".

const EMPTY_TEXT := "Pick a part to compare."
const NONE := "-"

const ARMOUR := [
	{"id": "front_armor", "label": "Front armour"},
	{"id": "side_armor", "label": "Side armour"},
	{"id": "rear_armor", "label": "Rear armour"},
]
const COMMON := [
	{"id": "weight", "label": "Weight", "lower_better": true},
	{"id": "price", "label": "Price CT", "lower_better": true},
]
const WEAPON_FIELDS := [
	{"id": "base_damage", "label": "Damage", "source": "projectile"},
	{"id": "armor_pen", "label": "Armour penetration", "source": "projectile"},
	{"id": "number_projectiles", "label": "Projectiles per shot"},
	{"id": "fire_rate", "label": "Fire interval s", "lower_better": true},
	{"id": "burst_size", "label": "Burst size"},
	{"id": "clip_size", "label": "Clip size"},
	{"id": "max_ammo", "label": "Max ammo"},
	{"id": "reload_speed", "label": "Reload time s", "lower_better": true},
	{"id": "muzzle_heat", "label": "Muzzle heat", "lower_better": true},
	{"id": "max_bloom_angle", "label": "Max bloom °", "lower_better": true},
	{"id": "min_power_rating", "label": "Minimum power rating", "lower_better": true},
	{"id": "requires_lock", "label": "Needs a lock", "kind": "flag"},
	{"id": "uses_battery", "label": "Uses the battery", "kind": "flag"},
	{"id": "is_indirect_fire", "label": "Indirect fire", "kind": "flag"},
]
## Edit these lists to change what the comparison shows.
const FIELDS := {
	"head": [
		{"id": "visual_range", "label": "Visual range m"},
		{"id": "illuminator_angle", "label": "Illuminator angle °"},
		{"id": "ir_sensitivity", "label": "IR sensitivity °C", "lower_better": true},
		{"id": "ir_identification", "label": "IR identification °C", "lower_better": true},
		{"id": "accuracy_modifier", "label": "Accuracy"},
		{"id": "rotation_acc", "label": "Turn rate"},
		{"id": "rotation_range", "label": "Turn range °"},
	] + ARMOUR + [{"id": "rcs_factor", "label": "RCS factor", "lower_better": true}] + COMMON,
	"core": [
		{"id": "shield_strength", "label": "Shield strength"},
		{"id": "stability", "label": "Stability"},
		{"id": "cargo_space", "label": "Cargo space", "kind": "text"},
		{"id": "coolant_volume", "label": "Coolant volume L"},
		{"id": "rotation_range", "label": "Turn range °"},
	] + ARMOUR + [{"id": "rcs_factor", "label": "RCS factor", "lower_better": true}] + COMMON,
	"shoulders": [
		{"id": "shield_strength", "label": "Shield strength"},
		{"id": "stability", "label": "Stability"},
		{"id": "arms_accuracy_modifier", "label": "Arm accuracy"},
		{"id": "melee_modifier", "label": "Melee"},
		{"id": "rotation_acc", "label": "Turn rate"},
		{"id": "rotation_range", "label": "Turn range °"},
	] + ARMOUR + [{"id": "rcs_factor", "label": "RCS factor", "lower_better": true}] + COMMON,
	"chassis": [
		{"id": "max_speed", "label": "Walk speed"},
		{"id": "move_acc", "label": "Acceleration"},
		{"id": "weight_capacity", "label": "Weight capacity"},
		{"id": "stability", "label": "Stability"},
		{"id": "rotation_acc", "label": "Turn rate"},
		{"id": "move_heat", "label": "Move heat", "lower_better": true},
		{"id": "is_legs", "label": "Legs", "kind": "flag"},
	] + ARMOUR + [{"id": "rcs_factor", "label": "RCS factor", "lower_better": true}] + COMMON,
	"generator": [
		{"id": "power_output", "label": "Power output kW"},
		{"id": "weapon_power_rating", "label": "Weapon power rating"},
		{"id": "battery_capacity", "label": "Battery capacity kWh"},
		{"id": "shield_capacity", "label": "Shield capacity"},
		{"id": "shield_strength", "label": "Shield strength"},
		{"id": "shield_regen_rate", "label": "Shield regen /s"},
		{"id": "shield_break_cooldown", "label": "Shield break cooldown s", "lower_better": true},
		{"id": "shield_project_heat", "label": "Shield heat", "lower_better": true},
		{"id": "cooling_power", "label": "Cooling power"},
		{"id": "ventilation_ratio", "label": "Ventilation ratio"},
		{"id": "external_thermal_capacity", "label": "External heat capacity"},
	] + COMMON,
	"chipset": [
		{"id": "can_lock", "label": "Can lock on", "kind": "flag"},
		{"id": "lock_on_speed", "label": "Lock speed"},
		{"id": "lock_on_strength", "label": "Lock strength"},
		{"id": "lock_on_duration", "label": "Lock duration s"},
		{"id": "accuracy_modifier", "label": "Accuracy"},
		{"id": "loot_search_time", "label": "Loot search time s", "lower_better": true},
	] + COMMON,
	"thruster": [
		{"id": "thrust_max_speed", "label": "Sprint speed"},
		{"id": "thrust_speed_multiplier", "label": "Sprint multiplier"},
		{"id": "dash_strength", "label": "Dash force"},
		{"id": "dash_cooldown", "label": "Dash cooldown", "lower_better": true},
		{"id": "dash_heat", "label": "Dash heat", "lower_better": true},
		{"id": "sprinting_heat", "label": "Sprint heat", "lower_better": true},
	] + COMMON,
	"internal": [
		{"id": "function", "label": "Function", "kind": "text"},
		{"id": "charges", "label": "Charges"},
		{"id": "use_cooldown", "label": "Cooldown s", "lower_better": true},
		{"id": "throw_range", "label": "Throw range"},
		{"id": "sensor_range", "label": "Sensor range"},
		{"id": "update_interval", "label": "Update interval s", "lower_better": true},
		{"id": "device_hp", "label": "Device health"},
		{"id": "device_lifetime", "label": "Device lifetime s"},
		{"id": "ECM", "label": "ECM"},
		{"id": "sensor_reduction", "label": "Sensor reduction"},
	] + COMMON,
	"arm_weapon": WEAPON_FIELDS + COMMON,
	"shoulder_weapon": WEAPON_FIELDS + COMMON,
}

# "part_type:field" -> the highest value any part of that type has (bar scale).
static var _type_max: Dictionary = {}

var _header: Label
var _empty: Label
var _rows_box: VBoxContainer
var _rows: Dictionary = {}  # field id -> {"old": Label, "value": Label, "bar": StatBar}
var _subject: Dictionary = {}
var _candidate: Dictionary = {}


func _init() -> void:
	theme_type_variation = &"StatGroup"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_box := MechUI.pane(&"AlertNotice")
	_header = MechUI.label(&"LabelMetaBright", "", true)
	_header.uppercase = true
	header_box.add_child(_header)
	add_child(header_box)
	_empty = MechUI.label(&"LabelMeta", EMPTY_TEXT, true)
	add_child(_empty)
	_rows_box = MechUI.vbox(&"StatGroup")
	add_child(_rows_box)
	show_compare({}, {})


## Shows subject against candidate; an empty candidate shows EMPTY_TEXT.
func show_compare(subject: Dictionary, candidate: Dictionary = {}) -> void:
	_subject = subject
	_candidate = candidate
	MechUI.clear(_rows_box)
	_rows.clear()
	var ready_to_compare := not subject.is_empty() and not candidate.is_empty()
	_header.get_parent().visible = ready_to_compare
	_empty.visible = not ready_to_compare
	_rows_box.visible = ready_to_compare
	if not ready_to_compare:
		return
	_header.text = "%s > %s" % [display_name(subject), display_name(candidate)]
	var part_type := str(subject.get("part_type", ""))
	for field in FIELDS.get(part_type, []):
		_rows_box.add_child(_build_row(part_type, field))


## What shows with nothing to compare (EMPTY_TEXT until changed).
func set_empty_text(text: String) -> void:
	_empty.text = text


func get_empty_text() -> String:
	return _empty.text if _empty.visible else ""


func get_header_text() -> String:
	return _header.text if _header.get_parent().visible else ""


func is_showing_empty() -> bool:
	return _empty.visible


## A row's text, "<old> <new  change>" (tests); "" when there's no such row.
func get_row_text(field_id: String) -> String:
	if not _rows.has(field_id):
		return ""
	var row: Dictionary = _rows[field_id]
	return ("%s %s" % [row.old.text, row.value.text]).strip_edges() if row.old.visible else row.value.text


func get_row_ids() -> Array:
	return _rows.keys()


# ---- values ---------------------------------------------------------------

static func field_of(part_type: String, field_id: String) -> Dictionary:
	for field in FIELDS.get(part_type, []):
		if field.id == field_id:
			return field
	return {}


## A part's value for one field: a float (grade-scaled), a bool for a flag,
## a String for text, or null when the part has no such value.
static func value_of(spec: Dictionary, field: Dictionary):
	var part := part_of(spec)
	if part == null or field.is_empty():
		return null
	var id: String = field.id
	var raw = part.get_projectile_stat(id) if field.get("source") == "projectile" and part.has_method("get_projectile_stat") \
			else part.get(id)
	var kind: String = field.get("kind", "number")
	if kind == "flag":
		if raw == null:
			return null
		return bool(raw)
	if kind == "text":
		return _text_of(raw)
	if not (raw is int or raw is float):
		return null
	return float(raw) * Grades.stat_mult(spec.get("grade"), id) if field.get("source") == "projectile" \
			else StatsPanel.sum_stat({"part": part}, id, {"part": spec.get("grade")})


## candidate - subject for a number field (0 when either has none).
static func difference(subject: Dictionary, candidate: Dictionary, field_id: String) -> float:
	var field := field_of(str(subject.get("part_type", "")), field_id)
	var a = value_of(subject, field)
	var b = value_of(candidate, field)
	if not (a is float and b is float):
		return 0.0
	return b - a


static func part_of(spec: Dictionary) -> Object:
	var part_type := str(spec.get("part_type", ""))
	var part_id := str(spec.get("part_id", ""))
	if not part_type in PlayerProgress.PART_TYPES or part_id == "":
		return null
	var parts: Dictionary = PartManager.get_parts(part_type)
	return parts.get(part_id)


## "Refined MA-L127": the part's name with its grade.
static func display_name(spec: Dictionary) -> String:
	var part := part_of(spec)
	var part_name = part.get("part_name") if part != null else null
	var shown := str(part_name) if part_name != null and str(part_name) != "" else str(spec.get("part_id", "?"))
	return Grades.label(spec.get("grade"), shown)


static func format_value(value) -> String:
	if value == null:
		return NONE
	if value is bool:
		return "YES" if value else "NO"
	if value is float or value is int:
		return StatsPanel._fmt(float(value))
	return str(value)


static func _text_of(raw) -> String:
	if raw == null:
		return NONE
	if raw is Array:
		return " × ".join(raw.map(func(v): return str(v)))
	return str(raw).capitalize() if raw is String else str(raw)


# The highest value of the field across every part of the type (Standard).
static func _max_of(part_type: String, field: Dictionary) -> float:
	var key := "%s:%s" % [part_type, field.id]
	if _type_max.has(key):
		return _type_max[key]
	var top := 0.0
	for part_id in PartManager.get_parts(part_type):
		var value = value_of({"part_type": part_type, "part_id": part_id}, field)
		if value is float:
			top = maxf(top, value)
	_type_max[key] = top
	return top


# ---- building -------------------------------------------------------------

func _build_row(part_type: String, field: Dictionary) -> Control:
	var row := MechUI.vbox(&"StatRow")
	if field.get("lower_better", false):
		row.tooltip_text = "Lower is better"
	var line := MechUI.hbox()
	var name_label := MechUI.label(&"LabelMeta", String(field.label).to_upper())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var old_label := MechUI.label(&"LabelDim")
	var value_label := MechUI.label(&"LabelBody")
	line.add_child(name_label)
	line.add_child(old_label)
	line.add_child(value_label)
	row.add_child(line)

	var cur = value_of(_subject, field)
	var new = value_of(_candidate, field)
	var numbers: bool = cur is float and new is float
	var changed: bool = (not is_equal_approx(cur, new)) if numbers else format_value(cur) != format_value(new)
	old_label.visible = changed
	old_label.text = "%s >" % format_value(cur)
	value_label.text = format_value(new) + ("  %s" % StatsPanel._signed(new - cur) if numbers and changed else "")
	value_label.theme_type_variation = &"LabelBodyBright" if changed else &"LabelBody"
	var bar: StatBar = null
	if field.get("kind", "number") == "number":
		bar = StatBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cur_n: float = cur if cur is float else 0.0
		var new_n: float = new if new is float else 0.0
		var top := maxf(maxf(_max_of(part_type, field), cur_n), maxf(new_n, 0.0001))
		bar.ratio = cur_n / top
		bar.preview_ratio = new_n / top if changed else -1.0
		row.add_child(bar)
	_rows[field.id] = {"old": old_label, "value": value_label, "bar": bar}
	return row
