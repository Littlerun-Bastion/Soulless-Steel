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
##   - any of it is inside the cone of a living mecha whose illuminator is on
##     (half its cone angle either side, out to its reach: in_cone with the
##     body's radius, body_radius, as its margin), in the same building as
##     that mecha (or both outside) and with no building wall between them:
##     walls shadow the light. Smoke casts no shadow.
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
## The illuminator's texture is drawn here (light_texture) and set by
## shape_light. The light points where its mecha's head points
## (Mecha._aim_light), so its cone turns with the head.

## What each MechaLight lights, drawn in code (light_texture): a cone ahead of
## the mecha and a circle round it. The cone is its head's illuminator_angle
## wide (DEFAULT_CONE_ANGLE with no head), within MIN_CONE_ANGLE and
## MAX_CONE_ANGLE, and reaches as far as the head sees (reach_of); the circle
## is LOCAL_RADIUS px. Each edge fades out over its *_SOFT width either side
## of it (px, or degrees for the cone's sides, at most a quarter of a narrow
## cone's angle; the reach's at most half the reach, range_soft), so the line
## where something is in or out of the cone (in_cone) runs down the middle of
## the fade. The circle and the fades are the same size in px at any reach.
## Placeholders.
const DEFAULT_CONE_ANGLE := 30.0
const MIN_CONE_ANGLE := 2.0
const MAX_CONE_ANGLE := 360.0
const CONE_RANGE_SOFT := 450.0
const CONE_EDGE_SOFT := 4.0
const LOCAL_RADIUS := 320.0
const LOCAL_SOFT := 80.0
## The drawn texture's side (texels). It covers the reach and its fade either
## way of the mecha (texture_extent): at a 150 m reach a texel is about
## 13 px, and the fades are many texels wide, so the edges stay smooth.
const LIGHT_TEXTURE_SIZE := 512
## Cone angles are rounded to this many degrees, and reaches to REACH_STEP
## m, so heads with nearly the same light share one texture.
const CONE_ANGLE_STEP := 0.5
const REACH_STEP := 5.0
## Where shape_light keeps a light's cone angle (degrees) and its reach (px)
## on the light.
const CONE_ANGLE_META := &"illuminator_cone_angle"
const CONE_RANGE_META := &"illuminator_cone_range"
const LIGHT_NODE := "MechaLight"
const DARKNESS_NODE := "MechaShadowGen"
## How much light every illuminator adds, and how much the darkness round the
## player takes away (at its centre). A cone shows the ground a little
## brighter than it is with no darkness, about half as bright as the old
## mixed NPC cones. Placeholders.
const LIGHT_ENERGY := 1.2
const DARKNESS_ENERGY := 0.6
## A mecha with its illuminator on gives itself away (in_light_range): the
## player sees an illuminator's cone anywhere inside its sight circle even
## when it can't see the mecha, so a mecha (NPC or player) notices such a
## mecha anywhere inside its own sight circle (Mecha.sight_radius). An
## Entity has no head and no circle: it notices one within a screen of it.
## The game shows 1920 x 1080 px at its 0.5 camera zoom, so a screen is
## SCREEN_HALF either way. Not into or out of another building (roofs hide
## the inside).
const SCREEN_HALF := Vector2(1920.0, 1080.0)
## The player's illuminator key (Player.press_illuminator_key), and the key it
## gets if project.godot doesn't define the action.
const KEY_ACTION := "toggle_illuminator"
const DEFAULT_KEY := KEY_C


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


## How far (px) a mecha's illuminator reaches: as far as its head sees, the
## head's visual_range (rounded to REACH_STEP m). Sensor damage hurts the
## optics, not the lamp, so it doesn't shorten the reach. With no head fitted,
## or the head shot off, Mecha.NO_HEAD_SIGHT.
static func reach_of(mecha: Node) -> float:
	var build = mecha.get("build") if mecha != null else null
	var head = build.get("head") if build is Dictionary else null
	if head == null or (mecha.has_method("is_part_lost") and mecha.is_part_lost("head")):
		return Mecha.NO_HEAD_SIGHT
	var metres = head.get("visual_range")
	if not (metres is float or metres is int):
		return Mecha.NO_HEAD_SIGHT
	return maxf(snappedf(float(metres), REACH_STEP), REACH_STEP) * MapSenses.PX_PER_METRE


## Gives a mecha's illuminator the drawn cone for `angle` degrees and `reach`
## px (its head's for either one that is negative), and keeps both on the
## light for in_cone. Mecha.set_head calls it whenever the head changes, and
## Mecha.lose_part when the head comes off.
static func shape_light(mecha: Node, angle := -1.0, cone_reach := -1.0) -> void:
	var light := light_of(mecha)
	if light == null:
		return
	var rounded := _rounded_angle(cone_angle_of(mecha) if angle < 0.0 else angle)
	var distance := reach_of(mecha) if cone_reach < 0.0 else cone_reach
	light.texture = light_texture(rounded, distance)
	light.texture_scale = texture_extent(distance) * 2.0 / LIGHT_TEXTURE_SIZE
	light.set_meta(CONE_ANGLE_META, rounded)
	light.set_meta(CONE_RANGE_META, distance)


## A light's cone angle (degrees), as shape_light set it.
static func cone_angle(light: PointLight2D) -> float:
	if light == null:
		return 0.0
	var angle = light.get_meta(CONE_ANGLE_META, DEFAULT_CONE_ANGLE)
	return float(angle) if (angle is float or angle is int) else DEFAULT_CONE_ANGLE


## How far (px) a light's cone reaches, as shape_light set it.
static func reach(light: PointLight2D) -> float:
	if light == null:
		return 0.0
	var distance = light.get_meta(CONE_RANGE_META, Mecha.NO_HEAD_SIGHT)
	return float(distance) if (distance is float or distance is int) else Mecha.NO_HEAD_SIGHT


## Whether a circle `margin` px round `point` reaches into a light's cone
## (angle and reach only, no walls); with no margin, whether the point is in
## it. The circle reaches past the cone's side by as much as it is wide seen
## from the light: asin(margin / distance) either side of the half angle.
static func in_cone(light: PointLight2D, point: Vector2, margin := 0.0) -> bool:
	if light == null:
		return false
	var offset: Vector2 = point - light.global_position
	var distance := offset.length()
	if distance - margin > reach(light):
		return false
	if distance <= margin:
		return true
	var forward := Vector2.UP.rotated(light.global_rotation)
	var widen := asin(margin / distance) if margin > 0.0 else 0.0
	return absf(forward.angle_to(offset)) <= deg_to_rad(cone_angle(light) * 0.5) + widen


## How far (px) a body reaches round its centre, for what lights it
## (in_cone's margin): a mecha's farthest outline point (Mecha.rcs_outlines,
## the parts it still has), an Entity's radius, nothing for anything else.
static func body_radius(body: Node2D) -> float:
	if body == null or not is_instance_valid(body):
		return 0.0
	if body.has_method("rcs_outlines"):
		var farthest := 0.0
		for entry in body.rcs_outlines():
			if body.is_part_lost(entry.lost) or not is_instance_valid(entry.node):
				continue
			var xform: Transform2D = entry.node.global_transform
			for point in entry.points:
				farthest = maxf(farthest, (xform * point).distance_to(body.global_position))
		return farthest
	var radius = body.get("radius")
	return float(radius) if (radius is float or radius is int) else 0.0


static var _textures := {}


## The light texture for a cone `angle` degrees wide reaching `cone_reach`
## px (see the constants above), drawn once per rounded angle and reach and
## shared by every light with them. White, with the light in its alpha: a
## cone pointing up (the light's forward, -y), fading out at its sides and at
## its reach, and a circle of LOCAL_RADIUS round the centre. It is
## mirror-symmetric, so each row works out its right half and copies it to
## the left.
static func light_texture(angle: float, cone_reach: float) -> ImageTexture:
	var rounded := _rounded_angle(angle)
	var key := Vector2(rounded, cone_reach)
	if _textures.has(key):
		return _textures[key]
	var size := LIGHT_TEXTURE_SIZE
	var half_size := size >> 1
	var texel := texture_extent(cone_reach) * 2.0 / size
	var soft := range_soft(cone_reach)
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
			var cone := 1.0 - smoothstep(cone_reach - soft, cone_reach + soft, r)
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
	_textures[key] = texture
	return texture


static func _rounded_angle(angle: float) -> float:
	return snappedf(clampf(angle, MIN_CONE_ANGLE, MAX_CONE_ANGLE), CONE_ANGLE_STEP)


## How wide (px) the fade at a cone's reach is either side of it:
## CONE_RANGE_SOFT, or half a short reach, so the cone is still at full light
## near the mecha.
static func range_soft(cone_reach: float) -> float:
	return minf(CONE_RANGE_SOFT, cone_reach * 0.5)


## How far (px) a drawn texture reaches from its centre: where the cone's
## fade ends, or the circle's if a short cone's ends first.
static func texture_extent(cone_reach: float) -> float:
	return maxf(cone_reach + range_soft(cone_reach), LOCAL_RADIUS + LOCAL_SOFT)


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
## shining, inside the observer's sight circle (a mecha) or within a screen of
## it (an Entity: SCREEN_HALF), in the same building or both outside.
static func in_light_range(observer: Node2D, mecha: Node2D) -> bool:
	if not is_shining(mecha) or mecha == observer:
		return false
	var offset := mecha.global_position - observer.global_position
	if observer.has_method("sight_radius"):
		var sight: float = observer.sight_radius()
		if offset.length_squared() > sight * sight:
			return false
	elif absf(offset.x) > SCREEN_HALF.x or absf(offset.y) > SCREEN_HALF.y:
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
	var margin := -1.0
	for mecha in _shining_mechas(body):
		if mecha == body or not is_instance_valid(mecha):
			continue
		if margin < 0.0:
			margin = body_radius(body)
		if not in_cone(light_of(mecha), to, margin):
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
