extends TestSuite

# MapStreamingTest: MapStreamer and StreamedScene (game/map/), and the NPC
# thinking rule (Enemy.think_interval). Chunk meshes far outside the camera's
# view are hidden and shown again when the camera comes near; a StreamedScene
# loads when a mecha comes near its bounds and is freed when every mecha has
# gone; and an NPC far from the player thinks every FAR_THINK_INTERVAL frames.

const STREAMED_PATH := "user://map_streaming_test_scene.tscn"
const ENEMY_SCRIPT := preload("res://game/mecha/Enemy.gd")


class FakeMecha extends Node2D:
	func _init() -> void:
		add_to_group("mecha")


var _root: Node2D = null


func run_tests() -> void:
	await case("chunks away from the camera are hidden", _test_chunks)
	await case("a streamed scene loads near a mecha and goes when it leaves", _test_streamed_scene)
	await case("NPCs far from the player think less often", _test_think_interval)


func before_each() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
		await wait_frames(2)
	_root = Node2D.new()
	add_child(_root)


func _quad(pos: Vector2, size: float) -> MeshInstance2D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var h := size / 2.0
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


func _test_chunks() -> void:
	var chunks := Node2D.new()
	_root.add_child(chunks)
	var near := _quad(Vector2(0, 0), 1000)
	var far := _quad(Vector2(30000, 0), 1000)
	chunks.add_child(near)
	chunks.add_child(far)
	var cam := Camera2D.new()
	_root.add_child(cam)
	cam.make_current()
	var streamer := MapStreamer.new()
	streamer.chunks_root = NodePath("../" + String(chunks.name))
	_root.add_child(streamer)
	await wait_frames(4)
	check(near.visible and not far.visible, "the chunk in view shows, the far one is hidden")
	check_eq(streamer.item_count(), 2, "both chunks are tracked")
	cam.position = Vector2(30000, 0)
	await wait_until(func(): return far.visible and not near.visible, 2.0)
	check(far.visible and not near.visible, "they swap when the camera moves")


func _test_streamed_scene() -> void:
	var content := Node2D.new()
	content.name = "Compound"
	var body := StaticBody2D.new()
	content.add_child(body)
	body.owner = content
	var packed := PackedScene.new()
	packed.pack(content)
	content.free()
	ResourceSaver.save(packed, STREAMED_PATH)
	var streamed := StreamedScene.new()
	streamed.scene_path = STREAMED_PATH
	streamed.position = Vector2(20000, 0)
	streamed.bounds = Rect2(-500, -500, 1000, 1000)
	_root.add_child(streamed)
	var mecha := FakeMecha.new()
	_root.add_child(mecha)
	var streamer := MapStreamer.new()
	streamer.chunks_root = NodePath("..")
	_root.add_child(streamer)
	await wait_seconds(0.5)
	check(not streamed.is_loaded(), "not loaded while the mecha is far")
	mecha.position = Vector2(17000, 0)
	var loaded := await wait_until(func(): return streamed.is_loaded(), 3.0)
	check(loaded, "loaded when the mecha comes within load distance")
	if loaded:
		check(streamed.instance.get_parent() == streamed, "the scene is a child of the StreamedScene")
	# Between load_distance and load_distance + unload_slack from the bounds.
	mecha.position = Vector2(19500 - streamer.load_distance - streamer.unload_slack / 2.0, 0)
	await wait_seconds(0.5)
	check(streamed.is_loaded(), "kept while the mecha is inside the slack")
	mecha.position = Vector2(0, 0)
	var gone := await wait_until(func(): return not streamed.is_loaded(), 3.0)
	check(gone, "freed when the mecha has gone")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STREAMED_PATH))


func _test_think_interval() -> void:
	check_eq(ENEMY_SCRIPT.think_interval(true), 1, "near the player: every frame")
	check_eq(ENEMY_SCRIPT.think_interval(false), ENEMY_SCRIPT.FAR_THINK_INTERVAL, "far from the player: every few frames")
	check(ENEMY_SCRIPT.FAR_THINK_INTERVAL > 1, "far NPCs skip frames")
