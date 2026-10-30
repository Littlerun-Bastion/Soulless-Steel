@tool
class_name FocusBrackets
extends Control

# Draws the four corner brackets on the focused MechWindow.
# Add it as the window's LAST child, so it draws over the titlebar.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var arm := float(get_theme_constant("bracket", "MechTokens"))
	var w := float(get_theme_constant("s2", "MechTokens"))
	var color := get_theme_color("g6", "MechTokens")
	var right := floorf(size.x)
	var bottom := floorf(size.y)

	# Each bracket is two whole-pixel rects drawn inside the window edge, because MechWindow clips its contents.
	draw_rect(Rect2(0, 0, arm, w), color)
	draw_rect(Rect2(0, 0, w, arm), color)
	draw_rect(Rect2(right - arm, 0, arm, w), color)
	draw_rect(Rect2(right - w, 0, w, arm), color)
	draw_rect(Rect2(0, bottom - w, arm, w), color)
	draw_rect(Rect2(0, bottom - arm, w, arm), color)
	draw_rect(Rect2(right - arm, bottom - w, arm, w), color)
	draw_rect(Rect2(right - w, bottom - arm, w, arm), color)
