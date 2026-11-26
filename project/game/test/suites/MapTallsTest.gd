extends TestSuite

# MapTallsTest: the talls sublayer of generated maps (game/map/TallsLean.gd,
# assets/shaders/TallsLean.gdshader, game/map/MapMeshFile.gd). A mesh file
# with a height channel (the generator's flag 2) loads with every vertex's
# height in UV.x, roof files keep their building id and stripe and plain
# files have no UV; the lean is the generator's rule (render_preview.py:
# shift = (vertex - camera) * h / (150 - h), heights clamped to 100 m); a
# point or triangle off screen never leans into the view; and the Talls node
# puts the screen's centre (camera pan and zoom included) and the player's
# position in its material every frame, turns the lean off with no camera,
# and sets the fade from its exports; and it lists the other mechas the
# player can see near the screen (weighted by their view alpha, at most
# MAX_GHOSTS, nearest first) for the shader to fade the talls over them.
# The overheads node (game/map/OverheadMeshFade.gd, OverheadGrain.gdshader)
# keeps the same ghost list, so a canopy never hides a mecha the player can
# see, and puts the player in its material for the fade round the player.
#
# build_meshes.gd converts every mesh file with MapMeshFile.load_mesh, the
# code path checked here.

const SHADER := preload("res://assets/shaders/TallsLean.gdshader")
const OVERHEAD_SHADER := preload("res://assets/shaders/OverheadGrain.gdshader")
const OVERHEAD_FADE := preload("res://game/map/OverheadMeshFade.gd")
const DIR := "user://test/talls/"


class FakePlayer extends Node2D:
	func _init() -> void:
		add_to_group("mecha")

	func is_player() -> bool:
		return true


class FakeMecha extends Node2D:
	var is_dead := false

	func _init() -> void:
		add_to_group("mecha")


# Synthetic talls geometry, as style.py's tall_prism, tall_post and
# tall_span draw it: vertices (world px), greys, alphas, heights (m) and
# indices, ready for MapMeshFile.write_mesh.
class TallsBuilder:
	var verts := PackedVector2Array()
	var greys := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	var heights := []
	var indices := PackedInt32Array()

	func tri(a: Vector2, b: Vector2, c: Vector2, ha: float, hb: float, hc: float, grey: float) -> void:
		for p in [[a, ha], [b, hb], [c, hc]]:
			indices.append(verts.size())
			verts.append(p[0])
			greys.append(grey)
			alphas.append(1.0)
			heights.append(p[1])

	# A solid from h0 to h1 metres on `ring` (world px): a quad per edge,
	# then the top.
	func prism(ring: PackedVector2Array, h0: float, h1: float, side: float, top: float) -> void:
		for k in ring.size():
			var p := ring[k]
			var q := ring[(k + 1) % ring.size()]
			tri(p, q, q, h0, h0, h1, side)
			tri(p, q, p, h0, h1, h1, side)
		var top_tris := Geometry2D.triangulate_polygon(ring)
		for k in range(0, top_tris.size(), 3):
			tri(ring[top_tris[k]], ring[top_tris[k + 1]], ring[top_tris[k + 2]], h1, h1, h1, top)

	func post(centre: Vector2, width_px: float, h0: float, h1: float, side: float, top: float) -> void:
		var r := width_px * 0.5
		prism(PackedVector2Array([centre + Vector2(-r, -r), centre + Vector2(r, -r), centre + Vector2(r, r),
				centre + Vector2(-r, r)]), h0, h1, side, top)

	# A flat strip from p0 (at h0 m) to p1 (at h1 m).
	func span(p0: Vector2, p1: Vector2, width_px: float, h0: float, h1: float, grey: float) -> void:
		var side := (p1 - p0).orthogonal().normalized() * width_px * 0.5
		tri(p0 + side, p1 + side, p1 - side, h0, h1, h1, grey)
		tri(p0 + side, p1 - side, p0 - side, h0, h1, h0, grey)

	func write(path: String) -> Error:
		return MapMeshFile.write_mesh(path, verts, greys, alphas, indices, MapMeshFile.HEIGHT, heights)


var _root: Node2D = null


func run_tests() -> void:
	await case("a talls mesh file keeps every vertex's height", _test_height_channel)
	await case("roof files keep their id and stripe, plain files have no UV", _test_other_channels)
	await case("the lean is the generator's rule", _test_lean_rule)
	await case("nothing off screen leans into the view", _test_never_leans_in)
	await case("the Talls node follows the screen's centre and the player", _test_material_follows)
	await case("talls fade over the other mechas the player can see", _test_ghosts)
	await case("with no camera the talls stand flat, without errors", _test_no_camera)
	await case("overheads fade over the player and the mechas the player can see", _test_overhead_ghosts)


func before_each() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
		await wait_frames(2)
	_root = Node2D.new()
	add_child(_root)
	DirAccess.make_dir_recursive_absolute(DIR)


func _test_height_channel() -> void:
	var b := TallsBuilder.new()
	b.post(Vector2(1000, 2000), 40.0, 0.0, 42.0, 0.3, 0.5)
	b.span(Vector2(1000, 2000), Vector2(1800, 2000), 30.0, 42.0, 40.0, 0.6)
	var path := DIR + "talls_0_0.bin"
	check_eq(b.write(path), OK, "the synthetic file is written")
	var mesh := MapMeshFile.load_mesh(path)
	if not check(mesh != null and mesh.get_surface_count() == 1, "it loads as one surface"):
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check_eq(verts.size(), b.verts.size(), "every vertex is there")
	check_eq(uvs.size(), verts.size(), "with a UV each")
	var heights_ok := true
	var positions_ok := true
	for i in verts.size():
		heights_ok = heights_ok and is_equal_approx(uvs[i].x, float(b.heights[i])) and uvs[i].y == 0.0
		positions_ok = positions_ok and verts[i].is_equal_approx(b.verts[i])
	check(heights_ok, "UV.x is each vertex's height in metres, UV.y 0")
	check(positions_ok, "positions are the ground positions")
	check(absf(colors[0].r - 0.3) < 0.01 and colors[0].a > 0.99, "greys and alphas come through (%s)" % str(colors[0]))
	check_eq(int(mesh.get_meta("triangles", 0)), roundi(b.indices.size() / 3.0), "the triangle count is kept for build_meshes' total")
	var top := 0.0
	for h in b.heights:
		top = maxf(top, float(h))
	check_eq(top, 42.0, "the post's top is at 42 m")


func _test_other_channels() -> void:
	var verts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(0, 100)])
	var greys := PackedFloat32Array([0.2, 0.2, 0.2])
	var alphas := PackedFloat32Array([1.0, 1.0, 1.0])
	var idx := PackedInt32Array([0, 1, 2])
	var roof_path := DIR + "roofs_0_0.bin"
	MapMeshFile.write_mesh(roof_path, verts, greys, alphas, idx, MapMeshFile.ROOF,
			[Vector2(7, 10003.5), Vector2(7, 10004.0), Vector2(7, 0)])
	var roof := MapMeshFile.load_mesh(roof_path)
	var uvs: PackedVector2Array = roof.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check(uvs[0].is_equal_approx(Vector2(7, 10003.5)) and uvs[2].is_equal_approx(Vector2(7, 0)),
			"a roof keeps its building id in UV.x and its stripe in UV.y")
	var plain_path := DIR + "ground_0_0.bin"
	MapMeshFile.write_mesh(plain_path, verts, greys, alphas, idx)
	var plain := MapMeshFile.load_mesh(plain_path)
	var plain_arrays := plain.surface_get_arrays(0)
	check(plain_arrays[Mesh.ARRAY_TEX_UV] == null or (plain_arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(),
			"a plain mesh has no UV")
	check_eq((plain_arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).size(), 3, "and its vertices")


# The generator's rule (render_preview.read_mesh), written out again.
func _preview_shift(ground: Vector2, camera: Vector2, h: float) -> Vector2:
	var hc := clampf(h, 0.0, 100.0)
	return (ground - camera) * (hc / maxf(150.0 - hc, 1.0))


func _test_lean_rule() -> void:
	check_eq(TallsLean.EYE_M, 150.0, "the eye is 150 m up, as in render_preview.py")
	check_eq(TallsLean.MAX_HEIGHT_M, 100.0, "heights clamp at 100 m, as in render_preview.py")
	var cam := Vector2(5000, -3000)
	check(TallsLean.lean_offset(Vector2(6000, -3000), cam, 0.0) == Vector2.ZERO, "the ground does not move")
	check(TallsLean.lean_offset(cam, cam, 60.0) == Vector2.ZERO, "nor does a point right under the eye")
	check(TallsLean.lean_offset(Vector2(6000, -3000), cam, 50.0).is_equal_approx(Vector2(500, 0)),
			"50 m up, 1000 px east of the centre: 500 px further east")
	check(TallsLean.lean_offset(Vector2(5000, -2000), cam, 75.0).is_equal_approx(Vector2(0, 1000)),
			"75 m up leans as far again as it is from the centre")
	check(TallsLean.lean_offset(Vector2(6000, -3000), cam, 500.0).is_equal_approx(Vector2(2000, 0)),
			"a height past 100 m leans as 100 m does")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1124
	var same := true
	for _i in 200:
		var g := Vector2(rng.randf_range(-50000, 50000), rng.randf_range(-50000, 50000))
		var c := Vector2(rng.randf_range(-50000, 50000), rng.randf_range(-50000, 50000))
		var h := rng.randf_range(0.0, 140.0)
		same = same and TallsLean.lean_offset(g, c, h).is_equal_approx(_preview_shift(g, c, h))
	check(same, "200 random points lean as the preview draws them")


func _test_never_leans_in() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var view_size := Vector2(1920, 1080) / 0.75
	var points_in := 0
	var tris_in := 0
	var tris := 0
	for _i in 2000:
		var cam := Vector2(rng.randf_range(-40000, 40000), rng.randf_range(-40000, 40000))
		var view := Rect2(cam - view_size * 0.5, view_size)
		var g := cam + Vector2(rng.randf_range(-6000, 6000), rng.randf_range(-6000, 6000))
		if not view.has_point(g) and view.has_point(g + TallsLean.lean_offset(g, cam, rng.randf_range(0, 100))):
			points_in += 1
		var a := cam + Vector2(rng.randf_range(-6000, 6000), rng.randf_range(-6000, 6000))
		var b := a + Vector2(rng.randf_range(-3000, 3000), rng.randf_range(-3000, 3000))
		var c := a + Vector2(rng.randf_range(-3000, 3000), rng.randf_range(-3000, 3000))
		var ground := PackedVector2Array([a, b, c])
		var view_poly := PackedVector2Array([view.position, Vector2(view.end.x, view.position.y), view.end,
				Vector2(view.position.x, view.end.y)])
		if not Geometry2D.intersect_polygons(ground, view_poly).is_empty():
			continue
		tris += 1
		var drawn := PackedVector2Array()
		for p in ground:
			drawn.append(p + TallsLean.lean_offset(p, cam, rng.randf_range(0, 100)))
		if not Geometry2D.intersect_polygons(drawn, view_poly).is_empty():
			tris_in += 1
	check_eq(points_in, 0, "no point outside the view leans into it (2000 tries)")
	check(tris > 200, "enough triangles off screen were tried (%d)" % tris)
	check_eq(tris_in, 0, "no triangle wholly off screen leans into it")


func _talls_node() -> TallsLean:
	var talls := TallsLean.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	talls.material = mat
	talls.fade_radius = 750.0
	talls.ghost_alpha = 0.2
	talls.ghost_radius = 320.0
	var b := TallsBuilder.new()
	b.post(Vector2(3000, 2000), 40.0, 0.0, 40.0, 0.3, 0.5)
	b.write(DIR + "talls_1_1.bin")
	var chunk := ChunkMesh.new()
	chunk.mesh = MapMeshFile.load_mesh(DIR + "talls_1_1.bin")
	chunk.bounds = Rect2(2980, 1980, 40, 40)
	chunk.use_parent_material = true
	talls.add_child(chunk)
	_root.add_child(talls)
	return talls


func _test_material_follows() -> void:
	var talls := _talls_node()
	var mat := talls.material as ShaderMaterial
	check_eq(talls.process_priority, TallsLean.PROCESS_PRIORITY, "it runs after the camera has moved")
	check_eq(float(mat.get_shader_parameter("fade_radius")), 750.0, "the fade radius comes from the export")
	check(is_equal_approx(float(mat.get_shader_parameter("ghost_alpha")), 0.2), "and the ghost alpha")
	check_eq(float(mat.get_shader_parameter("ghost_radius")), 320.0, "and the radius round other mechas")
	check_eq(float(mat.get_shader_parameter("eye_m")), TallsLean.EYE_M, "the eye height is set")
	var cam := Camera2D.new()
	cam.position = Vector2(3200, 1900)
	cam.offset = Vector2(400, -100)
	cam.zoom = Vector2(0.75, 0.75)
	_root.add_child(cam)
	cam.make_current()
	var player := FakePlayer.new()
	player.position = Vector2(2900, 2100)
	_root.add_child(player)
	await wait_frames(3)
	check(bool(mat.get_shader_parameter("lean")), "with a camera the talls lean")
	var centre: Vector2 = mat.get_shader_parameter("camera_centre")
	check(centre.distance_to(cam.get_screen_center_position()) < 0.5,
			"from the screen's centre, pan included (%s, camera says %s)" % [str(centre), str(cam.get_screen_center_position())])
	check(centre.distance_to(Vector2(3600, 1800)) < 0.5, "which is the camera plus its offset (%s)" % str(centre))
	var fade: Vector2 = mat.get_shader_parameter("fade_centre")
	check(fade.is_equal_approx(player.global_position), "the fade is round the player")
	cam.offset = Vector2(-600, 300)
	player.position = Vector2(100, 100)
	await wait_frames(2)
	centre = mat.get_shader_parameter("camera_centre")
	check(centre.distance_to(Vector2(2600, 2200)) < 0.5, "a new pan moves the centre the next frame (%s)" % str(centre))
	check((mat.get_shader_parameter("fade_centre") as Vector2).is_equal_approx(Vector2(100, 100)), "and the fade follows the player")
	player.queue_free()
	await wait_frames(40)
	check((mat.get_shader_parameter("fade_centre") as Vector2).x > 1e8, "with the player gone nothing fades")


func _ghost(mat: ShaderMaterial, i: int) -> Vector3:
	var ghosts: PackedVector3Array = mat.get_shader_parameter("ghosts")
	return ghosts[i] if i < ghosts.size() else Vector3.INF


func _test_ghosts() -> void:
	var talls := _talls_node()
	var mat := talls.material as ShaderMaterial
	var cam := Camera2D.new()
	cam.position = Vector2(3000, 2000)
	_root.add_child(cam)
	cam.make_current()
	var player := FakePlayer.new()
	player.position = Vector2(3000, 2000)
	_root.add_child(player)
	var seen := FakeMecha.new()
	seen.position = Vector2(3500, 2100)
	_root.add_child(seen)
	var unseen := FakeMecha.new()
	unseen.position = Vector2(2500, 1900)
	unseen.modulate.a = 0.0
	_root.add_child(unseen)
	var dead := FakeMecha.new()
	dead.position = Vector2(3200, 2200)
	dead.is_dead = true
	_root.add_child(dead)
	var far := FakeMecha.new()
	far.position = Vector2(30000, 2000)
	_root.add_child(far)
	await wait_seconds(TallsLean.GHOST_LIST_TIME + 0.1)
	check_eq(int(mat.get_shader_parameter("ghost_count")), 1,
			"one ghost: the seen mecha (not the player, a body the view hides, a dead one or one far off screen)")
	check(_ghost(mat, 0).is_equal_approx(Vector3(3500, 2100, 1.0)), "at its position, full weight (%s)" % str(_ghost(mat, 0)))
	seen.position = Vector2(3700, 2100)
	seen.modulate.a = 0.5
	await wait_frames(2)
	check(_ghost(mat, 0).is_equal_approx(Vector3(3700, 2100, 0.5)),
			"its position and visibility are written every frame (%s)" % str(_ghost(mat, 0)))
	unseen.modulate.a = 1.0
	await wait_frames(2)
	check_eq(int(mat.get_shader_parameter("ghost_count")), 2, "a body the view shows again makes a ghost")
	var crowd: Array[FakeMecha] = []
	for k in 30:
		var m := FakeMecha.new()
		m.position = Vector2(3000 + 80 * (k + 1), 2000)
		_root.add_child(m)
		crowd.append(m)
	await wait_seconds(TallsLean.GHOST_LIST_TIME + 0.1)
	check_eq(int(mat.get_shader_parameter("ghost_count")), TallsLean.MAX_GHOSTS, "at most MAX_GHOSTS")
	var nearest := true
	for i in TallsLean.MAX_GHOSTS:
		var g := _ghost(mat, i)
		nearest = nearest and Vector2(g.x, g.y).distance_to(cam.get_screen_center_position()) <= 80.0 * 14 + 1.0
	check(nearest, "the ones nearest the screen's centre")
	for m in crowd:
		m.queue_free()
	seen.queue_free()
	unseen.queue_free()
	await wait_frames(2)
	check_eq(int(mat.get_shader_parameter("ghost_count")), 0, "freed bodies leave no ghost")


func _test_no_camera() -> void:
	var talls := _talls_node()
	var mat := talls.material as ShaderMaterial
	await wait_frames(3)
	var viewport_cam := get_viewport().get_camera_2d()
	if viewport_cam != null:
		viewport_cam.enabled = false
		await wait_frames(2)
	check(not bool(mat.get_shader_parameter("lean")), "no camera: the talls stand where they are")
	if viewport_cam != null:
		viewport_cam.enabled = true
	var bare := TallsLean.new()
	_root.add_child(bare)
	await wait_frames(2)
	check(not bare.is_processing(), "a Talls node with no material does nothing")


func _test_overhead_ghosts() -> void:
	var overheads: Node2D = OVERHEAD_FADE.new()
	var mat := ShaderMaterial.new()
	mat.shader = OVERHEAD_SHADER
	overheads.material = mat
	overheads.set("ghost_radius", 360.0)
	var chunk := ChunkMesh.new()
	chunk.use_parent_material = true
	overheads.add_child(chunk)
	_root.add_child(overheads)
	check_eq(float(mat.get_shader_parameter("ghost_radius")), 360.0, "the radius round other mechas comes from the export")
	check_eq(int(mat.get_shader_parameter("ghost_count")), 0, "no ghosts before the first frame")
	var cam := Camera2D.new()
	cam.position = Vector2(3000, 2000)
	_root.add_child(cam)
	cam.make_current()
	var player := FakePlayer.new()
	player.position = Vector2(2600, 2000)
	_root.add_child(player)
	var under := FakeMecha.new()
	under.position = Vector2(3400, 2100)
	_root.add_child(under)
	var unseen := FakeMecha.new()
	unseen.position = Vector2(3300, 1800)
	unseen.modulate.a = 0.0
	_root.add_child(unseen)
	await wait_seconds(MapGhosts.LIST_TIME + 0.1)
	check((mat.get_shader_parameter("fade_centre") as Vector2).is_equal_approx(player.global_position),
			"the fade is round the player")
	check_eq(int(mat.get_shader_parameter("ghost_count")), 1, "one ghost: the mecha the player sees, not the player or a hidden one")
	check(_ghost(mat, 0).is_equal_approx(Vector3(3400, 2100, 1.0)), "at its position, full weight (%s)" % str(_ghost(mat, 0)))
	under.position = Vector2(3500, 2150)
	await wait_frames(2)
	check(_ghost(mat, 0).is_equal_approx(Vector3(3500, 2150, 1.0)), "and it follows the mecha every frame (%s)" % str(_ghost(mat, 0)))
	under.is_dead = true
	await wait_frames(2)
	check_eq(int(mat.get_shader_parameter("ghost_count")), 0, "a dead mecha leaves no ghost")
	var bare: Node2D = OVERHEAD_FADE.new()
	_root.add_child(bare)
	await wait_frames(2)
	check(not bare.is_processing(), "an Overheads node with no material does nothing")
