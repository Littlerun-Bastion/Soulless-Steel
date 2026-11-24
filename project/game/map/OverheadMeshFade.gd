extends Node2D

# The parent of the overhead chunk meshes (pipe bridges over roads, strut
# frames), drawn above mechas. Its ShaderMaterial (OverheadGrain.gdshader) is
# shared by the meshes through use_parent_material. Each frame this node puts
# the player's position in the material, which fades the meshes within
# fade_radius of it to ghost_alpha, so the player is never hidden under one.
# With no player, nothing fades.

@export var fade_radius := 600.0
@export var ghost_alpha := 0.25

const FAR := Vector2(1e9, 1e9)

var _player: Node2D = null
var _lookup := 0


func _ready() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		set_process(false)
		return
	mat.set_shader_parameter("fade_radius", fade_radius)
	mat.set_shader_parameter("ghost_alpha", ghost_alpha)
	mat.set_shader_parameter("fade_centre", FAR)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var mat := material as ShaderMaterial
	var at := FAR
	var player := _find_player()
	if player != null:
		at = player.global_position
	mat.set_shader_parameter("fade_centre", at)


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
