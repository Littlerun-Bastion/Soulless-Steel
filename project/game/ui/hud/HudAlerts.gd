class_name HudAlerts
extends PanelContainer

## Top centre: one alert at a time, the most urgent one.
##   critical (inverted)  capsule exposed, hull heat past the damage point,
##                        status effects, ECM interference on a lock
##   notice (outlined)    extracting
## Replaces the old blinking WRN labels, the ECM readout, the exposed banner
## and the extracting label. Order of urgency is the order in _pick().

var player = null
var extracting := false

const STATUS_WORDS := {"fire": "FIRE", "freezing": "FREEZING", "corrosion": "CORROSION",
	"electrified": "ELECTRIFIED", "overheating": "OVERHEATING"}

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = MechUI.label(&"AlertCriticalText")
	add_child(_label)
	visible = false


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	visible = false


## The alert on show ("" when none).
func get_current() -> String:
	return _label.text if visible else ""


func _process(_delta: float) -> void:
	var alert := _pick()
	visible = not alert.is_empty()
	if not visible:
		return
	var critical: bool = alert.critical
	theme_type_variation = &"AlertCritical" if critical else &"AlertNotice"
	_label.theme_type_variation = &"AlertCriticalText" if critical else &"LabelMetaBright"
	if _label.text != alert.text:
		_label.text = alert.text
		reset_size()
	# Keep it centred on its anchor as the text changes width.
	position.x = floorf((get_parent_area_size().x - size.x) * 0.5)


func _pick() -> Dictionary:
	if is_instance_valid(player):
		if player.is_exposed:
			return {"text": "! CAPSULE EXPOSED", "critical": true}
		if player.external_temp >= player.OVERHEAT_DAMAGE_TEMP:
			return {"text": "! EXT HEAT CRITICAL — COMPONENT DAMAGE", "critical": true}
		var statuses := []
		for status in STATUS_WORDS:
			if player.has_status(status):
				statuses.append(STATUS_WORDS[status])
		if not statuses.is_empty():
			return {"text": "! " + " · ".join(statuses), "critical": true}
		if player.get_locking_to() and player.ecm_strength_difference > 0.0:
			return {"text": "! ECM INTERFERENCE −%d%%" % roundi(player.ecm_strength_difference * 100.0), "critical": true}
	if extracting:
		return {"text": "EXTRACTING", "critical": false}
	return {}
