extends CanvasLayer

# The IR colour map over the world (Heatmap), and the sight mask over it
# (SightMask): black past the player's sight circle (Mecha.sight_radius), with
# a soft edge MASK_EDGE px wide, centred on the player's place on the screen.
# The circle's radius on the screen is the sight radius times the camera's
# zoom. The mask is off with no player, once the player is dead, and while
# controls are locked (cutscenes). The HUD (PlayerHUD, later on this layer,
# and the higher layers) draws over it.

const MASK_EDGE := 2.0

@onready var _mask: ColorRect = $SightMask

var player = null


func change_heatmap(heatmap):
	$Heatmap.material.set_shader_parameter("Colormap", heatmap)


## The mecha whose sight circle the mask shows (CombatScene._register_player).
func set_player(player_ref) -> void:
	player = player_ref
	_mask.material.set_shader_parameter("edge", MASK_EDGE)


func _process(_delta: float) -> void:
	var on: bool = is_instance_valid(player) and not player.is_dead and not player.controls_locked \
			and player.is_inside_tree()
	if _mask.visible != on:
		_mask.visible = on
	if not on:
		return
	var to_screen: Transform2D = player.get_viewport().get_canvas_transform()
	var material := _mask.material as ShaderMaterial
	material.set_shader_parameter("centre", to_screen * player.global_position)
	material.set_shader_parameter("radius", player.sight_radius() * to_screen.get_scale().x)
	material.set_shader_parameter("screen_size", player.get_viewport().get_visible_rect().size)


## Whether the mask shows now, and where: {"on", "centre", "radius"} in
## screen px.
func mask_state() -> Dictionary:
	var material := _mask.material as ShaderMaterial
	return {"on": _mask.visible, "centre": material.get_shader_parameter("centre"),
			"radius": material.get_shader_parameter("radius")}
