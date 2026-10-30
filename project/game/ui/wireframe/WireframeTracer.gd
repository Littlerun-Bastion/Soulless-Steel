class_name WireframeTracer
extends RefCounted

## Turns the wireframe sprites into outline paths (spec: "Vector frame readout").
## For each part it takes the thin single-line sprite (state 1), fills the
## inside, traces the outer edge (BitMap.opaque_to_polygons), moves it in by
## half the line width so it runs down the middle of the drawn line, then
## scales it to HUD size and drops points that add nothing.
##
## Run it again (TraceWireframes.gd, File > Run) only if the sprites change.

const SPRITE_DIR := "res://assets/images/ui/player_ui/"
const SOURCES := {
	"core": "ui_core_wireframe_1.png",
	"head": "ui_head_wireframe_1.png",
	"shoulder": "ui_shoulder_wireframe_1.png",
	"chassis_leg": "ui_chassis_leg_wireframe_1.png",
	"chassis_single": "ui_chassis_single_wireframe_1.png",
	"weapon": "ui_weapon_wireframe_1.png",
}
const SCALE := 0.4         # sprite px to HUD px; the display itself is drawn 1:1
const SIMPLIFY := 1.5      # sprite px: the traced pixel steps within this of a straight line go


static func trace_all() -> WireframeOutlines:
	var result := WireframeOutlines.new()
	for part in SOURCES:
		var outline := trace(SPRITE_DIR + SOURCES[part])
		if outline.is_empty():
			push_error("WireframeTracer: couldn't trace %s" % SOURCES[part])
		result.parts[part] = outline
	return result


static func trace(path: String) -> PackedVector2Array:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return PackedVector2Array()
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()

	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if image.get_pixel(x, y).a >= 0.5 else 0

	# Fill the inside: everything the outside can't reach is the silhouette.
	var outside := _flood_outside(solid, w, h)
	var bitmap := BitMap.new()
	bitmap.create(Vector2i(w, h))
	for y in h:
		for x in w:
			bitmap.set_bit(x, y, outside[y * w + x] == 0)
	var polygons := bitmap.opaque_to_polygons(Rect2i(0, 0, w, h), 0.5)
	var outer := _largest(polygons)
	if outer.is_empty():
		return outer
	# The trace follows pixel steps; straighten them before anything else,
	# so the chamfers come out as single diagonal edges.
	outer = _simplify_closed(outer, SIMPLIFY)

	# Down the middle of the drawn line.
	var inset := _line_width(solid, w, h) * 0.5
	if inset > 0.0:
		var shrunk := Geometry2D.offset_polygon(outer, -inset, Geometry2D.JOIN_MITER)
		if not shrunk.is_empty():
			outer = _largest(shrunk)

	var centre := Vector2(w, h) * 0.5
	var scaled := PackedVector2Array()
	for p in outer:
		scaled.append((p - centre) * SCALE)
	return scaled


static func _flood_outside(solid: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var outside := PackedByteArray()
	outside.resize(w * h)
	var queue: Array[int] = []
	for x in w:
		queue.append(x)
		queue.append((h - 1) * w + x)
	for y in h:
		queue.append(y * w)
		queue.append(y * w + w - 1)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		if outside[i] == 1 or solid[i] == 1:
			continue
		outside[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: queue.append(i - 1)
		if x < w - 1: queue.append(i + 1)
		if y > 0: queue.append(i - w)
		if y < h - 1: queue.append(i + w)
	return outside


# Width of the outermost line, read across the middle row from the left.
static func _line_width(solid: PackedByteArray, w: int, h: int) -> float:
	var y := h / 2
	var run := 0
	for x in w:
		if solid[y * w + x] == 1:
			run += 1
		elif run > 0:
			break
	return float(run)


static func _largest(polygons: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for poly in polygons:
		var area := absf(_area(poly))
		if area > best_area:
			best_area = area
			best = poly
	return best


static func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * 0.5


# Ramer-Douglas-Peucker on a closed outline: split it at the point farthest
# from the first, simplify both halves, join them again.
static func _simplify_closed(poly: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if poly.size() < 4:
		return poly
	# Start at the bottom-right corner, a real corner on every part, so no
	# straight edge is split at a stray point.
	var start := 0
	for i in poly.size():
		if poly[i].x + poly[i].y > poly[start].x + poly[start].y:
			start = i
	poly = poly.slice(start) + poly.slice(0, start)
	var far := 0
	var far_d := -1.0
	for i in poly.size():
		var d := poly[0].distance_squared_to(poly[i])
		if d > far_d:
			far_d = d
			far = i
	var first := poly.slice(0, far + 1)
	var second := poly.slice(far)
	second.append(poly[0])
	var a := _rdp(first, tolerance)
	var b := _rdp(second, tolerance)
	a.remove_at(a.size() - 1)   # shared with b's start
	b.remove_at(b.size() - 1)   # back to poly[0]
	a.append_array(b)
	# The split point may sit in the middle of a straight edge: drop points
	# that don't turn the line.
	var result := PackedVector2Array()
	for i in a.size():
		var prev := a[(i - 1 + a.size()) % a.size()]
		var next := a[(i + 1) % a.size()]
		if a[i].distance_to(Geometry2D.get_closest_point_to_segment(a[i], prev, next)) > 0.25:
			result.append(a[i])
	return result


static func _rdp(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var start := points[0]
	var end := points[points.size() - 1]
	var index := 0
	var worst := 0.0
	for i in range(1, points.size() - 1):
		var d := points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], start, end))
		if d > worst:
			worst = d
			index = i
	if worst <= tolerance:
		return PackedVector2Array([start, end])
	var left := _rdp(points.slice(0, index + 1), tolerance)
	var right := _rdp(points.slice(index), tolerance)
	left.remove_at(left.size() - 1)
	left.append_array(right)
	return left
