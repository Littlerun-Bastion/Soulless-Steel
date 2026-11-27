class_name HudAlerts
extends PanelContainer

## Top centre: one alert at a time, the most urgent one.
##   critical (inverted)  the Flag being lowered, Flagged (emergency: capsule
##                        exposed, weapons locked; or raised by choice:
##                        weapons locked), the capsule exposed with the Flag
##                        down, hull heat past the damage point,
##                        someone locking the player ("LOCKING" while the
##                        lock wedge narrows, "LOCKED" once it is a line:
##                        Mecha.lock_warning), status effects, ECM
##                        interference on a lock
##   notice (outlined)    a passing event for NOTICE_TIME s (show_notice):
##                        "YOU WERE SWEPT" (no bearing), "WARD DESTROYED",
##                        "EXTRACTION CANCELLED"; extracting, with the time
##                        left. While extracting a bar fills under whatever
##                        alert is on show.
##   place (outlined)     the name of a place the player has just entered
##                        (show_place), in the notice style but below every
##                        notice and the extraction: its NOTICE_TIME s count
##                        only while it is on show, and it is dropped if
##                        PLACE_WAIT s pass before it can be, or if the
##                        player is in another place or none by then
##                        (set_current_place).
## Replaces the old blinking WRN labels, the ECM readout, the exposed banner
## and the extracting label. Order of urgency is the order in _pick().

## Placeholder.
const NOTICE_TIME := 3.0
## Placeholder.
const PLACE_WAIT := 8.0

const CANCELLED := "EXTRACTION CANCELLED"
const BAR_WIDTH := 320.0

var player = null
var extracting := false:
	set(value):
		if extracting and not value and is_instance_valid(player):
			show_notice(CANCELLED)
		elif value and _notice == CANCELLED:
			_notice_time = 0.0
		extracting = value
var _notice := ""
var _notice_time := 0.0
var _place := ""
var _place_time := 0.0
var _place_wait := 0.0
var _place_shown := false

const STATUS_WORDS := {"fire": "FIRE", "freezing": "FREEZING", "corrosion": "CORROSION",
	"electrified": "ELECTRIFIED", "overheating": "OVERHEATING"}

var _label: Label
var _bar: HudGauge


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := MechUI.vbox()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_label = MechUI.label(&"AlertCriticalText")
	stack.add_child(_label)
	_bar = HudGauge.new()
	_bar.custom_minimum_size.x = BAR_WIDTH
	_bar.visible = false
	stack.add_child(_bar)
	visible = false


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	visible = false


## The alert on show ("" when none).
func get_current() -> String:
	return _label.text if visible else ""


func is_extract_bar_shown() -> bool:
	return visible and _bar.visible


func get_extract_ratio() -> float:
	return _bar.ratio


## A passing notice, outlined, for `seconds`; a newer one replaces it.
func show_notice(text: String, seconds := NOTICE_TIME) -> void:
	_notice = text
	_notice_time = seconds


## The name of a place the player has entered (see place above); a newer
## one replaces it.
func show_place(text: String, seconds := NOTICE_TIME) -> void:
	_place = text
	_place_time = seconds
	_place_wait = PLACE_WAIT
	_place_shown = false


## The place the player is in now ("" for none). A place name still waiting
## to be shown is dropped unless it is this one.
func set_current_place(text: String) -> void:
	if _place_time > 0.0 and not _place_shown and _place != text:
		_place_time = 0.0


## Someone's sweep found the player (Mecha.swept).
func show_swept() -> void:
	show_notice("YOU WERE SWEPT")


func _process(delta: float) -> void:
	_notice_time = maxf(_notice_time - delta, 0.0)
	var alert := _pick()
	if _place_time > 0.0:
		if alert.get("place", false):
			_place_shown = true
			_place_time = maxf(_place_time - delta, 0.0)
		else:
			_place_wait -= delta
			if _place_wait <= 0.0:
				_place_time = 0.0
	var progress: float = player.get_extract_progress() if extracting and is_instance_valid(player) else -1.0
	var bar_shown := progress >= 0.0
	if _bar.visible != bar_shown:
		_bar.visible = bar_shown
		reset_size()
	if bar_shown:
		_bar.ratio = progress
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
		if player.is_lowering_flag():
			return {"text": "! LOWERING FLAG", "critical": true}
		if player.is_flagged() and player.is_exposed:
			return {"text": "! FLAGGED · CAPSULE EXPOSED · WEAPONS LOCKED", "critical": true}
		if player.is_flagged():
			return {"text": "! FLAG RAISED · WEAPONS LOCKED", "critical": true}
		if player.is_exposed:
			return {"text": "! CAPSULE EXPOSED", "critical": true}
		if player.external_temp >= player.OVERHEAT_DAMAGE_TEMP:
			return {"text": "! EXT HEAT CRITICAL — COMPONENT DAMAGE", "critical": true}
		var warning: Dictionary = player.lock_warning() if player.has_method("lock_warning") else {}
		if not warning.is_empty():
			return {"text": "! LOCKED" if warning.state == "locked" else "! LOCKING", "critical": true}
		var statuses := []
		for status in STATUS_WORDS:
			if player.has_status(status):
				statuses.append(STATUS_WORDS[status])
		if not statuses.is_empty():
			return {"text": "! " + " · ".join(statuses), "critical": true}
		if player.get_locking_to() and player.ecm_strength_difference > 0.0:
			return {"text": "! ECM INTERFERENCE −%d%%" % roundi(player.ecm_strength_difference * 100.0), "critical": true}
	if _notice_time > 0.0:
		return {"text": _notice, "critical": false}
	if extracting:
		var left: float = player.get_extract_time_left() if is_instance_valid(player) else 0.0
		return {"text": "EXTRACTING  %.1fs" % left, "critical": false}
	if _place_time > 0.0:
		return {"text": _place, "critical": false, "place": true}
	return {}
