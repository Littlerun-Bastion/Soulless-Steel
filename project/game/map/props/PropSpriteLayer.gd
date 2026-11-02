@tool
class_name PropSpriteLayer
extends Node2D

# Draws sprites for some of a PropSpawner's spawn kinds. It is visual only:
# a VehicleField gives vehicles their bodies.
#
# Each sprite variant in each 500 m chunk is one MultiMeshInstance2D, so
# thousands of props cost a few dozen draw calls. A map uses one layer per
# depth: one at ground level for vehicles (below mechas), one above mechas
# for trees and bushes.
#
# textures: kind -> Array of Texture2D (the kind's sprite variants).
# spans:    kind -> PackedFloat32Array, per variant the fraction of the image
#           width that the drawn body covers. A spawn's size.x is the body's
#           width on screen; the height follows the texture's shape.
# A spawn's variant picks its texture; -1 picks one from its position.
#
# layers: kind -> Vector2i(min, max). Each spawn of that kind draws that many
#   different variants stacked on top of each other, each turned at random and
#   scaled 80-105%. Used for trees: 2-3 branch slices make each tree unique.
# tones: kind -> brightness multiplier (for example darker wrecks).
#
# With fade_near_player on, sprites the player is in or close to fade to
# ghost_alpha so the player stays visible. concealment_at() tells which kind
# covers a point; with `conceals` on, the layer joins the "foliage_layer"
# group so MapSenses uses it for detection checks.
#
# A VehicleField takes single sprites off the layer while their vehicles are
# moving (hide_sprite) and puts them back where they stopped (place_sprite).
# Sprites are found by their spawn's index in the spawner's list.

const CHUNK_SIZE := 10000.0
const CELL_SIZE := 1000.0
const FADE_SPEED := 3.0

signal rebuilt

@export var spawner: PropSpawner:
	set(value):
		if spawner and spawner.spawns_changed.is_connected(mark_dirty):
			spawner.spawns_changed.disconnect(mark_dirty)
		spawner = value
		if spawner and is_inside_tree():
			spawner.spawns_changed.connect(mark_dirty)
		mark_dirty()
## The spawner as a path, found when this layer enters the tree. Use it when
## the spawner is outside this layer's own scene (an exported node link can't
## point out of an instanced scene).
@export var spawner_path: NodePath
## Kinds this layer draws, in draw order (later kinds on top).
@export var kinds := PackedStringArray():
	set(value):
		kinds = value
		mark_dirty()
@export var textures := {}:
	set(value):
		textures = value
		mark_dirty()
@export var spans := {}:
	set(value):
		spans = value
		mark_dirty()
@export var layers := {}:
	set(value):
		layers = value
		mark_dirty()
@export var tones := {}:
	set(value):
		tones = value
		mark_dirty()
## Random brightness change per sprite, so repeats differ.
@export_range(0.0, 0.5) var tone_jitter := 0.1:
	set(value):
		tone_jitter = value
		mark_dirty()
@export var fade_near_player := false
## Joins the "foliage_layer" group, so what this layer draws hides things
## from detection (see MapSenses).
@export var conceals := false
@export_range(0.0, 1.0) var ghost_alpha := 0.3
## How far (px) beyond a sprite's edge the player still fades it.
@export var reveal_margin := 120.0

# Entry: [multimesh, index, position, radius, kind, tone, size, rotation
# offset from the spawn's, hidden, texture, base tone].
var _cells := {}
# Spawn index -> Array of its entries.
var _by_spawn := {}
# Entry id -> [entry, alpha] for sprites that are not fully shown.
var _fading := {}
var _nodes: Array[Node] = []
var _quad: ArrayMesh
var _dirty := true


func _ready() -> void:
	if spawner == null and not spawner_path.is_empty():
		spawner = get_node_or_null(spawner_path) as PropSpawner
	if conceals and not Engine.is_editor_hint():
		add_to_group("foliage_layer")
	if spawner and not spawner.spawns_changed.is_connected(mark_dirty):
		spawner.spawns_changed.connect(mark_dirty)
	_rebuild()


func _process(delta: float) -> void:
	if _dirty:
		_rebuild()
	if Engine.is_editor_hint() or not fade_near_player:
		return
	_update_fades(_find_player(), delta)


func mark_dirty() -> void:
	_dirty = true


# The variant a spawn's (first) sprite uses, or -1 if its kind has no
# textures here.
func variant_of(s: Dictionary) -> int:
	var count: int = textures.get(s.kind, []).size()
	if count == 0:
		return -1
	return _pick_variants(s, count, absi(hash(s.position)))[0]


# Texture, scale and tone for drawing a spawn's first sprite as a Sprite2D
# (facing along +x, centred). Empty if this layer doesn't draw it.
func sprite_info(spawn_index: int) -> Dictionary:
	var entries: Array = _by_spawn.get(spawn_index, [])
	if entries.is_empty():
		return {}
	var e: Array = entries[0]
	var tex: Texture2D = e[9]
	return {"texture": tex, "scale": Vector2(e[6].x / tex.get_width(), e[6].y / tex.get_height()), "tone": e[5]}


func hide_sprite(spawn_index: int) -> void:
	for e in _by_spawn.get(spawn_index, []):
		e[8] = true
		e[0].set_instance_transform_2d(e[1], Transform2D(Vector2.ZERO, Vector2.ZERO, e[2]))
		_fading.erase(_entry_id(e))


# Shows a spawn's sprites again at a new place (this node's space), with
# their brightness multiplied by tone_mult.
func place_sprite(spawn_index: int, pos: Vector2, rot: float, tone_mult := 1.0) -> void:
	for e in _by_spawn.get(spawn_index, []):
		var old_cell := _cell_of(e[2])
		var new_cell := _cell_of(pos)
		if old_cell != new_cell:
			_cells[old_cell].erase(e)
			_cells.get_or_add(new_cell, []).append(e)
		e[2] = pos
		e[8] = false
		e[5] = e[10] * tone_mult
		e[0].set_instance_transform_2d(e[1], Transform2D(rot + e[7], e[6], 0.0, pos))
		e[0].set_instance_color(e[1], Color(e[5], e[5], e[5], 1.0))


# The kind drawn by this layer that covers a point in this node's space,
# preferring kinds later in `kinds`; "" for none. A point counts when it is
# within 80% of the sprite's radius.
func concealment_at(pos: Vector2) -> String:
	var best := ""
	var cell := _cell_of(pos)
	for cx in range(cell.x - 1, cell.x + 2):
		for cy in range(cell.y - 1, cell.y + 2):
			for e in _cells.get(Vector2i(cx, cy), []):
				if pos.distance_to(e[2]) <= e[3] * 0.8 and kinds.find(e[4]) > kinds.find(best):
					best = e[4]
	return best


func _rebuild() -> void:
	_dirty = false
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_cells.clear()
	_by_spawn.clear()
	_fading.clear()
	if spawner == null:
		return
	if _quad == null:
		_quad = _make_quad()
	# kind -> variant -> chunk -> [[position, rotation, size, tone, radius,
	# spawn index, rotation offset]]
	var groups := {}
	var spawns := spawner.get_spawns()
	for si in spawns.size():
		var s: Dictionary = spawns[si]
		if not kinds.has(s.kind):
			continue
		var tex_list: Array = textures.get(s.kind, [])
		if tex_list.is_empty():
			continue
		var h := absi(hash(s.position))
		var tone: float = tones.get(s.kind, 1.0) * (1.0 + (float(h % 1000) / 1000.0 * 2.0 - 1.0) * tone_jitter)
		var radius: float = maxf(s.size.x, s.size.y) / 2.0
		var chunk := Vector2i(floori(s.position.x / CHUNK_SIZE), floori(s.position.y / CHUNK_SIZE))
		var picks := _pick_variants(s, tex_list.size(), h)
		for k in picks.size():
			var rot: float = s.rotation if k == 0 else s.rotation + float(absi(hash([h, k])) % 6283) / 1000.0
			var size_mult := 1.0 if k == 0 else 0.8 + float(absi(hash([h, k, 1])) % 250) / 1000.0
			groups.get_or_add(s.kind, {}).get_or_add(picks[k], {}).get_or_add(chunk, []).append(
				[s.position, rot, s.size.x * size_mult, tone, radius, si, rot - s.rotation])
	for kind in kinds:
		if not groups.has(kind):
			continue
		var kind_spans: PackedFloat32Array = spans.get(kind, PackedFloat32Array())
		for variant in groups[kind]:
			var tex: Texture2D = textures[kind][variant]
			var span: float = kind_spans[variant] if variant < kind_spans.size() else 1.0
			for chunk in groups[kind][variant]:
				_build_group(kind, tex, span, groups[kind][variant][chunk])
	rebuilt.emit()


# The variants a spawn draws: one, or several different ones for kinds in
# `layers`. All picks come from the spawn's position, so they never change.
func _pick_variants(s: Dictionary, count: int, h: int) -> PackedInt32Array:
	var first: int = s.get("variant", -1)
	if first < 0 or first >= count:
		first = h % count
	var out := PackedInt32Array([first])
	if layers.has(s.kind):
		var r: Vector2i = layers[s.kind]
		var n := mini(r.x + (h / 7) % (r.y - r.x + 1), count)
		var k := 1
		while out.size() < n:
			var v := absi(hash([h, k, 2])) % count
			if not out.has(v):
				out.append(v)
			k += 1
	return out


func _build_group(kind: String, tex: Texture2D, span: float, list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = list.size()
	var aspect := float(tex.get_height()) / float(tex.get_width())
	for i in list.size():
		var it: Array = list[i]
		var w: float = it[2] / maxf(span, 0.05)
		var size := Vector2(w, w * aspect)
		mm.set_instance_transform_2d(i, Transform2D(it[1], size, 0.0, it[0]))
		var tone: float = it[3]
		mm.set_instance_color(i, Color(tone, tone, tone, 1.0))
		var entry := [mm, i, it[0], it[4], kind, tone, size, it[6], false, tex, tone]
		_cells.get_or_add(_cell_of(it[0]), []).append(entry)
		_by_spawn.get_or_add(it[5], []).append(entry)
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	_nodes.append(node)


func _update_fades(player, delta: float) -> void:
	var targets := {}
	if player:
		var pos := to_local(player.global_position)
		var cell := _cell_of(pos)
		for cx in range(cell.x - 1, cell.x + 2):
			for cy in range(cell.y - 1, cell.y + 2):
				for e in _cells.get(Vector2i(cx, cy), []):
					if not e[8] and pos.distance_to(e[2]) <= e[3] + reveal_margin:
						var id := _entry_id(e)
						targets[id] = true
						if not _fading.has(id):
							_fading[id] = [e, 1.0]
	for id in _fading.keys():
		var item: Array = _fading[id]
		var e: Array = item[0]
		var a := move_toward(item[1], ghost_alpha if targets.has(id) else 1.0, FADE_SPEED * delta)
		item[1] = a
		e[0].set_instance_color(e[1], Color(e[5], e[5], e[5], a))
		if a >= 1.0:
			_fading.erase(id)


func _entry_id(e: Array) -> int:
	return e[0].get_instance_id() * 65536 + e[1]


func _find_player():
	for m in get_tree().get_nodes_in_group("mecha"):
		if m.has_method("is_player") and m.is_player():
			return m
	return null


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))


# A 1 x 1 quad centred on the origin, with UVs, for the multimeshes.
static func _make_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5),
		Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
