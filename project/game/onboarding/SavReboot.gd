extends CanvasLayer

## A wrecked SAV rebooted from afar: the picture dies, a boot log types out
## over the black, then the screen comes back on like a cold CRT, a line
## that opens up through static.

signal finished

const LAYER := 98
const HEADER := ["REMOTE LINK REQUEST // TROBAIRITZ", "HANDSHAKE ............ ACCEPTED", "", "SAV-OS COLD BOOT"]
const SYSTEMS := [["CORE", "OK"], ["WEAPONS", "OK"], ["SENSORS", "DAMAGED"], ["MOBILITY", "DAMAGED"],
		["COOLING", "DAMAGED"], ["SAFETY FLAG", "RAISED"]]
const LINE_WIDTH := 22
const FLICKERS := [0.05, 0.07, 0.04, 0.1, 0.03, 0.12]
const DARK_HOLD := 0.8
const LINE_GAP := 0.22
const LOG_HOLD := 0.9
const LINE_GROW_TIME := 0.15
const OPEN_TIME := 0.45
const STATIC_TIME := 1.0
const LINE_HEIGHT := 4.0
const LOG_LEFT := 96.0
const LOG_TOP_RATIO := 0.2
const TEXT_COLOUR := Color(0.6, 1.0, 0.65)
const BEAM_COLOUR := Color(0.85, 1.0, 0.9)
const FONT := preload("res://assets/fonts/data/VT323/VT323-Regular.ttf")
const FONT_SIZE := 32
const STATIC_SHADER := preload("res://game/onboarding/Static.gdshader")

var _cover: ColorRect = null
var _static: ColorRect = null
var _top: ColorRect = null
var _bottom: ColorRect = null
var _beam: ColorRect = null
var _log: BootLog = null
var _covering := false


func _ready() -> void:
	layer = LAYER
	_cover = _rect(Color.BLACK, true)
	_static = _rect(Color.WHITE, true)
	var static_material := ShaderMaterial.new()
	static_material.shader = STATIC_SHADER
	_static.material = static_material
	_top = _rect(Color.BLACK, false)
	_bottom = _rect(Color.BLACK, false)
	_beam = _rect(BEAM_COLOUR, false)
	_log = BootLog.new()
	_log.add_theme_font_override("font", FONT)
	_log.add_theme_font_size_override("font_size", FONT_SIZE)
	_log.add_theme_color_override("font_color", TEXT_COLOUR)
	add_child(_log)


func play() -> void:
	_log.position = Vector2(LOG_LEFT, get_viewport().get_visible_rect().size.y * LOG_TOP_RATIO)
	AudioManager.play_sfx("low_tone")
	var on := true
	for seconds in FLICKERS:
		_cover_screen(on)
		on = not on
		await _wait(seconds)
	_cover_screen(true)
	await _wait(DARK_HOLD)
	for line in HEADER:
		_log.add_line(line)
		await _wait(LINE_GAP)
	for system in SYSTEMS:
		_log.add_line(system[0].rpad(LINE_WIDTH, ".") + " " + system[1])
		await _wait(LINE_GAP)
	while _log.is_typing():
		await get_tree().process_frame
	await _wait(LOG_HOLD)
	await _switch_on()
	finished.emit()


func is_covering() -> bool:
	return _covering


func get_cover_rect() -> Rect2:
	return _cover.get_global_rect()


func get_log_text() -> String:
	return _log.text


func get_log_rect() -> Rect2:
	return _log.get_global_rect()


func _switch_on() -> void:
	AudioManager.play_sfx("startup")
	var screen := get_viewport().get_visible_rect().size
	var half := screen.y / 2.0
	_log.visible = false
	_top.position = Vector2.ZERO
	_top.size = Vector2(screen.x, half)
	_bottom.position = Vector2(0, half)
	_bottom.size = Vector2(screen.x, half)
	_beam.position = Vector2(screen.x / 2.0, half - LINE_HEIGHT / 2.0)
	_beam.size = Vector2(0, LINE_HEIGHT)
	for rect in [_top, _bottom, _beam]:
		rect.visible = true
	_cover.visible = false
	var grow := create_tween().set_parallel()
	grow.tween_property(_beam, "position:x", 0.0, LINE_GROW_TIME)
	grow.tween_property(_beam, "size:x", screen.x, LINE_GROW_TIME)
	await grow.finished
	_static.visible = true
	(_static.material as ShaderMaterial).set_shader_parameter("amount", 1.0)
	var open := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	open.tween_property(_top, "size:y", 0.0, OPEN_TIME)
	open.tween_property(_bottom, "position:y", screen.y, OPEN_TIME)
	open.tween_property(_beam, "modulate:a", 0.0, OPEN_TIME)
	await open.finished
	_covering = false
	var fade := create_tween()
	fade.tween_method(_set_static, 1.0, 0.0, STATIC_TIME)
	await fade.finished
	_static.visible = false


func _cover_screen(on: bool) -> void:
	_cover.visible = on
	_covering = on


func _set_static(amount: float) -> void:
	(_static.material as ShaderMaterial).set_shader_parameter("amount", amount)


func _wait(seconds: float) -> Signal:
	return create_tween().tween_interval(seconds).finished


func _rect(colour: Color, full_screen: bool) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	if full_screen:
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	return rect
