class_name HudVisionOutlines
extends Control

## Mechas and devices the player's Seeker covers but the player can't see
## (Player.get_outlined_bodies): the body stays hidden, and the HUD draws the
## inside edge of each of its sprites in G5 (VisionOutline.gdshader), through
## walls and darkness. The line is OUTLINE_WIDTH px on screen whatever the
## zoom or the sprite's scale. Glow and muzzle-flash sprites are left out
## (SKIP_SPRITES), as are sprites with no texture, hidden, or faded out.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const SHADER := preload("res://game/ui/hud/VisionOutline.gdshader")
const OUTLINE_WIDTH := 2.0
## The widest line (texels) the shader takes; a sprite drawn this small
## gets a thinner line than OUTLINE_WIDTH.
const MAX_WIDTH := 32.0
const SKIP_SPRITES := ["Glow", "SprintGlow", "Projectile"]

var player = null
var _drawn := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := ShaderMaterial.new()
	outline.shader = SHADER
	outline.set_shader_parameter("line_color", THEME.get_color(&"g5", &"MechTokens"))
	outline.set_shader_parameter("max_width", MAX_WIDTH)
	material = outline


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	queue_redraw()


## How many sprites were outlined in the last draw.
func get_drawn() -> int:
	return _drawn


## The sprites of `body` that get an outline.
static func outline_sprites(body: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for node in body.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite.texture == null or not sprite.is_visible_in_tree() or SKIP_SPRITES.has(String(sprite.name)):
			continue
		if sprite.modulate.a < 0.05 or sprite.self_modulate.a < 0.05:
			continue
		found.append(sprite)
	return found


func _process(_delta: float) -> void:
	var outlined := 0
	if is_instance_valid(player):
		outlined = player.get_outlined_bodies().size()
	if outlined > 0 or _drawn > 0:
		queue_redraw()


func _draw() -> void:
	_drawn = 0
	if not is_instance_valid(player):
		return
	var to_screen: Transform2D = player.get_viewport().get_canvas_transform()
	for body in player.get_outlined_bodies():
		for sprite in outline_sprites(body):
			_draw_sprite(sprite, to_screen)
			_drawn += 1
	draw_set_transform_matrix(Transform2D.IDENTITY)


# Draws `sprite` where it is on screen, the way Sprite2D draws itself
# (region, frames, offset, centring, flips), with the line width for its
# scale in the modulate.
func _draw_sprite(sprite: Sprite2D, to_screen: Transform2D) -> void:
	var xform: Transform2D = to_screen * sprite.global_transform
	var rect := sprite.get_rect()
	var source := Rect2(Vector2.ZERO, sprite.texture.get_size())
	if sprite.region_enabled:
		source = sprite.region_rect
	var frame_size := source.size / Vector2(sprite.hframes, sprite.vframes)
	source = Rect2(source.position + Vector2(sprite.frame_coords) * frame_size, frame_size)
	if sprite.flip_h:
		rect = Rect2(rect.position.x + rect.size.x, rect.position.y, -rect.size.x, rect.size.y)
	if sprite.flip_v:
		rect = Rect2(rect.position.x, rect.position.y + rect.size.y, rect.size.x, -rect.size.y)
	var texels := OUTLINE_WIDTH / maxf(absf(xform.get_scale().x), 0.001)
	draw_set_transform_matrix(xform)
	draw_texture_rect_region(sprite.texture, rect, source, Color(clampf(texels / MAX_WIDTH, 0.0, 1.0), 1.0, 1.0, 1.0))
