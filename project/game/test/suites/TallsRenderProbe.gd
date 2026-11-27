extends TestSuite

# TallsRenderProbe: draws talls meshes the way the generated map does (a
# TallsLean node with TallsLean.gdshader, ChunkMesh children using its
# material, z 4) over a plain ground with each object's footprint marked,
# moves the camera to several offsets and saves a screenshot of each. It
# needs a real renderer: run it non-headless, for example
#   godot --rendering-driver d3d12 --resolution 1920x1080 --position 20000,20000
#     res://game/test/RunAllTests.tscn -- --suite=TallsRenderProbe --quit
#     --bins=<dir> --out=<dir>
# --bins: a folder of talls_<r>_<c>.bin files (the generator's format, made
# with style.Layers' tall_prism, tall_post and tall_span); without it the
# probe draws its own (MapTallsTest.TallsBuilder). --out: where the PNGs go.
# --centre=x,y (world px): the camera's home for the shots (default: the
# middle of all the meshes).
# Each shot's camera centre and zoom go in its file name. The ghost shots put
# a stand-in NPC where the highest top leans over the ground, seen (the
# talls fade round it) and hidden by the player's view (they don't). A
# probe, not a test: it runs only when named, and never fails on what it
# sees.

const TALLS_TEST := preload("res://game/test/suites/MapTallsTest.gd")
const SHADER := preload("res://assets/shaders/TallsLean.gdshader")
const GRID_PX := 400.0


class FakePlayer extends Node2D:
	func _init() -> void:
		add_to_group("mecha")

	func is_player() -> bool:
		return true

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 100.0, Color(0.9, 0.3, 0.2))


class FakeNpc extends Node2D:
	func _init() -> void:
		add_to_group("mecha")

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 100.0, Color(0.3, 0.8, 0.4))


var _root: Node2D = null
var _talls: TallsLean = null
var _footprints: Array = []


func _init() -> void:
	case_timeout = 120


func run_tests() -> void:
	if not asked_for():
		return
	if DisplayServer.get_name() == "headless":
		print("  (TallsRenderProbe needs a renderer: run it without --headless)")
		return
	await case("talls lean away from the screen's centre", _test_shots)


func asked_for() -> bool:
	if get_tree().current_scene == self:
		return true
	for filter in TestSession.get_options()["suites"]:
		if str(filter).to_lower() in get_suite_name().to_lower():
			return true
	print("  (a probe: run it with --suite=%s)" % get_suite_name())
	return false


func _arg(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return ""


func _build() -> Rect2:
	_root = Node2D.new()
	add_child(_root)
	var ground := Polygon2D.new()
	ground.color = Color(0.16, 0.16, 0.16)
	_root.add_child(ground)
	var grid := Node2D.new()
	grid.draw.connect(func():
		for k in range(-30, 31):
			var c := Color(0.24, 0.24, 0.24) if k % 5 != 0 else Color(0.34, 0.34, 0.34)
			grid.draw_line(Vector2(k * GRID_PX, -12000), Vector2(k * GRID_PX, 12000), c, 4.0)
			grid.draw_line(Vector2(-12000, k * GRID_PX), Vector2(12000, k * GRID_PX), c, 4.0))
	_root.add_child(grid)
	_talls = TallsLean.new()
	_talls.name = "Talls"
	_talls.z_index = 4
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	mat.set_shader_parameter("grain", tex)
	_talls.material = mat
	_root.add_child(_talls)
	var bins := _arg("bins")
	var files: Array[String] = []
	if not bins.is_empty():
		for f in DirAccess.get_files_at(bins):
			if f.begins_with("talls_") and f.ends_with(".bin"):
				files.append(bins.path_join(f))
	if files.is_empty():
		DirAccess.make_dir_recursive_absolute("user://test/talls_probe/")
		var b = TALLS_TEST.TallsBuilder.new()
		b.post(Vector2(0, 0), 40.0, 0.0, 45.0, 0.42, 0.6)
		b.span(Vector2(0, 0), Vector2(1000, 0), 28.0, 45.0, 45.0, 0.55)
		b.span(Vector2(0, 0), Vector2(-300, 0), 32.0, 45.0, 45.0, 0.5)
		b.post(Vector2(-600, 200), 100.0, 0.0, 30.0, 0.35, 0.55)
		b.prism(PackedVector2Array([Vector2(600, -500), Vector2(1200, -500), Vector2(1200, -100), Vector2(600, -100)]),
				0.0, 40.0, 0.3, 0.45)
		var path := "user://test/talls_probe/talls_0_0.bin"
		b.write(path)
		files.append(path)
	var area := Rect2()
	for path in files:
		var mesh := MapMeshFile.load_mesh(path)
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var chunk := ChunkMesh.new()
		chunk.name = path.get_file().get_basename()
		chunk.mesh = mesh
		var aabb := mesh.get_aabb()
		chunk.bounds = Rect2(aabb.position.x, aabb.position.y, aabb.size.x, aabb.size.y)
		chunk.use_parent_material = true
		_talls.add_child(chunk)
		area = chunk.bounds if not area.has_area() else area.merge(chunk.bounds)
		_mark_footprints(mesh)
	var under := area.grow(8000.0)
	ground.polygon = PackedVector2Array([under.position, Vector2(under.end.x, under.position.y), under.end,
			Vector2(under.position.x, under.end.y)])
	grid.position = (area.get_center() / (GRID_PX * 5.0)).round() * GRID_PX * 5.0
	print("    %d talls meshes, over %s" % [_talls.get_child_count(), str(area)])
	return area


# Marks where each talls vertex stands on the ground (its height 0 point):
# a dot per vertex, drawn on the ground layer.
func _mark_footprints(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var marks := Node2D.new()
	marks.draw.connect(func():
		for v in verts:
			marks.draw_circle(v, 9.0, Color(0.55, 0.75, 0.95)))
	_root.add_child(marks)


# Where the centre of the highest top is drawn with the camera at `camera`:
# a spot the leaning top covers, away from the tall thing's foot.
func _under_highest_top(camera: Vector2) -> Vector2:
	var top := -1.0
	var sum := Vector2.ZERO
	var n := 0
	for chunk in _talls.get_children():
		var mesh := (chunk as ChunkMesh).mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in verts.size():
			if uvs[i].x > top + 0.01:
				top = uvs[i].x
				sum = Vector2.ZERO
				n = 0
			if absf(uvs[i].x - top) <= 0.01:
				sum += verts[i]
				n += 1
	var ground := sum / maxi(n, 1)
	return ground + TallsLean.lean_offset(ground, camera, top)


func _shot(cam: Camera2D, out: String, name: String, centre: Vector2, zoom: float, frames := 6) -> void:
	cam.position = centre
	cam.zoom = Vector2(zoom, zoom)
	for _i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var file := out.path_join("talls_%s_cam%+d%+d_z%.2f.png" % [name, roundi(centre.x), roundi(centre.y), zoom])
	img.save_png(file)
	var mat := _talls.material as ShaderMaterial
	print("    %s  lean=%s centre=%s" % [file.get_file(), str(mat.get_shader_parameter("lean")),
			str(mat.get_shader_parameter("camera_centre"))])


func _test_shots() -> void:
	var out := _arg("out")
	if out.is_empty():
		out = ProjectSettings.globalize_path("user://test/talls_probe")
	DirAccess.make_dir_recursive_absolute(out)
	var area := _build()
	var c := area.get_center()
	var centre := _arg("centre").split_floats(",")
	if centre.size() == 2:
		c = Vector2(centre[0], centre[1])
	var cam := Camera2D.new()
	_root.add_child(cam)
	cam.make_current()
	await wait_frames(2)
	await _shot(cam, out, "centre", c, 0.6)
	await _shot(cam, out, "west", c + Vector2(-1600, 0), 0.6)
	await _shot(cam, out, "southeast", c + Vector2(1400, 1000), 0.6)
	await _shot(cam, out, "north", c + Vector2(0, -1100), 0.6)
	await _shot(cam, out, "wide", c + Vector2(-800, 600), 0.35)
	var player := FakePlayer.new()
	player.z_index = 2
	_root.add_child(player)
	player.position = c + Vector2(300, 0)
	player.queue_redraw()
	# The Talls node looks for a new player every 30 frames.
	await _shot(cam, out, "fade", c + Vector2(-500, 300), 0.6, 40)
	player.queue_free()
	var npc := FakeNpc.new()
	npc.z_index = 2
	npc.position = _under_highest_top(c)
	_root.add_child(npc)
	print("    an NPC at %s, under the highest top as drawn from %s" % [str(npc.position), str(c)])
	await _shot(cam, out, "ghost_seen", c, 0.6, 20)
	npc.modulate.a = 0.0
	await _shot(cam, out, "ghost_unseen", c, 0.6)
	npc.queue_free()
	_talls.set_process(false)
	(_talls.material as ShaderMaterial).set_shader_parameter("lean", false)
	await _shot(cam, out, "flat", c, 0.6)
	check(true, "shots saved in " + out)
	_root.queue_free()
