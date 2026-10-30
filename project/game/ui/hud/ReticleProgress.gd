class_name ReticleProgress
extends Range

## Small progress readouts by the reticle (value 0-100, like a ProgressBar).
##   ring = true   reload: a G3 track and a S2 G5 arc, clockwise from the
##                 top, filling the control (20 x 20)
##   ring = false  lock-on charge: a S1 G4 frame and a G5 fill, left to right
## Replaces the circular_progress and change_mode_progress sprites (scaled
## to 0.1 and 0.2 x 0.4).

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")

@export var ring := false:
	set(value):
		ring = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _value_changed(_new_value: float) -> void:
	queue_redraw()


func get_ratio() -> float:
	return 0.0 if is_equal_approx(max_value, min_value) else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)


func _draw() -> void:
	var ratio := get_ratio()
	if ring:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 1.0
		draw_arc(center, radius, 0.0, TAU, 48, _color(&"g3"), 1.0, true)
		if ratio > 0.0:
			draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * ratio, 48, _color(&"g5"), 2.0, true)
		return
	var frame := Rect2(Vector2.ZERO, size).grow(-0.5)
	draw_rect(frame, _color(&"g4"), false, 1.0)
	var inner := Rect2(Vector2(2, 2), Vector2(maxf(size.x - 4.0, 0.0) * ratio, maxf(size.y - 4.0, 0.0)))
	if inner.size.x > 0.0:
		draw_rect(inner, _color(&"g5"))


static func _color(token: StringName) -> Color:
	return THEME.get_color(token, &"MechTokens")
