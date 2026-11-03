class_name BuildingField
extends Node2D

# Makes a map's generated buildings enterable without a node per building.
#
# The buildings exist only as footprints (a BuildingFootprints resource) and
# as merged interior and roof meshes. Each physics frame this node finds
# which footprint every mecha is in or near, and calls the same mecha methods
# that Building.gd's areas call: entering_building(true/false) while within
# `perimeter` of a footprint (the mecha slows), and entered_building() /
# exited_building() when it goes in or comes out (the player's camera zooms).
#
# While the player is in or near a building, every roof within reveal_radius
# fades out, so the player sees the interiors round them. Each roof vertex
# carries its building's id in UV.x; the roof material reads one fade value
# per id from a small texture that this node keeps up to date.
#
# Buildings within occluder_radius of the player get a LightOccluder2D of
# their outline, so walls cast shadows in the mechas' light cones (see
# MapSenses); they are made and freed as the player moves, every
# OCCLUDER_INTERVAL s, so a big map never has more than the ones in reach.
#
# Each building also gets its outline as a wall, on MapSenses.WALL_LAYER.
# Nothing collides with that layer, so mechas still walk through walls; rays
# see it, so walls stop shots by AP and block sight (see MapSenses). The
# outlines of all buildings whose centre is in one WALL_CELL_SIZE square are
# merged into one static body with one segment shape, made directly in the
# physics server (no node). Every ray pays for each body along its path,
# whatever its mask, so a few dozen merged bodies cost far less than one
# body per building.
#
# Hand-made maps: with no `footprints` resource, the field reads the
# Polygon2D children of a child node named "Footprints" as the buildings
# (drawn in the editor; the Polygon2D draws the floor) and gives each one a
# light outline (outline_color, outline_width).
#
# NPC steering reads the footprints through buildings_within(), building_at(),
# global_polygon() and distance_to_building(), all in global space, to keep
# mechas out of buildings they don't need to enter.
#
# Route planning: a grid of ROUTE_CELL squares over the buildings, where each
# square costs more to cross the more of it is building and the more vehicles
# are parked in it. It is built once on a worker thread after the map loads
# (routes_ready() tells when) and solved with AStarGrid2D. find_route() gives
# NPCs a path along the streets and open ground for long trips; local
# steering still handles what they meet on the way. Solid static bodies
# (walls, barriers, hand-made props) present when the grid is built block the
# squares they cover, grown by ROUTE_WALL_CLEARANCE. Scenes streamed in later
# don't. At most
# ROUTE_SOLVES_PER_FRAME routes are solved per physics frame; past that,
# find_route() returns nothing and the NPC asks again on a later frame.

const CELL_SIZE := 2000.0
const FADE_SPEED := 2.3
const FADE_TEX_SIZE := 128
const WALL_CELL_SIZE := 5000.0
## Route grid square (px). 250 px is 12.5 m, a little more than a mecha.
const ROUTE_CELL := 250.0
## Extra cost for a square fully covered by building.	
const ROUTE_BUILDING_WEIGHT := 6.0
## Extra cost per vehicle parked in a square, and per heavy vehicle (over
## ROUTE_HEAVY_MASS kg), up to ROUTE_VEHICLE_MAX in all.
const ROUTE_VEHICLE_WEIGHT := 0.5
const ROUTE_HEAVY_VEHICLE_WEIGHT := 2.0
const ROUTE_HEAVY_MASS := 3000.0
const ROUTE_VEHICLE_MAX := 3.0
## The grid reaches this far (px) past the outermost buildings, vehicles
## and static bodies.
const ROUTE_MARGIN := 4000.0
## Static bodies block route squares within this distance (px).
const ROUTE_WALL_CLEARANCE := 100.0
const ROUTE_SOLVES_PER_FRAME := 1
const OCCLUDER_INTERVAL := 0.25
## Occluders are freed only this far (px) past occluder_radius, so one at
## the edge doesn't flicker in and out.
const OCCLUDER_SLACK := 1000.0

@export var footprints: BuildingFootprints
@export var roof_material: ShaderMaterial
## Roofs within this distance (px) of the player fade out. 300 px is 15 m.
@export var reveal_radius := 300.0
## Within this distance (px) of a footprint a mecha counts as entering and is
## slowed, as with Building.tscn's Perimeter area.
@export var perimeter := 70.0
## A mecha this close (px) to a footprint still counts as inside, so the
## narrow gaps between neighbouring houses don't flicker the camera zoom.
@export var inside_margin := 30.0
## Outline drawn round buildings read from a "Footprints" node.
@export var outline_color := Color(0.75, 0.75, 0.75)
@export var outline_width := 8.0
## Buildings within this distance (px) of the player cast light shadows: a
## little past the screen corners at the default zoom (about 2200 px), since
## a shadow only shows on screen. Every light that casts shadows pays for
## each occluder in its reach, so keep it tight.
@export var occluder_radius := 3000.0

var _polys: Array[PackedVector2Array] = []
var _rects: Array[Rect2] = []
# Grid cell -> ids of buildings close enough to matter for a point in it.
var _cells := {}
# Mecha instance id -> [inside, near].
var _mecha_state := {}
# Building id -> current roof alpha, for roofs that are not fully shown.
var _fade := {}
var _fade_image: Image
var _fade_texture: ImageTexture
var _wall_bodies: Array[RID] = []
var _wall_shapes: Array[RID] = []
var _route_grid: AStarGrid2D = null
var _route_origin := Vector2.ZERO
var _route_task := -1
var _route_result: Array = []
var _route_frame := -1
var _route_solves := 0
# Building id -> its LightOccluder2D, for buildings near the player.
var _occluders := {}
var _occluder_timer := 0.0


func _ready() -> void:
	add_to_group("building_field")
	if footprints == null and has_node("Footprints"):
		footprints = _footprints_from_nodes(get_node("Footprints"))
	if footprints == null:
		push_warning("BuildingField has no footprints.")
		set_physics_process(false)
		return
	if footprints.count() > FADE_TEX_SIZE * FADE_TEX_SIZE:
		push_warning("BuildingField: more buildings than the fade texture holds.")
	var reach := maxf(maxf(perimeter, inside_margin), reveal_radius)
	for i in footprints.count():
		var poly := footprints.polygon(i)
		var rect := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			rect = rect.expand(p)
		_polys.append(poly)
		_rects.append(rect)
		var grown := rect.grow(reach)
		var c0 := _cell_of(grown.position)
		var c1 := _cell_of(grown.end)
		for cx in range(c0.x, c1.x + 1):
			for cy in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cy)
				if not _cells.has(key):
					_cells[key] = PackedInt32Array()
				_cells[key].append(i)
	if not Engine.is_editor_hint():
		_build_walls()
		_start_route_build.call_deferred()
	_fade_image = Image.create(FADE_TEX_SIZE, FADE_TEX_SIZE, false, Image.FORMAT_R8)
	_fade_image.fill(Color.WHITE)
	_fade_texture = ImageTexture.create_from_image(_fade_image)
	if roof_material:
		roof_material.set_shader_parameter("fade_tex", _fade_texture)
		roof_material.set_shader_parameter("use_fade", true)


func _exit_tree() -> void:
	if _route_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_route_task)
		_route_task = -1
	for rid in _wall_bodies:
		PhysicsServer2D.free_rid(rid)
	for rid in _wall_shapes:
		PhysicsServer2D.free_rid(rid)
	_wall_bodies.clear()
	_wall_shapes.clear()


func wall_body_count() -> int:
	return _wall_bodies.size()


func _build_walls() -> void:
	var space := get_world_2d().space
	var xform := global_transform
	# Cell -> wall segments (pairs of points) of the buildings centred in it.
	var cells := {}
	for i in _polys.size():
		var poly := _polys[i]
		var key := Vector2i((_rects[i].get_center() / WALL_CELL_SIZE).floor())
		var segments: PackedVector2Array = cells.get(key, PackedVector2Array())
		for k in poly.size():
			segments.append(poly[k])
			segments.append(poly[(k + 1) % poly.size()])
		cells[key] = segments
	for key in cells:
		var segments: PackedVector2Array = cells[key]
		var shape := PhysicsServer2D.concave_polygon_shape_create()
		PhysicsServer2D.shape_set_data(shape, segments)
		var body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_collision_layer(body, MapSenses.WALL_MASK)
		PhysicsServer2D.body_set_collision_mask(body, 0)
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
		PhysicsServer2D.body_attach_object_instance_id(body, get_instance_id())
		PhysicsServer2D.body_set_space(body, space)
		_wall_bodies.append(body)
		_wall_shapes.append(shape)


func _physics_process(delta: float) -> void:
	if _route_task >= 0 and WorkerThreadPool.is_task_completed(_route_task):
		_finish_route_build()
	var reveal_at = null
	var player_at = null
	var seen := {}
	for mech in get_tree().get_nodes_in_group("mecha"):
		if not (mech is Node2D) or not mech.has_method("entered_building"):
			continue
		if mech.has_method("is_player") and mech.is_player():
			player_at = mech.global_position
		var id: int = mech.get_instance_id()
		seen[id] = true
		var pos := to_local(mech.global_position)
		var dist := _nearest_distance(pos)
		var inside := dist <= inside_margin
		var near := dist <= perimeter
		var state: Array = _mecha_state.get(id, [false, false])
		if near != state[1]:
			mech.entering_building(near)
		if inside != state[0]:
			if inside:
				mech.entered_building()
			else:
				mech.exited_building()
		_mecha_state[id] = [inside, near]
		if near and mech.has_method("is_player") and mech.is_player():
			reveal_at = pos
	for id in _mecha_state.keys():
		if not seen.has(id):
			_mecha_state.erase(id)
	_update_fades(reveal_at, delta)
	_occluder_timer -= delta
	if _occluder_timer <= 0.0 and player_at != null:
		_occluder_timer = OCCLUDER_INTERVAL
		update_occluders(player_at)


# Gives the buildings within occluder_radius of `global_pos` an occluder and
# frees those well past it.
func update_occluders(global_pos: Vector2) -> void:
	var keep := {}
	for i in buildings_within(global_pos, occluder_radius):
		keep[i] = true
		if not _occluders.has(i):
			var shape := OccluderPolygon2D.new()
			shape.polygon = _polys[i]
			shape.closed = true
			var occluder := LightOccluder2D.new()
			occluder.occluder = shape
			add_child(occluder)
			_occluders[i] = occluder
	for i in _occluders.keys():
		if not keep.has(i) and distance_to_building(i, global_pos) > occluder_radius + OCCLUDER_SLACK:
			_occluders[i].queue_free()
			_occluders.erase(i)


func occluder_count() -> int:
	return _occluders.size()


# Building ids within `radius` of a map position.
func buildings_near(pos: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _cells.get(_cell_of(pos), PackedInt32Array()):
		if _rects[i].grow(radius).has_point(pos) and _distance_to(i, pos) <= radius:
			out.append(i)
	return out


# Buildings from the Polygon2D children of `holder` (in this node's space),
# each given an outline.
func _footprints_from_nodes(holder: Node) -> BuildingFootprints:
	var out := BuildingFootprints.new()
	var starts := PackedInt32Array([0])
	for child in holder.get_children():
		var poly := child as Polygon2D
		if poly == null or poly.polygon.size() < 3:
			continue
		for v in poly.polygon:
			out.points.append(to_local(poly.to_global(v)))
		starts.append(out.points.size())
		if not Engine.is_editor_hint():
			var line := Line2D.new()
			line.points = poly.polygon
			line.closed = true
			line.width = outline_width
			line.default_color = outline_color
			line.joint_mode = Line2D.LINE_JOINT_SHARP
			poly.add_child(line)
	if starts.size() < 2:
		return null
	out.starts = starts
	return out


static func find(node: Node) -> BuildingField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("building_field") as BuildingField


# Building ids whose footprints come within `radius` of a global position.
# Unlike buildings_near(), the radius can be larger than a grid cell.
func buildings_within(global_pos: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _polys.is_empty():
		return out
	var pos := to_local(global_pos)
	var c0 := _cell_of(pos - Vector2(radius, radius))
	var c1 := _cell_of(pos + Vector2(radius, radius))
	var seen := {}
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for i in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if seen.has(i):
					continue
				seen[i] = true
				if _rects[i].grow(radius).has_point(pos):
					out.append(i)
	return out


# The building whose footprint contains a global position, or -1.
func building_at(global_pos: Vector2) -> int:
	var pos := to_local(global_pos)
	for i in _cells.get(_cell_of(pos), PackedInt32Array()):
		if _rects[i].has_point(pos) and Geometry2D.is_point_in_polygon(pos, _polys[i]):
			return i
	return -1


func global_polygon(i: int) -> PackedVector2Array:
	return global_transform * _polys[i]


# Distance from a global position to building i's footprint (0 inside).
func distance_to_building(i: int, global_pos: Vector2) -> float:
	return _distance_to(i, to_local(global_pos))


# ---- Route planning ----

# True once the route grid is built.
func routes_ready() -> bool:
	return _route_grid != null


# A route from one global position to another, as global points: the first
# is the next point to head for, the last is `to`. Straight stretches are
# merged into single legs. Empty when the grid isn't ready yet, or when this
# frame's solves are used up (ask again later).
func find_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _route_grid == null:
		return PackedVector2Array()
	var frame := Engine.get_physics_frames()
	if frame != _route_frame:
		_route_frame = frame
		_route_solves = 0
	if _route_solves >= ROUTE_SOLVES_PER_FRAME:
		return PackedVector2Array()
	_route_solves += 1
	var a := _route_cell(to_local(from))
	var b := _route_cell(to_local(to))
	var cells := _route_grid.get_id_path(a, b, true)
	var out := PackedVector2Array()
	if cells.size() > 1:
		var kept := _route_simplify(cells)
		for k in range(1, kept.size()):
			out.append(to_global(_route_centre(kept[k])))
	if out.is_empty():
		out.append(to)
	else:
		out[out.size() - 1] = to
	return out


# How much a route grid square costs to cross (1 = open ground), at a global
# position.
func route_cost_at(global_pos: Vector2) -> float:
	if _route_grid == null:
		return 1.0
	return _route_grid.get_point_weight_scale(_route_cell(to_local(global_pos)))


func _route_cell(local_pos: Vector2) -> Vector2i:
	var r := _route_grid.region
	var c := Vector2i(((local_pos - _route_origin) / ROUTE_CELL).floor())
	return c.clamp(r.position, r.end - Vector2i.ONE)


func _route_centre(cell: Vector2i) -> Vector2:
	return _route_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * ROUTE_CELL


# Keeps only the cells where the route turns: from each kept cell, jumps to
# the furthest later cell (up to 40 on) that a straight line reaches for no
# more cost than the path itself takes between them.
func _route_simplify(cells: Array[Vector2i]) -> Array[Vector2i]:
	var kept: Array[Vector2i] = [cells[0]]
	var i := 0
	while i < cells.size() - 1:
		var best := i + 1
		var path_cost := 0.0
		for j in range(i + 1, mini(cells.size(), i + 40)):
			path_cost += _route_grid.get_point_weight_scale(cells[j]) * Vector2(cells[j - 1]).distance_to(Vector2(cells[j]))
			if j > i + 1 and _route_line_cost(cells[i], cells[j]) <= path_cost * 1.02:
				best = j
		kept.append(cells[best])
		i = best
	return kept


# What a straight line between two cells costs, in the same units as the
# path (weight times cells crossed); INF through a blocked square.
func _route_line_cost(a: Vector2i, b: Vector2i) -> float:
	var length := Vector2(a).distance_to(Vector2(b))
	var steps := maxi(ceili(length * 2.0), 1)
	var cost := 0.0
	for s in range(1, steps + 1):
		var c := Vector2i((Vector2(a) + (Vector2(b) - Vector2(a)) * (float(s) / steps)).round())
		if _route_grid.is_point_solid(c):
			return INF
		cost += _route_grid.get_point_weight_scale(c)
	return cost * length / steps


# Gathers what the grid needs on the main thread, then builds it on a worker
# thread. Waits for the VehicleField (built a frame after load) if there is one.
func _start_route_build() -> void:
	if _polys.is_empty() or _route_task >= 0 or _route_grid != null:
		return
	var vehicles := VehicleField.find(self)
	if vehicles and not vehicles.is_built():
		get_tree().create_timer(0.1, true, true).timeout.connect(_start_route_build, CONNECT_ONE_SHOT)
		return
	var bounds := _rects[0]
	for r in _rects:
		bounds = bounds.merge(r)
	var veh_pos := PackedVector2Array()
	var veh_mass := PackedFloat32Array()
	if vehicles:
		for i in vehicles.vehicle_count():
			if not vehicles.is_trampled(i) and not vehicles.is_destroyed(i):
				veh_pos.append(to_local(vehicles.vehicle_transform(i).origin))
				veh_mass.append(vehicles.vehicle_mass(i))
				bounds = bounds.expand(veh_pos[veh_pos.size() - 1])
	var solids := _static_outlines()
	for poly in solids:
		for v in poly:
			bounds = bounds.expand(v)
	bounds = bounds.grow(ROUTE_MARGIN)
	_route_task = WorkerThreadPool.add_task(_build_route_grid.bind(bounds, veh_pos, veh_mass, solids), false, "BuildingField routes")


# Outlines (this node's space) of the collision shapes of every static body in
# the scene, grown by ROUTE_WALL_CLEARANCE.
func _static_outlines() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for body in get_tree().root.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			var local := PackedVector2Array()
			if child is CollisionShape2D and not child.disabled and child.shape != null:
				var shape: Shape2D = child.shape
				var r := shape.get_rect()
				local = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
				local = child.transform * local
			elif child is CollisionPolygon2D and not child.disabled and child.polygon.size() >= 3:
				local = child.transform * child.polygon
			if local.is_empty():
				continue
			var mine := PackedVector2Array()
			for v in local:
				mine.append(to_local(body.to_global(v)))
			var grown := Geometry2D.offset_polygon(mine, ROUTE_WALL_CLEARANCE)
			if not grown.is_empty():
				out.append(grown[0])
	return out


func _build_route_grid(bounds: Rect2, veh_pos: PackedVector2Array, veh_mass: PackedFloat32Array, solids: Array[PackedVector2Array]) -> void:
	var origin := bounds.position
	var size := Vector2i((bounds.size / ROUTE_CELL).ceil())
	var extra := PackedFloat32Array()
	extra.resize(size.x * size.y)
	# Building cover: five samples per square (centre and four inner corners).
	var offsets := [Vector2(0.5, 0.5), Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	for i in _polys.size():
		var poly := _polys[i]
		var r := _rects[i]
		var c0 := Vector2i(((r.position - origin) / ROUTE_CELL).floor())
		var c1 := Vector2i(((r.end - origin) / ROUTE_CELL).floor())
		for cx in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
			for cy in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
				var inside := 0
				for o in offsets:
					var p: Vector2 = origin + (Vector2(cx, cy) + o) * ROUTE_CELL
					if r.has_point(p) and Geometry2D.is_point_in_polygon(p, poly):
						inside += 1
				if inside > 0:
					var k := cy * size.x + cx
					extra[k] = minf(extra[k] + ROUTE_BUILDING_WEIGHT * inside / 5.0, ROUTE_BUILDING_WEIGHT)
	var veh := PackedFloat32Array()
	veh.resize(size.x * size.y)
	for i in veh_pos.size():
		var c := Vector2i(((veh_pos[i] - origin) / ROUTE_CELL).floor())
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
			continue
		var k := c.y * size.x + c.x
		var w := ROUTE_HEAVY_VEHICLE_WEIGHT if veh_mass[i] > ROUTE_HEAVY_MASS else ROUTE_VEHICLE_WEIGHT
		veh[k] = minf(veh[k] + w, ROUTE_VEHICLE_MAX)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(ROUTE_CELL, ROUTE_CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for cy in size.y:
		for cx in size.x:
			var k := cy * size.x + cx
			var w := 1.0 + extra[k] + veh[k]
			if w > 1.0:
				grid.set_point_weight_scale(Vector2i(cx, cy), w)
	for poly in solids:
		var r := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			r = r.expand(v)
		var c0 := Vector2i(((r.position - origin) / ROUTE_CELL).floor())
		var c1 := Vector2i(((r.end - origin) / ROUTE_CELL).floor())
		for cx in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
			for cy in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
				var cell_pos := origin + Vector2(cx, cy) * ROUTE_CELL
				var cell := PackedVector2Array([cell_pos, cell_pos + Vector2(ROUTE_CELL, 0), cell_pos + Vector2(ROUTE_CELL, ROUTE_CELL), cell_pos + Vector2(0, ROUTE_CELL)])
				if not Geometry2D.intersect_polygons(cell, poly).is_empty():
					grid.set_point_solid(Vector2i(cx, cy), true)
	_route_result = [grid, origin]


func _finish_route_build() -> void:
	WorkerThreadPool.wait_for_task_completion(_route_task)
	_route_task = -1
	if _route_result.size() == 2:
		_route_grid = _route_result[0]
		_route_origin = _route_result[1]
	_route_result = []


func _update_fades(reveal_at, delta: float) -> void:
	var targets := {}
	if reveal_at != null:
		for i in buildings_near(reveal_at, reveal_radius):
			targets[i] = true
			if not _fade.has(i):
				_fade[i] = 1.0
	var changed := false
	for i in _fade.keys():
		var target := 0.0 if targets.has(i) else 1.0
		var a := move_toward(_fade[i], target, FADE_SPEED * delta)
		if a != _fade[i]:
			_fade_image.set_pixel(i % FADE_TEX_SIZE, i / FADE_TEX_SIZE, Color(a, a, a))
			changed = true
		if a >= 1.0:
			_fade.erase(i)
		else:
			_fade[i] = a
	if changed:
		_fade_texture.update(_fade_image)


func _nearest_distance(pos: Vector2) -> float:
	var best := INF
	for i in _cells.get(_cell_of(pos), PackedInt32Array()):
		if best < INF and not _rects[i].grow(best).has_point(pos):
			continue
		best = minf(best, _distance_to(i, pos))
		if best == 0.0:
			break
	return best


func _distance_to(i: int, pos: Vector2) -> float:
	var poly := _polys[i]
	if Geometry2D.is_point_in_polygon(pos, poly):
		return 0.0
	var best := INF
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)))
	return best


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
