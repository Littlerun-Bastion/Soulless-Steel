extends TestSuite

# MapStreamingTest: MapStreamer and StreamedScene (game/map/), and the NPC
# thinking rule (Enemy.think_interval). Chunk meshes far outside the camera's
# view are hidden and shown again when the camera comes near; a StreamedScene
# loads when a mecha comes near its bounds and is freed when every mecha has
# gone, its loot crates keeping what they held (so leaving and coming back
# can't refill them); an NPC far from the player thinks every
# FAR_THINK_INTERVAL frames; and preloading round a start position (the
# loading screen's) loads the chunks the first view there wants, so the
# camera arriving there waits for none.

const STREAMED_PATH := "user://map_streaming_test_scene.tscn"
const CRATE_SCENE_PATH := "user://map_streaming_test_crates.tscn"
const LOOT_CONTAINER := preload("res://game/mecha/LootContainer.tscn")
const SALVAGE_TABLE := preload("res://database/loot-tables/wreck_salvage.tres")
const ENEMY_SCRIPT := preload("res://game/mecha/Enemy.gd")
const CHUNK_MESH_PATH := "user://map_streaming_test_chunk.res"


class FakeMecha extends Node2D:
	func _init() -> void:
		add_to_group("mecha")


var _root: Node2D = null


func run_tests() -> void:
	await case("chunks away from the camera are hidden", _test_chunks)
	await case("chunk meshes load near the camera and are freed far away", _test_chunk_meshes)
	await case("a streamed scene loads near a mecha and goes when it leaves", _test_streamed_scene)
	await case("a streamed scene's crates keep their loot when it reloads", _test_crates_remembered)
	await case("NPCs far from the player think less often", _test_think_interval)
	await case("preloading round the start loads what the first view wants", _test_preload)


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


func _test_chunk_meshes() -> void:
	var quad := _quad(Vector2.ZERO, 1000)
	ResourceSaver.save(quad.mesh, CHUNK_MESH_PATH)
	quad.free()
	var chunks := Node2D.new()
	_root.add_child(chunks)
	var near := ChunkMesh.new()
	near.mesh_path = CHUNK_MESH_PATH
	near.bounds = Rect2(-500, -500, 1000, 1000)
	var mid := ChunkMesh.new()
	mid.mesh_path = CHUNK_MESH_PATH
	mid.position = Vector2(6000, 0)
	mid.bounds = Rect2(-500, -500, 1000, 1000)
	var far := ChunkMesh.new()
	far.mesh_path = CHUNK_MESH_PATH
	far.position = Vector2(60000, 0)
	far.bounds = Rect2(-500, -500, 1000, 1000)
	for c in [near, mid, far]:
		chunks.add_child(c)
	var cam := Camera2D.new()
	_root.add_child(cam)
	cam.make_current()
	var streamer := MapStreamer.new()
	streamer.chunks_root = NodePath("../" + String(chunks.name))
	_root.add_child(streamer)
	await wait_until(func(): return near.is_loaded() and mid.is_loaded(), 3.0)
	check(near.is_loaded(), "the chunk in view is loaded")
	check(mid.is_loaded(), "a chunk just outside the view is loaded in the background")
	check(not far.is_loaded(), "a far chunk is not loaded")
	check_eq(streamer.chunk_mesh_count(), 3, "all three chunks are tracked")
	cam.position = Vector2(60000, 0)
	var swapped := await wait_until(func(): return far.is_loaded() and not near.is_loaded(), 3.0)
	check(swapped, "moving the camera loads the far chunk and frees the first")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHUNK_MESH_PATH))


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


# A compound with one crate that rolls salvage, driven through the
# StreamedScene calls MapStreamer makes (stream_in / poll / stream_out).
func _test_crates_remembered() -> void:
	var content := Node2D.new()
	content.name = "Compound"
	var crate := LOOT_CONTAINER.instantiate()
	crate.name = "Crate"
	crate.loot_table = SALVAGE_TABLE
	crate.loot_rolls = 4
	content.add_child(crate)
	crate.owner = content
	var packed := PackedScene.new()
	packed.pack(content)
	content.free()
	ResourceSaver.save(packed, CRATE_SCENE_PATH)

	var first := _crate_area(Vector2(20000, 0))
	var second := _crate_area(Vector2(-20000, 0))
	var a := await _load_crate(first)
	var b := await _load_crate(second)
	if a == null or b == null:
		check(false, "the crates load")
		return
	var a_items: Array = a.inventory.get_stacks()
	var b_items: Array = b.inventory.get_stacks()
	check(not a_items.is_empty() and not b_items.is_empty(), "both crates rolled loot")
	check(not a_items.any(func(s): return s in b_items), "two placements of a compound have their own loot")

	# Take one item and mark it searched, then leave and come back.
	a.inventory.remove_item_stack(a_items[0])
	a.npc_searched = true
	first.stream_out()
	await wait_frames(2)
	check(not first.is_loaded() and not is_instance_valid(a), "the compound was freed")
	a = await _load_crate(first)
	if a == null:
		return
	var back: Array = a.inventory.get_stacks()
	check_eq(back.size(), a_items.size() - 1, "the crate came back without the item taken")
	check(a_items.slice(1).all(func(s): return s in back), "and with the very same items, not a new roll")
	check(a.npc_searched, "an NPC's search is remembered too")

	# An untouched crate keeps its first roll however often its area reloads.
	for i in 3:
		second.stream_out()
		await wait_frames(2)
		b = await _load_crate(second)
		if b == null:
			return
	check_eq(b.inventory.get_stacks().size(), b_items.size(), "an unopened crate keeps its first roll")
	check(b_items.all(func(s): return s in b.inventory.get_stacks()), "item for item")

	# A new map (a new run) rolls its crates afresh.
	var fresh := _crate_area(Vector2(0, 20000))
	var c := await _load_crate(fresh)
	if c != null:
		check(not c.inventory.get_stacks().any(func(s): return s in a_items or s in b_items), "a new run's crates roll new loot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CRATE_SCENE_PATH))


func _crate_area(pos: Vector2) -> StreamedScene:
	var streamed := StreamedScene.new()
	streamed.scene_path = CRATE_SCENE_PATH
	streamed.position = pos
	_root.add_child(streamed)
	return streamed


func _load_crate(streamed: StreamedScene) -> LootContainer:
	streamed.stream_in()
	var loaded := await wait_until(func():
		streamed.poll()
		return streamed.is_loaded(), 3.0)
	if not check(loaded, "the compound loads"):
		return null
	return streamed.instance.get_node_or_null("Crate") as LootContainer


func _test_think_interval() -> void:
	check_eq(ENEMY_SCRIPT.think_interval(true), 1, "near the player: every frame")
	check_eq(ENEMY_SCRIPT.think_interval(false), ENEMY_SCRIPT.FAR_THINK_INTERVAL, "far from the player: every few frames")
	check(ENEMY_SCRIPT.FAR_THINK_INTERVAL > 1, "far NPCs skip frames")


func _test_preload() -> void:
	var quad := _quad(Vector2.ZERO, 1000)
	ResourceSaver.save(quad.mesh, CHUNK_MESH_PATH)
	quad.free()
	var chunks := Node2D.new()
	_root.add_child(chunks)
	var start := Vector2(40000, 0)
	var made := []
	for offset in [Vector2.ZERO, Vector2(5000, 0), Vector2(40000, 0)]:
		var chunk := ChunkMesh.new()
		chunk.mesh_path = CHUNK_MESH_PATH
		chunk.position = start + offset
		chunk.bounds = Rect2(-500, -500, 1000, 1000)
		chunks.add_child(chunk)
		made.append(chunk)
	var cam := Camera2D.new()
	_root.add_child(cam)
	cam.make_current()
	var streamer := MapStreamer.new()
	streamer.chunks_root = NodePath("../" + String(chunks.name))
	_root.add_child(streamer)
	var loaded := streamer.preload_around(start, Vector2(4000, 2000))
	check_eq(loaded, 2, "the chunk at the start and the one within the load margin are loaded")
	check(made[0].is_loaded() and made[1].is_loaded() and not made[2].is_loaded(), "and not the far one")
	check_eq(MapStreamer.find(_root), streamer, "the streamer is found from the tree")
	cam.position = start
	await wait_frames(30)
	check_eq(streamer.waited_loads, 0, "the camera arriving at the start waits for no chunk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHUNK_MESH_PATH))
