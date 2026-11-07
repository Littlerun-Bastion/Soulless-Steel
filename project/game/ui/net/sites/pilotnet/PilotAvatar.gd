class_name PilotAvatar
extends Control

## A pilot's picture on pilot.net's new look: a CELLS x CELLS pattern,
## mirrored left to right, made from the callsign's hash (the same every
## time, any case). Filled cells in INK on GROUND, in a 1 px FRAME, all
## MechTokens greys, drawn at whole pixels in the middle of the control.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const CELLS := 5
const GROUND := "g5"
const FRAME := "g4"
const INKS := ["g2", "g3"]

var callsign := ""
## A cell's side in pixels.
var cell := 8


func _init(new_callsign := "", new_cell := 8) -> void:
	callsign = new_callsign
	cell = new_cell
	custom_minimum_size = Vector2.ONE * side()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The picture's side in pixels, frame included.
func side() -> int:
	return CELLS * cell + 2


## The pattern for a callsign: rows of CELLS bools, true where a cell is
## filled. The left half and middle come from the hash's low bits; one with
## nothing filled gets its middle cell.
static func pattern(name: String) -> Array:
	var h := absi(name.to_lower().hash())
	var half := (CELLS + 1) / 2
	var rows := []
	var any := false
	for y in CELLS:
		var row := []
		row.resize(CELLS)
		for x in half:
			var on := ((h >> (y * half + x)) & 1) == 1
			row[x] = on
			row[CELLS - 1 - x] = on
			any = any or on
		rows.append(row)
	if not any:
		rows[CELLS / 2][CELLS / 2] = true
	return rows


## The grey the callsign's cells are drawn in.
static func ink_of(name: String) -> String:
	return INKS[(absi(name.to_lower().hash()) >> 20) % INKS.size()]


func _draw() -> void:
	var length := side()
	var origin := ((size - Vector2(length, length)) / 2.0).floor()
	var frame := THEME.get_color(FRAME, "MechTokens")
	draw_rect(Rect2(origin, Vector2(length, length)), THEME.get_color(GROUND, "MechTokens"))
	draw_rect(Rect2(origin, Vector2(length, 1)), frame)
	draw_rect(Rect2(origin + Vector2(0, length - 1), Vector2(length, 1)), frame)
	draw_rect(Rect2(origin, Vector2(1, length)), frame)
	draw_rect(Rect2(origin + Vector2(length - 1, 0), Vector2(1, length)), frame)
	var ink := THEME.get_color(ink_of(callsign), "MechTokens")
	var rows := pattern(callsign)
	for y in CELLS:
		for x in CELLS:
			if rows[y][x]:
				draw_rect(Rect2(origin + Vector2(1 + x * cell, 1 + y * cell), Vector2(cell, cell)), ink)
