@tool
class_name PropSpawner
extends Node2D

# Decides where props go on a map. It merges three sources into one list:
#
#   spawn_set         points the map generator placed by rule (parked cars
#                     along kerbs, trees along main roads, bushes by houses).
#   PropZone children hand-drawn areas: CLEAR removes generated points inside
#                     them, SCATTER adds more points inside them.
#   PropSpawnPoint    single hand-placed points, each with a chance.
#   children
#
# Nothing is instanced yet. get_spawns() returns the merged list, and
# spawns_in_rect() gives the ones in an area, for a streamer that creates
# props near the player. Markers show every spawn in the editor (and in game
# with show_markers_in_game) so placement can be checked.
#
# Each spawn is a Dictionary: kind (String), position (Vector2, this node's
# space), rotation (float), size (Vector2 px), source ("generated", "zone" or
# "manual"), variant (int, -1 when not chosen). spawns_changed is emitted
# whenever the list is rebuilt.

signal spawns_changed

const DEFAULT_SIZE := {
	"vehicle": Vector2(88, 36), "truck": Vector2(170, 50), "vehicle_wreck": Vector2(88, 38),
	"tree": Vector2(240, 240), "bush": Vector2(60, 60),
	"debris": Vector2(24, 24),
}
const MARKER_COLOR := {
	"vehicle": Color(1.0, 0.78, 0.25), "truck": Color(1.0, 0.55, 0.1),
	"vehicle_wreck": Color(1.0, 0.3, 0.3), "tree": Color(0.35, 0.9, 0.45),
	"bush": Color(0.65, 1.0, 0.6),
	"debris": Color(0.75, 0.75, 0.75),
}
const CELL_SIZE := 2000.0

@export var spawn_set: PropSpawnSet:
	set(value):
		spawn_set = value
		mark_dirty()
## Used to keep SCATTER zone points out of buildings.
@export var building_field: BuildingField
## Changes which hand-placed points roll in and where zones scatter.
@export var map_seed := 1:
	set(value):
		map_seed = value
		mark_dirty()
@export var show_markers := true:
	set(value):
		show_markers = value
		queue_redraw()
@export var show_markers_in_game := false:
	set(value):
		show_markers_in_game = value
		queue_redraw()

var _spawns: Array = []
var _cells := {}
var _dirty := true
var _signature := 0
var _check_timer := 0.0


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Zones and points have no change signal for edited outlines, so check
		# a signature of them twice a second.
		_check_timer -= delta
		if _check_timer <= 0.0:
			_check_timer = 0.5
			var sig := _children_signature()
			if sig != _signature:
				_signature = sig
				_dirty = true
	if _dirty:
		_rebuild()


func mark_dirty() -> void:
	_dirty = true


func get_spawns() -> Array:
	if _dirty:
		_rebuild()
	return _spawns


func spawns_in_rect(rect: Rect2) -> Array:
	if _dirty:
		_rebuild()
	var out := []
	var c0 := _cell_of(rect.position)
	var c1 := _cell_of(rect.end)
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for i in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if rect.has_point(_spawns[i].position):
					out.append(_spawns[i])
	return out


func _rebuild() -> void:
	_dirty = false
	_spawns.clear()
	var clears: Array[PropZone] = []
	var scatters: Array[PropZone] = []
	var manual: Array[PropSpawnPoint] = []
	for child in get_children():
		if child is PropZone:
			(clears if child.mode == PropZone.Mode.CLEAR else scatters).append(child)
		elif child is PropSpawnPoint:
			manual.append(child)
	var clear_outlines := clears.map(func(z): return z.outline())
	if spawn_set:
		for i in spawn_set.count():
			var k: String = spawn_set.kinds[spawn_set.kind[i]]
			var p: Vector2 = spawn_set.position[i]
			if _cleared(k, p, clears, clear_outlines):
				continue
			var v := spawn_set.variant[i] if i < spawn_set.variant.size() else -1
			_spawns.append({"kind": k, "position": p, "rotation": spawn_set.rotation[i],
				"size": spawn_set.size[i], "source": "generated", "variant": v})
	for z in scatters:
		_scatter(z)
	for m in manual:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([map_seed, m.name])
		if rng.randf() > m.chance:
			continue
		_spawns.append({"kind": m.kind, "position": m.position, "rotation": m.rotation,
			"size": m.size if m.size != Vector2.ZERO else DEFAULT_SIZE.get(m.kind, Vector2(40, 40)),
			"source": "manual", "variant": m.variant})
	_cells.clear()
	for i in _spawns.size():
		var key := _cell_of(_spawns[i].position)
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(i)
	queue_redraw()
	spawns_changed.emit()


func _cleared(k: String, p: Vector2, zones: Array[PropZone], outlines: Array) -> bool:
	for j in zones.size():
		if zones[j].applies_to(k) and Geometry2D.is_point_in_polygon(p, outlines[j]):
			return true
	return false


func _scatter(z: PropZone) -> void:
	var poly := z.outline()
	if poly.size() < 3 or z.kinds.is_empty() or z.min_spacing <= 0.0:
		return
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([map_seed, z.name, z.zone_seed])
	var cell := z.min_spacing
	var keep := clampf(z.density * cell * cell / 40000.0, 0.0, 1.0)
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			if rng.randf() < keep:
				var p := Vector2(x + rng.randf() * cell * 0.7, y + rng.randf() * cell * 0.7)
				if Geometry2D.is_point_in_polygon(p, poly) and not _in_building(p):
					var k: String = z.kinds[rng.randi() % z.kinds.size()]
					_spawns.append({"kind": k, "position": p, "rotation": rng.randf() * TAU,
						"size": DEFAULT_SIZE.get(k, Vector2(40, 40)), "source": "zone", "variant": -1})
			x += cell
		y += cell


func _in_building(p: Vector2) -> bool:
	if building_field == null or not building_field.is_inside_tree():
		return false
	return not building_field.buildings_near(building_field.to_local(to_global(p)), 20.0).is_empty()


func _children_signature() -> int:
	var parts := []
	for child in get_children():
		if child is PropZone:
			parts.append([child.name, child.transform, child.polygon, child.mode, child.kinds, child.density])
		elif child is PropSpawnPoint:
			parts.append([child.name, child.transform, child.kind, child.chance])
	return hash(parts)


func _draw() -> void:
	if not show_markers or (not Engine.is_editor_hint() and not show_markers_in_game):
		return
	for s in _spawns:
		var col: Color = MARKER_COLOR.get(s.kind, Color.WHITE)
		var width := 6.0 if s.source == "manual" else 3.0
		if s.source != "generated":
			col = col.lightened(0.4)
		var half: Vector2 = s.size / 2.0
		if s.kind in ["tree", "bush"]:
			draw_arc(s.position, half.x, 0.0, TAU, 16 if s.kind == "tree" else 8, col, width)
		else:
			var xf := Transform2D(s.rotation, s.position)
			var corners := PackedVector2Array([
				xf * Vector2(-half.x, -half.y), xf * Vector2(half.x, -half.y),
				xf * Vector2(half.x, half.y), xf * Vector2(-half.x, half.y), xf * Vector2(-half.x, -half.y)])
			draw_polyline(corners, col, width)
			if s.kind != "debris":
				draw_line(xf * Vector2(half.x * 0.5, -half.y), xf * Vector2(half.x * 0.5, half.y), col, width)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
