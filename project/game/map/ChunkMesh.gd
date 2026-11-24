@tool
class_name ChunkMesh
extends MeshInstance2D

# One chunk of a generated map's meshes, loaded only while it is near the
# camera. The mesh is not part of the scene: the node holds its file path
# (mesh_path) and its bounds (in this node's space), and a MapStreamer loads
# the mesh on a background thread when the camera comes near and frees it when
# the camera has gone. A big map's meshes do not all fit in memory at once.
#
# In the editor the mesh is loaded as soon as the node is, so the whole map
# shows; it is never saved into a scene (see _validate_property), so a scene
# that instances the map does not end up holding every mesh.

@export_file("*.res") var mesh_path := ""
@export var bounds := Rect2()

var _loading := false


func _ready() -> void:
	if Engine.is_editor_hint():
		if mesh == null and not mesh_path.is_empty() and ResourceLoader.exists(mesh_path):
			mesh = load(mesh_path)
		return
	add_to_group("chunk_mesh")


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE


func is_loaded() -> bool:
	return mesh != null


func global_bounds() -> Rect2:
	return global_transform * bounds


# Loads the mesh now, waiting for it (for chunks that are already on screen).
func load_now() -> void:
	if mesh != null:
		return
	if _loading:
		mesh = ResourceLoader.load_threaded_get(mesh_path) as Mesh
		_loading = false
	else:
		mesh = load(mesh_path) as Mesh


func stream_in() -> void:
	if mesh != null or _loading or mesh_path.is_empty():
		return
	if ResourceLoader.load_threaded_request(mesh_path) == OK:
		_loading = true


func stream_out() -> void:
	if _loading:
		# A background load can't be stopped; take it and drop it.
		ResourceLoader.load_threaded_get(mesh_path)
		_loading = false
	mesh = null


# Takes the mesh once its background load has finished.
func poll() -> void:
	if not _loading:
		return
	var status := ResourceLoader.load_threaded_get_status(mesh_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_loading = false
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		mesh = ResourceLoader.load_threaded_get(mesh_path) as Mesh
	else:
		push_warning("ChunkMesh: could not load %s" % mesh_path)
