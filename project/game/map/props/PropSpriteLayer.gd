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
#
# Every sprite drawn is a record in packed arrays (_r_*), not an object: a big
# map draws tens of thousands. A spawn's records are chained through _r_next
# from _spawn_first[spawn index]; _cells files the records by CELL_SIZE square
# for the fade and concealment look-ups.
#
# Light shadows: a kind in shadow_heights casts a short shadow away from each
# mecha's illuminator that lights it (Illumination.shining_mechas,
# light_strength, no building wall between). A shadow is the sprite's own
# silhouette smeared away from the light by SHADOW_SHADER, as long as a
# point light LIGHT_HEIGHT_M up would throw it from the sprite's height
# (shadow_length_m), at most SHADOW_PER_HEIGHT times that height and
# MAX_SHADOW_M. Shadows are drawn under this layer's sprites, only round the
# camera's view, from one MultiMesh per texture that is refilled every frame.
# A hidden sprite (a moving vehicle) casts none.

const CHUNK_SIZE := 10000.0
const CELL_SIZE := 1000.0
const FADE_SPEED := 3.0
const PX_PER_M := 20.0
## Placeholders.
const LIGHT_HEIGHT_M := 7.0
const SHADOW_PER_HEIGHT := 2.0
const MAX_SHADOW_M := 5.0
## Lights fainter than this on a sprite (Illumination.light_strength) give it
## no shadow.
const MIN_LIGHT := 0.05
## Wall checks between a light and a sprite are kept this long (s).
const WALL_CHECK_TIME := 0.25
const SHADOW_SHADER := """
shader_type canvas_item;
render_mode unshaded;

// INSTANCE_CUSTOM: xy the shadow's offset in the sprite's UV units, z its
// opacity. The quad covers the sprite and the offset; a point is in shadow
// when stepping back along the offset lands on the sprite.
const int STEPS = 24;
uniform float tip_fade = 0.6;
varying vec3 shadow_data;
varying vec2 sprite_uv;

void vertex() {
	shadow_data = INSTANCE_CUSTOM.xyz;
	sprite_uv = min(vec2(0.0), shadow_data.xy) + UV * (vec2(1.0) + abs(shadow_data.xy));
}

void fragment() {
	vec2 dx = dFdx(sprite_uv);
	vec2 dy = dFdy(sprite_uv);
	float a = 0.0;
	for (int i = 0; i <= STEPS; i++) {
		float t = float(i) / float(STEPS);
		vec2 p = sprite_uv - shadow_data.xy * t;
		if (p.x >= 0.0 && p.y >= 0.0 && p.x <= 1.0 && p.y <= 1.0) {
			a = max(a, textureGrad(TEXTURE, p, dx, dy).a * (1.0 - t * tip_fade));
		}
	}
	COLOR = vec4(0.0, 0.0, 0.0, a * shadow_data.z);
}
"""

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
@export_group("Light Shadows")
## kind -> PackedFloat32Array: per variant, the sprite's height (m) for its
## light shadow; 0 (or a kind not here) casts none.
@export var shadow_heights := {}:
	set(value):
		shadow_heights = value
		mark_dirty()
## Opacity of a shadow in full light.
@export_range(0.0, 1.0) var shadow_alpha := 0.55

var _r_group := PackedInt32Array()
var _r_index := PackedInt32Array()
var _r_pos := PackedVector2Array()
var _r_radius := PackedFloat32Array()
var _r_kind := PackedByteArray()
var _r_tone := PackedFloat32Array()
var _r_base_tone := PackedFloat32Array()
var _r_size := PackedVector2Array()
var _r_rot_off := PackedFloat32Array()
var _r_rot := PackedFloat32Array()
var _r_height := PackedFloat32Array()
var _r_hidden := PackedByteArray()
var _r_next := PackedInt32Array()
var _spawn_first := PackedInt32Array()
var _groups: Array[MultiMesh] = []
var _group_tex: Array[Texture2D] = []
# Cell -> record ids.
var _cells := {}
# Record id -> alpha, for sprites that are not fully shown.
var _fading := {}
var _nodes: Array[Node] = []
var _quad: ArrayMesh
var _dirty := true
var _casts_shadows := false
# Texture -> MultiMeshInstance2D drawing that texture's shadows.
var _shadow_pools := {}
# Mecha instance id -> {record id: whether a wall is between}, emptied every
# WALL_CHECK_TIME s.
var _wall_checks := {}
var _wall_check_timer := 0.0
# This frame's shadows, as _update_shadows collected them.
var _frame_shadows := {}
static var _shadow_material: ShaderMaterial


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
	if Engine.is_editor_hint():
		return
	if _casts_shadows:
		var shadow_start := FrameProfiler.start()
		_update_shadows(delta)
		FrameProfiler.add("prop_shadows", shadow_start)
	if not fade_near_player:
		return
	var profile_start := FrameProfiler.start()
	_update_fades(_find_player(), delta)
	FrameProfiler.add("prop_layers", profile_start)


func mark_dirty() -> void:
	_dirty = true


# The variant a spawn's (first) sprite uses, or -1 if its kind has no
# textures here. `s` has the spawn's kind, position and variant.
func variant_of(s: Dictionary) -> int:
	var count: int = textures.get(s.kind, []).size()
	if count == 0:
		return -1
	return _pick_variants(s.kind, int(s.get("variant", -1)), count, absi(hash(s.position)))[0]


# The same, for the spawner's spawn `spawn_index`.
func variant_of_spawn(spawn_index: int) -> int:
	var kind := spawner.spawn_kind(spawn_index)
	var count: int = textures.get(kind, []).size()
	if count == 0:
		return -1
	return _pick_variants(kind, spawner.spawn_variant(spawn_index), count,
			absi(hash(spawner.spawn_position(spawn_index))))[0]


# Texture, scale and tone for drawing a spawn's first sprite as a Sprite2D
# (facing along +x, centred). Empty if this layer doesn't draw it.
func sprite_info(spawn_index: int) -> Dictionary:
	var r := _first_record(spawn_index)
	if r < 0:
		return {}
	var tex: Texture2D = _group_tex[_r_group[r]]
	return {"texture": tex, "scale": Vector2(_r_size[r].x / tex.get_width(), _r_size[r].y / tex.get_height()),
		"tone": _r_tone[r]}


# Where a spawn's first sprite is drawn (this node's space), its tone and its
# base tone (before a VehicleField darkened it), and whether it is hidden.
func sprite_position(spawn_index: int) -> Vector2:
	var r := _first_record(spawn_index)
	return _r_pos[r] if r >= 0 else Vector2.INF


func sprite_tone(spawn_index: int) -> float:
	var r := _first_record(spawn_index)
	return _r_tone[r] if r >= 0 else 0.0


func sprite_base_tone(spawn_index: int) -> float:
	var r := _first_record(spawn_index)
	return _r_base_tone[r] if r >= 0 else 0.0


func is_sprite_hidden(spawn_index: int) -> bool:
	var r := _first_record(spawn_index)
	return r >= 0 and _r_hidden[r] == 1


func sprite_count() -> int:
	return _r_pos.size()


func hide_sprite(spawn_index: int) -> void:
	var r := _first_record(spawn_index)
	while r >= 0:
		_r_hidden[r] = 1
		_groups[_r_group[r]].set_instance_transform_2d(_r_index[r], Transform2D(Vector2.ZERO, Vector2.ZERO, _r_pos[r]))
		_fading.erase(r)
		r = _r_next[r]


# Shows a spawn's sprites again at a new place (this node's space), with
# their brightness multiplied by tone_mult.
func place_sprite(spawn_index: int, pos: Vector2, rot: float, tone_mult := 1.0) -> void:
	var r := _first_record(spawn_index)
	while r >= 0:
		var old_cell := _cell_of(_r_pos[r])
		var new_cell := _cell_of(pos)
		if old_cell != new_cell:
			var list: PackedInt32Array = _cells[old_cell]
			list.remove_at(list.find(r))
			_cells[old_cell] = list
			if not _cells.has(new_cell):
				_cells[new_cell] = PackedInt32Array()
			_cells[new_cell].append(r)
		_r_pos[r] = pos
		_r_rot[r] = rot + _r_rot_off[r]
		_r_hidden[r] = 0
		var tone := _r_base_tone[r] * tone_mult
		_r_tone[r] = tone
		var mm := _groups[_r_group[r]]
		mm.set_instance_transform_2d(_r_index[r], Transform2D(rot + _r_rot_off[r], _r_size[r], 0.0, pos))
		mm.set_instance_color(_r_index[r], Color(tone, tone, tone, 1.0))
		r = _r_next[r]


# The kind drawn by this layer that covers a point in this node's space,
# preferring kinds later in `kinds`; "" for none. A point counts when it is
# within 80% of the sprite's radius.
func concealment_at(pos: Vector2) -> String:
	var best := -1
	var cell := _cell_of(pos)
	for cx in range(cell.x - 1, cell.x + 2):
		for cy in range(cell.y - 1, cell.y + 2):
			for r in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if _r_kind[r] > best and pos.distance_to(_r_pos[r]) <= _r_radius[r] * 0.8:
					best = _r_kind[r]
	return kinds[best] if best >= 0 else ""


func _first_record(spawn_index: int) -> int:
	return _spawn_first[spawn_index] if spawn_index >= 0 and spawn_index < _spawn_first.size() else -1


func _clear_records() -> void:
	_r_group = PackedInt32Array()
	_r_index = PackedInt32Array()
	_r_pos = PackedVector2Array()
	_r_radius = PackedFloat32Array()
	_r_kind = PackedByteArray()
	_r_tone = PackedFloat32Array()
	_r_base_tone = PackedFloat32Array()
	_r_size = PackedVector2Array()
	_r_rot_off = PackedFloat32Array()
	_r_rot = PackedFloat32Array()
	_r_height = PackedFloat32Array()
	_r_hidden = PackedByteArray()
	_r_next = PackedInt32Array()
	_spawn_first = PackedInt32Array()
	_groups.clear()
	_group_tex.clear()
	_cells.clear()
	_fading.clear()
	_wall_checks.clear()
	_frame_shadows = {}


func _rebuild() -> void:
	_dirty = false
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	for tex in _shadow_pools:
		_shadow_pools[tex].queue_free()
	_shadow_pools.clear()
	_clear_records()
	_casts_shadows = false
	if spawner == null:
		return
	if _quad == null:
		_quad = _make_quad()
	var n := spawner.spawn_count()
	_spawn_first.resize(n)
	_spawn_first.fill(-1)
	# kind -> variant -> chunk -> Array of sprites, SPRITE_STRIDE floats each:
	# position x, y, rotation, width, tone, radius, spawn index, rotation
	# offset. (An Array, not a packed one, so appending never copies it.)
	var groups := {}
	for si in spawner.indices_of_kinds(kinds):
		var kind := spawner.spawn_kind(si)
		var tex_list: Array = textures.get(kind, [])
		if tex_list.is_empty():
			continue
		var pos := spawner.spawn_position(si)
		var size := spawner.spawn_size(si)
		var base_rot := spawner.spawn_rotation(si)
		var h := absi(hash(pos))
		var tone: float = tones.get(kind, 1.0) * (1.0 + (float(h % 1000) / 1000.0 * 2.0 - 1.0) * tone_jitter)
		var radius: float = maxf(size.x, size.y) / 2.0
		var chunk := Vector2i(floori(pos.x / CHUNK_SIZE), floori(pos.y / CHUNK_SIZE))
		var picks := _pick_variants(kind, spawner.spawn_variant(si), tex_list.size(), h)
		for k in picks.size():
			var rot: float = base_rot if k == 0 else base_rot + float(absi(hash([h, k])) % 6283) / 1000.0
			var size_mult := 1.0 if k == 0 else 0.8 + float(absi(hash([h, k, 1])) % 250) / 1000.0
			var by_variant: Dictionary = groups.get_or_add(kind, {})
			var by_chunk: Dictionary = by_variant.get_or_add(picks[k], {})
			var list: Array = by_chunk.get_or_add(chunk, [])
			list.append_array([pos.x, pos.y, rot, size.x * size_mult, tone, radius, si, rot - base_rot])
	for kind in kinds:
		if not groups.has(kind):
			continue
		var kind_spans: PackedFloat32Array = spans.get(kind, PackedFloat32Array())
		var kind_heights: PackedFloat32Array = shadow_heights.get(kind, PackedFloat32Array())
		for variant in groups[kind]:
			var tex: Texture2D = textures[kind][variant]
			var span: float = kind_spans[variant] if variant < kind_spans.size() else 1.0
			var height: float = kind_heights[variant] if variant < kind_heights.size() else 0.0
			if height > 0.0:
				_casts_shadows = true
			for chunk in groups[kind][variant]:
				_build_group(kinds.find(kind), tex, span, height, groups[kind][variant][chunk])
	rebuilt.emit()


# The variants a spawn draws: one, or several different ones for kinds in
# `layers`. All picks come from the spawn's position (h), so they never change.
func _pick_variants(kind: String, variant: int, count: int, h: int) -> PackedInt32Array:
	var first := variant
	if first < 0 or first >= count:
		first = h % count
	var out := PackedInt32Array([first])
	if layers.has(kind):
		var r: Vector2i = layers[kind]
		@warning_ignore("integer_division")
		var n := mini(r.x + (h / 7) % (r.y - r.x + 1), count)
		var k := 1
		while out.size() < n:
			var v := absi(hash([h, k, 2])) % count
			if not out.has(v):
				out.append(v)
			k += 1
	return out


const SPRITE_STRIDE := 8


func _build_group(kind_index: int, tex: Texture2D, span: float, height: float, list: Array) -> void:
	@warning_ignore("integer_division")
	var count := list.size() / SPRITE_STRIDE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = count
	var group := _groups.size()
	_groups.append(mm)
	_group_tex.append(tex)
	var aspect := float(tex.get_height()) / float(tex.get_width())
	for i in count:
		var o := i * SPRITE_STRIDE
		var pos := Vector2(float(list[o]), float(list[o + 1]))
		var w: float = float(list[o + 3]) / maxf(span, 0.05)
		var size := Vector2(w, w * aspect)
		var tone: float = list[o + 4]
		mm.set_instance_transform_2d(i, Transform2D(float(list[o + 2]), size, 0.0, pos))
		mm.set_instance_color(i, Color(tone, tone, tone, 1.0))
		var r := _r_pos.size()
		var si := int(list[o + 6])
		_r_group.append(group)
		_r_index.append(i)
		_r_pos.append(pos)
		_r_radius.append(float(list[o + 5]))
		_r_kind.append(kind_index)
		_r_tone.append(tone)
		_r_base_tone.append(tone)
		_r_size.append(size)
		_r_rot_off.append(float(list[o + 7]))
		_r_rot.append(float(list[o + 2]))
		_r_height.append(height)
		_r_hidden.append(0)
		# Chained after the spawn's earlier records, so its first sprite stays
		# first (sprite_info).
		_r_next.append(-1)
		var first := _spawn_first[si]
		if first < 0:
			_spawn_first[si] = r
		else:
			var last := first
			while _r_next[last] >= 0:
				last = _r_next[last]
			_r_next[last] = r
		var key := _cell_of(pos)
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(r)
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.light_mask = light_mask
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	_nodes.append(node)


func _update_fades(player, delta: float) -> void:
	var targets := {}
	if player:
		var pos := to_local(player.global_position)
		var cell := _cell_of(pos)
		for cx in range(cell.x - 1, cell.x + 2):
			for cy in range(cell.y - 1, cell.y + 2):
				for r in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
					if _r_hidden[r] == 0 and pos.distance_to(_r_pos[r]) <= _r_radius[r] + reveal_margin:
						targets[r] = true
						if not _fading.has(r):
							_fading[r] = 1.0
	for r in _fading.keys():
		var a := move_toward(_fading[r], ghost_alpha if targets.has(r) else 1.0, FADE_SPEED * delta)
		_fading[r] = a
		var tone := _r_tone[r]
		_groups[_r_group[r]].set_instance_color(_r_index[r], Color(tone, tone, tone, a))
		if a >= 1.0:
			_fading.erase(r)


## How long (m) a light shadow is for a sprite `height_m` tall, `distance_m`
## from a light LIGHT_HEIGHT_M up: the light's line over the sprite's top
## meets the ground that far past it, capped (see the top of this script).
static func shadow_length_m(distance_m: float, height_m: float) -> float:
	if height_m <= 0.0:
		return 0.0
	var thrown := distance_m * height_m / maxf(LIGHT_HEIGHT_M - height_m, 0.5)
	return minf(thrown, minf(height_m * SHADOW_PER_HEIGHT, MAX_SHADOW_M))


## How many light shadows were drawn this frame.
func shadow_count() -> int:
	return get_shadows().size()


## The light shadows drawn this frame: {"transform" (the quad, this node's
## space), "offset" (the shadow's reach in the sprite's UV units),
## "alpha"}.
func get_shadows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tex in _frame_shadows:
		var list: Array = _frame_shadows[tex]
		for o in range(0, list.size(), SHADOW_STRIDE):
			out.append({"transform": Transform2D(Vector2(list[o], list[o + 1]), Vector2(list[o + 2], list[o + 3]),
					Vector2(list[o + 4], list[o + 5])), "offset": Vector2(list[o + 6], list[o + 7]), "alpha": list[o + 8]})
	return out


func _update_shadows(delta: float) -> void:
	_wall_check_timer -= delta
	if _wall_check_timer <= 0.0:
		_wall_check_timer = WALL_CHECK_TIME
		_wall_checks.clear()
	# Texture -> flat floats, SHADOW_STRIDE per shadow: transform x, y,
	# origin, then the shader's offset and opacity.
	var shadows := {}
	_frame_shadows = shadows
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var lights := Illumination.shining_mechas(self) if cam != null else []
	if not lights.is_empty():
		var max_px := MAX_SHADOW_M * PX_PER_M
		var half := get_viewport_rect().size / cam.zoom * 0.5 + Vector2(max_px, max_px)
		var centre := to_local(cam.get_screen_center_position())
		var view := Rect2(centre - half, half * 2.0)
		for mecha in lights:
			var light := Illumination.light_of(mecha)
			var from := to_local(light.global_position)
			var extent := Illumination.texture_extent(Illumination.reach(light))
			var box := view.intersection(Rect2(from - Vector2(extent, extent), Vector2(extent, extent) * 2.0))
			if not box.has_area():
				continue
			var lo := _cell_of(box.position)
			var hi := _cell_of(box.end)
			for cx in range(lo.x, hi.x + 1):
				for cy in range(lo.y, hi.y + 1):
					for r in _cells.get(Vector2i(cx, cy), PackedInt32Array()):
						if _r_height[r] <= 0.0 or _r_hidden[r] == 1 or not box.has_point(_r_pos[r]):
							continue
						var strength := Illumination.light_strength(light, to_global(_r_pos[r]))
						if strength < MIN_LIGHT or _wall_between(mecha, r):
							continue
						_add_shadow(shadows, r, _r_pos[r] - from, strength)
	for tex in _shadow_pools:
		if not shadows.has(tex):
			_shadow_pools[tex].multimesh.visible_instance_count = 0
	for tex in shadows:
		_fill_pool(tex, shadows[tex])


const SHADOW_STRIDE := 9


func _add_shadow(shadows: Dictionary, r: int, from_light: Vector2, strength: float) -> void:
	var distance := from_light.length()
	var length := shadow_length_m(distance / PX_PER_M, _r_height[r]) * PX_PER_M
	if distance < 1.0 or length < 1.0:
		return
	var size := _r_size[r]
	var rot := _r_rot[r]
	var offset := from_light / distance * length
	var uv_offset := offset.rotated(-rot) / size
	var corner := Vector2(minf(uv_offset.x, 0.0), minf(uv_offset.y, 0.0))
	var cover := Vector2.ONE + uv_offset.abs()
	var shift := ((corner + cover * 0.5 - Vector2(0.5, 0.5)) * size).rotated(rot)
	var xform := Transform2D(rot, size * cover, 0.0, _r_pos[r] + shift)
	var list: Array = shadows.get_or_add(_group_tex[_r_group[r]], [])
	list.append_array([xform.x.x, xform.x.y, xform.y.x, xform.y.y, xform.origin.x, xform.origin.y,
			uv_offset.x, uv_offset.y, strength * shadow_alpha])


func _fill_pool(tex: Texture2D, list: Array) -> void:
	var pool: MultiMeshInstance2D = _shadow_pools.get(tex)
	if pool == null:
		pool = _make_pool(tex)
	var mm := pool.multimesh
	@warning_ignore("integer_division")
	var count := list.size() / SHADOW_STRIDE
	if mm.instance_count < count:
		mm.instance_count = maxi(count, mm.instance_count * 2)
	for i in count:
		var o := i * SHADOW_STRIDE
		mm.set_instance_transform_2d(i, Transform2D(Vector2(list[o], list[o + 1]),
				Vector2(list[o + 2], list[o + 3]), Vector2(list[o + 4], list[o + 5])))
		mm.set_instance_custom_data(i, Color(list[o + 6], list[o + 7], list[o + 8], 0.0))
	mm.visible_instance_count = count


func _make_pool(tex: Texture2D) -> MultiMeshInstance2D:
	if _shadow_material == null:
		var shader := Shader.new()
		shader.code = SHADOW_SHADER
		_shadow_material = ShaderMaterial.new()
		_shadow_material.shader = shader
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _quad
	var pool := MultiMeshInstance2D.new()
	pool.multimesh = mm
	pool.texture = tex
	pool.material = _shadow_material
	pool.light_mask = 0
	pool.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(pool, false, Node.INTERNAL_MODE_FRONT)
	_shadow_pools[tex] = pool
	return pool


# Whether a building wall is between a mecha and record r's sprite: the
# light doesn't reach it there.
func _wall_between(mecha: Node2D, r: int) -> bool:
	var checks: Dictionary = _wall_checks.get_or_add(mecha.get_instance_id(), {})
	if not checks.has(r):
		checks[r] = MapSenses.walls_between(mecha.get_world_2d(), mecha.global_position, to_global(_r_pos[r]))
	return checks[r]


# The player, looked up again every PLAYER_LOOKUP_TIME s (a group walk a
# frame is a waste for one node that rarely changes).
const PLAYER_LOOKUP_TIME := 1.0
var _player = null
var _player_lookup := 0.0


func _find_player():
	_player_lookup -= get_process_delta_time()
	if _player_lookup > 0.0 and is_instance_valid(_player):
		return _player
	_player_lookup = PLAYER_LOOKUP_TIME
	_player = null
	for m in get_tree().get_nodes_in_group("mecha"):
		if m.has_method("is_player") and m.is_player():
			_player = m
			break
	return _player


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
