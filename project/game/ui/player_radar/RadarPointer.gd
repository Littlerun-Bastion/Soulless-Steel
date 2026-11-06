extends RefCounted

## How the radar (PlayerRadar) draws one track: its mark, its chevrons and
## the bracket of the player's own lock. Each draws on `canvas` at `at` (the
## mark's centre, on or outside the ring) for a track at `bearing` (radians:
## the mark points outward along it).
##   triangle  a mech        diamond  an Entity
##   square    UNKNOWN (IR)  round    an alarm
## A hollow mark (a ghost) is drawn as its outline.
## Chevrons sit outside the mark, CHEVRON_STEP px apart: more is closer.
## The bracket turns with the bearing and stays inside the first chevron.

## Placeholders (px).
const MARK_SIZE := 6.0
const CHEVRON_FIRST := 10.0
const CHEVRON_STEP := 5.0
const CHEVRON_HALF := 6.0
const CHEVRON_HEIGHT := 3.0
## Half the bracket's size out along the bearing and across it, and its
## corners' leg length.
const BRACKET_DEPTH := 8.0
const BRACKET_WIDTH := 9.0
const BRACKET_LEG := 4.0
const LINE := 2.0


static func draw_mark(canvas: CanvasItem, at: Vector2, bearing: float, shape: String, color: Color, hollow: bool) -> void:
	var out := Vector2.from_angle(bearing)
	var side := out.orthogonal()
	var points: PackedVector2Array
	match shape:
		"triangle":
			points = PackedVector2Array([at + out * MARK_SIZE, at - out * MARK_SIZE * 0.7 + side * MARK_SIZE * 0.8,
					at - out * MARK_SIZE * 0.7 - side * MARK_SIZE * 0.8])
		"square":
			var s := MARK_SIZE * 0.75
			points = PackedVector2Array([at + (out + side) * s, at + (out - side) * s, at - (out + side) * s, at - (out - side) * s])
		"round":
			if hollow:
				canvas.draw_arc(at, MARK_SIZE * 0.8, 0.0, TAU, 16, color, LINE, true)
			else:
				canvas.draw_circle(at, MARK_SIZE * 0.8, color)
			return
		_:
			points = PackedVector2Array([at + out * MARK_SIZE, at + side * MARK_SIZE * 0.7, at - out * MARK_SIZE,
					at - side * MARK_SIZE * 0.7])
	if hollow:
		var loop := points.duplicate()
		loop.append(points[0])
		canvas.draw_polyline(loop, color, LINE, true)
	else:
		canvas.draw_colored_polygon(points, color)


static func draw_chevrons(canvas: CanvasItem, at: Vector2, bearing: float, count: int, color: Color) -> void:
	var out := Vector2.from_angle(bearing)
	var side := out.orthogonal()
	for i in count:
		var base := at + out * (CHEVRON_FIRST + CHEVRON_STEP * i)
		canvas.draw_polyline(PackedVector2Array([base - side * CHEVRON_HALF, base + out * CHEVRON_HEIGHT,
				base + side * CHEVRON_HALF]), color, LINE, true)


static func draw_bracket(canvas: CanvasItem, at: Vector2, bearing: float, color: Color) -> void:
	var out := Vector2.from_angle(bearing)
	var side := out.orthogonal()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var along: Vector2 = out * corner.x
		var across: Vector2 = side * corner.y
		var tip: Vector2 = at + along * BRACKET_DEPTH + across * BRACKET_WIDTH
		canvas.draw_polyline(PackedVector2Array([tip - along * BRACKET_LEG, tip, tip - across * BRACKET_LEG]), color, LINE, true)
