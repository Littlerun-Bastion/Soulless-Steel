class_name TallsLean
extends Node2D

# The parent of the talls chunk meshes (crane masts and jibs, pylons,
# minarets, frame floors), drawn above everything else on the map. Its
# ShaderMaterial (TallsLean.gdshader) is shared by the meshes through
# use_parent_material. Each frame this node puts these in the material:
#   camera_centre  the centre of the screen in world px, from the viewport's
#                  canvas transform (so camera pan, shake and zoom are all
#                  in it); the shader leans every vertex away from it by its
#                  height (see lean_offset). With no Camera2D (the editor, a
#                  test with no camera) lean is off and the talls stand flat.
#   fade_centre    the player's position: talls within fade_radius of it
#                  fade to ghost_alpha.
#   ghosts         the other mechas and Entities near the screen, each with
#                  a weight: its modulate alpha, which the player's view sets
#                  to 0 for a body it can't see (MapGhosts). Talls drawn
#                  within ghost_radius of one fade to ghost_alpha by that
#                  weight, so a leaning top never hides what the player
#                  could see without it, and never gives away what it
#                  can't. The list is gathered every GHOST_LIST_TIME s
#                  (bodies near the screen, nearest the centre first, at
#                  most MAX_GHOSTS); their positions are written every
#                  frame. With no talls meshes none of this runs.
# process_priority is high, so this runs after the camera has moved for the
# frame and the lean matches what the screen shows.
#
# Culling: Godot culls a mesh by its ground bounds. A leaned vertex is always
# further from the screen centre than its ground position, so a chunk whose
# ground bounds are off screen also draws off screen, and the chunks
# MapStreamer hides or has not loaded yet (by their ground bounds) could not
# have shown either. Each chunk's cull rect is still grown by cull_margin,
# for a camera that moves after this node has run in a frame.

const EYE_M := 150.0
## Heights are clamped to this (m), well below EYE_M.
const MAX_HEIGHT_M := 100.0
const FAR := Vector2(1e9, 1e9)
const PROCESS_PRIORITY := 1000
## The size of the shader's ghosts array.
const MAX_GHOSTS := MapGhosts.MAX
const GHOST_LIST_TIME := MapGhosts.LIST_TIME

@export var fade_radius := 600.0
@export var ghost_alpha := 0.25
## Talls drawn within this many px of a mecha the player can see fade.
@export var ghost_radius := 300.0
@export var cull_margin := 1000.0

var _player: Node2D = null
var _lookup := 0
var _ghosts := MapGhosts.new()


func _ready() -> void:
	process_priority = PROCESS_PRIORITY
	var mat := material as ShaderMaterial
	if mat == null:
		set_process(false)
		return
	mat.set_shader_parameter("eye_m", EYE_M)
	mat.set_shader_parameter("max_height_m", MAX_HEIGHT_M)
	mat.set_shader_parameter("fade_radius", fade_radius)
	mat.set_shader_parameter("ghost_alpha", ghost_alpha)
	mat.set_shader_parameter("fade_centre", FAR)
	mat.set_shader_parameter("lean", false)
	mat.set_shader_parameter("ghost_radius", ghost_radius)
	_ghosts.write(mat)
	if Engine.is_editor_hint():
		set_process(false)
		return
	_grow_cull_rects()
	child_entered_tree.connect(_on_child_entered)


# Where a camera EYE_M above `camera` (world px) sees a point at `ground`
# (world px) `height_m` above the ground: the talls shader's rule.
static func lean_offset(ground: Vector2, camera: Vector2, height_m: float) -> Vector2:
	var h := clampf(height_m, 0.0, MAX_HEIGHT_M)
	return (ground - camera) * (h / (EYE_M - h))


# The centre of what `viewport` shows, in world px.
static func screen_centre(viewport: Viewport) -> Vector2:
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect().get_center()


func _process(delta: float) -> void:
	if get_child_count() == 0:
		return
	update_lean()
	_ghosts.update(get_viewport(), _find_player(), material as ShaderMaterial, delta)


# Puts this frame's camera centre and player position in the material.
func update_lean() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var viewport := get_viewport()
	var has_camera := viewport != null and viewport.get_camera_2d() != null
	mat.set_shader_parameter("lean", has_camera)
	if has_camera:
		mat.set_shader_parameter("camera_centre", screen_centre(viewport))
	var player := _find_player()
	mat.set_shader_parameter("fade_centre", player.global_position if player != null else FAR)


func _on_child_entered(child: Node) -> void:
	_grow_cull_rect.call_deferred(child)


func _grow_cull_rects() -> void:
	for child in get_children():
		_grow_cull_rect(child)


func _grow_cull_rect(child: Variant) -> void:
	if not is_instance_valid(child):
		return
	var chunk := child as ChunkMesh
	if chunk == null:
		return
	RenderingServer.canvas_item_set_custom_rect(chunk.get_canvas_item(), true, chunk.bounds.grow(cull_margin))


func _find_player() -> Node2D:
	if is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = null
	_lookup -= 1
	if _lookup > 0:
		return null
	_lookup = 30
	for mech in get_tree().get_nodes_in_group("mecha"):
		if mech is Node2D and mech.has_method("is_player") and mech.is_player():
			_player = mech
			break
	return _player
