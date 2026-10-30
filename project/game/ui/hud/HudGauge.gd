class_name HudGauge
extends Control

## A 12px HUD gauge drawn on whole pixels: S1 frame, solid fill, and an
## optional threshold marker (a 2px tick that overhangs the frame by 4px).
##   normal    frame G5, fill G5
##   critical  frame G6, fill G6 (the row's text goes bright too)
##   empty     frame G3 (nothing to show, e.g. no battery)
## Colours come from MechTokens in MechTheme.

const HEIGHT := 12
const MARKER_OVERHANG := 4

var ratio := 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, ratio):
			ratio = value
			queue_redraw()
## -1 = no marker.
var marker := -1.0:
	set(value):
		marker = value
		queue_redraw()
var critical := false:
	set(value):
		if value != critical:
			critical = value
			queue_redraw()
var empty := false:
	set(value):
		if value != empty:
			empty = value
			queue_redraw()


func _ready() -> void:
	custom_minimum_size.y = HEIGHT + MARKER_OVERHANG * 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := floorf(size.x)
	var top := float(MARKER_OVERHANG)
	var h := float(HEIGHT)
	if w < 4.0:
		return
	var line := _token(&"g3") if empty else (_token(&"g6") if critical else _token(&"g5"))
	draw_rect(Rect2(0, top, w, 1), line)
	draw_rect(Rect2(0, top + h - 1, w, 1), line)
	draw_rect(Rect2(0, top, 1, h), line)
	draw_rect(Rect2(w - 1, top, 1, h), line)
	if not empty:
		draw_rect(Rect2(1, top + 1, floorf((w - 2) * ratio), h - 2), line)
	if marker >= 0.0:
		var x := 1.0 + floorf((w - 2) * clampf(marker, 0.0, 1.0)) - 1.0
		# A dark core with a bright edge, so it shows over the fill too.
		draw_rect(Rect2(x - 1, 0, 4, h + MARKER_OVERHANG * 2), _token(&"g0"))
		draw_rect(Rect2(x, 0, 2, h + MARKER_OVERHANG * 2), _token(&"g6"))


func _token(name: StringName) -> Color:
	return get_theme_color(name, &"MechTokens")
