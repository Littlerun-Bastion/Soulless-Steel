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
# Nothing is instanced yet. The merged list is held in packed arrays, one
# value per spawn (a big map has tens of thousands of spawns, and a
# Dictionary per spawn costs tens of MB): spawn i has spawn_kind(i),
# spawn_position(i) (this node's space), spawn_rotation(i), spawn_size(i)
# (px), spawn_variant(i) (-1 when not chosen) and spawn_source(i)
# ("generated", "zone" or "manual"). indices_of_kinds() and indices_in_rect()
# find spawns without building anything. get_spawns(), spawn() and
# spawns_in_rect() give Dictionaries with the same fields, built when asked,
# for tools and tests. Markers show every spawn in the editor (and in game
# with show_markers_in_game) so placement can be checked. spawns_changed is
# emitted whenever the list is rebuilt.
#
# kept_share thins the generated points of chosen kinds (fewer parked cars,
# say) without regenerating the map.
#
# With no CLEAR zone and nothing thinned, the generated points are taken over
# as they are (packed arrays are shared until written), so a big map loads
# its spawns at once.

signal spawns_changed

const DEFAULT_SIZE := {
	"vehicle": Vector2(88, 36), "truck": Vector2(170, 50), "vehicle_wreck": Vector2(88, 38),
	"tree": Vector2(240, 240), "bush": Vector2(60, 60),
	"debris": Vector2(24, 24),
	"stall": Vector2(60, 50), "bus": Vector2(240, 50), "military": Vector2(180, 72),
	"container": Vector2(122, 49),
	"hut": Vector2(120, 60), "clutter": Vector2(40, 40),
}
const MARKER_COLOR := {
	"vehicle": Color(1.0, 0.78, 0.25), "truck": Color(1.0, 0.55, 0.1),
	"vehicle_wreck": Color(1.0, 0.3, 0.3), "tree": Color(0.35, 0.9, 0.45),
	"bush": Color(0.65, 1.0, 0.6),
	"debris": Color(0.75, 0.75, 0.75),
	"stall": Color(0.95, 0.5, 0.85), "bus": Color(1.0, 0.65, 0.2),
	"hut": Color(0.8, 0.45, 0.95), "clutter": Color(0.6, 0.6, 0.7),
	"military": Color(0.7, 0.8, 0.35), "container": Color(0.4, 0.7, 1.0),
}
const CELL_SIZE := 2000.0
const SOURCES := ["generated", "zone", "manual"]
enum { GENERATED, ZONE, MANUAL }

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
## Share of each kind's generated spawns that are kept (kind -> 0..1, for
## example {"vehicle": 0.7} for fewer parked cars); kinds not listed keep
## all of theirs. Which spawns go is fixed by map_seed and each spawn's place
## in spawn_set, so the same ones go every time.
@export var kept_share: Dictionary[String, float] = {}:
	set(value):
		kept_share = value
		mark_dirty()
@export var show_markers := true:
	set(value):
		show_markers = value
		queue_redraw()
@export var show_markers_in_game := false:
	set(value):
		show_markers_in_game = value
		queue_redraw()

var _kind_names := PackedStringArray()
var _kind_ids := {}
var _s_kind := PackedByteArray()
var _s_pos := PackedVector2Array()
var _s_rot := PackedFloat32Array()
var _s_size := PackedVector2Array()
var _s_variant := PackedInt32Array()
var _s_source := PackedByteArray()
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


func _ensure_built() -> void:
	if _dirty:
		_rebuild()


func spawn_count() -> int:
	_ensure_built()
	return _s_pos.size()


func spawn_kind(i: int) -> String:
	return _kind_names[_s_kind[i]]


## The kind's id (spawn_kind_id compares with it), or -1 if no spawn has it.
func kind_id(kind: String) -> int:
	_ensure_built()
	return _kind_ids.get(kind, -1)


func spawn_kind_id(i: int) -> int:
	return _s_kind[i]


func spawn_position(i: int) -> Vector2:
	return _s_pos[i]


func spawn_rotation(i: int) -> float:
	return _s_rot[i]


func spawn_size(i: int) -> Vector2:
	return _s_size[i]


func spawn_variant(i: int) -> int:
	return _s_variant[i]


func spawn_source(i: int) -> String:
	return SOURCES[_s_source[i]]


## Spawn i as a Dictionary (kind, position, rotation, size, source, variant).
func spawn(i: int) -> Dictionary:
	_ensure_built()
	return {"kind": spawn_kind(i), "position": _s_pos[i], "rotation": _s_rot[i],
		"size": _s_size[i], "source": spawn_source(i), "variant": _s_variant[i]}


## Indices of every spawn of the given kinds, in list order.
func indices_of_kinds(kinds: PackedStringArray) -> PackedInt32Array:
	_ensure_built()
	var wanted := PackedByteArray()
	wanted.resize(_kind_names.size())
	for k in kinds:
		if _kind_ids.has(k):
			wanted[_kind_ids[k]] = 1
	var out := PackedInt32Array()
	for i in _s_kind.size():
		if wanted[_s_kind[i]] == 1:
			out.append(i)
	return out


## Indices of the spawns inside `rect` (this node's space).
func indices_in_rect(rect: Rect2) -> PackedInt32Array:
	_ensure_built()
	var out := PackedInt32Array()
	var c0 := _cell_of(rect.position)
	var c1 := _cell_of(rect.end)
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for i in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if rect.has_point(_s_pos[i]):
					out.append(i)
	return out


## Every spawn as a Dictionary, built now (tools and tests; game code uses
## the packed accessors).
func get_spawns() -> Array:
	_ensure_built()
	var out := []
	for i in _s_pos.size():
		out.append(spawn(i))
	return out


func spawns_in_rect(rect: Rect2) -> Array:
	var out := []
	for i in indices_in_rect(rect):
		out.append(spawn(i))
	return out


func _kind_id_for(kind: String) -> int:
	if not _kind_ids.has(kind):
		_kind_ids[kind] = _kind_names.size()
		_kind_names.append(kind)
	return _kind_ids[kind]


func _add(kind: String, pos: Vector2, rot: float, size: Vector2, source: int, variant: int) -> void:
	_s_kind.append(_kind_id_for(kind))
	_s_pos.append(pos)
	_s_rot.append(rot)
	_s_size.append(size)
	_s_variant.append(variant)
	_s_source.append(source)


func _rebuild() -> void:
	_dirty = false
	_kind_names = PackedStringArray()
	_kind_ids = {}
	_s_kind = PackedByteArray()
	_s_pos = PackedVector2Array()
	_s_rot = PackedFloat32Array()
	_s_size = PackedVector2Array()
	_s_variant = PackedInt32Array()
	_s_source = PackedByteArray()
	var clears: Array[PropZone] = []
	var scatters: Array[PropZone] = []
	var manual: Array[PropSpawnPoint] = []
	for child in get_children():
		if child is PropZone:
			(clears if child.mode == PropZone.Mode.CLEAR else scatters).append(child)
		elif child is PropSpawnPoint:
			manual.append(child)
	if spawn_set:
		_take_generated(clears)
	for z in scatters:
		_scatter(z)
	for m in manual:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([map_seed, m.name])
		if rng.randf() > m.chance:
			continue
		_add(m.kind, m.position, m.rotation,
				m.size if m.size != Vector2.ZERO else DEFAULT_SIZE.get(m.kind, Vector2(40, 40)), MANUAL, m.variant)
	_cells.clear()
	for i in _s_pos.size():
		var key := _cell_of(_s_pos[i])
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(i)
	queue_redraw()
	spawns_changed.emit()


func _take_generated(clears: Array[PropZone]) -> void:
	var n := spawn_set.count()
	for k in spawn_set.kinds:
		_kind_id_for(k)
	var has_variants := spawn_set.variant.size() >= n
	var shares := _kept_shares()
	if clears.is_empty() and shares.is_empty():
		_s_kind = spawn_set.kind
		_s_pos = spawn_set.position
		_s_rot = spawn_set.rotation
		_s_size = spawn_set.size
		if has_variants:
			_s_variant = spawn_set.variant
		else:
			_s_variant.resize(n)
			_s_variant.fill(-1)
		_s_source.resize(n)
		_s_source.fill(GENERATED)
		return
	var clear_outlines := clears.map(func(z): return z.outline())
	for i in n:
		var kid: int = spawn_set.kind[i]
		if not shares.is_empty() and shares[kid] < 1.0 and _unit_hash(i) >= shares[kid]:
			continue
		var k: String = spawn_set.kinds[kid]
		var p: Vector2 = spawn_set.position[i]
		if not clears.is_empty() and _cleared(k, p, clears, clear_outlines):
			continue
		_add(k, p, spawn_set.rotation[i], spawn_set.size[i], GENERATED, spawn_set.variant[i] if has_variants else -1)


# kept_share by spawn_set kind id (1 for kinds not listed), or empty when
# every kind keeps all of its spawns.
func _kept_shares() -> PackedFloat32Array:
	var shares := PackedFloat32Array()
	var thinning := false
	for k in spawn_set.kinds:
		var share := clampf(kept_share.get(k, 1.0), 0.0, 1.0)
		shares.append(share)
		thinning = thinning or share < 1.0
	return shares if thinning else PackedFloat32Array()


# A number in 0..1 for generated spawn i, the same on every load with the
# same map_seed.
func _unit_hash(i: int) -> float:
	return float(hash(Vector2i(i, map_seed)) & 0xFFFFFF) / float(0x1000000)


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
					_add(k, p, rng.randf() * TAU, DEFAULT_SIZE.get(k, Vector2(40, 40)), ZONE, -1)
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
	for i in _s_pos.size():
		var kind := spawn_kind(i)
		var source: int = _s_source[i]
		var col: Color = MARKER_COLOR.get(kind, Color.WHITE)
		var width := 6.0 if source == MANUAL else 3.0
		if source != GENERATED:
			col = col.lightened(0.4)
		var half: Vector2 = _s_size[i] / 2.0
		if kind in ["tree", "bush"]:
			draw_arc(_s_pos[i], half.x, 0.0, TAU, 16 if kind == "tree" else 8, col, width)
		else:
			var xf := Transform2D(_s_rot[i], _s_pos[i])
			var corners := PackedVector2Array([
				xf * Vector2(-half.x, -half.y), xf * Vector2(half.x, -half.y),
				xf * Vector2(half.x, half.y), xf * Vector2(-half.x, half.y), xf * Vector2(-half.x, -half.y)])
			draw_polyline(corners, col, width)
			if kind != "debris":
				draw_line(xf * Vector2(half.x * 0.5, -half.y), xf * Vector2(half.x * 0.5, half.y), col, width)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
