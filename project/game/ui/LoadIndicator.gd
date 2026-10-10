extends Label
class_name LoadIndicator

# HUD readout of the mecha's load — parts plus cargo — against its weight
# capacity, e.g. "LOAD 412 / 500". Over capacity the mecha slows down
# (Mecha.is_overweight); the readout turns amber near the limit and red over
# it, next to the existing blinking "WRN WGHT" status.

const WARN_RATIO := 0.9
const NORMAL_COLOR := Color(1, 1, 1)
const WARN_COLOR := Color(1, 0.75, 0.3)
const OVER_COLOR := Color(1, 0.35, 0.35)
const UPDATE_INTERVAL := 0.25  # get_stat walks every part; no need per frame

var player = null
var _timer := 0.0


func setup(player_ref) -> void:
	player = player_ref
	_timer = 0.0
	_update()


func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	_update()


func _update() -> void:
	visible = is_instance_valid(player)
	if not visible:
		return
	var load_now: float = player.get_total_weight()
	var capacity: float = player.get_stat("weight_capacity")
	text = format_load(load_now, capacity)
	modulate = color_for(load_now, capacity)


static func format_load(load_now: float, capacity: float) -> String:
	return "LOAD %d / %d" % [roundi(load_now), roundi(capacity)]


static func color_for(load_now: float, capacity: float) -> Color:
	if capacity <= 0.0:
		return NORMAL_COLOR
	if load_now > capacity:
		return OVER_COLOR
	if load_now >= capacity * WARN_RATIO:
		return WARN_COLOR
	return NORMAL_COLOR
