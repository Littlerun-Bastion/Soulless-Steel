class_name HudBoot
extends Node

## Takes the HUD dark, then brings it back one system at a time: the system's
## panels flicker on like a cold screen while its line types out in the log.
## A system is [name, items]; an item that is no CanvasItem (the top strip's
## CanvasLayer) is left to whoever listens to lit_changed.

signal booted
signal lit_changed

const FLICKER := [0.06, 0.08, 0.04, 0.12, 0.05]
const SYSTEM_GAP := 0.15
const HOLD := 0.6
const LOG_FADE := 0.8
const LINE_WIDTH := 14
const LOG_POSITION := Vector2(48, 240)
const HEADER := "SAV-OS // FIELD REPAIR"
const FOOTER := "ALL SYSTEMS ONLINE"

var _systems: Array = []
var _layers := {}
var _unlit := {}
var _booting := false
var _log: BootLog = null
var _tween: Tween = null


func _ready() -> void:
	_log = BootLog.new()
	_log.theme = preload("res://game/ui/mech_os/MechTheme.tres")
	_log.theme_type_variation = &"LabelBodyBright"
	_log.position = LOG_POSITION
	add_child(_log)


func go_dark(systems: Array) -> void:
	if _tween != null:
		_tween.kill()
	_booting = false
	for system in systems:
		for item in system[1]:
			if item is CanvasItem and not _layers.has(item):
				_layers[item] = item.visibility_layer
			_light(item, false)
	_tween = null
	_systems = systems


func boot() -> void:
	if _unlit.is_empty() or _booting:
		return
	_booting = true
	_log.clear_log()
	_log.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_callback(_log.add_line.bind(HEADER))
	_tween.tween_interval(SYSTEM_GAP)
	for system in _systems:
		_tween.tween_callback(_log.add_line.bind(system[0].rpad(LINE_WIDTH, ".") + " OK"))
		var on := true
		for seconds in FLICKER:
			_tween.tween_callback(_light_system.bind(system, on))
			_tween.tween_interval(seconds)
			on = not on
		_tween.tween_callback(_light_system.bind(system, true))
		_tween.tween_interval(SYSTEM_GAP)
	_tween.tween_callback(_log.add_line.bind(FOOTER))
	_tween.tween_interval(HOLD)
	_tween.tween_callback(_finish)
	_tween.tween_property(_log, "modulate:a", 0.0, LOG_FADE)
	_tween.tween_callback(_log.clear_log)


func is_dark() -> bool:
	return not _unlit.is_empty()


func is_booting() -> bool:
	return _booting


func is_lit(item: Object) -> bool:
	return not _unlit.has(item)


func get_log_text() -> String:
	return _log.text


func _light_system(system: Array, on: bool) -> void:
	for item in system[1]:
		_light(item, on)


func _light(item: Object, on: bool) -> void:
	if not is_instance_valid(item):
		return
	if item is CanvasItem:
		item.visibility_layer = _layers.get(item, item.visibility_layer) if on else 0
	if on:
		_unlit.erase(item)
	else:
		_unlit[item] = true
	lit_changed.emit()


func _finish() -> void:
	_booting = false
	_unlit.clear()
	_layers.clear()
	booted.emit()
