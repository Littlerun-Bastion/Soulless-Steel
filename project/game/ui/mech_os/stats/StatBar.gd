@tool
class_name StatBar
extends Control

## An 8px stat bar drawn on whole pixels (S1 track, G5 fill).
## With a preview value it also shows the change:
##   gain  — G6 vertical hatching from the current value to the new one
##   loss  — a dashed G5 ghost over the length that would be lost
## Colours and strokes come from the MechTokens type in MechTheme.

const HEIGHT := 8
const HATCH_STEP := 3
const DASH := 3
const GAP := 2

var ratio := 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()

## -1 = no preview.
var preview_ratio := -1.0:
	set(value):
		preview_ratio = value if value < 0.0 else clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var g3 := get_theme_color("g3", "MechTokens")
	var g5 := get_theme_color("g5", "MechTokens")
	var g6 := get_theme_color("g6", "MechTokens")
	var w := floorf(size.x)
	var h := float(HEIGHT)
	if w < 4.0:
		return

	# Track: four 1px rects, so the frame never straddles a pixel edge.
	draw_rect(Rect2(0, 0, w, 1), g3)
	draw_rect(Rect2(0, h - 1, w, 1), g3)
	draw_rect(Rect2(0, 0, 1, h), g3)
	draw_rect(Rect2(w - 1, 0, 1, h), g3)

	var inner := w - 2.0
	var cur_x := floorf(inner * ratio)
	draw_rect(Rect2(1, 1, cur_x, h - 2), g5)

	if preview_ratio < 0.0:
		return
	var new_x := floorf(inner * preview_ratio)
	if new_x > cur_x:
		var x := cur_x
		while x < new_x:
			draw_rect(Rect2(1 + x, 1, 1, h - 2), g6)
			x += HATCH_STEP
	elif new_x < cur_x:
		var from_x := 1.0 + new_x
		var to_x := 1.0 + cur_x
		# Cut the solid fill back to the new value, then outline what goes.
		draw_rect(Rect2(from_x, 1, to_x - from_x, h - 2), get_theme_color("g1", "MechTokens"))
		_dash_h(from_x, to_x, 0.0, g5)
		_dash_h(from_x, to_x, h - 1, g5)
		draw_rect(Rect2(to_x - 1, 0, 1, h), g5)


func _dash_h(from_x: float, to_x: float, y: float, color: Color) -> void:
	var x := from_x
	while x < to_x:
		draw_rect(Rect2(x, y, minf(DASH, to_x - x), 1), color)
		x += DASH + GAP
