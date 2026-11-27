extends Node2D

# The parent of the overhead chunk meshes (pipe bridges over roads, strut
# frames, platform and pavilion roofs, gas-station canopies, depot shelters),
# drawn above mechas. Its ShaderMaterial (OverheadGrain.gdshader) is shared by the meshes
# through use_parent_material. Each frame this node puts in the material:
#   fade_centre  the player's position: the meshes within fade_radius of it
#                fade to ghost_alpha, so the player is never hidden under one.
#   ghosts       the other mechas and Entities near the screen the player can
#                see (MapGhosts, weighted by their view alpha): the meshes
#                within ghost_radius of one fade to ghost_alpha by that
#                weight, so a canopy never hides a mecha the player could see
#                without it, and never gives away one it can't.
# With no player nothing fades round the player; with no camera there are no
# ghosts.

@export var fade_radius := 600.0
@export var ghost_alpha := 0.25
## Overheads within this many px of a mecha the player can see fade.
@export var ghost_radius := 300.0

const FAR := Vector2(1e9, 1e9)

var _player: Node2D = null
var _lookup := 0
var _ghosts := MapGhosts.new()


func _ready() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		set_process(false)
		return
	mat.set_shader_parameter("fade_radius", fade_radius)
	mat.set_shader_parameter("ghost_alpha", ghost_alpha)
	mat.set_shader_parameter("fade_centre", FAR)
	mat.set_shader_parameter("ghost_radius", ghost_radius)
	_ghosts.write(mat)
	if Engine.is_editor_hint():
		set_process(false)


func _process(delta: float) -> void:
	if get_child_count() == 0:
		return
	var mat := material as ShaderMaterial
	var at := FAR
	var player := _find_player()
	if player != null:
		at = player.global_position
	mat.set_shader_parameter("fade_centre", at)
	_ghosts.update(get_viewport(), player, mat, delta)


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
