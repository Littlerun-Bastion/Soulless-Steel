@tool
class_name OverheadPath
extends Line2D

# A visual-only elevated structure (viaduct, overpass, conveyor gantry) along
# this line's points. Edit the points with Godot's Line2D tools; the structure
# rebuilds itself in the editor.
#
# Nothing collides with it. The deck draws above mechas (give this node a
# z_index above the roofs). The deck is cut into sections; a section the
# player is under fades to ghost_alpha so the player stays visible. Piers are
# drawn at ground level (below mechas), so they show when the deck fades.
#
# The Line2D's own stroke is hidden: only the built structure draws.

const FADE_SPEED := 3.0

@export var deck_width := 200.0:
	set(value):
		deck_width = value
		_dirty = true
## Length of each fading section, in px.
@export var section_length := 1000.0:
	set(value):
		section_length = maxf(value, 100.0)
		_dirty = true
@export_range(0.0, 1.0) var deck_value := 0.06:
	set(value):
		deck_value = value
		_dirty = true
## Width of the soft shadow round the deck, in px.
@export var shadow_width := 120.0:
	set(value):
		shadow_width = value
		_dirty = true
@export var joint_spacing := 500.0:
	set(value):
		joint_spacing = value
		_dirty = true
## Distance between piers along the path, in px; 0 for no piers.
@export var pier_spacing := 600.0:
	set(value):
		pier_spacing = value
		_dirty = true
@export var pier_size := Vector2(60, 90):
	set(value):
		pier_size = value
		_dirty = true
@export_range(0.0, 1.0) var ghost_alpha := 0.25
## How far (px) beyond a section's deck the player still fades it.
@export var fade_margin := 60.0

var _dirty := true
var _last_points := PackedVector2Array()
# One entry per section: {node, hull, rect}.
var _sections: Array = []
var _piers: Node2D


func _ready() -> void:
	self_modulate = Color(1, 1, 1, 0)
	_rebuild()


func _process(delta: float) -> void:
	if points != _last_points:
		_dirty = true
	if _dirty:
		_rebuild()
	if Engine.is_editor_hint():
		return
	var player = _find_player()
	var at := to_local(player.global_position) if player else Vector2.INF
	for s in _sections:
		var under: bool = player != null and s.rect.has_point(at) and Geometry2D.is_point_in_polygon(at, s.hull)
		var node: Node2D = s.node
		node.modulate.a = move_toward(node.modulate.a, ghost_alpha if under else 1.0, FADE_SPEED * delta)


func _find_player():
	for m in get_tree().get_nodes_in_group("mecha"):
		if m.has_method("is_player") and m.is_player():
			return m
	return null


func _rebuild() -> void:
	_dirty = false
	_last_points = points.duplicate()
	for s in _sections:
		s.node.queue_free()
	_sections.clear()
	if _piers:
		_piers.queue_free()
		_piers = null
	if points.size() < 2:
		return
	for part in _split(points, section_length):
		_sections.append(_build_section(part))
	if pier_spacing > 0.0:
		_piers = _build_piers()


func _build_section(part: PackedVector2Array) -> Dictionary:
	var half := deck_width / 2.0
	var m := _MeshBuilder.new()
	for k in [1.0, 0.66, 0.33]:
		for poly in Geometry2D.offset_polyline(part, half + shadow_width * k, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT):
			m.polygon(poly, Color(0, 0, 0, 0.18))
	var deck: Array = Geometry2D.offset_polyline(part, half, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT)
	for poly in deck:
		m.polygon(poly, Color(deck_value, deck_value, deck_value))
	for d in [-half + 12.0, half - 12.0]:
		m.line(_offset_curve(part, d), 3.5, Color(0.2, 0.2, 0.2))
	for d in [-half, half]:
		m.line(_offset_curve(part, d), 7.0, Color(0.38, 0.38, 0.38))
	for t in _stations(part, joint_spacing, joint_spacing / 2.0):
		var p: Vector2 = t[0]
		var n: Vector2 = t[1] * (half - 12.0)
		m.line(PackedVector2Array([p - n, p + n]), 2.5, Color(0.13, 0.13, 0.13))
	var node := _mesh_node(m.build())
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	var hull := PackedVector2Array()
	var rect := Rect2()
	if not deck.is_empty():
		var grown: Array = Geometry2D.offset_polygon(deck[0], fade_margin)
		hull = grown[0] if not grown.is_empty() else deck[0]
		rect = Rect2(hull[0], Vector2.ZERO)
		for p in hull:
			rect = rect.expand(p)
	return {"node": node, "hull": hull, "rect": rect}


func _build_piers() -> Node2D:
	var m := _MeshBuilder.new()
	for t in _stations(points, pier_spacing, pier_spacing / 2.0):
		var p: Vector2 = t[0]
		var n: Vector2 = t[1]
		var u := Vector2(-n.y, n.x)
		var a := u * pier_size.y / 2.0
		var b := n * pier_size.x / 2.0
		var q := PackedVector2Array([p - a - b, p + a - b, p + a + b, p - a + b])
		for k in [1.0, 0.5]:
			for halo in Geometry2D.offset_polygon(q, 40.0 * k):
				m.polygon(halo, Color(0, 0, 0, 0.3))
		m.polygon(q, Color(0.05, 0.05, 0.05))
		var outline := q.duplicate()
		outline.append(q[0])
		m.line(outline, 5.0, Color(0.38, 0.38, 0.38))
	var node := _mesh_node(m.build())
	# Ground level: below the mechas and roofs, whatever this node's z_index.
	node.z_as_relative = false
	node.z_index = 0
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
	return node


# A node that draws one mesh: one draw call however many shapes it holds.
static func _mesh_node(mesh: ArrayMesh) -> Node2D:
	var node := Node2D.new()
	node.draw.connect(func():
		if mesh.get_surface_count() > 0:
			node.draw_mesh(mesh, null))
	return node


# Collects filled shapes, in draw order, into one vertex-coloured mesh.
class _MeshBuilder:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()

	func polygon(poly: PackedVector2Array, col: Color) -> void:
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in idx:
			verts.append(poly[i])
			colors.append(col)

	func line(pts: PackedVector2Array, width: float, col: Color) -> void:
		for poly in Geometry2D.offset_polyline(pts, width / 2.0, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT):
			polygon(poly, col)

	func build() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


# Cuts a polyline into pieces of about `length` px; neighbouring pieces share
# their end points.
static func _split(pts: PackedVector2Array, length: float) -> Array:
	var out := []
	var cur := PackedVector2Array([pts[0]])
	var run := 0.0
	for i in range(1, pts.size()):
		var a := cur[cur.size() - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		while run + seg >= length:
			var cut := a.lerp(b, (length - run) / seg)
			cur.append(cut)
			out.append(cur)
			cur = PackedVector2Array([cut])
			seg = cut.distance_to(b)
			a = cut
			run = 0.0
		cur.append(b)
		run += seg
	if cur.size() > 1 and run > 1.0:
		out.append(cur)
	return out


# Points every `spacing` px along a polyline, starting at `start`, as
# [position, unit normal].
static func _stations(pts: PackedVector2Array, spacing: float, start: float) -> Array:
	var out := []
	if spacing <= 0.0:
		return out
	var next := start
	var walked := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var dir := (b - a) / seg
		while next <= walked + seg:
			out.append([a + dir * (next - walked), Vector2(-dir.y, dir.x)])
			next += spacing
		walked += seg
	return out


# The polyline moved sideways by d px (positive to the left of travel).
static func _offset_curve(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var prev_dir := (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var next_dir := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else Vector2.ZERO
		var dir := (prev_dir + next_dir).normalized()
		if dir == Vector2.ZERO:
			dir = next_dir if next_dir != Vector2.ZERO else prev_dir
		var normal := Vector2(-dir.y, dir.x)
		var scale := 1.0
		if prev_dir != Vector2.ZERO and next_dir != Vector2.ZERO:
			scale = 1.0 / maxf(normal.dot(Vector2(-next_dir.y, next_dir.x)), 0.5)
		out.append(pts[i] + normal * d * scale)
	return out
