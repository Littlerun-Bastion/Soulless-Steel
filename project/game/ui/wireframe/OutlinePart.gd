class_name OutlinePart
extends Node2D

## One part of the HUD frame readout, drawn as an outline (no sprite).
## state follows WireframeDisplay's part states:
##   3 full      S1 G5 outline
##   2 okay      S1 G5 outline over G4 hatching clipped to the shape
##   1 critical  S2 G6 outline, blinking
##   0 dead      S1 G3 dashed outline
##  -1 gone      not drawn
## mirror draws the outline with x negated (the right shoulder and leg use
## the left outlines). Colours come from MechTokens in MechTheme.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const HATCH_STEP := 3.0
const DASH := 3.0
const GAP := 2.0
const BLINK_TIME := 0.25

var outline := PackedVector2Array():
	set(value):
		outline = value
		_rebuild()
var mirror := false:
	set(value):
		mirror = value
		_rebuild()
var state := 3:
	set(value):
		state = value
		visible = value >= 0
		_blink_on = true
		_blink_time = 0.0
		set_process(value == 1)
		queue_redraw()
var antialiased := false:
	set(value):
		antialiased = value
		queue_redraw()

var _points := PackedVector2Array()   # outline as drawn (mirrored if needed)
var _hatch: Array = []                # clipped hatch segments for state 2
var _blink_on := true
var _blink_time := 0.0


func _ready() -> void:
	set_process(state == 1)


func _process(delta: float) -> void:
	_blink_time += delta
	if _blink_time >= BLINK_TIME:
		_blink_time -= BLINK_TIME
		_blink_on = not _blink_on
		queue_redraw()


func _draw() -> void:
	if _points.size() < 3:
		return
	match state:
		3:
			_draw_closed(_color(&"g5"), 1.0)
		2:
			var g4 := _color(&"g4")
			for segment in _hatch:
				draw_polyline(segment, g4, 1.0, antialiased)
			_draw_closed(_color(&"g5"), 1.0)
		1:
			if _blink_on:
				_draw_closed(_color(&"g6"), 2.0)
		0:
			_draw_dashed(_color(&"g3"))


func _draw_closed(color: Color, width: float) -> void:
	var closed := _points.duplicate()
	closed.append(_points[0])
	draw_polyline(closed, color, width, antialiased)


# Dashes run on round the corners, so the pattern stays even.
func _draw_dashed(color: Color) -> void:
	var on := true
	var left := DASH
	for i in _points.size():
		var a := _points[i]
		var b := _points[(i + 1) % _points.size()]
		var length := a.distance_to(b)
		var done := 0.0
		while done < length:
			var step := minf(left, length - done)
			if on:
				draw_line(a.lerp(b, done / length), a.lerp(b, (done + step) / length), color, 1.0, antialiased)
			done += step
			left -= step
			if left <= 0.0:
				on = not on
				left = DASH if on else GAP


func _rebuild() -> void:
	_points = PackedVector2Array()
	for p in outline:
		_points.append(Vector2(-p.x, p.y) if mirror else p)
	if mirror:
		_points.reverse()
	_hatch = _make_hatch(_points)
	queue_redraw()


# Diagonal lines every HATCH_STEP px, cut to the inside of the outline.
static func _make_hatch(points: PackedVector2Array) -> Array:
	var segments: Array = []
	if points.size() < 3:
		return segments
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	var c := box.position.x + box.position.y
	var end := box.end.x + box.end.y
	while c <= end:
		# The line x + y = c across the box.
		var line := PackedVector2Array([Vector2(c - box.end.y, box.end.y), Vector2(c - box.position.y, box.position.y)])
		segments.append_array(Geometry2D.intersect_polyline_with_polygon(line, points))
		c += HATCH_STEP
	return segments


static func _color(token: StringName) -> Color:
	return THEME.get_color(token, &"MechTokens")
