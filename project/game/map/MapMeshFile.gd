class_name MapMeshFile
extends RefCounted

# Reads one chunk mesh file of the map generator (tools/helwan_map, style.py)
# into an ArrayMesh. build_meshes.gd converts every file of a run with it;
# tests read synthetic files with it.
#
# The file: int32 vertex count, int32 index count, int32 channel flag
# (NONE, ROOF or HEIGHT), float32 x,y per vertex (world px), uint8
# grey,alpha per vertex, then for ROOF float32 building id and float32
# stripe coordinate per vertex, or for HEIGHT float32 height (metres above
# the ground) per vertex, then uint32 vertex indices, three per triangle in
# draw order.
#
# The extra channels go into UV, where the shaders read them: roofs carry
# UV = (building id, stripe) for CityGrain.gdshader, talls UV = (height, 0)
# for TallsLean.gdshader. The mesh's "triangles" meta is its triangle count.

const NONE := 0
const ROOF := 1
const HEIGHT := 2


static func load_mesh(path: String) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapMeshFile: could not open " + path)
		return null
	var count := f.get_32()
	var index_count := f.get_32()
	var flag := f.get_32()
	var xy := f.get_buffer(count * 8).to_float32_array()
	var ga := f.get_buffer(count * 2)
	var first := PackedFloat32Array()
	var second := PackedFloat32Array()
	if flag == ROOF:
		first = f.get_buffer(count * 4).to_float32_array()
		second = f.get_buffer(count * 4).to_float32_array()
	elif flag == HEIGHT:
		first = f.get_buffer(count * 4).to_float32_array()
	elif flag != NONE:
		push_error("MapMeshFile: unknown channel flag %d in %s" % [flag, path])
		return null
	var indices := f.get_buffer(index_count * 4).to_int32_array()
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(count)
	colors.resize(count)
	if flag != NONE:
		uvs.resize(count)
	for i in count:
		verts[i] = Vector2(xy[i * 2], xy[i * 2 + 1])
		var g := ga[i * 2] / 255.0
		colors[i] = Color(g, g, g, ga[i * 2 + 1] / 255.0)
		if flag == ROOF:
			uvs[i] = Vector2(first[i], second[i])
		elif flag == HEIGHT:
			uvs[i] = Vector2(first[i], 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	if flag != NONE:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if count > 0 and index_count > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	@warning_ignore("integer_division")
	mesh.set_meta("triangles", index_count / 3)
	return mesh


# Writes a mesh file (the generator's format). Tests and probes make
# synthetic files with it. `channels` is per vertex: Vector2(id, stripe) for
# ROOF, a float height for HEIGHT; empty for NONE.
static func write_mesh(path: String, verts: PackedVector2Array, greys: PackedFloat32Array,
		alphas: PackedFloat32Array, indices: PackedInt32Array, flag := NONE, channels := []) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_32(verts.size())
	f.store_32(indices.size())
	f.store_32(flag)
	for v in verts:
		f.store_float(v.x)
		f.store_float(v.y)
	for i in verts.size():
		f.store_8(clampi(roundi(greys[i] * 255.0), 0, 255))
		f.store_8(clampi(roundi(alphas[i] * 255.0), 0, 255))
	if flag == ROOF:
		for c in channels:
			f.store_float((c as Vector2).x)
		for c in channels:
			f.store_float((c as Vector2).y)
	elif flag == HEIGHT:
		for c in channels:
			f.store_float(float(c))
	for i in indices:
		f.store_32(i)
	f.close()
	return OK
