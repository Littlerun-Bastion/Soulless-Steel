class_name BloodStains
extends Node2D

## The mechas' white-hot coolant-blood on the ground. One per combat scene
## (CombatScene._setup_heatmap), under the wrecks and the mechas.
##   splatter  (add_splatter, a mecha entering the emergency Flag) a
##             directional spray thrown away from the attacker, dense at the
##             mecha with streaks beyond it, droplets past the streaks and
##             blobs scattered round the mecha
##   pool      (add_pool, a mecha dying) a big round pool with a few lobes,
##             spreading out under the wreck over POOL_GROW_TIME s
##   small     (add_small_splatter, a hit destroying an internal component)
##             one smaller directional splatter, its dense end at the part
##             and its streaks along the hit
## Every use varies: a random spray image or sheet frame, flips, small turns
## and size changes. Round splats, the sprays and the small-splatter sheet
## are Yosqi's sprites; droplets are frames of the drip sheet the mechas'
## blood particles use.
##
## spray() is the moving blood: a tight, fast jet of droplets
## (blood_particle1) along a direction, slowing to a stop within
## SPRAY_LIFETIME s. It draws above the mechas. A pool of SPRAY_EMITTERS
## one-shot emitters is reused in turn.
##
## A stain starts white-hot (G6) and cools step by step through the greys to
## a dull G3 stain over COOL_TIME s, and stays for the rest of the scene, so a
## bright one means a recent kill. Drawn unshaded, so a hot stain shows in the
## dark like any heat.
##
## At most MAX_STAINS stains are on the map: past that, the oldest fades out
## over FADE_TIME s to make room. Stains live in a fixed pool of slots (the
## extra FADE_SLACK hold the ones fading out) drawn in five MultiMeshes, one
## per texture, with no node per stain. Colours refresh every REFRESH_TIME s.

const ROUND_TEXTURE_PATH := "res://assets/images/fx/blood_splat_round.png"
const ROUND_FALLBACK := preload("res://assets/images/fx/blood_pool1.png")
const SPRAY_TEXTURES := [preload("res://assets/images/fx/blood_spray_1.png"), preload("res://assets/images/fx/blood_spray_2.png")]
const DRIP_SHEET := preload("res://assets/images/fx/blood_drip_sheet.png")
const DRIP_FRAMES := 6  # the sheet is DRIP_FRAMES x DRIP_FRAMES
## Ten small splatters, 2 across and 5 down, each with its dense end against
## the right edge of its cell and its streaks running left.
const SMALL_SHEET_PATH := "res://assets/images/fx/blood_splatter_small_sheet.png"
const SMALL_GRID := Vector2i(2, 5)
const DROPLET := preload("res://assets/images/fx/blood_particle1.png")

const MAX_STAINS := 64
const FADE_SLACK := 8
const FADE_TIME := 1.0
const COOL_TIME := 60.0
const REFRESH_TIME := 0.25
## White-hot to cold, the palette greys G6 to G3.
const HEAT_STEPS := [Color(0.949, 0.949, 0.949), Color(0.839, 0.839, 0.839),
		Color(0.541, 0.541, 0.541), Color(0.227, 0.227, 0.227)]

## Pieces a stain can hold, per texture.
const ROUNDS_PER_STAIN := 6
const DROPS_PER_STAIN := 12

## Splatter sizes (px). The spray's dense end sits SPRAY_BACKSET of its
## length behind the mecha's centre.
const SPRAY_LENGTH := 640.0
const SPRAY_BACKSET := 0.12
const SPLATTER_GROW_TIME := 0.15
const BLOB_SIZE := Vector2(80, 190)
const BLOB_REACH := Vector2(40, 160)
const DROP_SIZE := Vector2(24, 60)
const DROP_SPREAD := 0.35  # rad either side of the spray's line
## Pool sizes (px).
const POOL_SIZE := 420.0
const POOL_LOBE_SIZE := Vector2(150, 250)
const POOL_LOBE_REACH := Vector2(60, 130)
const POOL_GROW_TIME := 3.0
const POOL_START := 0.15  # the pool starts at this fraction of its size
## Small splatter length (px); its dense end sits SMALL_BACKSET of that
## behind the part.
const SMALL_LENGTH := Vector2(220, 320)
const SMALL_BACKSET := 0.06

## The droplet jet (spray). Placeholders.
const SPRAY_EMITTERS := 12
const SPRAY_AMOUNT := 40
const SPRAY_LIFETIME := 0.7
const SPRAY_SPREAD := 6.0  # degrees either side of the direction
const SPRAY_SPEED := Vector2(700, 1900)
const SPRAY_DAMPING := Vector2(1800, 2800)
const SPRAY_SCALE := Vector2(0.75, 2.0)
const SPRAY_Z := 9

enum Kind { SPLATTER, POOL, SMALL }
const KIND_NAMES := ["splatter", "pool", "small"]
enum Batch { ROUND, SPRAY_1, SPRAY_2, DROPS, SMALL }

# Draws frame INSTANCE_CUSTOM.x of a sheet `grid` frames across and down.
const SHEET_SHADER_CODE := "shader_type canvas_item;
render_mode unshaded;
uniform vec2 grid = vec2(6.0, 6.0);
void vertex() {
	float f = INSTANCE_CUSTOM.x;
	UV = (UV + vec2(mod(f, grid.x), floor(f / grid.x))) / grid;
}
"

var now := 0.0

class Pieces:
	var per_slot: int
	var multimesh := MultiMesh.new()
	var pos := PackedVector2Array()
	var rot := PackedFloat32Array()
	var size := PackedVector2Array()
	var alpha := PackedFloat32Array()

var _batches: Array[Pieces] = []
var _used := PackedByteArray()
var _kind := PackedByteArray()
var _born := PackedFloat32Array()
var _fade_at := PackedFloat32Array()
var _grow_time := PackedFloat32Array()
var _centre := PackedVector2Array()
var _dir := PackedVector2Array()
var _refresh := 0.0
var _sprays: Array[GPUParticles2D] = []
var _next_spray := 0
var _small_sheet: Texture2D = null


## The scene's blood stains, or null.
static func find(node: Node) -> BloodStains:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("blood_stains") as BloodStains


func _ready() -> void:
	add_to_group("blood_stains")
	light_mask = 0
	var slots := MAX_STAINS + FADE_SLACK
	_used.resize(slots)
	_kind.resize(slots)
	_born.resize(slots)
	_fade_at.resize(slots)
	_grow_time.resize(slots)
	_centre.resize(slots)
	_dir.resize(slots)
	var round_texture: Texture2D = ROUND_FALLBACK
	if ResourceLoader.exists(ROUND_TEXTURE_PATH):
		round_texture = load(ROUND_TEXTURE_PATH)
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var sheet_shader := Shader.new()
	sheet_shader.code = SHEET_SHADER_CODE
	_add_batch(round_texture, ROUNDS_PER_STAIN, unshaded, false)
	_add_batch(SPRAY_TEXTURES[0], 1, unshaded, false)
	_add_batch(SPRAY_TEXTURES[1], 1, unshaded, false)
	_add_batch(DRIP_SHEET, DROPS_PER_STAIN, _sheet_material(sheet_shader, Vector2(DRIP_FRAMES, DRIP_FRAMES)), true)
	_small_sheet = load(SMALL_SHEET_PATH)
	_add_batch(_small_sheet, 1, _sheet_material(sheet_shader, Vector2(SMALL_GRID)), true)
	_add_sprays(unshaded)


func _sheet_material(shader: Shader, grid: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("grid", grid)
	return mat


func _add_sprays(mat: Material) -> void:
	var process := ParticleProcessMaterial.new()
	process.particle_flag_disable_z = true
	process.particle_flag_align_y = true
	process.direction = Vector3(1, 0, 0)
	process.spread = SPRAY_SPREAD
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = SPRAY_SPEED.x
	process.initial_velocity_max = SPRAY_SPEED.y
	process.damping_min = SPRAY_DAMPING.x
	process.damping_max = SPRAY_DAMPING.y
	process.scale_min = SPRAY_SCALE.x
	process.scale_max = SPRAY_SCALE.y
	process.lifetime_randomness = 0.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.5))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	process.scale_curve = shrink_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(HEAT_STEPS[0], 1.0))
	fade.set_color(1, Color(HEAT_STEPS[1], 0.0))
	fade.add_point(0.6, Color(HEAT_STEPS[0], 1.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	for i in SPRAY_EMITTERS:
		var emitter := GPUParticles2D.new()
		emitter.name = "Spray%d" % i
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.9
		emitter.amount = SPRAY_AMOUNT
		emitter.lifetime = SPRAY_LIFETIME
		emitter.local_coords = false
		emitter.texture = DROPLET
		emitter.process_material = process
		emitter.material = mat
		emitter.light_mask = 0
		emitter.z_as_relative = false
		emitter.z_index = SPRAY_Z
		emitter.visibility_rect = Rect2(-2000, -2000, 4000, 4000)
		add_child(emitter)
		_sprays.append(emitter)


func _add_batch(texture: Texture2D, per_slot: int, mat: Material, custom: bool) -> void:
	var pieces := Pieces.new()
	pieces.per_slot = per_slot
	var count := per_slot * (MAX_STAINS + FADE_SLACK)
	pieces.pos.resize(count)
	pieces.rot.resize(count)
	pieces.size.resize(count)
	pieces.alpha.resize(count)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	pieces.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	pieces.multimesh.use_colors = true
	pieces.multimesh.use_custom_data = custom
	pieces.multimesh.mesh = quad
	pieces.multimesh.instance_count = count
	for i in count:
		pieces.multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
		pieces.multimesh.set_instance_color(i, Color(1, 1, 1, 0))
	var drawn := MultiMeshInstance2D.new()
	drawn.multimesh = pieces.multimesh
	drawn.texture = texture
	drawn.material = mat
	drawn.light_mask = 0
	add_child(drawn)
	_batches.append(pieces)


func _process(dt: float) -> void:
	now += dt
	for slot in _used.size():
		if _used[slot] and now - _born[slot] < _grow_time[slot]:
			_place(slot)
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = REFRESH_TIME
		_redraw()


## A splatter at `at`, the mecha entering the Flag, thrown along `away` (from
## the attacker through the mecha). Returns its slot.
func add_splatter(at: Vector2, away: Vector2) -> int:
	var dir := away.normalized() if away != Vector2.ZERO else Vector2.RIGHT
	var slot := _take_slot(Kind.SPLATTER, at, dir, SPLATTER_GROW_TIME)
	var spray_batch := Batch.SPRAY_1 if randf() < 0.5 else Batch.SPRAY_2
	var texture: Texture2D = SPRAY_TEXTURES[spray_batch - Batch.SPRAY_1]
	var length := SPRAY_LENGTH * randf_range(0.85, 1.15)
	var spray_size := Vector2(length, length * texture.get_height() / float(texture.get_width()))
	if randf() < 0.5:
		spray_size.y = -spray_size.y
	# The image's streaks run right to left: turn its left (-x) onto dir.
	var spray_at := at + dir * length * (0.5 - SPRAY_BACKSET)
	_set_piece(spray_batch, slot, 0, spray_at, (-dir).angle() + randf_range(-0.12, 0.12), spray_size, 1.0)

	var blobs := randi_range(3, ROUNDS_PER_STAIN)
	for k in blobs:
		var reach := randf_range(BLOB_REACH.x, BLOB_REACH.y) if k > 0 else 30.0
		var blob_at := at + Vector2.RIGHT.rotated(randf() * TAU) * reach
		var blob := randf_range(BLOB_SIZE.x, BLOB_SIZE.y) * (1.4 if k == 0 else 1.0)
		_set_piece(Batch.ROUND, slot, k, blob_at, randf() * TAU, _flipped(Vector2(blob, blob)), randf_range(0.75, 1.0))

	var drops := randi_range(DROPS_PER_STAIN / 2, DROPS_PER_STAIN)
	for k in drops:
		var drop_dir := dir.rotated(randf_range(-DROP_SPREAD, DROP_SPREAD))
		var drop_at := at + drop_dir * length * randf_range(0.6, 1.25)
		var drop := randf_range(DROP_SIZE.x, DROP_SIZE.y)
		_set_piece(Batch.DROPS, slot, k, drop_at, randf() * TAU, Vector2(drop, drop), randf_range(0.7, 1.0),
				randi() % (DRIP_FRAMES * DRIP_FRAMES))
	_place(slot)
	return slot


## A pool spreading under a dying mecha at `at`. Returns its slot.
func add_pool(at: Vector2) -> int:
	var slot := _take_slot(Kind.POOL, at, Vector2.ZERO, POOL_GROW_TIME)
	var pool := POOL_SIZE * randf_range(0.9, 1.1)
	_set_piece(Batch.ROUND, slot, 0, at, randf() * TAU, _flipped(Vector2(pool, pool)), 1.0)
	var lobes := randi_range(2, 3)
	for k in lobes:
		var lobe_at := at + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(POOL_LOBE_REACH.x, POOL_LOBE_REACH.y)
		var lobe := randf_range(POOL_LOBE_SIZE.x, POOL_LOBE_SIZE.y)
		_set_piece(Batch.ROUND, slot, k + 1, lobe_at, randf() * TAU, _flipped(Vector2(lobe, lobe)), 0.9)
	_place(slot)
	return slot


## A small splatter, a hit destroying an internal component: its dense end
## at `at` (the part), its streaks thrown along `dir` (the hit). Returns its
## slot.
func add_small_splatter(at: Vector2, dir: Vector2) -> int:
	dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var slot := _take_slot(Kind.SMALL, at, dir, SPLATTER_GROW_TIME)
	var cell := Vector2(_small_sheet.get_size()) / Vector2(SMALL_GRID)
	var length := randf_range(SMALL_LENGTH.x, SMALL_LENGTH.y)
	var piece_size := Vector2(length, length * cell.y / cell.x)
	if randf() < 0.5:
		piece_size.y = -piece_size.y
	var piece_at := at + dir * length * (0.5 - SMALL_BACKSET)
	_set_piece(Batch.SMALL, slot, 0, piece_at, (-dir).angle() + randf_range(-0.1, 0.1), piece_size, 1.0,
			randi() % (SMALL_GRID.x * SMALL_GRID.y))
	_place(slot)
	return slot


## A jet of droplets from `at` along `dir`; `strength` (0 to 1) is the share
## of a full jet's droplets, so a small one is a few drops.
func spray(at: Vector2, dir: Vector2, strength := 1.0) -> void:
	if _sprays.is_empty():
		return
	var emitter := _sprays[_next_spray]
	_next_spray = (_next_spray + 1) % _sprays.size()
	emitter.global_position = at
	emitter.global_rotation = dir.angle() if dir != Vector2.ZERO else randf() * TAU
	emitter.amount_ratio = clampf(strength, 0.05, 1.0)
	emitter.restart()
	emitter.emitting = true


## How many stains are on the map (not counting ones fading out).
func stain_count() -> int:
	var count := 0
	for slot in _used.size():
		if _used[slot] and _fade_at[slot] < 0.0:
			count += 1
	return count


## The stains on the map, oldest first: {"kind" ("splatter", "pool",
## "small"), "position", "direction" (a splatter's, from the attacker, or a
## small one's, the hit's; ZERO for a pool), "age" (s), "color" (now)}.
func get_stains() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for slot in _by_age():
		if _fade_at[slot] >= 0.0:
			continue
		found.append({"kind": KIND_NAMES[_kind[slot]],
				"position": _centre[slot], "direction": _dir[slot], "age": now - _born[slot],
				"color": heat_color(now - _born[slot])})
	return found


## A stain's tint at `age` s: G6 when fresh, a step darker every third of
## COOL_TIME, G3 once cold.
static func heat_color(age: float) -> Color:
	var step := clampi(int(age / COOL_TIME * (HEAT_STEPS.size() - 1)), 0, HEAT_STEPS.size() - 1)
	return HEAT_STEPS[step]


func _take_slot(kind: Kind, at: Vector2, dir: Vector2, grow_time: float) -> int:
	if stain_count() >= MAX_STAINS:
		for slot in _by_age():
			if _fade_at[slot] < 0.0:
				_fade_at[slot] = now
				break
	var free := _used.find(0)
	if free == -1:
		# Every spare slot is still fading: take the oldest of those now.
		var by_age := _by_age()
		free = by_age[0]
		for slot in by_age:
			if _fade_at[slot] >= 0.0:
				free = slot
				break
	_clear(free)
	_used[free] = 1
	_kind[free] = kind
	_born[free] = now
	_fade_at[free] = -1.0
	_grow_time[free] = grow_time
	_centre[free] = at
	_dir[free] = dir
	return free


# Used slots, oldest first.
func _by_age() -> Array:
	var slots := []
	for slot in _used.size():
		if _used[slot]:
			slots.append(slot)
	slots.sort_custom(func(a, b): return _born[a] < _born[b])
	return slots


func _set_piece(batch: Batch, slot: int, k: int, at: Vector2, rotation_rad: float, piece_size: Vector2,
		piece_alpha: float, frame := 0) -> void:
	var pieces := _batches[batch]
	var i := slot * pieces.per_slot + k
	pieces.pos[i] = at
	pieces.rot[i] = rotation_rad
	pieces.size[i] = piece_size
	pieces.alpha[i] = piece_alpha
	if pieces.multimesh.use_custom_data:
		pieces.multimesh.set_instance_custom_data(i, Color(frame, 0, 0, 0))


func _flipped(piece_size: Vector2) -> Vector2:
	return Vector2(piece_size.x * (1.0 if randf() < 0.5 else -1.0), piece_size.y * (1.0 if randf() < 0.5 else -1.0))


func _clear(slot: int) -> void:
	for pieces in _batches:
		for k in pieces.per_slot:
			var i := slot * pieces.per_slot + k
			pieces.alpha[i] = 0.0
			pieces.multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
			pieces.multimesh.set_instance_color(i, Color(1, 1, 1, 0))
	_used[slot] = 0


# Sets the slot's transforms, scaled about its centre while it grows.
func _place(slot: int) -> void:
	var grown := 1.0
	if _grow_time[slot] > 0.0:
		var t := clampf((now - _born[slot]) / _grow_time[slot], 0.0, 1.0)
		var start := POOL_START if _kind[slot] == Kind.POOL else 0.5
		grown = lerpf(start, 1.0, 1.0 - (1.0 - t) * (1.0 - t))
	var centre := _centre[slot]
	for pieces in _batches:
		for k in pieces.per_slot:
			var i := slot * pieces.per_slot + k
			if pieces.alpha[i] <= 0.0:
				continue
			var at := centre + (pieces.pos[i] - centre) * grown
			pieces.multimesh.set_instance_transform_2d(i, Transform2D(pieces.rot[i], pieces.size[i] * grown, 0.0, at))
	_color(slot)


func _color(slot: int) -> void:
	var fade := 1.0
	if _fade_at[slot] >= 0.0:
		fade = 1.0 - clampf((now - _fade_at[slot]) / FADE_TIME, 0.0, 1.0)
	var tint := heat_color(now - _born[slot])
	for pieces in _batches:
		for k in pieces.per_slot:
			var i := slot * pieces.per_slot + k
			if pieces.alpha[i] > 0.0:
				pieces.multimesh.set_instance_color(i, Color(tint, pieces.alpha[i] * fade))


func _redraw() -> void:
	for slot in _used.size():
		if not _used[slot]:
			continue
		if _fade_at[slot] >= 0.0 and now - _fade_at[slot] >= FADE_TIME:
			_clear(slot)
			continue
		_color(slot)
