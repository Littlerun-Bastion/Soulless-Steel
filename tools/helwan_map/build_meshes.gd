extends SceneTree

# Turns the generator's work files into the Godot resources that
# helwan_generated.tscn uses, in res://assets/maps/helwan/.
#
# Run from the Godot project folder:
#   godot --headless -s path/to/build_meshes.gd -- path/to/work_dir
#
# work_dir/manifest.json lists the mesh names. Each name.bin holds:
#   int32 vertex count, int32 index count, int32 1 if roof channels follow
#   (else 0), float32 x,y per vertex (world px), uint8 grey,alpha per vertex,
#   then for roofs float32 building id and float32 stripe coordinate per
#   vertex, then uint32 vertex indices (three per triangle, in draw order).
# The building id goes into UV.x and the stripe coordinate into UV.y, where
# the roof shader reads them. Each becomes name.res (ArrayMesh).
#
# footprints.bin -> footprints.res (BuildingFootprints): int32 building count
# n, then per building int32 point count and float32 x,y per point; then
# (version 2) n uint8 ruin states and n uint8 district codes.
#
# districts.bin -> districts.res (MapDistricts): int32 width, int32 height,
# float32 origin x, origin y, cell size (px), then width x height uint8
# codes, row by row.
#
# obstacles.bin -> obstacles.res (MapObstacles): int32 count; per obstacle
# int32 kind, int32 point count k, k x float32 x,y.
#
# props.json -> props.res (PropSpawnSet) and salvage.json -> salvage.res
# (SalvageSpawnSet); see props.py and salvage.py for their fields.

const OUT_DIR := "res://assets/maps/helwan"
const FOOTPRINTS_SCRIPT := "res://game/map/BuildingFootprints.gd"
const DISTRICTS_SCRIPT := "res://game/map/MapDistricts.gd"
const OBSTACLES_SCRIPT := "res://game/map/MapObstacles.gd"
const SPAWN_SET_SCRIPT := "res://game/map/props/PropSpawnSet.gd"
const SALVAGE_SCRIPT := "res://game/map/salvage/SalvageSpawnSet.gd"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the work folder after --")
		quit(1)
		return
	var src: String = args[0]
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(src + "/manifest.json"))
	if manifest == null:
		push_error("Could not read manifest.json in " + src)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var names: Array = manifest.keys() if manifest is Dictionary else manifest
	var total := 0
	for mesh_name in names:
		var mesh := _load_mesh(src + "/" + mesh_name + ".bin")
		total += mesh.get_meta("triangles", 0)
		_save(mesh, "%s/%s.res" % [OUT_DIR, mesh_name])
	var fp := _load_footprints(src + "/footprints.bin")
	_save(fp, OUT_DIR + "/footprints.res")
	var props := _load_props(src + "/props.json")
	_save(props, OUT_DIR + "/props.res")
	var districts := _load_districts(src + "/districts.bin")
	_save(districts, OUT_DIR + "/districts.res")
	var obstacles := _load_obstacles(src + "/obstacles.bin")
	_save(obstacles, OUT_DIR + "/obstacles.res")
	var salvage := _load_salvage(src + "/salvage.json")
	_save(salvage, OUT_DIR + "/salvage.res")
	print("built ", names.size(), " meshes, triangles: ", total, ", buildings: ", fp.count(),
		", prop spawns: ", props.count(), ", district cells: ", districts.codes.size(),
		", obstacles: ", obstacles.count(), ", salvage sources: ", salvage.count())
	quit()


func _save(res: Resource, path: String) -> void:
	if ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Could not save " + path)


func _load_mesh(path: String) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	var count := f.get_32()
	var index_count := f.get_32()
	var has_roof := f.get_32() == 1
	var xy := f.get_buffer(count * 8).to_float32_array()
	var ga := f.get_buffer(count * 2)
	var ids := f.get_buffer(count * 4).to_float32_array() if has_roof else PackedFloat32Array()
	var stripes := f.get_buffer(count * 4).to_float32_array() if has_roof else PackedFloat32Array()
	var indices := f.get_buffer(index_count * 4).to_int32_array()
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(count)
	colors.resize(count)
	if has_roof:
		uvs.resize(count)
	for i in count:
		verts[i] = Vector2(xy[i * 2], xy[i * 2 + 1])
		var g := ga[i * 2] / 255.0
		colors[i] = Color(g, g, g, ga[i * 2 + 1] / 255.0)
		if has_roof:
			uvs[i] = Vector2(ids[i], stripes[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	if has_roof:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("triangles", index_count / 3)
	return mesh


func _load_footprints(path: String) -> Resource:
	var fp: Resource = load(FOOTPRINTS_SCRIPT).new()
	var f := FileAccess.open(path, FileAccess.READ)
	var n := f.get_32()
	var points := PackedVector2Array()
	var starts := PackedInt32Array([0])
	for i in n:
		var k := f.get_32()
		var xy := f.get_buffer(k * 8).to_float32_array()
		for j in k:
			points.append(Vector2(xy[j * 2], xy[j * 2 + 1]))
		starts.append(points.size())
	fp.points = points
	fp.starts = starts
	if f.get_length() - f.get_position() >= n * 2:
		fp.state = f.get_buffer(n)
		fp.district = f.get_buffer(n)
	return fp


func _load_districts(path: String) -> Resource:
	var d: Resource = load(DISTRICTS_SCRIPT).new()
	if not FileAccess.file_exists(path):
		push_error("No districts.bin in the work folder")
		return d
	var f := FileAccess.open(path, FileAccess.READ)
	var w := f.get_32()
	var h := f.get_32()
	var ox := f.get_float()
	var oy := f.get_float()
	d.cell_px = f.get_float()
	d.origin = Vector2(ox, oy)
	d.size = Vector2i(w, h)
	d.codes = f.get_buffer(w * h)
	return d


func _load_obstacles(path: String) -> Resource:
	var o: Resource = load(OBSTACLES_SCRIPT).new()
	if not FileAccess.file_exists(path):
		push_error("No obstacles.bin in the work folder")
		return o
	var f := FileAccess.open(path, FileAccess.READ)
	var n := f.get_32()
	var points := PackedVector2Array()
	var starts := PackedInt32Array([0])
	var kinds := PackedByteArray()
	for i in n:
		kinds.append(f.get_32())
		var k := f.get_32()
		var xy := f.get_buffer(k * 8).to_float32_array()
		for j in k:
			points.append(Vector2(xy[j * 2], xy[j * 2 + 1]))
		starts.append(points.size())
	o.points = points
	o.starts = starts
	o.kind = kinds
	return o


func _load_props(path: String) -> Resource:
	var spawn_set: Resource = load(SPAWN_SET_SCRIPT).new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("Could not read " + path)
		return spawn_set
	var n: int = data.items.size()
	var kind := PackedByteArray()
	var pos := PackedVector2Array()
	var rot := PackedFloat32Array()
	var size := PackedVector2Array()
	var variant := PackedInt32Array()
	variant.resize(n)
	kind.resize(n)
	pos.resize(n)
	rot.resize(n)
	size.resize(n)
	for i in n:
		var it: Array = data.items[i]
		kind[i] = int(it[0])
		pos[i] = Vector2(it[1], it[2])
		rot[i] = it[3]
		size[i] = Vector2(it[4], it[5])
		variant[i] = int(it[6]) if it.size() > 6 else -1
	spawn_set.kinds = PackedStringArray(data.kinds)
	spawn_set.kind = kind
	spawn_set.position = pos
	spawn_set.rotation = rot
	spawn_set.size = size
	spawn_set.variant = variant
	return spawn_set


func _load_salvage(path: String) -> Resource:
	var s: Resource = load(SALVAGE_SCRIPT).new()
	if not FileAccess.file_exists(path):
		push_error("No salvage.json in the work folder")
		return s
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("Could not read " + path)
		return s
	var n: int = data.items.size()
	var kind := PackedByteArray()
	var pos := PackedVector2Array()
	var rot := PackedFloat32Array()
	var size := PackedVector2Array()
	var building := PackedInt32Array()
	var amount := PackedInt32Array()
	var vehicle := PackedByteArray()
	kind.resize(n)
	pos.resize(n)
	rot.resize(n)
	size.resize(n)
	building.resize(n)
	amount.resize(n)
	vehicle.resize(n)
	for i in n:
		var it: Array = data.items[i]
		kind[i] = int(it[0])
		pos[i] = Vector2(it[1], it[2])
		rot[i] = it[3]
		size[i] = Vector2(it[4], it[5])
		building[i] = int(it[6])
		amount[i] = int(it[7])
		vehicle[i] = int(it[8])
	s.kinds = PackedStringArray(data.kinds)
	s.kind = kind
	s.position = pos
	s.rotation = rot
	s.size = size
	s.building = building
	s.amount = amount
	s.vehicle = vehicle
	return s
