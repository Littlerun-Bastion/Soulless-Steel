class_name HudStatus
extends HBoxContainer

## Bottom-left HUD block: the frame readout (240 x 240) and the gauges.
## (No armour or shield gauges: the old hp/shield numbers are being replaced
## by the component damage system; the frame readout shows the damage.)
##   INT COOLANT             internal heat as a share of the overheat point
##   EXT TEMP                outer hull temperature; the tick marks where heat
##                           starts damaging components, past it the row is bright
##   BATTERY                 hidden when the generator has none
##   DASH F B L R · WT       dash directions (bright = ready) and the load;
##                           over capacity the load inverts (replaces LoadIndicator)
## Everything reads the player each frame, except the load (every 0.25 s:
## it walks every part).
## While the MechOS sidebar is out, the block moves right to clear it
## (FieldMode.rail_right), following the sidebar as it slides.

const WIREFRAME := preload("res://game/ui/WireframeDisplay.tscn")
const FRAME_SIZE := 240
const GAUGES_WIDTH := 320
const RAIL_GAP := 16.0          # space between the sidebar and the block
const LOAD_INTERVAL := 0.25
const EXT_TEMP_RANGE := 1.5   # the bar runs to 1.5 x the component-damage point
const DASH_DIRS := {"fwd": "F", "rwd": "B", "left": "L", "right": "R"}

var player = null
var wireframe: WireframeDisplay

var _rows: Dictionary = {}       # key -> {"name": Label, "value": Label, "gauge": HudGauge, "box": Control}
var _dash_labels: Dictionary = {}
var _weight_label: Label
var _damage_label: Label
var _load_timer := 0.0
var _base_left := 0.0


func _ready() -> void:
	theme_type_variation = &"BarGroup"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_left = offset_left
	_build_frame()
	_build_gauges()
	MechUI.ignore_mouse(self)


func setup(player_ref) -> void:
	player = player_ref
	wireframe.setup(player)
	_update_load()
	_update()


func player_died() -> void:
	player = null


func _process(delta: float) -> void:
	_clear_rail()
	if not is_instance_valid(player):
		return
	_update()
	_load_timer -= delta
	if _load_timer <= 0.0:
		_load_timer = LOAD_INTERVAL
		_update_load()


## "WT 39.8 / 48"
static func format_weight(load_now: float, capacity: float) -> String:
	return "WT %s / %s" % [MechUI.fmt(snappedf(load_now, 0.1)), MechUI.fmt(snappedf(capacity, 0.1))]


static func is_over(load_now: float, capacity: float) -> bool:
	return capacity > 0.0 and load_now > capacity


# ---- building -----------------------------------------------------------

func _build_frame() -> void:
	var frame := MechUI.pane(&"HudPanel")
	frame.custom_minimum_size = Vector2(FRAME_SIZE, FRAME_SIZE)
	frame.size_flags_vertical = Control.SIZE_SHRINK_END
	var area := Control.new()
	frame.add_child(area)
	area.add_child(MechUI.label(&"LabelMeta", "FRAME"))
	wireframe = WIREFRAME.instantiate()
	# The frame's inside is 216 x 216 (12px padding). The readout turns with
	# the mecha and reaches about 104px from its centre, so it sits at the
	# middle, nudged up clear of the damage note.
	wireframe.position = Vector2(108, 98)
	area.add_child(wireframe)
	_damage_label = MechUI.label(&"LabelMeta")
	_damage_label.position = Vector2(0, 216 - 18)
	_damage_label.clip_text = true
	_damage_label.size = Vector2(216, 18)
	area.add_child(_damage_label)
	add_child(frame)


func _build_gauges() -> void:
	var panel := MechUI.pane(&"HudPanel")
	panel.custom_minimum_size.x = GAUGES_WIDTH
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var stack := MechUI.vbox(&"HudStack")
	panel.add_child(stack)
	for key in ["coolant", "ext_temp", "battery"]:
		stack.add_child(_make_row(key, {"coolant": "INT COOLANT", "ext_temp": "EXT TEMP",
				"battery": "BATTERY"}[key]))

	var bottom := MechUI.hbox(&"BarRow")
	bottom.add_child(MechUI.label(&"LabelMeta", "DASH"))
	for dir in DASH_DIRS:
		var letter := MechUI.label(&"LabelMetaBright", DASH_DIRS[dir])
		bottom.add_child(letter)
		_dash_labels[dir] = letter
	bottom.add_child(MechUI.spacer())
	_weight_label = MechUI.label(&"LabelMeta")
	bottom.add_child(_weight_label)
	stack.add_child(bottom)
	add_child(panel)


func _make_row(key: String, title: String) -> VBoxContainer:
	var box := MechUI.vbox(&"StatRow")
	var line := MechUI.hbox()
	var name_label := MechUI.label(&"LabelMeta", title)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := MechUI.label(&"LabelBody")
	line.add_child(name_label)
	line.add_child(value)
	var gauge := HudGauge.new()
	gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(line)
	box.add_child(gauge)
	_rows[key] = {"name": name_label, "value": value, "gauge": gauge, "box": box}
	return box


# ---- updating -----------------------------------------------------------

func _update() -> void:
	var coolant := float(player.internal_temp) / maxf(float(player.overheat_temp), 1.0)
	_set_row("coolant", "SATURATED" if coolant >= 1.0 else "%d%%" % roundi(coolant * 100.0), coolant, coolant >= 1.0)

	var damage_point: float = player.OVERHEAT_DAMAGE_TEMP
	var ext: float = player.external_temp
	_set_row("ext_temp", "%d°" % roundi(player.AMBIENT_TEMP + ext), ext / (damage_point * EXT_TEMP_RANGE),
			ext >= damage_point)
	_rows.ext_temp.gauge.marker = 1.0 / EXT_TEMP_RANGE

	var capacity := float(player.battery_capacity)
	_rows.battery.box.visible = capacity > 0.0
	if capacity > 0.0:
		_set_row("battery", "%d / %d" % [roundi(player.battery), roundi(capacity)], player.battery / capacity, false)

	for dir in _dash_labels:
		var ready: bool = player.dash_cooldown[dir] <= 0.0
		_dash_labels[dir].theme_type_variation = &"LabelMetaBright" if ready else &"LabelDim"

	if wireframe.has_method("get_damage_summary"):
		_damage_label.text = wireframe.get_damage_summary()


## How far right the block moves for a sidebar whose right edge is at x.
static func rail_push(rail_right: float, base_left: float) -> float:
	return maxf(0.0, rail_right + RAIL_GAP - base_left) if rail_right > 0.0 else 0.0


func _clear_rail() -> void:
	var left := _base_left + roundf(rail_push(FieldMode.rail_right, _base_left))
	if offset_left != left:
		offset_left = left


func _update_load() -> void:
	var load_now: float = player.get_total_weight()
	var capacity: float = player.get_stat("weight_capacity")
	_weight_label.text = format_weight(load_now, capacity)
	_weight_label.theme_type_variation = &"Badge" if is_over(load_now, capacity) else &"LabelMeta"


func _set_row(key: String, text: String, ratio: float, critical: bool) -> void:
	var row: Dictionary = _rows[key]
	row.value.text = text
	row.value.theme_type_variation = &"LabelBodyBright" if critical else &"LabelBody"
	row.name.theme_type_variation = &"LabelMetaBright" if critical else &"LabelMeta"
	row.gauge.ratio = ratio
	row.gauge.critical = critical
