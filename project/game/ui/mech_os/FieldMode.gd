class_name FieldMode
extends Node

## The field rules for MechOS (spec: "UI states and input").
## MechOS adds this as a child in _ready; it needs nothing else.
##
## The field is any combat scene (MouseManager.aim_available). There:
##   - The sidebar is hidden. Holding the free-cursor key (Alt) slides it out.
##   - Only field apps are on it: EQP, CGO, LOG, SYS. Messenger, Deployments,
##     Materials and the browser come back when the player leaves the field.
##   - While Alt is up, windows hide, except the loot pair (the container and
##     Mech Cargo). Those stay on screen; MechOS already stops them taking
##     the mouse while the player aims. Hidden windows are not closed: holding
##     Alt shows them again where they were.
## Pause and game over change nothing here (spec: sidebar "unchanged").
##
## Off duty (no live player registered with MechOS.set_player: intro, title,
## ladder, and after the player's mecha is gone) the sidebar and windows are
## hidden at once, with no slide. CombatScene and the Hangar register a player.
##
## rail_right is the sidebar's right edge on screen (0 while it's hidden), so
## HUD blocks on the left can move out of its way (HudStatus).

const FIELD_HIDDEN_APPS := ["messenger", "deployments", "materials", "net"]
## Windows that stay visible while aiming (opened by E or the cargo key).
const PINNED_APPS := ["container", "mech_cargo"]
const SLIDE_TIME := 0.12

## The sidebar's right edge in screen pixels, 0 while hidden.
static var rail_right := 0.0

var in_field := false
var sidebar_out := true
var on_duty := true

var _os: Node                 # MechOS
var _docked := Vector2.ZERO   # the sidebar's offset_left / offset_right when out
var _restore: Dictionary = {} # app id -> available before the field
var _tween: Tween


func _ready() -> void:
	_os = get_parent()
	var bar: Control = _os.taskbar
	_docked = Vector2(bar.offset_left, bar.offset_right)


func _process(_delta: float) -> void:
	var field: bool = MouseManager.aim_available
	if field != in_field:
		_set_field(field)
	var duty: bool = is_instance_valid(_os.player_ref)
	var instant := duty != on_duty
	on_duty = duty
	var os_shown: bool = on_duty and (not field or MouseManager.free_cursor_held)
	_slide_sidebar(os_shown, instant)
	_update_windows(os_shown)
	var bar: Control = _os.taskbar
	rail_right = bar.get_global_rect().end.x if bar.visible else 0.0


func _set_field(on: bool) -> void:
	in_field = on
	if on:
		_restore.clear()
		for app_id in FIELD_HIDDEN_APPS:
			_restore[app_id] = _os.is_app_available(app_id)
			_os.set_app_available(app_id, false)
	else:
		for app_id in _restore:
			_os.set_app_available(app_id, _restore[app_id])
		_restore.clear()


# instant: going on or off duty snaps the sidebar instead of sliding it.
func _slide_sidebar(out: bool, instant := false) -> void:
	if out == sidebar_out and not instant:
		return
	sidebar_out = out
	var bar: Control = _os.taskbar
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var width := _docked.y - _docked.x
	var from := bar.offset_left
	var to := _docked.x if out else -width - 1.0
	if instant:
		_place_sidebar(to)
		bar.visible = out
		return
	if out:
		bar.visible = true
	_tween = create_tween()
	_tween.tween_method(_place_sidebar, from, to, SLIDE_TIME)
	if not out:
		_tween.tween_callback(func(): bar.visible = false)


# Moves the sidebar by its left edge, on whole pixels.
func _place_sidebar(left: float) -> void:
	var bar: Control = _os.taskbar
	left = roundf(left)
	bar.offset_left = left
	bar.offset_right = left + (_docked.y - _docked.x)


func _update_windows(os_shown: bool) -> void:
	for app_id in _os.open_windows:
		var window: Control = _os.open_windows[app_id]
		var show_it: bool = os_shown or app_id in PINNED_APPS
		if window.visible != show_it:
			window.visible = show_it
