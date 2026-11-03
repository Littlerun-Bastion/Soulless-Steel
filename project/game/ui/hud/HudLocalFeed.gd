class_name HudLocalFeed
extends VBoxContainer

## Top left: the last LINES lines of Local (LocalPilots.message), newest at
## the bottom. Broadcasts and join or leave lines are LabelBody; barks the
## player heard are LabelMeta, dimmer. The feed fades out once no line has
## come for IDLE_TIME s and is back at full with the next one. The labels
## are a fixed pool. While the MechOS sidebar is out the feed moves right to
## clear it, as HudStatus does (FieldMode.rail_right).

## Placeholders.
const LINES := 4
const IDLE_TIME := 8.0
const FADE_TIME := 1.0
const WIDTH := 560.0

var local: LocalPilots = null

var _labels: Array[Label] = []
var _shown := 0
var _idle := INF
var _base_left := 0.0


func _ready() -> void:
	theme_type_variation = &"TightStack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_left = offset_left
	for i in LINES:
		var label := MechUI.label(&"LabelBody")
		label.custom_minimum_size.x = WIDTH
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.visible = false
		add_child(label)
		_labels.append(label)
	modulate.a = 0.0


func setup(local_ref: LocalPilots) -> void:
	if local != null and local.message.is_connected(_on_message):
		local.message.disconnect(_on_message)
	local = local_ref
	local.message.connect(_on_message)


func player_died() -> void:
	if local != null and local.message.is_connected(_on_message):
		local.message.disconnect(_on_message)
	local = null
	visible = false


## The lines on show, oldest first ("" lines skipped).
func get_lines() -> Array[String]:
	var lines: Array[String] = []
	for label in _labels:
		if label.visible:
			lines.append(label.text)
	return lines


func _on_message(entry: Dictionary) -> void:
	for i in LINES - 1:
		_labels[i].text = _labels[i + 1].text
		_labels[i].theme_type_variation = _labels[i + 1].theme_type_variation
	var last := _labels[LINES - 1]
	last.text = LocalPilots.format(entry)
	last.theme_type_variation = &"LabelMeta" if entry.bark else &"LabelBody"
	_shown = mini(_shown + 1, LINES)
	for i in LINES:
		_labels[i].visible = i >= LINES - _shown
	_idle = 0.0
	modulate.a = 1.0


func _process(delta: float) -> void:
	var left := _base_left + roundf(HudStatus.rail_push(FieldMode.rail_right, _base_left))
	if offset_left != left:
		offset_left = left
	_idle += delta
	modulate.a = clampf(1.0 - (_idle - IDLE_TIME) / FADE_TIME, 0.0, 1.0)
