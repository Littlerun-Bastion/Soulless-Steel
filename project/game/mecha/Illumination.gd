class_name Illumination
extends RefCounted

## Who is lit by an IR illuminator (a mecha's MechaLight cone, see MapSenses).
## A lit body can be seen from anywhere its light shows, walls between or
## not, so the player's view (Player.can_see_body) and NPC senses
## (Enemy.update_senses) both use seen_lit. Switching an illuminator off
## (Mecha.set_illuminator) leaves its mecha dark: seen only the usual way.
##
## A body is lit when:
##   - it is a living mecha with its own illuminator on (it stands in its own
##     light), or
##   - it is inside the cone of a living mecha whose illuminator is on
##     (half its cone angle either side, out to CONE_RANGE), in the same
##     building as that mecha (or both outside) and with no building wall
##     between them: walls shadow the light. Smoke casts no shadow.
## An observer sees a lit body (seen_lit) if they are in the same building (or
## both outside: roofs hide the inside of a building) and the body isn't in or
## behind thick smoke. Range is the observer's to check.
##
## is_lit is worked out once per physics frame per body, as every observer
## asks about the same bodies.
##
## How they are drawn (style_lights, from Mecha._ready): the player's darkness
## (MechaShadowGen) takes light away (Light2D.BLEND_MODE_SUB) and every
## illuminator adds it back (BLEND_MODE_ADD), all at the same energy. Adding
## and taking away give the same picture whatever order Godot draws the lights
## in; mixing (BLEND_MODE_MIX) paints each light over the ones before it, so
## the order would decide whether a cone showed at all.
##
## Only the player's darkness is on (Player.setup switches it on). Every
## mecha has the node and Mecha.tscn has it on; left on, each NPC's would take
## its own darkness away round it too, once per mecha nearby, until the
## ground and the cones went black.
##
## The illuminator's texture is drawn here (light_texture), not taken from
## the scene: shape_light replaces whatever texture Mecha.tscn gives it.

## What each MechaLight lights, drawn in code (light_texture): a cone ahead of
## the mecha and a circle round it. The cone is its head's illuminator_angle
## wide (DEFAULT_CONE_ANGLE with no head), within MIN_CONE_ANGLE and
## MAX_CONE_ANGLE, and reaches CONE_RANGE px; the circle is LOCAL_RADIUS px.
## Each edge fades out over its *_SOFT width either side of it (px, or
## degrees for the cone's sides, at most a quarter of a narrow cone's angle),
## so the line where something is in or out of the cone (in_cone) runs down
## the middle of the fade. Placeholders.
const DEFAULT_CONE_ANGLE := 30.0
const MIN_CONE_ANGLE := 2.0
const MAX_CONE_ANGLE := 360.0
const CONE_RANGE := 4500.0
const CONE_RANGE_SOFT := 450.0
const CONE_EDGE_SOFT := 4.0
const LOCAL_RADIUS := 320.0
const LOCAL_SOFT := 80.0
## The drawn texture's side (texels). It covers CONE_RANGE + CONE_RANGE_SOFT
## either way of the mecha, so a texel is about 19 px; the fades are many
## texels wide, so the edges stay smooth.
const LIGHT_TEXTURE_SIZE := 512
## Cone angles are rounded to this many degrees, so heads with nearly the
## same angle share one texture.
const CONE_ANGLE_STEP := 0.5
## Where shape_light keeps a light's cone angle (degrees) on the light.
const CONE_ANGLE_META := &"illuminator_cone_angle"
const LIGHT_NODE := "MechaLight"
const DARKNESS_NODE := "MechaShadowGen"
## How much light every illuminator adds, and how much the darkness round the
## player takes away (at its centre). A cone shows the ground a little
## brighter than it is with no darkness, about half as bright as the old
## mixed NPC cones. Placeholders.
const LIGHT_ENERGY := 1.2
const DARKNESS_ENERGY := 0.6
## A mecha with its illuminator on gives itself away to anyone within a
## screen of it (in_light_range): the player sees an illuminator's cone on
## screen even when it can't see the mecha, so every NPC and Entity knows
## where such a mecha is within the same reach. The game shows 1920 x 1080 px
## at its 0.5 camera zoom, so a screen is SCREEN_HALF either way of the
## observer. Not into or out of another building (roofs hide the inside).
const SCREEN_HALF := Vector2(1920.0, 1080.0)
## The player's illuminator key (Player.toggle_illuminator), and the key it
## gets if project.godot doesn't define the action.
const KEY_ACTION := "toggle_illuminator"
const DEFAULT_KEY := KEY_L


## Adds the illuminator key action, bound to DEFAULT_KEY, if the project's
## Input Map lacks it. One set in Project Settings is left as it is.
static func ensure_key_action() -> void:
	if InputMap.has_action(KEY_ACTION):
		return
	InputMap.add_action(KEY_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = DEFAULT_KEY
	InputMap.action_add_event(KEY_ACTION, key)

static var _lit_cache := {}
static var _lit_cache_frame := -1


## Gives a mecha's illuminator and darkness lights their blend modes and
## energies (see above), shapes its illuminator for its head (shape_light),
## and switches its darkness off: the player switches its own back on. The
## darkness keeps its texture, and both keep their shadows, as the scene has
## them.
static func style_lights(mecha: Node) -> void:
	var light := light_of(mecha)
	if light:
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.color = Color.WHITE
		light.energy = LIGHT_ENERGY
		shape_light(mecha)
	var darkness := mecha.get_node_or_null(DARKNESS_NODE) as PointLight2D
	if darkness:
		darkness.blend_mode = Light2D.BLEND_MODE_SUB
		darkness.color = Color.WHITE
		darkness.energy = DARKNESS_ENERGY
		darkness.enabled = false


static func light_of(mecha: Node) -> PointLight2D:
	if mecha == null or not is_instance_valid(mecha):
		return null
	return mecha.get_node_or_null(LIGHT_NODE) as PointLight2D


## The cone angle (degrees) a mecha's head gives its illuminator.
static func cone_angle_of(mecha: Node) -> float:
	var build = mecha.get("build") if mecha != null else null
	var head = build.get("head") if build is Dictionary else null
	if head != null:
		var angle = head.get("illuminator_angle")
		if angle is float or angle is int:
			return float(angle)
	return DEFAULT_CONE_ANGLE


## Gives a mecha's illuminator the drawn cone for `angle` degrees (its head's
## when `angle` is negative), scaled to CONE_RANGE, and keeps the angle on
## the light for in_cone. Mecha.set_head calls it whenever the head changes.
static func shape_light(mecha: Node, angle := -1.0) -> void:
	var light := light_of(mecha)
	if light == null:
		return
	var rounded := _rounded_angle(cone_angle_of(mecha) if angle < 0.0 else angle)
	light.texture = light_texture(rounded)
	light.texture_scale = _texture_extent() * 2.0 / LIGHT_TEXTURE_SIZE
	light.set_meta(CONE_ANGLE_META, rounded)


## A light's cone angle (degrees), as shape_light set it.
static func cone_angle(light: PointLight2D) -> float:
	if light == null:
		return 0.0
	var angle = light.get_meta(CONE_ANGLE_META, DEFAULT_CONE_ANGLE)
	return float(angle) if (angle is float or angle is int) else DEFAULT_CONE_ANGLE


## How far (px) a light's cone reaches.
static func reach(light: PointLight2D) -> float:
	return 0.0 if light == null else CONE_RANGE


## Whether `point` is inside a light's cone (angle and reach only, no walls).
static func in_cone(light: PointLight2D, point: Vector2) -> bool:
	if light == null:
		return false
	var offset: Vector2 = point - light.global_position
	if offset.length() > reach(light):
		return false
	var forward := Vector2.UP.rotated(light.global_rotation)
	return absf(rad_to_deg(forward.angle_to(offset))) <= cone_angle(light) * 0.5


static var _textures := {}


## The light texture for a cone `angle` degrees wide (see the constants
## above), drawn once per rounded angle and shared by every light with it.
## White, with the light in its alpha: a cone pointing up (the light's
## forward, -y), fading out at its sides and at CONE_RANGE, and a circle of
## LOCAL_RADIUS round the centre. It is mirror-symmetric, so each row works
## out its right half and copies it to the left.
static func light_texture(angle: float) -> ImageTexture:
	var rounded := _rounded_angle(angle)
	if _textures.has(rounded):
		return _textures[rounded]
	var size := LIGHT_TEXTURE_SIZE
	var half_size := size >> 1
	var texel := _texture_extent() * 2.0 / size
	var half_angle := deg_to_rad(rounded * 0.5)
	var edge := minf(deg_to_rad(CONE_EDGE_SOFT), half_angle * 0.5)
	var all_round := rounded >= 360.0
	var data := PackedByteArray()
	data.resize(size * size * 2)
	for y in size:
		var wy := (y + 0.5 - half_size) * texel
		var row := y * size
		for x in half_size:
			var wx := (x + 0.5) * texel
			var r := sqrt(wx * wx + wy * wy)
			var local := 1.0 - smoothstep(LOCAL_RADIUS - LOCAL_SOFT, LOCAL_RADIUS + LOCAL_SOFT, r)
			var cone := 1.0 - smoothstep(CONE_RANGE - CONE_RANGE_SOFT, CONE_RANGE + CONE_RANGE_SOFT, r)
			if not all_round:
				cone *= 1.0 - smoothstep(half_angle - edge, half_angle + edge, atan2(wx, -wy))
			var alpha := int(roundf(maxf(local, cone) * 255.0))
			var right := (row + half_size + x) * 2
			var left := (row + half_size - 1 - x) * 2
			data[right] = 255
			data[right + 1] = alpha
			data[left] = 255
			data[left + 1] = alpha
	var texture := ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_LA8, data))
	_textures[rounded] = texture
	return texture


static func _rounded_angle(angle: float) -> float:
	return snappedf(clampf(angle, MIN_CONE_ANGLE, MAX_CONE_ANGLE), CONE_ANGLE_STEP)


# How far (px) the drawn texture reaches from its centre: the cone's fade
# ends there.
static func _texture_extent() -> float:
	return CONE_RANGE + CONE_RANGE_SOFT


## Whether a mecha's illuminator is lighting right now.
static func is_shining(mecha: Node) -> bool:
	if mecha == null or not is_instance_valid(mecha) or not mecha.is_in_group("mecha"):
		return false
	if mecha.get("is_dead") == true or mecha.get("illuminator_on") != true:
		return false
	var light := light_of(mecha)
	return light != null and light.enabled


static func is_lit(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var frame := Engine.get_physics_frames()
	if frame != _lit_cache_frame:
		_lit_cache.clear()
		_lit_cache_frame = frame
	var id := body.get_instance_id()
	if _lit_cache.has(id):
		return _lit_cache[id]
	var lit := _lit_lookup(body)
	_lit_cache[id] = lit
	return lit


## Whether `mecha` gives itself away to `observer` by its own illuminator:
## shining, within a screen of the observer (SCREEN_HALF), in the same
## building or both outside.
static func in_light_range(observer: Node2D, mecha: Node2D) -> bool:
	if not is_shining(mecha) or mecha == observer:
		return false
	var offset := mecha.global_position - observer.global_position
	if absf(offset.x) > SCREEN_HALF.x or absf(offset.y) > SCREEN_HALF.y:
		return false
	return MapSenses.building_key_of(observer) == MapSenses.building_key_of(mecha)


## Whether `observer` sees `body` by the light on it (see the rules above).
static func seen_lit(observer: Node2D, body: Node2D) -> bool:
	if not is_lit(body):
		return false
	if MapSenses.smoke_between(observer.global_position, body.global_position) or MapSenses.in_smoke(body.global_position):
		return false
	return MapSenses.building_key_of(observer) == MapSenses.building_key_of(body)


# The mechas with their illuminator on, once per physics frame: every lit
# check walks them.
static var _shining_cache: Array = []
static var _shining_cache_frame := -1


static func _shining_mechas(node: Node) -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _shining_cache_frame:
		_shining_cache_frame = frame
		_shining_cache = node.get_tree().get_nodes_in_group("mecha").filter(func(m): return is_shining(m))
	return _shining_cache


static func _lit_lookup(body: Node2D) -> bool:
	if is_shining(body):
		return true
	var to := body.global_position
	var body_key := ""
	var key_known := false
	for mecha in _shining_mechas(body):
		if mecha == body or not is_instance_valid(mecha):
			continue
		if not in_cone(light_of(mecha), to):
			continue
		var from: Vector2 = mecha.global_position
		if not key_known:
			body_key = MapSenses.building_key_of(body)
			key_known = true
		if MapSenses.building_key_of(mecha) != body_key:
			continue
		if not MapSenses.walls_between(body.get_world_2d(), from, to):
			return true
	return false
