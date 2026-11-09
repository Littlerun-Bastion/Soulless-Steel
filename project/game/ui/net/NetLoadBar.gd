@tool
class_name NetLoadBar
extends Control

## The status bar's load bar, like the Windows 98 progress bar: a sunken
## well of BLOCKS blocks with S1 gaps, filling block by block. Drawn on
## whole pixels in the MechTokens greys; empty when no page is loading.

const BLOCKS := 20
const BLOCK_W := 6
const GAP := 1
const HEIGHT := 14
const FRAME := 1

## 0-100.
var progress := 0:
	set(value):
		var clamped := clampi(value, 0, 100)
		if clamped != progress:
			progress = clamped
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(FRAME * 2 + GAP + BLOCKS * (BLOCK_W + GAP), HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Blocks lit at this progress.
func lit_blocks() -> int:
	return int(floor(progress * BLOCKS / 100.0))


func _draw() -> void:
	var g0 := get_theme_color("g0", "MechTokens")
	var g2 := get_theme_color("g2", "MechTokens")
	var g4 := get_theme_color("g4", "MechTokens")
	var g5 := get_theme_color("g5", "MechTokens")
	var w := float(custom_minimum_size.x)
	var h := float(HEIGHT)
	draw_rect(Rect2(0, 0, w, h), g0)
	draw_rect(Rect2(0, 0, w, FRAME), g2)
	draw_rect(Rect2(0, 0, FRAME, h), g2)
	draw_rect(Rect2(0, h - FRAME, w, FRAME), g4)
	draw_rect(Rect2(w - FRAME, 0, FRAME, h), g4)
	var x := float(FRAME + GAP)
	var top := float(FRAME + GAP)
	var block_h := h - (FRAME + GAP) * 2
	for i in lit_blocks():
		draw_rect(Rect2(x, top, BLOCK_W, block_h), g5)
		x += BLOCK_W + GAP
