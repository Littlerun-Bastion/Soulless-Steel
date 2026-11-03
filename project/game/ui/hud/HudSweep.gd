class_name HudSweep
extends PanelContainer

## Top centre, under the alerts: the sensor sweep (Player, "SENSOR SWEEP").
##   aiming        "SWEEP 90° · [R] CANCEL" while the sweep key is held
##   result        "SWEEP 90° — 2 MECH · 3 STALKER" (or NO RETURNS) for
##                 READOUT_TIME s after a sweep: kinds and counts only
##   refused       "SWEEP RECHARGING 7S" for REFUSED_TIME s
## HudPanel, text LabelMetaBright. Hidden otherwise.

## Placeholders.
const READOUT_TIME := 6.0
const REFUSED_TIME := 2.0

var player = null

var _label: Label
var _text := ""
var _time := 0.0


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = MechUI.label(&"LabelMetaBright")
	add_child(_label)
	MechUI.ignore_mouse(self)
	visible = false


func setup(player_ref) -> void:
	player = player_ref
	player.sweep_done.connect(_on_sweep_done)
	player.sweep_refused.connect(_on_sweep_refused)


func player_died() -> void:
	player = null
	visible = false


## The text on show ("" when hidden).
func get_text() -> String:
	return _label.text if visible else ""


func _on_sweep_done(result: Dictionary) -> void:
	_show("SWEEP %d° — %s" % [roundi(result.width), Mecha.describe_sweep(result.counts)], READOUT_TIME)


func _on_sweep_refused(reason: String) -> void:
	if reason == "cooldown" and is_instance_valid(player):
		_show("SWEEP RECHARGING %dS" % ceili(player.sweep_cooldown), REFUSED_TIME)


func _show(text: String, seconds: float) -> void:
	_text = text
	_time = seconds


func _process(delta: float) -> void:
	_time = maxf(_time - delta, 0.0)
	var text := ""
	if is_instance_valid(player) and player.is_sweep_aiming():
		text = "SWEEP %d° · [%s] CANCEL" % [roundi(player.sweep_width), MechUI.key_name("reload_mode")]
	elif _time > 0.0:
		text = _text
	visible = text != ""
	if not visible:
		return
	if _label.text != text:
		_label.text = text
		reset_size()
	position.x = floorf((get_parent_area_size().x - size.x) * 0.5)
