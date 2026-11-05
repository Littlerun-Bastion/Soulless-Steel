class_name MapStreamer
extends Node

# Streams a map at runtime, in two ways:
#
# Drawing, round the camera: every map chunk mesh (MeshInstance2D) under
# `chunks_root`, and every sprite batch of the PropSpriteLayers under it, is
# hidden while its bounds are more than view_margin outside the camera's view.
# Hidden nodes cost nothing to draw or to cull.
#
# Hand-made scenes, round every mecha and round the camera: each
# StreamedScene in the tree is loaded (on a background thread) while any
# mecha is within load_distance of its bounds, or the camera's screen centre
# is within the larger of load_distance and the screen's half-diagonal plus
# view_margin; it is freed once every one of them is unload_slack further
# away than that. Hand-made scenes have collision (walls, props), so they
# stream round every mecha, not only the player: NPCs far from the player
# still meet them. The camera's centre follows the player's camera pan, so
# what the player looks at is loaded too.
#
# Collision that is built by code (building walls, vehicle boxes) is handled
# by BuildingField and VehicleField; this node does not touch it.

## Seconds between checks.
const INTERVAL := 0.2

@export var chunks_root: NodePath = NodePath("..")
## How far (px) outside the camera's view a chunk stays shown.
@export var view_margin := 2000.0
@export var load_distance := 4000.0
@export var unload_slack := 1500.0

var _items: Array = []  # [CanvasItem, Rect2 in global space]
var _timer := 0.0
var _dirty := true


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	_watch_layers.call_deferred()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 and not _dirty:
		return
	var profile_start := FrameProfiler.start()
	_timer = INTERVAL
	if _dirty:
		_collect()
	_update_chunks()
	_update_scenes()
	FrameProfiler.add("map_streamer", profile_start)


func mark_dirty() -> void:
	_dirty = true


func visible_item_count() -> int:
	var n := 0
	for it in _items:
		if is_instance_valid(it[0]) and (it[0] as CanvasItem).visible:
			n += 1
	return n


func item_count() -> int:
	return _items.size()


func _watch_layers() -> void:
	var root := get_node_or_null(chunks_root)
	if root == null:
		return
	for layer in root.find_children("*", "PropSpriteLayer", true, false):
		if not layer.rebuilt.is_connected(mark_dirty):
			layer.rebuilt.connect(mark_dirty)
	mark_dirty()


func _collect() -> void:
	_dirty = false
	_items.clear()
	var root := get_node_or_null(chunks_root)
	if root == null:
		return
	for node in root.find_children("*", "MeshInstance2D", true, false):
		var mi := node as MeshInstance2D
		if mi.mesh:
			_items.append([mi, _global_rect(mi, mi.mesh.get_aabb())])
	for layer in root.find_children("*", "PropSpriteLayer", true, false):
		for child in layer.get_children(true):
			var mmi := child as MultiMeshInstance2D
			if mmi and mmi.multimesh and mmi.multimesh.instance_count > 0:
				_items.append([mmi, _global_rect(mmi, mmi.multimesh.get_aabb())])


func _global_rect(node: Node2D, aabb: AABB) -> Rect2:
	var local := Rect2(aabb.position.x, aabb.position.y, aabb.size.x, aabb.size.y)
	return node.global_transform * local


func _update_chunks() -> void:
	var view := _camera_rect()
	if not view.has_area():
		return
	view = view.grow(view_margin)
	for it in _items:
		if not is_instance_valid(it[0]):
			# A sprite layer rebuilt its batches; collect them again next time.
			_dirty = true
			continue
		var item: CanvasItem = it[0]
		var near: bool = view.intersects(it[1])
		if item.visible != near:
			item.visible = near


func _camera_rect() -> Rect2:
	var viewport := get_viewport()
	var cam := viewport.get_camera_2d() if viewport else null
	if cam == null:
		return Rect2()
	var size := viewport.get_visible_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size / 2.0, size)


func _update_scenes() -> void:
	var anchors: Array[Vector2] = []
	for m in get_tree().get_nodes_in_group("mecha"):
		if m is Node2D and (m as Node2D).is_inside_tree():
			anchors.append((m as Node2D).global_position)
	var view: Array[Vector2] = []
	var view_load := load_distance
	var viewport := get_viewport()
	var cam := viewport.get_camera_2d() if viewport else null
	if cam != null:
		view.append(cam.get_screen_center_position())
		var size := viewport.get_visible_rect().size / cam.zoom
		view_load = maxf(load_distance, size.length() * 0.5 + view_margin)
	for s in get_tree().get_nodes_in_group("streamed_scene"):
		var scene := s as StreamedScene
		if scene == null:
			continue
		var d := scene.distance_to_nearest(anchors)
		var d_view := scene.distance_to_nearest(view) if not view.is_empty() else INF
		if d <= load_distance or d_view <= view_load:
			scene.stream_in()
		elif d > load_distance + unload_slack and d_view > view_load + unload_slack:
			scene.stream_out()
		scene.poll()
