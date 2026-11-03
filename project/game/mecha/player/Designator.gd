extends Node2D

# Draws the player's shoulder weapon designators in world space. Player puts
# it on its own CanvasLayer that follows the camera, above the IR heatmap
# layer, so the IR colour map doesn't tint it. Player fills `marks` each
# physics frame while a fire button is held (Player._update_designators);
# this node only draws them.
#
# Each mark is a Dictionary:
#   shape        weapon.designator: circle, line, line_box, rect, point
#   centre       the mecha's position; range arcs are drawn round it
#   origin       the weapon's muzzle
#   point        where the salvo is aimed
#   end          where the designator stops: `point`, or for direct fire
#                the first wall or solid body on the way
#   radius       scatter radius: the circle's radius, or half the side of a
#                line_box's landing box
#   width        a rect's width (the laser beam)
#   facing       the mecha's facing (unit vector)
#   gimbal       degrees either side of facing the weapon can aim
#   min_range, max_range
#   look_limits  the SYS setting; with it on the range arcs span the gimbal
#   direct       direct fire: a line runs from the muzzle to `end`
#   dashed       the weapon can't fire at the point now (out of the look
#                angle, reloading, indoors...): drawn in the disabled style
# Strokes are the theme's S1/S2 in screen pixels, whatever the zoom.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const MIN_CIRCLE_RADIUS := 30.0
const CROSS_SIZE := 12.0
const BOX_SIZE := 24.0
const DASH := 10.0
const ARC_POINTS := 48

var marks: Array[Dictionary] = []


func set_marks(new_marks: Array[Dictionary]) -> void:
	if marks.is_empty() and new_marks.is_empty():
		return
	marks = new_marks
	queue_redraw()


func _draw() -> void:
	if marks.is_empty():
		return
	var px := 1.0 / maxf(get_viewport().get_canvas_transform().get_scale().x, 0.01)
	var s1 := THEME.get_constant(&"s1", &"MechTokens") * px
	var s2 := THEME.get_constant(&"s2", &"MechTokens") * px
	var bright := THEME.get_color(&"g5", &"MechTokens")
	var dim := THEME.get_color(&"g4", &"MechTokens")
	var faint := THEME.get_color(&"g3", &"MechTokens")
	for mark in marks:
		var dashed: bool = mark.dashed
		var color := dim if dashed else bright
		var width := s1 if dashed else s2
		_draw_range_arcs(mark, faint, s1, px)
		var origin: Vector2 = mark.origin
		var end: Vector2 = mark.end
		if mark.shape == "rect":
			_rect(origin, end, maxf(mark.width, s2), color, width, dashed, px)
		elif mark.direct or mark.shape == "line" or mark.shape == "line_box":
			_line(origin, end, dim if mark.shape == "circle" else color, s1 if mark.shape == "circle" else width, dashed, px)
		if mark.shape == "circle":
			_circle(end, maxf(mark.radius, MIN_CIRCLE_RADIUS), color, width, dashed, px)
			_cross(end, CROSS_SIZE * px, color, width)
		elif mark.shape == "line_box":
			_box(end, maxf(mark.radius * 2.0, BOX_SIZE * px), origin.direction_to(end), color, width, dashed, px)
		elif mark.shape == "point":
			_box(end, BOX_SIZE * px, origin.direction_to(end), color, width, dashed, px)
		elif mark.shape == "line":
			_cross(end, CROSS_SIZE * px, color, width)


# The min and max range, faint: across the gimbal with look limits on, all
# round without.
func _draw_range_arcs(mark: Dictionary, color: Color, width: float, px: float) -> void:
	var centre: Vector2 = mark.centre
	var facing: Vector2 = mark.facing
	var half := deg_to_rad(mark.gimbal) if mark.look_limits else PI
	for r in [mark.min_range, mark.max_range]:
		if r <= 0.0:
			continue
		draw_arc(centre, r, facing.angle() - half, facing.angle() + half, ARC_POINTS, color, width)
	if mark.look_limits:
		for side in [-half, half]:
			var dir := facing.rotated(side)
			_line(centre + dir * mark.min_range, centre + dir * mark.max_range, color, width, true, px)


func _line(a: Vector2, b: Vector2, color: Color, width: float, dashed: bool, px: float) -> void:
	if dashed:
		draw_dashed_line(a, b, color, width, DASH * px)
	else:
		draw_line(a, b, color, width)


func _circle(centre: Vector2, radius: float, color: Color, width: float, dashed: bool, px: float) -> void:
	if not dashed:
		draw_arc(centre, radius, 0.0, TAU, ARC_POINTS, color, width)
		return
	var dashes := maxi(int(TAU * radius / (DASH * px * 2.0)), 4)
	var step := TAU / dashes
	for i in dashes:
		draw_arc(centre, radius, i * step, i * step + step * 0.5, 4, color, width)


func _cross(centre: Vector2, size: float, color: Color, width: float) -> void:
	draw_line(centre - Vector2(size, 0), centre + Vector2(size, 0), color, width)
	draw_line(centre - Vector2(0, size), centre + Vector2(0, size), color, width)


# The laser's beam: a rectangle `size` wide from `a` to `b`.
func _rect(a: Vector2, b: Vector2, size: float, color: Color, width: float, dashed: bool, px: float) -> void:
	var side := a.direction_to(b).orthogonal() * size * 0.5
	if side == Vector2.ZERO:
		return
	var corners := [a - side, b - side, b + side, a + side]
	for i in 4:
		_line(corners[i], corners[(i + 1) % 4], color, width, dashed, px)


func _box(centre: Vector2, size: float, dir: Vector2, color: Color, width: float, dashed: bool, px: float) -> void:
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var half_a := dir * size * 0.5
	var half_b := dir.orthogonal() * size * 0.5
	var corners := [centre - half_a - half_b, centre + half_a - half_b, centre + half_a + half_b, centre - half_a + half_b]
	for i in 4:
		_line(corners[i], corners[(i + 1) % 4], color, width, dashed, px)
