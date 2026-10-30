extends Node2D

## One contact on the radar: chevrons just outside the ring, pointing at the
## contact (up, before the node's rotation). More chevrons = closer.
##   level 1  far   1 chevron, G4
##   level 2  mid   2 chevrons, G5
##   level 3  near  3 chevrons, G6, and the ring brightened under them
## Replaces the player_directional_pointer sprites.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const RING_RADIUS := 75.0
const FIRST := 80.0      # distance from the centre to the first chevron
const STEP := 5.0
const HALF_WIDTH := 7.0
const HEIGHT := 4.0
const ARC := 0.2         # radians of ring brightened at level 3

var level := 1:
	set(value):
		level = clampi(value, 1, 3)
		queue_redraw()


func _draw() -> void:
	var color := THEME.get_color(([&"g4", &"g5", &"g6"] as Array)[level - 1], &"MechTokens")
	for i in level:
		var base := -(FIRST + STEP * i)
		draw_polyline(PackedVector2Array([
			Vector2(-HALF_WIDTH, base), Vector2(0, base - HEIGHT), Vector2(HALF_WIDTH, base),
		]), color, 2.0, true)
	if level == 3:
		draw_arc(Vector2.ZERO, RING_RADIUS, -PI / 2 - ARC, -PI / 2 + ARC, 12, color, 2.0, true)
