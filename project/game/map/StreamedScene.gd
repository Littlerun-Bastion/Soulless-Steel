@tool
class_name StreamedScene
extends Node2D

# A hand-made scene (a compound, a landmark) that the map loads only while a
# mecha is near it. Place this node where the scene goes, set scene_path, and
# set `bounds` (in this node's space) to cover what the scene contains; the
# editor draws the bounds as a box.
#
# A MapStreamer loads the scene on a background thread when any mecha comes
# within its load distance of the bounds, adds it as a child of this node, and
# frees it when every mecha is far away again.
#
# Loot crates (LootContainer) in the scene are remembered for the run: when
# the scene is freed, each crate's contents are kept here, and handed back to
# it when the scene loads again. Otherwise every crate would roll new loot
# each time a mecha came back, which could be farmed forever. Anything else
# the scene changes (opened doors) is still lost when it is freed; keep such
# state outside the scene.
#
# In the editor, the scene shows as a preview child that is not saved.

@export_file("*.tscn") var scene_path := "":
	set(value):
		scene_path = value
		_refresh_preview()
@export var bounds := Rect2(-1000, -1000, 2000, 2000):
	set(value):
		bounds = value
		queue_redraw()
@export var preview_in_editor := true:
	set(value):
		preview_in_editor = value
		_refresh_preview()

signal streamed_in(instance: Node)
signal streamed_out

var instance: Node = null
var _loading := false
var _preview: Node = null
# The scene's crates while it is unloaded: path in the scene -> [Inventory,
# npc_searched]. Lives as long as this node, i.e. for the run.
var _loot_memory: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	add_to_group("streamed_scene")


func is_loaded() -> bool:
	return instance != null


# Distance (px) from the nearest point to the bounds, or INF.
func distance_to_nearest(points: Array[Vector2]) -> float:
	var rect := global_transform * bounds
	var best := INF
	for p in points:
		var closest := p.clamp(rect.position, rect.end)
		best = minf(best, closest.distance_to(p))
	return best


func stream_in() -> void:
	if instance != null or _loading or scene_path.is_empty():
		return
	if ResourceLoader.load_threaded_request(scene_path) == OK:
		_loading = true


func stream_out() -> void:
	if instance == null:
		return
	_remember_loot()
	instance.queue_free()
	instance = null
	streamed_out.emit()


# Adds the scene once its background load has finished.
func poll() -> void:
	if not _loading:
		return
	var status := ResourceLoader.load_threaded_get_status(scene_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_loading = false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("StreamedScene: could not load %s" % scene_path)
		return
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		return
	instance = packed.instantiate()
	_restore_loot()  # before it enters the tree, so the crates don't roll
	add_child(instance)
	streamed_in.emit(instance)


# Every crate in the scene, opened or not, so walking away can't re-roll one.
func _remember_loot() -> void:
	for crate in _crates():
		_loot_memory[instance.get_path_to(crate)] = [crate.inventory, crate.npc_searched]


func _restore_loot() -> void:
	for path in _loot_memory:
		var crate := instance.get_node_or_null(path) as LootContainer
		if crate != null:
			crate.restore(_loot_memory[path][0], _loot_memory[path][1])


func _crates() -> Array:
	return instance.find_children("*", "", true, false).filter(func(n): return n is LootContainer)


func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview:
		_preview.queue_free()
		_preview = null
	if preview_in_editor and not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed:
			_preview = packed.instantiate()
			add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	queue_redraw()


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(bounds, Color(0.4, 0.8, 1.0, 0.8), false, 8.0)
