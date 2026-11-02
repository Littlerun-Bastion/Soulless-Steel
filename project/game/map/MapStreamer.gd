class_name MapStreamer
extends Node

# Streams a map at runtime, in two ways:
#
# Drawing, round the camera: every map chunk mesh (MeshInstance2D) under
# `chunks_root`, and every sprite batch of the PropSpriteLayers under it, is
# hidden while its bounds are more than view_margin outside the camera's view.
# Hidden nodes cost nothing to draw or to cull.
#
# Hand-made scenes, round every mecha: each StreamedScene in the tree is
# loaded (on a background thread) while any mecha is within load_distance of
# its bounds, and freed once every mecha is more than load_distance +
# unload_slack away. Hand-made scenes have collision (walls, props), so they
# stream round every mecha, not only the player: NPCs far from the player
# still meet them.
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
	_timer = INTERVAL
	if _dirty:
		_collect()
	_update_chunks()
	_update_scenes()


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
	for s in get_tree().get_nodes_in_group("streamed_scene"):
		var scene := s as StreamedScene
		if scene == null:
			continue
		var d := scene.distance_to_nearest(anchors)
		if d <= load_distance:
			scene.stream_in()
		elif d > load_distance + unload_slack:
			scene.stream_out()
		scene.poll()
