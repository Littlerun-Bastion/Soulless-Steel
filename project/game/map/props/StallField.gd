class_name StallField
extends Node2D

# Breakable props: the PropSpawner's spawns of one kind (`kind`: market
# stalls by default; a second StallField takes the industrial huts and
# cabins), drawn by a PropSpriteLayer. They are called stalls below. Stalls
# are props, not buildings: they have no body, stop no shot and cost no AP. A
# stall breaks at once when a mecha walks into it, when a shot passes over
# it, or when a blast reaches it; it then stays broken for the rest of the
# expedition (nothing is saved).
#
# Mechas: every CHECK_FRAMES physics frames, each mecha's round footprint
# (Illumination.body_radius) is tested against the stalls in the cells round
# it; a stall it overlaps breaks, thrown the way the mecha moves.
#
# Shots: SimpleProjectile calls shot_through() with the part of its path it
# flew each step, and MapSenses.trace_shot (the complex rounds) does the same
# for real shots; a blast calls blast_at(). These are static and reach every
# StallField in the scene, so the callers need no reference.
#
# A broken stall's sprite comes off the layer. In its place: the broken
# sprite "<sprite>_broken.png" next to the stall's own sprite (for example
# stall_canopy_broken.png), or the stall's own sprite darkened to
# BROKEN_TONE, pushed a little the way it was hit, plus a few loose pieces
# and (with spills_goods) spilled goods thrown that way.
#
# Broken from the start: a spawn whose variant's texture is itself a
# "..._broken" file is a ruin the map was made with. The layer draws it like
# any other sprite; here it only counts as broken, so nothing breaks it
# again and no node is made for it.

const CELL_SIZE := 1000.0
const CHECK_FRAMES := 3
## How far (px) a broken stall's remains are pushed the way it was hit.
const THROW := 40.0
const BROKEN_TONE := 0.45
## Loose pieces thrown out of a broken stall, and how far (px) they fly.
const PIECES := Vector2i(3, 5)
const PIECE_THROW := Vector2(60.0, 180.0)
const GOODS := Vector2i(5, 10)
const PIECE_TONE := 0.4
const GOODS_TONE := 0.6

static var _fields: Array[StallField] = []

@export var spawner_path: NodePath
@export var layer_path: NodePath
## The spawn kind this field breaks.
@export var kind := "stall"
## Whether a breaking stall spills goods (a market stall does, a cabin
## doesn't).
@export var spills_goods := true

var _layer: PropSpriteLayer = null
var _spawn_index := PackedInt32Array()
var _pos := PackedVector2Array()
var _rot := PackedFloat32Array()
var _size := PackedVector2Array()
var _variant := PackedInt32Array()
var _broken := PackedByteArray()
var _cells := {}
var _radius := {}
var _built := false
var _broken_textures := {}
var _rng := RandomNumberGenerator.new()

signal stall_broken(index: int)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_fields.append(self)
	_rng.seed = hash(get_path())
	_build.call_deferred()


func _exit_tree() -> void:
	_fields.erase(self)


static func find(node: Node) -> StallField:
	for field in _fields:
		if is_instance_valid(field) and field.is_inside_tree() and field.get_tree() == node.get_tree():
			return field
	return null


## Breaks every stall the segment from `from` to `to` (global) passes over,
## in every StallField in the scene. `by` is what shot (unused for now).
static func shot_through(_by: Node, from: Vector2, to: Vector2) -> void:
	for field in _fields:
		if is_instance_valid(field) and field._built:
			field.break_along(from, to)


## Breaks every stall within `radius` px of a blast at `pos` (global).
static func blast_at(pos: Vector2, radius: float) -> void:
	for field in _fields:
		if is_instance_valid(field) and field._built:
			field.break_in_radius(pos, radius)


func stall_count() -> int:
	return _pos.size()


func broken_count() -> int:
	var n := 0
	for b in _broken:
		n += b
	return n


func is_built() -> bool:
	return _built


func is_broken(i: int) -> bool:
	return _broken[i] == 1


func stall_position(i: int) -> Vector2:
	return _pos[i]


func stall_size(i: int) -> Vector2:
	return _size[i]


func break_along(from: Vector2, to: Vector2) -> void:
	var r := Rect2(from, Vector2.ZERO).expand(to)
	var dir := (to - from).normalized()
	for i in _stalls_in(r):
		if _broken[i] == 0 and _segment_hits(i, from, to):
			break_stall(i, dir)


func break_in_radius(pos: Vector2, radius: float) -> void:
	for i in _stalls_in(Rect2(pos, Vector2.ZERO).grow(radius)):
		if _broken[i] == 0 and _pos[i].distance_to(pos) <= radius + _size[i].length() * 0.5:
			var away := _pos[i] - pos
			break_stall(i, away.normalized() if away.length_squared() > 1.0 else Vector2.RIGHT)


func break_stall(i: int, push_dir: Vector2) -> void:
	if _broken[i] == 1:
		return
	_broken[i] = 1
	_show_broken(i, push_dir)
	stall_broken.emit(i)


func _physics_process(_delta: float) -> void:
	if not _built or Engine.get_physics_frames() % CHECK_FRAMES != 0:
		return
	for mech in get_tree().get_nodes_in_group("mecha"):
		if not (mech is Node2D) or mech.get("is_dead") == true:
			continue
		var body := mech as Node2D
		var radius: float = _radius.get(body.get_instance_id(), -1.0)
		if radius < 0.0:
			radius = Illumination.body_radius(body)
			_radius[body.get_instance_id()] = radius
		var at := body.global_position
		for i in _stalls_in(Rect2(at, Vector2.ZERO).grow(radius)):
			if _broken[i] == 0 and _circle_hits(i, at, radius):
				var push := Vector2.ZERO
				if body is CharacterBody2D:
					push = (body as CharacterBody2D).velocity
				if push.length_squared() < 1.0:
					push = _pos[i] - at
				break_stall(i, push.normalized() if push.length_squared() > 0.0 else Vector2.RIGHT)


func _build() -> void:
	_layer = get_node_or_null(layer_path) as PropSpriteLayer
	var spawner := get_node_or_null(spawner_path) as PropSpawner
	if spawner == null:
		push_warning("StallField: spawner not found")
		return
	var kind_textures: Array = _layer.textures.get(kind, []) if _layer != null else []
	for si in spawner.indices_of_kinds(PackedStringArray([kind])):
		var i := _pos.size()
		_spawn_index.append(si)
		_pos.append(spawner.to_global(spawner.spawn_position(si)))
		_rot.append(spawner.spawn_rotation(si) + spawner.global_rotation)
		_size.append(spawner.spawn_size(si))
		_variant.append(_layer.variant_of_spawn(si) if _layer != null else spawner.spawn_variant(si))
		var ruin := false
		if _variant[i] >= 0 and _variant[i] < kind_textures.size():
			var texture := kind_textures[_variant[i]] as Texture2D
			ruin = texture != null and texture.resource_path.get_basename().ends_with("_broken")
		_broken.append(1 if ruin else 0)
		var key := _cell_of(_pos[i])
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(i)
	_built = true


func _stalls_in(rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	# A stall is filed by its centre; reach past the rect by the largest
	# stall's half-diagonal.
	var grown := rect.grow(CELL_SIZE * 0.25)
	var c0 := _cell_of(grown.position)
	var c1 := _cell_of(grown.end)
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var list: PackedInt32Array = _cells.get(Vector2i(cx, cy), PackedInt32Array())
			out.append_array(list)
	return out


# Stall i's outline corners, global.
func _corners(i: int) -> PackedVector2Array:
	var half := _size[i] * 0.5
	var xf := Transform2D(_rot[i], _pos[i])
	return PackedVector2Array([xf * Vector2(-half.x, -half.y), xf * Vector2(half.x, -half.y),
			xf * Vector2(half.x, half.y), xf * Vector2(-half.x, half.y)])


func _segment_hits(i: int, from: Vector2, to: Vector2) -> bool:
	var poly := _corners(i)
	if Geometry2D.is_point_in_polygon(from, poly) or Geometry2D.is_point_in_polygon(to, poly):
		return true
	for k in 4:
		if Geometry2D.segment_intersects_segment(from, to, poly[k], poly[(k + 1) % 4]) != null:
			return true
	return false


func _circle_hits(i: int, centre: Vector2, radius: float) -> bool:
	var local := Transform2D(_rot[i], _pos[i]).affine_inverse() * centre
	var half := _size[i] * 0.5
	var nearest := local.clamp(-half, half)
	return nearest.distance_squared_to(local) <= radius * radius


func _show_broken(i: int, push_dir: Vector2) -> void:
	var holder := Node2D.new()
	holder.light_mask = _layer.light_mask if _layer != null else light_mask
	add_child(holder)
	holder.global_position = _pos[i] + push_dir * THROW
	holder.global_rotation = _rot[i] + _rng.randf_range(-0.25, 0.25)
	var info := _layer.sprite_info(_spawn_index[i]) if _layer != null else {}
	if not info.is_empty():
		_layer.hide_sprite(_spawn_index[i])
		var normal: Texture2D = info.texture
		var broken := _broken_texture(normal)
		var sprite := Sprite2D.new()
		sprite.texture = broken if broken != null else normal
		var size: Vector2 = Vector2(info.scale) * normal.get_size()
		sprite.scale = size / sprite.texture.get_size()
		var tone: float = info.tone * (1.0 if broken != null else BROKEN_TONE)
		sprite.modulate = Color(tone, tone, tone)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.light_mask = holder.light_mask
		holder.add_child(sprite)
	_throw_pieces(i, holder, push_dir)


# Loose boards and poles, and spilled goods, thrown the way the stall was hit.
func _throw_pieces(i: int, holder: Node2D, push_dir: Vector2) -> void:
	var span := maxf(_size[i].x, _size[i].y)
	for k in _rng.randi_range(PIECES.x, PIECES.y):
		var piece := Polygon2D.new()
		var w := _rng.randf_range(0.08, 0.16) * span
		var h := _rng.randf_range(0.35, 0.7) * span
		piece.polygon = PackedVector2Array([Vector2(-w, -h) * 0.5, Vector2(w, -h) * 0.5, Vector2(w, h) * 0.5, Vector2(-w, h) * 0.5])
		piece.color = Color(PIECE_TONE, PIECE_TONE, PIECE_TONE)
		piece.light_mask = holder.light_mask
		add_child(piece)
		var dir := push_dir.rotated(_rng.randf_range(-0.7, 0.7))
		piece.global_position = _pos[i] + dir * _rng.randf_range(PIECE_THROW.x, PIECE_THROW.y)
		piece.global_rotation = _rng.randf() * TAU
	if not spills_goods:
		return
	for k in _rng.randi_range(GOODS.x, GOODS.y):
		var good := Polygon2D.new()
		var r := _rng.randf_range(0.03, 0.06) * span
		good.polygon = PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
		var tone := GOODS_TONE * _rng.randf_range(0.7, 1.1)
		good.color = Color(tone, tone, tone)
		good.light_mask = holder.light_mask
		add_child(good)
		var dir := push_dir.rotated(_rng.randf_range(-1.2, 1.2))
		good.global_position = _pos[i] + dir * _rng.randf_range(0.0, PIECE_THROW.x * 1.5)
		good.global_rotation = _rng.randf() * TAU


func _broken_texture(normal: Texture2D) -> Texture2D:
	var path := normal.resource_path
	if path.is_empty():
		return null
	var broken_path := path.get_basename() + "_broken." + path.get_extension()
	if not _broken_textures.has(broken_path):
		_broken_textures[broken_path] = load(broken_path) as Texture2D if ResourceLoader.exists(broken_path) else null
	return _broken_textures[broken_path]


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
