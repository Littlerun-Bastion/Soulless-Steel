@tool
class_name WindowCloseButton
extends Button


const BOX := 24
const ARM := 10   # the X spans ARM + 2 pixels
const INSET := 6  # (BOX - (ARM + 2)) / 2

var window_focused := false:
	set(value):
		window_focused = value
		queue_redraw()


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(BOX, BOX)


func _draw() -> void:
	var w := float(get_theme_constant("s2", "MechTokens"))
	var token := "g6" if (window_focused or is_hovered()) else "g4"
	var color := get_theme_color(token, "MechTokens")
	var origin := ((size - Vector2(BOX, BOX)) * 0.5).floor()

	# Two diagonals, one w × w square per pixel step: crisp at any angle the
	# CRT shader bends it, and the same weight as every other S2 stroke.
	for i in ARM + 1:
		draw_rect(Rect2(origin + Vector2(INSET + i, INSET + i), Vector2(w, w)), color)
		draw_rect(Rect2(origin + Vector2(INSET + ARM - i, INSET + i), Vector2(w, w)), color)
