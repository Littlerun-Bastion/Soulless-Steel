class_name Reticle
extends Node2D

## The aiming reticle at the cursor.
##   lock_size 0   the cursor crosshair (cursor_crosshair.png, drawn 1:1)
##   lock_size > 0 lock-on mode: four S1 G6 corner brackets, lock_size px
##                 from the centre, so the box matches the chipset's lock
##                 area at any size with 1px lines.
## Replaces the lock-on sprites that were scaled to the lock size.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const CURSOR := preload("res://assets/images/ui/player_ui/cursor_crosshair.png")
const MIN_CORNER := 4.0
const CORNER_SHARE := 0.35

var lock_size := 0.0:
	set(value):
		if value == lock_size:
			return
		lock_size = value
		queue_redraw()


## The corner bracket lines for a lock box of this half-size, as pairs of
## points (for draw_multiline). Points sit on pixel centres.
static func bracket_lines(half: float) -> PackedVector2Array:
	var h := floorf(half) + 0.5
	var c := maxf(MIN_CORNER, floorf(half * CORNER_SHARE))
	var lines := PackedVector2Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(h * sx, h * sy)
			lines.append_array([corner, corner - Vector2(c * sx, 0)])
			lines.append_array([corner, corner - Vector2(0, c * sy)])
	return lines


func _draw() -> void:
	if lock_size <= 0.0:
		draw_texture(CURSOR, -CURSOR.get_size() / 2.0)
		return
	draw_multiline(bracket_lines(lock_size), THEME.get_color(&"g6", &"MechTokens"), 1.0)
