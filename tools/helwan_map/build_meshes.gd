extends SceneTree

# Turns the generator's work files into the Godot resources that
# helwan_generated.tscn uses, in res://assets/maps/helwan/.
#
# Run from the Godot project folder:
#   godot --headless -s path/to/build_meshes.gd -- path/to/work_dir
#
# work_dir/manifest.json lists the mesh names. Each name.bin (style.py's
# format, read by game/map/MapMeshFile.gd) becomes name.res (ArrayMesh):
# roofs carry the building id in UV.x and the stripe coordinate in UV.y,
# talls their height in metres in UV.x, where the shaders read them.
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
# props.json -> props.res (PropSpawnSet.from_json) and salvage.json ->
# salvage.res (SalvageSpawnSet.from_json); see props.py and salvage.py for
# their fields. Kinds go by name (each file lists its kind names), stored as
# one byte per item, so a file may name at most 256 kinds.
#
# landmarks.json -> landmarks.res (MapLandmarks): {"items": [{name, kind, x,
# y, radius, outline}]} in world px; an empty set when the file is missing.

const OUT_DIR := "res://assets/maps/helwan"
const FOOTPRINTS_SCRIPT := "res://game/map/BuildingFootprints.gd"
const DISTRICTS_SCRIPT := "res://game/map/MapDistricts.gd"
const OBSTACLES_SCRIPT := "res://game/map/MapObstacles.gd"
const SPAWN_SET_SCRIPT := "res://game/map/props/PropSpawnSet.gd"
const SALVAGE_SCRIPT := "res://game/map/salvage/SalvageSpawnSet.gd"
const MESH_FILE_SCRIPT := "res://game/map/MapMeshFile.gd"
const LANDMARKS_SCRIPT := "res://game/map/MapLandmarks.gd"


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
	var mesh_file: GDScript = load(MESH_FILE_SCRIPT)
	for mesh_name in names:
		var mesh: ArrayMesh = mesh_file.load_mesh(src + "/" + mesh_name + ".bin")
		if mesh == null:
			continue
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
	var landmarks := _load_landmarks(src + "/landmarks.json")
	_save(landmarks, OUT_DIR + "/landmarks.res")
	print("built ", names.size(), " meshes, triangles: ", total, ", buildings: ", fp.count(),
		", prop spawns: ", props.count(), ", district cells: ", districts.codes.size(),
		", obstacles: ", obstacles.count(), ", salvage sources: ", salvage.count(),
		", landmarks: ", landmarks.count())
	quit()


func _save(res: Resource, path: String) -> void:
	if ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Could not save " + path)


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
	var script: GDScript = load(SPAWN_SET_SCRIPT)
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("Could not read " + path)
		return script.new()
	return script.from_json(data)


func _load_salvage(path: String) -> Resource:
	var script: GDScript = load(SALVAGE_SCRIPT)
	if not FileAccess.file_exists(path):
		push_error("No salvage.json in the work folder")
		return script.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("Could not read " + path)
		return script.new()
	return script.from_json(data)


func _load_landmarks(path: String) -> Resource:
	var script: GDScript = load(LANDMARKS_SCRIPT)
	if not FileAccess.file_exists(path):
		push_warning("No landmarks.json in the work folder: the map has no named places")
		return script.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("Could not read " + path)
		return script.new()
	return script.from_json(data)
