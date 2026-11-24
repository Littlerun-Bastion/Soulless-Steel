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
# Buildings round the camera's view get a LightOccluder2D of their outline, so
# walls cast shadows in the mechas' light cones (see MapSenses): those within
# the screen's half-diagonal plus occluder_margin of the screen's centre,
# which follows the player's camera pan. Buildings wholly further than the
# player's sight circle plus the margin are left out: the screen is black
# there (with no player, none are). They are made and freed every
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
# Ruin states (BuildingFootprints.state): intact and damaged buildings work
# as above (a damaged roof has holes in its mesh). A gutted building keeps its
# wall and its edge slow, but a mecha in it is not told entered_building():
# there is no roof to hide under, so the camera doesn't zoom. A collapsed
# building is only rubble on the ground: no wall, no slow, no entering, no
# roof fade, no occluder, no route cost, and NPC steering doesn't see it. It
# keeps its id (the meshes are tagged by id) but is in no lookup cell.
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
# Route planning: a grid of ROUTE_CELL squares, where each square costs more
# to cross the more of it is building and the more vehicles are parked in it.
# Routes give NPCs a path along the streets and open ground for long trips;
# local steering still handles what they meet on the way. On a map with a
# MapBounds the grid covers the play area only (an NPC never routes into the
# border band); otherwise it reaches ROUTE_MARGIN past the outermost
# buildings, vehicles and static bodies. Solid static bodies (walls,
# barriers, hand-made props) present when the grid is built, grown by
# ROUTE_WALL_CLEARANCE, and the ObstacleField's pipes and pools, grown by
# ROUTE_OBSTACLE_CLEARANCE, block the squares they cover; NPC steering sees
# the same grown outlines as hard obstacles (solids_within). Scenes streamed
# in later don't count. The grid
# is built once on a worker thread after the map loads (routes_ready() tells
# when).
#
# Routes are solved off the main thread, one search at a time, on a thread
# of the field's own: AStarGrid2D can't answer two searches at once. An NPC
# asks with request_route() and collects the route with take_route() a frame
# or a few later, so no physics frame waits for a search. The thread reads
# only what the build made (a RouteGrid: the searcher and packed copies of
# the squares' costs and blocked flags); the main thread reads only the
# packed copies (route_cost_at). find_route() asks and waits, for tests and
# tools.

const CELL_SIZE := 2000.0
const FADE_SPEED := 2.3
## One texel per building id, so up to 262,144 buildings.
const FADE_TEX_SIZE := 512
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
## The ObstacleField's pipes and pools block route squares within this
## distance (px). Less than a wall's: a plant's racks leave gaps of 26 m for
## mechas to pass, and an NPC gets through one only if the grown racks leave
## it room (on top of this, steering keeps the NPC's own radius away).
const ROUTE_OBSTACLE_CLEARANCE := 40.0
## A route not collected this long (ms) after it was solved is dropped (its
## NPC is gone).
const ROUTE_RESULT_TTL_MS := 10000
const OCCLUDER_INTERVAL := 0.25
## Occluders are freed only this far (px) past their reach, so one at the
## edge doesn't flicker in and out.
const OCCLUDER_SLACK := 1000.0

@export var footprints: BuildingFootprints
## The district of every part of the map (generated maps only).
@export var districts: MapDistricts
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
## How far (px) past the screen's corners, and past the player's sight
## circle, buildings still cast light shadows: a shadow only shows on screen.
## Every light that casts shadows pays for each occluder in its reach, so
## keep it tight.
@export var occluder_margin := 800.0

var _polys: Array[PackedVector2Array] = []
var _rects: Array[Rect2] = []
var _states := PackedByteArray()
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
var _route_grid: RouteGrid = null
var _route_task := -1
var _route_result: RouteGrid = null
# The route solver (see Route planning). The queue, the results and the
# stats are shared with its thread, under _route_mutex.
var _route_thread: Thread = null
var _route_mutex := Mutex.new()
var _route_semaphore := Semaphore.new()
var _route_quit := false
var _route_queue: Array[RouteJob] = []
# Ticket -> [route (global points), Time.get_ticks_msec() when solved].
var _route_results := {}
var _route_cancelled := {}
var _route_next_ticket := 1
var _route_solve_usec := PackedInt32Array()
var _route_search_usec := PackedInt32Array()
# Building id -> its LightOccluder2D, for buildings near the player.
var _occluders := {}
var _occluder_timer := 0.0
# Footprints in global space and their centres, filled as asked for.
var _global_polys: Array[PackedVector2Array] = []
var _centres: Array[Vector2] = []
# The static bodies' outlines (see solids_ready).
var _solid_polys: Array[PackedVector2Array] = []
var _solid_rects: Array[Rect2] = []
var _solid_global: Array[PackedVector2Array] = []
var _solid_centres: Array[Vector2] = []
# CELL_SIZE grid cell -> ids of the solids whose outline reaches into it.
var _solid_cells := {}
var _solids_gathered := false


# A built route grid: what the solver thread searches and the main thread
# reads. Nothing in it changes once it is built. weights[k] and solid[k] are
# square (x, y)'s cost and blocked flag, k = y * size.x + x; origin is the
# grid's corner in this node's space and xform the node's global transform
# when it was built.
class RouteGrid:
	var astar: AStarGrid2D
	var size := Vector2i.ZERO
	var origin := Vector2.ZERO
	var weights := PackedFloat32Array()
	var solid := PackedByteArray()
	var xform := Transform2D.IDENTITY

	func cell_of(local_pos: Vector2) -> Vector2i:
		var c := Vector2i(((local_pos - origin) / ROUTE_CELL).floor())
		return c.clamp(Vector2i.ZERO, size - Vector2i.ONE)

	func centre_of(cell: Vector2i) -> Vector2:
		return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * ROUTE_CELL

	func index(cell: Vector2i) -> int:
		return cell.y * size.x + cell.x

	func is_solid(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			return true
		return solid[cell.y * size.x + cell.x] != 0

	func weight(cell: Vector2i) -> float:
		return weights[cell.y * size.x + cell.x]


# One route asked for: from and to as squares, the goal as given (global);
# search_usec is how long the grid search itself took (the rest of a solve
# is merging the straight stretches).
class RouteJob:
	var ticket := 0
	var grid: RouteGrid
	var from_cell := Vector2i.ZERO
	var to_cell := Vector2i.ZERO
	var goal := Vector2.ZERO
	var search_usec := 0


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
	_states.resize(footprints.count())
	for i in footprints.count():
		var poly := footprints.polygon(i)
		var rect := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			rect = rect.expand(p)
		_polys.append(poly)
		_rects.append(rect)
		_states[i] = footprints.state_of(i)
		if _states[i] == BuildingFootprints.COLLAPSED:
			continue
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
	_stop_route_solver()
	for rid in _wall_bodies:
		PhysicsServer2D.free_rid(rid)
	for rid in _wall_shapes:
		PhysicsServer2D.free_rid(rid)
	_wall_bodies.clear()
	_wall_shapes.clear()


func wall_body_count() -> int:
	return _wall_bodies.size()


func building_count() -> int:
	return _polys.size()


# Building i's ruin state (BuildingFootprints.INTACT ... COLLAPSED).
func state_of(i: int) -> int:
	return _states[i] if i >= 0 and i < _states.size() else BuildingFootprints.INTACT


# Whether building i still stands as a building (has a wall): not collapsed.
func is_standing(i: int) -> bool:
	return state_of(i) != BuildingFootprints.COLLAPSED


# Building i's outline in this node's space.
func local_polygon(i: int) -> PackedVector2Array:
	return _polys[i]


func local_rect(i: int) -> Rect2:
	return _rects[i]


func _build_walls() -> void:
	var space := get_world_2d().space
	var xform := global_transform
	# Cell -> wall segments (pairs of points) of the buildings centred in it.
	var cells := {}
	for i in _polys.size():
		if _states[i] == BuildingFootprints.COLLAPSED:
			continue
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
	var profile_start := FrameProfiler.start()
	_physics_step(delta)
	FrameProfiler.add("buildings", profile_start)


func _physics_step(delta: float) -> void:
	if _route_task >= 0 and WorkerThreadPool.is_task_completed(_route_task):
		_finish_route_build()
	var reveal_at = null
	var player = null
	var seen := {}
	for mech in get_tree().get_nodes_in_group("mecha"):
		if not (mech is Node2D) or not mech.has_method("entered_building"):
			continue
		if mech.has_method("is_player") and mech.is_player():
			player = mech
		var id: int = mech.get_instance_id()
		seen[id] = true
		var pos := to_local(mech.global_position)
		var nearest := _nearest(pos)
		var dist: float = nearest[0]
		var inside := dist <= inside_margin and _states[nearest[1]] != BuildingFootprints.GUTTED
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
	if _occluder_timer <= 0.0:
		_occluder_timer = OCCLUDER_INTERVAL
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		if cam != null:
			var limit_at := Vector2.INF
			var limit := INF
			if is_instance_valid(player) and player.has_method("sight_radius"):
				limit_at = player.global_position
				limit = player.sight_radius() + occluder_margin
			update_occluders(cam.get_screen_center_position(), view_reach(cam), limit_at, limit)


## How far (px) from the screen's centre buildings get occluders: the
## screen's half-diagonal at `cam`'s zoom, plus occluder_margin.
func view_reach(cam: Camera2D) -> float:
	var size := get_viewport().get_visible_rect().size / cam.zoom
	return size.length() * 0.5 + occluder_margin


# Gives the buildings within `radius` of `global_pos` an occluder and frees
# those well past it. With `limit_at` given, buildings further than `limit`
# from it are left out (and freed). A negative radius is the current camera's
# view_reach.
func update_occluders(global_pos: Vector2, radius := -1.0, limit_at := Vector2.INF, limit := INF) -> void:
	if radius < 0.0:
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		radius = view_reach(cam) if cam != null else occluder_margin
	var keep := {}
	for i in buildings_within(global_pos, radius):
		if limit_at != Vector2.INF and distance_to_building(i, limit_at) > limit:
			continue
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
		if keep.has(i):
			continue
		var outside_view := distance_to_building(i, global_pos) > radius + OCCLUDER_SLACK
		var outside_sight := limit_at != Vector2.INF and distance_to_building(i, limit_at) > limit + OCCLUDER_SLACK
		if outside_view or outside_sight:
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


# Building i's footprint in global space, worked out once: buildings don't
# move, and NPC steering asks for the same ones every rebuild.
func global_polygon(i: int) -> PackedVector2Array:
	if _global_polys.is_empty():
		_global_polys.resize(_polys.size())
		_centres.resize(_polys.size())
		_centres.fill(Vector2.INF)
	var poly: PackedVector2Array = _global_polys[i]
	if poly.is_empty():
		poly = global_transform * _polys[i]
		_global_polys[i] = poly
	return poly


# The centre of building i's footprint (global), the mean of its points.
func polygon_centre(i: int) -> Vector2:
	global_polygon(i)
	if _centres[i] == Vector2.INF:
		_centres[i] = _mean(_global_polys[i])
	return _centres[i]


# Distance from a global position to building i's footprint (0 inside).
func distance_to_building(i: int, global_pos: Vector2) -> float:
	return _distance_to(i, to_local(global_pos))


# ---- Static bodies (solids) ----
# The outlines of the scene's static bodies, grown by ROUTE_WALL_CLEARANCE
# (the ObstacleField's by ROUTE_OBSTACLE_CLEARANCE),
# as gathered for the route grid (_static_outlines). NPC steering projects
# them as hard obstacles instead of casting shapes against the bodies.

# True once the outlines are gathered (with the route grid's build).
func solids_ready() -> bool:
	return _solids_gathered


# Ids of the solids whose outline's bounding box comes within `radius` of a
# global position.
func solids_within(global_pos: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _solid_polys.is_empty():
		return out
	var pos := to_local(global_pos)
	var c0 := _cell_of(pos - Vector2(radius, radius))
	var c1 := _cell_of(pos + Vector2(radius, radius))
	var seen := {}
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for i in _solid_cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if seen.has(i):
					continue
				seen[i] = true
				if _solid_rects[i].grow(radius).has_point(pos):
					out.append(i)
	return out


# Whether a global position is inside a solid's outline (grown, as
# gathered).
func is_in_solid(global_pos: Vector2) -> bool:
	var pos := to_local(global_pos)
	for i in _solid_cells.get(_cell_of(pos), PackedInt32Array()):
		if _solid_rects[i].has_point(pos) and Geometry2D.is_point_in_polygon(pos, _solid_polys[i]):
			return true
	return false


# Solid i's outline in global space (cached).
func solid_polygon(i: int) -> PackedVector2Array:
	var poly: PackedVector2Array = _solid_global[i]
	if poly.is_empty():
		poly = global_transform * _solid_polys[i]
		_solid_global[i] = poly
	return poly


func solid_centre(i: int) -> Vector2:
	if _solid_centres[i] == Vector2.INF:
		_solid_centres[i] = _mean(solid_polygon(i))
	return _solid_centres[i]


# Distance from a global position to solid i's outline (0 inside).
func distance_to_solid(i: int, global_pos: Vector2) -> float:
	var pos := to_local(global_pos)
	var poly := _solid_polys[i]
	if Geometry2D.is_point_in_polygon(pos, poly):
		return 0.0
	var best := INF
	for k in poly.size():
		best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, poly[k], poly[(k + 1) % poly.size()])))
	return best


# For a global position inside solid i's outline: the direction away from
# its nearest edge (the way out).
func solid_outward_normal(i: int, global_pos: Vector2) -> Vector2:
	var poly := solid_polygon(i)
	var best := INF
	var nearest := global_pos
	var edge := Vector2.RIGHT
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		var p := Geometry2D.get_closest_point_to_segment(global_pos, a, b)
		var d := global_pos.distance_squared_to(p)
		if d < best:
			best = d
			nearest = p
			edge = b - a
	var away := global_pos - nearest
	if away.length_squared() < 0.0001:
		# On the edge itself: perpendicular to it, toward the outline's centre.
		away = edge.orthogonal()
		if away.dot(solid_centre(i) - global_pos) < 0.0:
			away = -away
	return away.normalized()


static func _mean(poly: PackedVector2Array) -> Vector2:
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	return centre / maxf(poly.size(), 1.0)


# ---- Route planning ----

# True once the route grid is built.
func routes_ready() -> bool:
	return _route_grid != null


# Asks for a route from one global position to another; take_route() gives
# it once the solver thread has it (usually a frame or two later). Returns
# the ticket to collect it with, or 0 while the grid isn't built.
func request_route(from: Vector2, to: Vector2) -> int:
	var grid := _route_grid
	if grid == null:
		return 0
	if _route_thread == null:
		_start_route_solver()
	var job := RouteJob.new()
	job.grid = grid
	job.from_cell = grid.cell_of(to_local(from))
	job.to_cell = grid.cell_of(to_local(to))
	job.goal = to
	_route_mutex.lock()
	job.ticket = _route_next_ticket
	_route_next_ticket += 1
	_route_queue.append(job)
	_route_mutex.unlock()
	_route_semaphore.post()
	return job.ticket


# Whether the route for `ticket` is solved (take_route() then has it).
func is_route_solved(ticket: int) -> bool:
	_route_mutex.lock()
	var solved := _route_results.has(ticket)
	_route_mutex.unlock()
	return solved


# The route for `ticket`, as global points: the first is the next point to
# head for, the last is the goal (moved into the grid if it was outside).
# Straight stretches are merged into single legs. Empty while it is still
# being solved; once given, the ticket is spent.
func take_route(ticket: int) -> PackedVector2Array:
	_route_mutex.lock()
	var entry: Array = _route_results.get(ticket, [])
	_route_results.erase(ticket)
	_drop_stale_routes()
	_route_mutex.unlock()
	return PackedVector2Array() if entry.is_empty() else entry[0]


# Forgets a route asked for and no longer wanted.
func cancel_route(ticket: int) -> void:
	if ticket <= 0:
		return
	_route_mutex.lock()
	if _route_results.has(ticket):
		_route_results.erase(ticket)
	else:
		_route_cancelled[ticket] = true
	_route_mutex.unlock()


# A route from one global position to another (see take_route), waiting for
# the solver: for tests and tools. NPCs use request_route(). Empty when the
# grid isn't built.
func find_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var ticket := request_route(from, to)
	if ticket == 0:
		return PackedVector2Array()
	var started := Time.get_ticks_msec()
	while not is_route_solved(ticket):
		if Time.get_ticks_msec() - started > ROUTE_RESULT_TTL_MS:
			cancel_route(ticket)
			return PackedVector2Array()
		OS.delay_usec(100)
	return take_route(ticket)


# The solver's numbers: how many routes it solved, the median, 95th
# percentile and worst time (ms) of a whole solve ("median_ms", "p95_ms",
# "worst_ms") and of its grid search alone ("search_median_ms" ...), and how
# many routes wait in the queue.
func route_stats() -> Dictionary:
	_route_mutex.lock()
	var solves := _route_solve_usec.duplicate()
	var searches := _route_search_usec.duplicate()
	var queued := _route_queue.size()
	_route_mutex.unlock()
	var out := {"searches": solves.size(), "queued": queued}
	for pair in [["", solves], ["search_", searches]]:
		var times: PackedInt32Array = pair[1]
		times.sort()
		var n := times.size()
		@warning_ignore("integer_division")
		out[pair[0] + "median_ms"] = times[n / 2] / 1000.0 if n > 0 else 0.0
		out[pair[0] + "p95_ms"] = times[mini(int(n * 0.95), n - 1)] / 1000.0 if n > 0 else 0.0
		out[pair[0] + "worst_ms"] = times[n - 1] / 1000.0 if n > 0 else 0.0
	return out


# How much a route grid square costs to cross (1 = open ground), at a global
# position; INF where the square is blocked.
func route_cost_at(global_pos: Vector2) -> float:
	var grid := _route_grid
	if grid == null:
		return 1.0
	var cell := grid.cell_of(to_local(global_pos))
	return INF if grid.is_solid(cell) else grid.weight(cell)


# The route grid square (ROUTE_CELL px) a global position is in, as a key for
# caches; a square of the same size over the map when the grid isn't built.
func route_cell(global_pos: Vector2) -> Vector2i:
	var local := to_local(global_pos)
	if _route_grid == null:
		return Vector2i((local / ROUTE_CELL).floor())
	return _route_grid.cell_of(local)


# The area the route grid covers, in global space (empty while it isn't
# built).
func route_area() -> Rect2:
	var grid := _route_grid
	if grid == null:
		return Rect2()
	return grid.xform * Rect2(grid.origin, Vector2(grid.size) * ROUTE_CELL)


# How many building walls the segment from `a` to `b` (global) crosses: each
# footprint edge it cuts is one wall, so passing through a building counts
# two. Plain maths over the footprints near the segment, no physics.
func walls_crossed(a: Vector2, b: Vector2) -> int:
	if _polys.is_empty():
		return 0
	var mid := (a + b) * 0.5
	var walls := 0
	# buildings_within gathers every building near the segment's midpoint,
	# most of them nowhere near the line itself; the footprint's rectangle is
	# tested against the segment first, so only the buildings it actually
	# passes have their edges checked (a cold position pick asks this for
	# dozens of segments at once, and this is what made it a frame hitch).
	var la := to_local(a)
	var lb := to_local(b)
	for i in buildings_within(mid, a.distance_to(b) * 0.5 + 1.0):
		if not segment_hits_rect(la, lb, _rects[i]):
			continue
		var poly := global_polygon(i)
		for k in poly.size():
			if Geometry2D.segment_intersects_segment(a, b, poly[k], poly[(k + 1) % poly.size()]) != null:
				walls += 1
	return walls


# Whether the segment a-b passes through `rect` (Liang-Barsky clipping).
static func segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var lo := rect.position
	var hi := rect.end
	# Each of the four edges clips the parameter range [t0, t1].
	for side in 4:
		var p: float
		var q: float
		if side == 0:
			p = -d.x
			q = a.x - lo.x
		elif side == 1:
			p = d.x
			q = hi.x - a.x
		elif side == 2:
			p = -d.y
			q = a.y - lo.y
		else:
			p = d.y
			q = hi.y - a.y
		if p == 0.0:
			if q < 0.0:
				return false
			continue
		var t := q / p
		if p < 0.0:
			if t > t1:
				return false
			t0 = maxf(t0, t)
		else:
			if t < t0:
				return false
			t1 = minf(t1, t)
	return t0 <= t1


# ---- Route solver (its own thread) ----

func _start_route_solver() -> void:
	_route_quit = false
	_route_thread = Thread.new()
	_route_thread.start(_route_worker)


func _stop_route_solver() -> void:
	if _route_thread == null:
		return
	_route_mutex.lock()
	_route_quit = true
	_route_mutex.unlock()
	_route_semaphore.post()
	_route_thread.wait_to_finish()
	_route_thread = null
	_route_mutex.lock()
	_route_queue.clear()
	_route_mutex.unlock()


# The solver thread: one queued route at a time, until told to quit. It
# touches the field's queue, results and stats only under the mutex, and
# nothing else of the field.
func _route_worker() -> void:
	while true:
		_route_semaphore.wait()
		_route_mutex.lock()
		if _route_quit:
			_route_mutex.unlock()
			return
		var job: RouteJob = null
		if not _route_queue.is_empty():
			job = _route_queue.pop_front()
			if _route_cancelled.has(job.ticket):
				_route_cancelled.erase(job.ticket)
				job = null
		_route_mutex.unlock()
		if job == null:
			continue
		var started := Time.get_ticks_usec()
		var route := _solve_route(job)
		var took := Time.get_ticks_usec() - started
		_route_mutex.lock()
		if _route_cancelled.has(job.ticket):
			_route_cancelled.erase(job.ticket)
		else:
			_route_results[job.ticket] = [route, Time.get_ticks_msec()]
		if _route_solve_usec.size() >= 4096:
			_route_solve_usec = _route_solve_usec.slice(1024)
			_route_search_usec = _route_search_usec.slice(1024)
		_route_solve_usec.append(took)
		_route_search_usec.append(job.search_usec)
		_route_mutex.unlock()


# Drops solved routes nobody collected within ROUTE_RESULT_TTL_MS. Called
# with the mutex held.
func _drop_stale_routes() -> void:
	if _route_results.size() < 16:
		return
	var now := Time.get_ticks_msec()
	for ticket in _route_results.keys():
		if now - int(_route_results[ticket][1]) > ROUTE_RESULT_TTL_MS:
			_route_results.erase(ticket)


# One route, on the solver thread: reads only the job and its grid. A start
# or goal square that is blocked (standing in a wall's clearance) is moved to
# the nearest open square.
static func _solve_route(job: RouteJob) -> PackedVector2Array:
	var grid := job.grid
	var a := _open_cell_near(grid, job.from_cell)
	var b := _open_cell_near(grid, job.to_cell)
	var out := PackedVector2Array()
	if a.x >= 0 and b.x >= 0 and a != b:
		var started := Time.get_ticks_usec()
		var cells := grid.astar.get_id_path(a, b, true)
		job.search_usec = Time.get_ticks_usec() - started
		if cells.size() > 1:
			var kept := _route_simplify(grid, cells)
			for k in range(1, kept.size()):
				out.append(grid.xform * grid.centre_of(kept[k]))
	var goal := _clamp_to_grid(grid, job.goal)
	if out.is_empty():
		out.append(goal)
	else:
		out[out.size() - 1] = goal
	return out


## A blocked start or goal square is moved to an open one at most this many
## squares away.
const ROUTE_OPEN_SEARCH := 4


# `cell`, or the nearest open square to it within ROUTE_OPEN_SEARCH (by
# rings); (-1, -1) when there is none.
static func _open_cell_near(grid: RouteGrid, cell: Vector2i) -> Vector2i:
	if not grid.is_solid(cell):
		return cell
	for r in range(1, ROUTE_OPEN_SEARCH + 1):
		for dx in range(-r, r + 1):
			for dy: int in [-r, r]:
				var c := cell + Vector2i(dx, dy)
				if not grid.is_solid(c):
					return c
		for dy in range(-r + 1, r):
			for dx: int in [-r, r]:
				var c := cell + Vector2i(dx, dy)
				if not grid.is_solid(c):
					return c
	return Vector2i(-1, -1)


# A global position moved into the grid's area, half a square in from its
# edge.
static func _clamp_to_grid(grid: RouteGrid, global_pos: Vector2) -> Vector2:
	var local := grid.xform.affine_inverse() * global_pos
	var lo := grid.origin + Vector2(ROUTE_CELL, ROUTE_CELL) * 0.5
	var hi := grid.origin + Vector2(grid.size) * ROUTE_CELL - Vector2(ROUTE_CELL, ROUTE_CELL) * 0.5
	var clamped := local.clamp(lo, hi)
	return global_pos if clamped == local else grid.xform * clamped


# Keeps only the cells where the route turns: from each kept cell, jumps to
# the furthest later cell (up to ROUTE_SIMPLIFY_REACH on) that a straight
# line reaches for no more cost than the path itself takes between them. The
# path's cost from its start is summed once (path_cost), and the candidates
# are tried from the furthest down, so the first line that passes is the
# jump.
const ROUTE_SIMPLIFY_REACH := 39

static func _route_simplify(grid: RouteGrid, cells: Array[Vector2i]) -> Array[Vector2i]:
	var n := cells.size()
	var w := grid.size.x
	var weights := grid.weights
	var path_cost := PackedFloat64Array()
	path_cost.resize(n)
	for j in range(1, n):
		var c := cells[j]
		path_cost[j] = path_cost[j - 1] + weights[c.y * w + c.x] * Vector2(cells[j - 1]).distance_to(Vector2(c))
	var kept: Array[Vector2i] = [cells[0]]
	var i := 0
	while i < n - 1:
		var best := i + 1
		for j in range(mini(n - 1, i + ROUTE_SIMPLIFY_REACH), i + 1, -1):
			if _route_line_cost(grid, cells[i], cells[j]) <= (path_cost[j] - path_cost[i]) * 1.02:
				best = j
				break
		kept.append(cells[best])
		i = best
	return kept


# What a straight line between two cells costs, in the same units as the
# path (weight times cells crossed); INF through a blocked square. Every
# sample lies between the two cells, so inside the grid.
static func _route_line_cost(grid: RouteGrid, a: Vector2i, b: Vector2i) -> float:
	var w := grid.size.x
	var solid := grid.solid
	var weights := grid.weights
	var from := Vector2(a)
	var length := from.distance_to(Vector2(b))
	var steps := maxi(ceili(length * 2.0), 1)
	var step := (Vector2(b) - from) / steps
	var cost := 0.0
	for s in range(1, steps + 1):
		var c := Vector2i((from + step * s).round())
		var k := c.y * w + c.x
		if solid[k] != 0:
			return INF
		cost += weights[k]
	return cost * length / steps


# ---- Route grid build ----

# Gathers what the grid needs on the main thread, then builds it on a worker
# thread. Waits for the VehicleField (built a frame after load) if there is one.
func _start_route_build() -> void:
	if _polys.is_empty() or _route_task >= 0 or _route_grid != null:
		return
	var vehicles := VehicleField.find(self)
	if vehicles and not vehicles.is_built():
		get_tree().create_timer(0.1, true, true).timeout.connect(_start_route_build, CONNECT_ONE_SHOT)
		return
	var area := _route_play_area()
	var bounds := area
	if not area.has_area():
		bounds = _rects[0]
		for r in _rects:
			bounds = bounds.merge(r)
	var veh_pos := PackedVector2Array()
	var veh_mass := PackedFloat32Array()
	if vehicles:
		for i in vehicles.vehicle_count():
			if not vehicles.is_trampled(i) and not vehicles.is_destroyed(i):
				var at := to_local(vehicles.vehicle_transform(i).origin)
				if area.has_area() and not area.has_point(at):
					continue
				veh_pos.append(at)
				veh_mass.append(vehicles.vehicle_mass(i))
				if not area.has_area():
					bounds = bounds.expand(at)
	var solids := _static_outlines()
	solids.append_array(_obstacle_outlines())
	if not area.has_area():
		for poly in solids:
			for v in poly:
				bounds = bounds.expand(v)
		bounds = bounds.grow(ROUTE_MARGIN)
	_keep_solids(solids)
	_route_task = WorkerThreadPool.add_task(_build_route_grid.bind(bounds, veh_pos, veh_mass, solids, global_transform), false, "BuildingField routes")


# The play area in this node's space, from the map's MapBounds; an empty
# rect on a map without one.
func _route_play_area() -> Rect2:
	var bounds := MapBounds.find(self)
	if bounds == null:
		return Rect2()
	var r := bounds.global_play_rect()
	var inv := global_transform.affine_inverse()
	var corners: Array[Vector2] = [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var out := Rect2(inv * r.position, Vector2.ZERO)
	for p in corners:
		out = out.expand(inv * p)
	return out


# Keeps the solid outlines for NPC steering (solids_within and friends), with
# a CELL_SIZE lookup of which reach into each cell.
func _keep_solids(solids: Array[PackedVector2Array]) -> void:
	_solid_polys = solids
	_solid_rects.clear()
	_solid_global.clear()
	_solid_centres.clear()
	_solid_cells.clear()
	for i in solids.size():
		var poly := solids[i]
		var rect := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			rect = rect.expand(v)
		_solid_rects.append(rect)
		_solid_global.append(PackedVector2Array())
		_solid_centres.append(Vector2.INF)
		var c0 := _cell_of(rect.position)
		var c1 := _cell_of(rect.end)
		for cx in range(c0.x, c1.x + 1):
			for cy in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cy)
				if not _solid_cells.has(key):
					_solid_cells[key] = PackedInt32Array()
				_solid_cells[key].append(i)
	_solids_gathered = true


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


# The ObstacleField's outlines (pipes, pools) in this node's space, grown by
# ROUTE_OBSTACLE_CLEARANCE. The field has built them by now: it comes before
# this node in the scene.
func _obstacle_outlines() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var field := ObstacleField.find(self)
	if field == null:
		return out
	var inv := global_transform.affine_inverse()
	for poly in field.outlines():
		var grown := Geometry2D.offset_polygon(inv * poly, ROUTE_OBSTACLE_CLEARANCE)
		if not grown.is_empty():
			out.append(grown[0])
	return out


func _build_route_grid(bounds: Rect2, veh_pos: PackedVector2Array, veh_mass: PackedFloat32Array, solids: Array[PackedVector2Array], xform: Transform2D) -> void:
	var origin := bounds.position
	var size := Vector2i((bounds.size / ROUTE_CELL).ceil()).max(Vector2i.ONE)
	var n := size.x * size.y
	var extra := PackedFloat32Array()
	extra.resize(n)
	# Building cover: five samples per square (centre and four inner corners).
	var offsets := [Vector2(0.5, 0.5), Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	for i in _polys.size():
		if _states[i] == BuildingFootprints.COLLAPSED:
			continue
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
	veh.resize(n)
	for i in veh_pos.size():
		var c := Vector2i(((veh_pos[i] - origin) / ROUTE_CELL).floor())
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
			continue
		var k := c.y * size.x + c.x
		var w := ROUTE_HEAVY_VEHICLE_WEIGHT if veh_mass[i] > ROUTE_HEAVY_MASS else ROUTE_VEHICLE_WEIGHT
		veh[k] = minf(veh[k] + w, ROUTE_VEHICLE_MAX)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(ROUTE_CELL, ROUTE_CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var weights := PackedFloat32Array()
	weights.resize(n)
	for cy in size.y:
		for cx in size.x:
			var k := cy * size.x + cx
			var w := 1.0 + extra[k] + veh[k]
			weights[k] = w
			if w > 1.0:
				astar.set_point_weight_scale(Vector2i(cx, cy), w)
	var solid := PackedByteArray()
	solid.resize(n)
	for poly in solids:
		var r := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			r = r.expand(v)
		var c0 := Vector2i(((r.position - origin) / ROUTE_CELL).floor())
		var c1 := Vector2i(((r.end - origin) / ROUTE_CELL).floor())
		for cx in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
			for cy in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
				var k := cy * size.x + cx
				if solid[k] != 0:
					continue
				var cell_pos := origin + Vector2(cx, cy) * ROUTE_CELL
				var cell := PackedVector2Array([cell_pos, cell_pos + Vector2(ROUTE_CELL, 0), cell_pos + Vector2(ROUTE_CELL, ROUTE_CELL), cell_pos + Vector2(0, ROUTE_CELL)])
				if not Geometry2D.intersect_polygons(cell, poly).is_empty():
					solid[k] = 1
					astar.set_point_solid(Vector2i(cx, cy), true)
	var grid := RouteGrid.new()
	grid.astar = astar
	grid.size = size
	grid.origin = origin
	grid.weights = weights
	grid.solid = solid
	grid.xform = xform
	_route_result = grid


func _finish_route_build() -> void:
	WorkerThreadPool.wait_for_task_completion(_route_task)
	_route_task = -1
	if _route_result != null:
		_route_grid = _route_result
	_route_result = null


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


# [distance, id] of the building nearest a position in this node's space;
# [INF, -1] with none in its cell.
func _nearest(pos: Vector2) -> Array:
	var best := INF
	var best_id := -1
	for i in _cells.get(_cell_of(pos), PackedInt32Array()):
		if best < INF and not _rects[i].grow(best).has_point(pos):
			continue
		var d := _distance_to(i, pos)
		if d < best:
			best = d
			best_id = i
		if best == 0.0:
			break
	return [best, best_id]


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
