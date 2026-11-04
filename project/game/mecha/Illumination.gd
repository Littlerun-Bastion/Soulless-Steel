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
##     (CONE_HALF_ANGLE either side, out to the light's reach), in the same
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
## in; mixing (BLEND_MODE_MIX, as both were) paints each light over the ones
## before it, so the order decided whether a cone showed at all.

## The cone each MechaLight lights: its aimed_glow texture is lit to about 15
## degrees either side and to 0.44 of its width from the centre.
const CONE_HALF_ANGLE := 15.0
const CONE_REACH := 0.44
const LIGHT_NODE := "MechaLight"
const DARKNESS_NODE := "MechaShadowGen"
## How much light every illuminator adds, and how much the darkness round the
## player takes away (at its centre). A cone shows the ground a little
## brighter than it is with no darkness, about half as bright as the old
## mixed NPC cones. Placeholders.
const LIGHT_ENERGY := 1.2
const DARKNESS_ENERGY := 0.6
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
## energies (see above). Their textures, reach and shadows stay as the scene
## has them.
static func style_lights(mecha: Node) -> void:
	var light := light_of(mecha)
	if light:
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.color = Color.WHITE
		light.energy = LIGHT_ENERGY
	var darkness := mecha.get_node_or_null(DARKNESS_NODE) as PointLight2D
	if darkness:
		darkness.blend_mode = Light2D.BLEND_MODE_SUB
		darkness.color = Color.WHITE
		darkness.energy = DARKNESS_ENERGY


static func light_of(mecha: Node) -> PointLight2D:
	if mecha == null or not is_instance_valid(mecha):
		return null
	return mecha.get_node_or_null(LIGHT_NODE) as PointLight2D


## How far (px) a light's cone reaches.
static func reach(light: PointLight2D) -> float:
	if light == null or light.texture == null:
		return 0.0
	return light.texture.get_width() * light.texture_scale * CONE_REACH


## Whether `point` is inside a light's cone (angle and reach only, no walls).
static func in_cone(light: PointLight2D, point: Vector2) -> bool:
	if light == null:
		return false
	var offset: Vector2 = point - light.global_position
	if offset.length() > reach(light):
		return false
	var forward := Vector2.UP.rotated(light.global_rotation)
	return absf(rad_to_deg(forward.angle_to(offset))) <= CONE_HALF_ANGLE


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
