extends TestSuite

# MapLayersTest: the map layers from the districts and ruins brief.
# The border band (MapBounds) stops a mecha but no ray; the camera never
# shows past the map's edge; pipes and pools (ObstacleField) stop a mecha and
# a pushed car but no shot or sight, merged into one body per cell; market
# stalls (StallField) break when a mecha walks into one, a shot flies over
# one or a blast reaches one, and stop no shot; gutted buildings keep their
# wall and slow but don't count as inside; collapsed ones have no wall, no
# slow and are no building at all; a mecha in a damaged building shows to
# the player outside (through the roof's holes), one in an intact building
# doesn't.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const CAMERA := preload("res://game/ui/Camera.gd")
const STALL_TEX := preload("res://assets/images/map/props/vehicle_hatchback.png")
const RUIN_TEX := preload("res://assets/images/map/props/stall_canopy_broken.png")

const DT := 1.0 / 60.0
const WALK := 480.0
# Building squares 400 px wide: A at x 0..400, B at 1000..1400, both y 0..400.
const A := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]
const B := [Vector2(1000, 0), Vector2(1400, 0), Vector2(1400, 400), Vector2(1000, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null


func _init() -> void:
	time_scale = 1.0


func run_tests() -> void:
	await case("the border band stops a mecha, not a ray", _test_border)
	await case("the camera never shows past the map's edge", _test_camera)
	await case("pipes stop mechas and cars, not shots or sight", _test_obstacles)
	await case("a stall breaks when a mecha walks into it", _test_stall_walk)
	await case("a stall breaks under a shot or a blast and stops nothing", _test_stall_shot)
	await case("huts break like stalls; a ruined one is broken from the start", _test_huts)
	await case("a gutted building keeps its wall and slow but isn't entered", _test_gutted)
	await case("a collapsed building is only rubble", _test_collapsed)
	await case("a mecha in a damaged building shows through the roof", _test_damaged_view)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)


func _mecha(pos: Vector2, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.global_rotation = 0.0
	mecha.set_illuminator(false)
	_arena.mechas.append(mecha)
	return mecha


func _walk(mecha: Mecha, vel: Vector2, seconds: float) -> void:
	for _i in int(seconds / DT):
		await get_tree().physics_frame
		mecha.move(vel)


func _field(polys: Array, states: Array = []) -> BuildingField:
	var footprints := BuildingFootprints.new()
	var starts := PackedInt32Array([0])
	for poly in polys:
		footprints.points.append_array(PackedVector2Array(poly))
		starts.append(footprints.points.size())
	footprints.starts = starts
	footprints.state = PackedByteArray(states)
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	return field


func _rays_pass(from: Vector2, to: Vector2) -> bool:
	var space := _arena.get_world_2d().direct_space_state
	for mask in [MapSenses.SHOT_MASK, MapSenses.SIGHT_MASK, MapSenses.NON_WALL_MASK]:
		var query := PhysicsRayQueryParameters2D.create(from, to, mask)
		if not space.intersect_ray(query).is_empty():
			return false
	return true


func _test_border() -> void:
	var bounds := MapBounds.new()
	bounds.map_rect = Rect2(-3000, -3000, 6000, 6000)
	bounds.border = 1000.0
	_arena.add_child(bounds)
	await get_tree().physics_frame
	check_eq(bounds.play_rect(), Rect2(-2000, -2000, 4000, 4000), "the play area is the map less the band")
	check(bounds.is_in_play_area(Vector2(1900, 0)) and not bounds.is_in_play_area(Vector2(2100, 0)), "the play area test")
	var mecha := _mecha(Vector2(1500, 0))
	await get_tree().physics_frame
	await _walk(mecha, Vector2(WALK, 0), 2.0)
	check(mecha.global_position.x < 2000.0, "the mecha stops at the band's edge (x %.0f)" % mecha.global_position.x)
	check(mecha.global_position.x > 1700.0, "after walking up to it (x %.0f)" % mecha.global_position.x)
	check(_rays_pass(Vector2(1800, 200), Vector2(2800, 200)), "shot, sight and steering rays cross the band")
	check(MapSenses.trace_shot(_arena.get_world_2d(), Vector2(1800, 200), Vector2(2800, 200), 1).stop == null,
			"a shot is not stopped by it")


func _test_camera() -> void:
	var map := Rect2(-3000, -3000, 6000, 6000)
	var view := Vector2(2000, 1000)
	check_eq(CAMERA.view_centre_in(map, Vector2(0, 0), view), Vector2(0, 0), "a view inside the map stays")
	check_eq(CAMERA.view_centre_in(map, Vector2(2800, -2900), view), Vector2(2000, -2500), "a view past a corner is pulled in")
	check_eq(CAMERA.view_centre_in(map, Vector2(100, 2900), Vector2(8000, 1000)), Vector2(0, 2500),
			"a view wider than the map is centred on it")
	var bounds := MapBounds.new()
	bounds.map_rect = Rect2(-10000, -10000, 20000, 20000)
	bounds.border = 4000.0
	map = bounds.map_rect
	_arena.add_child(bounds)
	var cam := Camera2D.new()
	cam.set_script(CAMERA)
	cam.position = Vector2(6000, 0)
	cam.zoom = Vector2(0.5, 0.5)
	_arena.add_child(cam)
	cam.make_current()
	cam.pan_offset = Vector2(3000, 0)
	await wait_frames(3)
	var size := get_viewport().get_visible_rect().size / cam.zoom
	var right := cam.global_position.x + cam.offset.x + size.x * 0.5
	check(right <= map.end.x + 0.5, "a pan toward the edge stops with the view's edge on the map's (%.0f)" % right)
	check(cam.offset.x > 0.0, "it still pans as far as it can")
	cam.pan_offset = Vector2.ZERO
	await wait_frames(2)
	check_eq(cam.offset, Vector2.ZERO, "back in the middle, no clamp")
	print("    view at zoom 0.5: %.0f x %.0f px; half-width %.0f px against the 200 m band (4000 px)" % [size.x, size.y, size.x * 0.5])


func _test_obstacles() -> void:
	# A pipe rack outline across the way, 100 px deep.
	var obstacles := MapObstacles.new()
	obstacles.points = PackedVector2Array([Vector2(800, -600), Vector2(900, -600), Vector2(900, 600), Vector2(800, 600),
			Vector2(5800, 0), Vector2(5900, 0), Vector2(5900, 100), Vector2(5800, 100)])
	obstacles.starts = PackedInt32Array([0, 4, 8])
	obstacles.kind = PackedByteArray([MapObstacles.PIPE, MapObstacles.POOL])
	var field := ObstacleField.new()
	field.obstacles = obstacles
	_arena.add_child(field)
	check_eq(field.count(), 2, "both outlines are read")
	check_eq(field.body_count(), 2, "one body per cell (two cells here)")
	check(ObstacleField.find(_arena) == field, "find() reaches it")
	check(field.is_blocked(Vector2(850, 0)) and not field.is_blocked(Vector2(700, 0)), "is_blocked inside the outline only")
	var mecha := _mecha(Vector2(300, 0))
	await get_tree().physics_frame
	await _walk(mecha, Vector2(WALK, 0), 2.0)
	check(mecha.global_position.x < 800.0, "the mecha stops at the pipes (x %.0f)" % mecha.global_position.x)
	check(_rays_pass(Vector2(600, 300), Vector2(1100, 300)), "shot, sight and steering rays pass over them")
	check(not MapSenses.walls_between(_arena.get_world_2d(), Vector2(600, 300), Vector2(1100, 300)), "they are no wall")
	check(not MapSenses.sight_blocked(_arena.get_world_2d(), Vector2(600, 300), Vector2(1100, 300)), "sight passes")


# A field of breakable props of `kind` at `points`; `variants` gives each
# one's texture (0 the intact one, 1 a "_broken" file), all 0 if empty.
func _stalls(points: Array, kind := "stall", variants: Array = []) -> StallField:
	var spawn_set := PropSpawnSet.new()
	spawn_set.kinds = PackedStringArray([kind])
	for k in points.size():
		spawn_set.kind.append(0)
		spawn_set.position.append(points[k])
		spawn_set.rotation.append(0.0)
		spawn_set.size.append(Vector2(60, 50))
		spawn_set.variant.append(variants[k] if k < variants.size() else 0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawn_set
	_arena.add_child(spawner)
	var layer := PropSpriteLayer.new()
	layer.name = "Stalls"
	layer.kinds = PackedStringArray([kind])
	layer.textures = {kind: [STALL_TEX, RUIN_TEX]}
	layer.spans = {kind: PackedFloat32Array([1.0, 1.0])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
	var field := StallField.new()
	field.spawner_path = NodePath("../PropSpawner")
	field.layer_path = NodePath("../Stalls")
	field.kind = kind
	field.spills_goods = kind == "stall"
	_arena.add_child(field)
	return field


func _test_stall_walk() -> void:
	var field := _stalls([Vector2(600, 0), Vector2(600, 800)])
	var mecha := _mecha(Vector2(200, 0))
	await wait_frames(3)
	check(field.is_built() and field.stall_count() == 2, "two stalls are read")
	await _walk(mecha, Vector2(WALK, 0), 1.5)
	check(field.is_broken(0), "the stall in the mecha's way breaks")
	check(not field.is_broken(1), "the one off to the side doesn't")
	check(mecha.global_position.x > 700.0, "the stall doesn't stop the mecha (x %.0f)" % mecha.global_position.x)
	check(field.get_child_count() > 1, "its remains and pieces are drawn")
	await _walk(mecha, Vector2(-WALK, 0), 1.0)
	check(field.is_broken(0) and field.broken_count() == 1, "it stays broken")


func _test_stall_shot() -> void:
	var field := _stalls([Vector2(600, 0), Vector2(600, 800), Vector2(2000, 0)])
	await wait_frames(3)
	var w := _arena.get_world_2d()
	var probe := MapSenses.trace_shot(w, Vector2(200, 0), Vector2(1000, 0), 1)
	check(not field.is_broken(0), "a trace without damage (a probe) breaks nothing")
	check(probe.stop == null, "a stall doesn't stop a shot")
	var shot := MapSenses.trace_shot(w, Vector2(200, 0), Vector2(1000, 0), 1, false, true)
	check(field.is_broken(0), "a real shot over the stall breaks it")
	check(shot.stop == null and shot.ap == 1, "and goes on with its AP")
	StallField.shot_through(null, Vector2(200, 800), Vector2(500, 800))
	check(not field.is_broken(1), "a shot that ends short of a stall leaves it")
	StallField.blast_at(Vector2(2050, 60), 150.0)
	check(field.is_broken(2), "a blast breaks the stall in its radius")
	check(not field.is_broken(1), "but not one far away")


func _test_huts() -> void:
	var field := _stalls([Vector2(600, 0), Vector2(600, 800), Vector2(2000, 0)], "hut", [0, 1, 0])
	var mecha := _mecha(Vector2(200, 0))
	await wait_frames(3)
	check(field.is_built() and field.stall_count() == 3, "a field of another kind reads its spawns")
	check(field.is_broken(1) and field.broken_count() == 1, "a spawn drawn with a _broken texture is a ruin from the start")
	check(field.get_child_count() == 0, "and has no node of its own")
	StallField.blast_at(Vector2(600, 800), 150.0)
	check(field.get_child_count() == 0, "a blast on a ruin breaks nothing more")
	await _walk(mecha, Vector2(WALK, 0), 1.5)
	check(field.is_broken(0), "an intact hut in the mecha's way breaks")
	var pieces := field.get_child_count()
	check(pieces >= 1 + StallField.PIECES.x and pieces <= 1 + StallField.PIECES.y, "into its remains and loose pieces, with no goods (%d nodes)" % pieces)
	check(not field.is_broken(2), "the one far away stands")


func _test_gutted() -> void:
	var field := _field([A, B], [BuildingFootprints.GUTTED, BuildingFootprints.INTACT])
	var w := _arena.get_world_2d()
	await get_tree().physics_frame
	check(MapSenses.walls_between(w, Vector2(-200, 200), Vector2(200, 200)), "its whole outline is still a wall")
	check(field.building_at(Vector2(200, 200)) == 0, "it is still a building (two inside see each other)")
	var mecha := _mecha(Vector2(200, 200))
	await wait_frames(3)
	check(mecha.is_entering_building, "the edge slow applies")
	check(not mecha.is_inside_building, "but the mecha isn't inside (no roof: no zoom)")
	mecha.global_position = Vector2(1200, 200)
	await wait_frames(3)
	check(mecha.is_inside_building, "in the intact building it is")


func _test_collapsed() -> void:
	var field := _field([A, B], [BuildingFootprints.COLLAPSED, BuildingFootprints.INTACT])
	var w := _arena.get_world_2d()
	await get_tree().physics_frame
	check(not MapSenses.walls_between(w, Vector2(-200, 200), Vector2(200, 200)), "no wall")
	check(MapSenses.walls_between(w, Vector2(700, 200), Vector2(1200, 200)), "the intact one keeps its wall")
	check_eq(field.building_at(Vector2(200, 200)), -1, "it is no building")
	check(not field.is_standing(0) and field.is_standing(1), "is_standing")
	check(field.buildings_within(Vector2(200, 200), 100.0).is_empty(), "NPC steering doesn't see it")
	check_eq(field.walls_crossed(Vector2(-200, 200), Vector2(600, 200)), 0, "walls_crossed counts none")
	var mecha := _mecha(Vector2(200, 200))
	await wait_frames(3)
	check(not mecha.is_entering_building and not mecha.is_inside_building, "no slow, no entering")
	check_eq(field.wall_body_count(), 1, "only the standing building has a wall body")


func _test_damaged_view() -> void:
	_field([A, B], [BuildingFootprints.DAMAGED, BuildingFootprints.INTACT])
	var player: Mecha = _mecha(Vector2(-150, 200), PLAYER)
	player.mecha_name = "Player"
	player.set_physics_process(false)
	var in_damaged := _mecha(Vector2(100, 200))
	var in_intact := _mecha(Vector2(1100, 200))
	await wait_frames(3)
	check(player.can_see_body(in_damaged), "the mecha in the damaged building shows (through the holes)")
	player.global_position = Vector2(850, 200)
	await wait_frames(2)
	check(not player.can_see_body(in_intact), "the one in the intact building stays hidden")
