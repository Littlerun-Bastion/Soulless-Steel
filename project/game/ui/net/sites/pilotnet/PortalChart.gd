class_name PortalChart
extends Control

## A small price chart for pilot.net's new look: prices oldest to newest
## across the control, the lowest at the bottom and the highest at the top,
## as a LINE over an AREA down to the bottom, in a 1 px FRAME. MechTokens
## greys at whole pixels (each point on a pixel's centre).

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const FRAME := "g4"
const AREA := "g5"
const LINE := "g2"
const GROUND := "g6"

var prices: Array = []


func _init(new_prices: Array = [], chart_size := Vector2(180, 110)) -> void:
	prices = new_prices
	custom_minimum_size = chart_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The points the line goes through, in the control's pixels.
func points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if prices.size() < 2:
		return out
	var low := float(prices[0])
	var high := float(prices[0])
	for value in prices:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	var width := floorf(size.x) - 3.0
	var height := floorf(size.y) - 3.0
	for i in prices.size():
		var t := 0.5 if high <= low else (float(prices[i]) - low) / (high - low)
		out.append(Vector2(1.0 + roundf(i * width / (prices.size() - 1)), 1.0 + roundf((1.0 - t) * height)) + Vector2(0.5, 0.5))
	return out


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size.floor())
	var frame := THEME.get_color(FRAME, "MechTokens")
	draw_rect(box, THEME.get_color(GROUND, "MechTokens"))
	var line := points()
	if not line.is_empty():
		var area := PackedVector2Array(line)
		area.append(Vector2(line[line.size() - 1].x, box.size.y - 1.0))
		area.append(Vector2(line[0].x, box.size.y - 1.0))
		draw_colored_polygon(area, THEME.get_color(AREA, "MechTokens"))
		draw_polyline(line, THEME.get_color(LINE, "MechTokens"), 1.0)
	draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), frame)
	draw_rect(Rect2(Vector2(0, box.size.y - 1), Vector2(box.size.x, 1)), frame)
	draw_rect(Rect2(box.position, Vector2(1, box.size.y)), frame)
	draw_rect(Rect2(Vector2(box.size.x - 1, 0), Vector2(1, box.size.y)), frame)
