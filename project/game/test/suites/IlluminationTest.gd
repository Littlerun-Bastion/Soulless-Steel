extends TestSuite

# IlluminationTest: IR illuminators (Mecha.set_illuminator, Illumination).
# A mecha with its illuminator on, and whatever its cone falls on, is lit;
# walls shadow the light and a building's inside is apart from the outside.
# The player sees a lit body through walls, and with its own illuminator off
# loses its cone; the illuminator key and the HUD row. An NPC sees a lit
# target through walls, and with its own illuminator off sees unlit ones
# only close by; its behaviour runs dark in its dark states. Every
# illuminator, the player's darkness, flares and car alarm lamps add or take
# light away rather than mix it (so the draw order can't hide a cone), the
# player's and an NPC's alike, and a mecha's fire glow is off unless it burns.
# The illuminator's cone and circle are drawn in code, as wide as the head's
# illuminator_angle, and that angle is what is lit and what the player and
# an NPC see a dark mecha in.
#
# The player is held still (no physics) and its view is stepped by hand; NPCs
# are paused and their senses stepped by hand. Illumination works out each
# body once per physics frame, so every change waits a frame.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")

# A generated building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2(-5000, -5000)
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-3000, 3000), randf_range(-3000, 3000))


var _arena: FakeArena = null
var _player = null


func run_tests() -> void:
	await case("a mecha's own light and its cone light things; walls shadow it", _test_lit)
	await case("the player sees what is lit through walls", _test_view_lit)
	await case("with its illuminator off the player loses its cone", _test_player_dark)
	await case("the illuminator key and the HUD row", _test_key_and_hud)
	await case("an NPC sees lit targets through walls, and less with its own off", _test_npc_senses)
	await case("an NPC's behaviour runs dark by intent, and holds the setting", _test_npc_states)
	await case("every light adds or takes away, the same for everyone", _test_light_style)
	await case("the cone is drawn in code, as wide as the head's illuminator angle", _test_drawn_cone)
	await case("an NPC sees unlit mechas only in its cone or close by", _test_npc_cone)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	_player = _mecha(Vector2(-600, 200), Vector2.UP, true, PLAYER)
	_player.mecha_name = "Player"
	_player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame


# A mecha held still (no physics) at `pos`, facing `facing`, lit or dark.
func _mecha(pos: Vector2, facing: Vector2, lit: bool, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_physics_process(false)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.global_rotation = Vector2.UP.angle_to(facing)
	mecha.set_illuminator(lit)
	_arena.mechas.append(mecha)
	return mecha


func _enemy(pos: Vector2) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Illumination test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(false)
	enemy.paused = true
	_arena.mechas.append(enemy)
	return enemy


# Puts the player at `pos` facing `facing`, then runs its view long enough
# for a full fade.
func _look(pos: Vector2, facing: Vector2) -> void:
	_player.global_position = pos
	_player.global_rotation = Vector2.UP.angle_to(facing)
	await get_tree().physics_frame
	for i in 12:
		_player._update_view(0.1)


func _shown(body) -> bool:
	return not _player.is_hidden_from_view(body) and body.modulate.a > 0.95


func _hidden(body) -> bool:
	return _player.is_hidden_from_view(body) and body.modulate.a < 0.05


func _action(action: String, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _test_lit() -> void:
	var o := Vector2(-4000, 4000)
	var lamp := _mecha(o, Vector2.UP, true)
	var light := Illumination.light_of(lamp)
	var reach := Illumination.reach(light)
	check(light != null and reach > 2000.0, "its MechaLight reaches well past the screen (%.0f px)" % reach)
	var ahead := _mecha(o + Vector2(0, -1200), Vector2.UP, false)
	var aside := _mecha(o + Vector2.UP.rotated(deg_to_rad(40.0)) * 1200.0, Vector2.UP, false)
	var past := _mecha(o + Vector2(0, -(reach + 300.0)), Vector2.UP, false)
	await get_tree().physics_frame
	check(not Illumination.is_lit(aside), "a dark one off to the side isn't")
	check(Illumination.is_lit(ahead), "a dark one in another's cone is")
	check(not Illumination.is_lit(past), "but not past the light's reach")

	var toggles := []
	lamp.illuminator_toggled.connect(func(on: bool): toggles.append(on))
	lamp.set_illuminator(false)
	lamp.set_illuminator(false)
	check(not lamp.illuminator_on and not light.enabled, "switching it off turns the light off")
	check_eq(toggles, [false], "and says so once")
	await get_tree().physics_frame
	check(not Illumination.is_lit(lamp) and not Illumination.is_lit(ahead), "then neither is lit")
	lamp.set_illuminator(true)
	check(light.enabled and toggles == [false, true], "on again")

	var by_wall := _mecha(Vector2(-600, 200), Vector2.RIGHT, true)
	var behind := _mecha(Vector2(800, 200), Vector2.UP, false)
	var inside := _mecha(Vector2(300, 300), Vector2.UP, false)
	by_wall.global_rotation = Vector2.UP.angle_to(Vector2(900, 100).normalized())
	await get_tree().physics_frame
	check(Illumination.in_cone(Illumination.light_of(by_wall), inside.global_position), "(the building is in its cone)")
	check(not Illumination.is_lit(behind), "the building's walls shadow what is behind it")
	check(not Illumination.is_lit(inside), "and what is in it")
	lamp.is_dead = true
	await get_tree().physics_frame
	check(not Illumination.is_shining(lamp) and not Illumination.is_lit(ahead), "a dead mecha lights nothing")
	lamp.is_dead = false


func _test_view_lit() -> void:
	var lit := _mecha(Vector2(800, 200), Vector2.UP, true)
	var dark := _mecha(Vector2(800, 330), Vector2.UP, false)
	var inside := _mecha(Vector2(300, 300), Vector2.UP, true)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_shown(lit), "a lit mecha behind the building is seen")
	check(_hidden(dark), "a dark one beside it isn't")
	check(_hidden(inside), "nor a lit one inside the building (the roof hides it)")
	check(not _player.contacts.best_for(lit).is_empty(), "the lit one is a sight contact")
	lit.set_illuminator(false)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(lit), "switching its illuminator off hides it")
	var lamp := _mecha(Vector2(1500, 330), Vector2.LEFT, true)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_shown(lamp), "a third mecha lit beyond the building is seen")
	check(_shown(dark), "and so is the dark one its cone falls on")


func _test_player_dark() -> void:
	var o := Vector2(-4000, 4000)
	var ahead := _mecha(o + Vector2(0, -1500), Vector2.UP, false)
	var close := _mecha(o + Vector2(0, _player.VIEW_PERIPHERAL - 50.0), Vector2.UP, false)
	await _look(o, Vector2.UP)
	check(_shown(ahead), "with its illuminator on the player sees a dark mecha in its cone")
	_player.toggle_illuminator()
	check(not _player.illuminator_on and not _player.Light.enabled, "toggling switches it off")
	await _look(o, Vector2.UP)
	check(_hidden(ahead), "then the dark mecha ahead is hidden")
	check(_shown(close), "but one within 20 m is still seen")
	check(not Illumination.is_lit(_player), "and the player itself is dark")
	var lamp := _mecha(o + Vector2(-1500, -1500), Vector2(1, 0), true)
	await _look(o, Vector2.UP)
	check(_shown(lamp), "it still sees a lit mecha")


func _test_key_and_hud() -> void:
	MouseManager.set_aim_available(true)
	var weapons := HudWeapons.new()
	add_child(weapons)
	weapons.setup(_player)
	var row := weapons.get_row_text("illuminator")
	check(row.contains("IR") and row.contains("ILLUMINATOR") and row.ends_with("ON / LIT"), "the IR row reads ON (%s)" % row)
	check(row.begins_with(MechUI.key_name("toggle_illuminator")), "under its key")
	_player._input(_action("toggle_illuminator"))
	check(not _player.illuminator_on, "the illuminator key switches it off")
	weapons._update()
	check(weapons.get_row_text("illuminator").ends_with("OFF / DARK"), "the row reads OFF (%s)" % weapons.get_row_text("illuminator"))
	_player._input(_action("toggle_illuminator"))
	check(_player.illuminator_on, "and on again")
	check(InputMap.has_action("toggle_illuminator"), "the key is an input action")
	weapons.queue_free()

	# A project.godot without the action: the game adds it, on L.
	var events := InputMap.action_get_events(Illumination.KEY_ACTION)
	InputMap.erase_action(Illumination.KEY_ACTION)
	Illumination.ensure_key_action()
	var added := InputMap.action_get_events(Illumination.KEY_ACTION)
	check(added.size() == 1 and added[0] is InputEventKey and (added[0] as InputEventKey).physical_keycode == KEY_L,
			"with the action missing from the project, it is added on L")
	var pressed := InputEventKey.new()
	pressed.physical_keycode = KEY_L
	pressed.pressed = true
	_player._input(pressed)
	check(not _player.illuminator_on, "and the key works")
	_player.set_illuminator(true)
	InputMap.erase_action(Illumination.KEY_ACTION)
	InputMap.add_action(Illumination.KEY_ACTION)
	for event in events:
		InputMap.action_add_event(Illumination.KEY_ACTION, event)
	Illumination.ensure_key_action()
	check_eq(InputMap.action_get_events(Illumination.KEY_ACTION).size(), events.size(), "an action the project has is left alone")


func _test_npc_senses() -> void:
	var enemy := _enemy(Vector2(-3000, -3000))
	enemy.auto_illuminator = false
	enemy.global_rotation = 0.0
	var foe := _mecha(Vector2(800, 200), Vector2.UP, true)
	enemy.mark_traitor(foe)
	enemy.global_position = Vector2(-250, 200)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "it sees a lit mecha behind a building")
	foe.set_illuminator(false)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(not enemy.is_seeing(foe), "not once it goes dark")

	var sight: float = enemy.engage_distance * lerpf(0.6, 1.4, foe.get_thermal_signature())
	var o := Vector2(-4000, -4000)
	enemy.global_position = o
	foe.global_position = o + Vector2(0, -sight * 0.75)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "with its own illuminator on it sees a dark mecha in the open ahead (%.0f px)" % (sight * 0.75))
	enemy.set_illuminator(false)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(not enemy.is_seeing(foe), "with it off, not that far")
	foe.global_position = o + Vector2(0, -sight * enemy.DARK_SIGHT_MULT * 0.8)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "only close by")
	foe.global_position = o + Vector2(0, sight * 0.75)
	foe.set_illuminator(true)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "but a lit one at the full range, behind it too")


# The texture's alpha `offset` px from a light's centre, in the light's own
# frame (forward is -y).
func _alpha_at(light: PointLight2D, offset: Vector2) -> float:
	var image: Image = light.texture.get_image()
	var texel: float = light.texture_scale
	var half := image.get_width() * 0.5
	var px := Vector2(half, half) + offset / texel
	return image.get_pixel(clampi(int(px.x), 0, image.get_width() - 1), clampi(int(px.y), 0, image.get_height() - 1)).a


func _test_drawn_cone() -> void:
	var plain := _mecha(Vector2(3000, 3000), Vector2.UP, true)
	var light := Illumination.light_of(plain)
	var head_angle: float = plain.build.head.illuminator_angle
	check(light.texture is ImageTexture and light.texture.get_width() == Illumination.LIGHT_TEXTURE_SIZE,
			"the illuminator's texture is drawn in code")
	check_eq(Illumination.cone_angle(light), head_angle, "at its head's angle")
	check(is_equal_approx(light.texture_scale * Illumination.LIGHT_TEXTURE_SIZE * 0.5, Illumination.CONE_RANGE + Illumination.CONE_RANGE_SOFT),
			"scaled to the cone's range")
	var half := head_angle * 0.5
	var soft := Illumination.CONE_EDGE_SOFT
	check(_alpha_at(light, Vector2(0, -2000)) > 0.98, "full light ahead")
	check(_alpha_at(light, Vector2.UP.rotated(deg_to_rad(half - soft - 1.0)) * 2000.0) > 0.95, "just inside the cone's side")
	check(_alpha_at(light, Vector2.UP.rotated(deg_to_rad(half + soft + 1.0)) * 2000.0) < 0.02, "none just outside it")
	check(absf(_alpha_at(light, Vector2.UP.rotated(deg_to_rad(half)) * 2000.0) - 0.5) < 0.15, "half on the edge itself")
	check(absf(_alpha_at(light, Vector2(0, -Illumination.CONE_RANGE)) - 0.5) < 0.1, "half at the cone's range")
	check(_alpha_at(light, Vector2(0, -(Illumination.CONE_RANGE + Illumination.CONE_RANGE_SOFT * 0.9))) < 0.05, "none past it")
	check(_alpha_at(light, Vector2(0, Illumination.LOCAL_RADIUS - Illumination.LOCAL_SOFT - 30.0)) > 0.95, "a circle round the mecha, behind it too")
	check(_alpha_at(light, Vector2(0, Illumination.LOCAL_RADIUS + Illumination.LOCAL_SOFT + 30.0)) < 0.02, "and none past it")
	check(is_equal_approx(_alpha_at(light, Vector2(-700, -1500)), _alpha_at(light, Vector2(700, -1500))), "both sides alike")

	var other := _mecha(Vector2(3000, -3000), Vector2.UP, true)
	check(Illumination.light_of(other).texture == light.texture, "mechas with the same angle share one texture")
	var started := Time.get_ticks_usec()
	Illumination.shape_light(plain, 90.0)
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	check(ms < 1000.0, "a new angle is drawn once (%.0f ms)" % ms)
	check(light.texture != Illumination.light_of(other).texture and Illumination.cone_angle(light) == 90.0, "a wider head gets its own cone")
	check(_alpha_at(light, Vector2.UP.rotated(deg_to_rad(40.0)) * 2000.0) > 0.95, "lit 40 degrees off")
	check(_alpha_at(light, Vector2.UP.rotated(deg_to_rad(50.0)) * 2000.0) < 0.02, "not 50")
	Illumination.shape_light(plain, 1000.0)
	check_eq(Illumination.cone_angle(light), Illumination.MAX_CONE_ANGLE, "angles are kept within the limits")
	check(_alpha_at(light, Vector2(0, 2000)) > 0.98, "and a full circle lights all round")
	Illumination.shape_light(plain)
	check_eq(Illumination.cone_angle(light), head_angle, "shaped for its head again")

	# The cone's angle is what is lit, and what the player and an NPC see.
	var o := Vector2(-4000, 4000)
	var lamp := _mecha(o, Vector2.UP, true)
	var at_25 := _mecha(o + Vector2.UP.rotated(deg_to_rad(25.0)) * 1500.0, Vector2.UP, false)
	await get_tree().physics_frame
	check(not Illumination.is_lit(at_25), "with a %.0f degree cone, a dark mecha 25 degrees off isn't lit" % head_angle)
	Illumination.shape_light(lamp, 60.0)
	await get_tree().physics_frame
	check(Illumination.is_lit(at_25), "with a 60 degree one it is")
	lamp.set_illuminator(false)
	await _look(o + Vector2(0, 100), Vector2.UP)
	check(_hidden(at_25), "the player doesn't see it with its head's cone")
	Illumination.shape_light(_player, 60.0)
	check_eq(_player.get_view_angle(), 60.0, "the player's view cone follows its light")
	await _look(o + Vector2(0, 100), Vector2.UP)
	check(_shown(at_25), "and with a 60 degree one it does")
	Illumination.shape_light(_player)


func _test_npc_cone() -> void:
	var enemy := _enemy(Vector2(-3000, -3000))
	enemy.auto_illuminator = false
	var o := Vector2(-4000, -4000)
	enemy.global_position = o
	enemy.global_rotation = 0.0
	var foe := _mecha(o + Vector2(0, -1200), Vector2.UP, false)
	enemy.mark_traitor(foe)
	var where := {
		"ahead": Vector2(0, -1200),
		"25 degrees off": Vector2.UP.rotated(deg_to_rad(25.0)) * 1200.0,
		"to the side": Vector2(1200, 0),
		"behind": Vector2(0, 1200),
		"close behind": Vector2(0, enemy.PERIPHERAL_SIGHT - 50.0),
	}
	var seen := {}
	for cone in [["head", -1.0], ["wide", 60.0]]:
		Illumination.shape_light(enemy, cone[1])
		for key in where:
			foe.global_position = o + where[key]
			await get_tree().physics_frame
			enemy.update_senses(0.1)
			seen["%s, %s" % [key, cone[0]]] = enemy.is_seeing(foe)
	var head_angle: float = enemy.build.head.illuminator_angle
	check(seen["ahead, head"], "an NPC sees a dark mecha ahead in its cone")
	check(not seen["25 degrees off, head"], "not one 25 degrees off with its head's %.0f degree cone" % head_angle)
	check(seen["25 degrees off, wide"], "but does with a 60 degree one")
	check(not seen["to the side, head"] and not seen["to the side, wide"], "nor one to the side")
	check(not seen["behind, head"], "nor one behind it")
	check(seen["close behind, head"], "but one close behind it, yes")
	# Dark itself, it sees only within DARK_SIGHT_MULT of its range: at least
	# that share of the coldest target's range (0.6 of engage_distance).
	enemy.set_illuminator(false)
	var dark_reach: float = enemy.engage_distance * 0.6 * enemy.DARK_SIGHT_MULT
	foe.global_position = o + Vector2(0, -(enemy.PERIPHERAL_SIGHT + dark_reach) * 0.5)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "dark itself, it still sees ahead (close by)")
	foe.global_position = o + Vector2(0, 1200)
	foe.set_illuminator(true)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	check(enemy.is_seeing(foe), "and a lit mecha behind it is seen all the same")


func _test_npc_states() -> void:
	var enemy := _enemy(Vector2(-3000, -3000))
	var behaviour = enemy.logic.behaviour
	check(not behaviour.wants_illuminator(enemy, "ambush") and not behaviour.wants_illuminator(enemy, "flee"),
			"lying in wait and running are dark")
	for intent in ["roam", "ambush", "flee", "loot", "investigate", "extract"]:
		enemy.logic.g.set_state(intent)
		enemy._illuminator_hold = 0.0
		enemy._update_illuminator()
		var wanted: bool = behaviour.wants_illuminator(enemy, intent)
		check_eq(enemy.illuminator_on, wanted, "%s: illuminator %s" % [intent, "on" if wanted else "off"])
	# Engaging: dark while closing on a target that hasn't fired, lit once it
	# has, and lit while trading shots.
	behaviour.stance = "closing"
	check(not behaviour.wants_illuminator(enemy, "engage"), "closing on a quiet target: dark")
	enemy.under_fire_timer = 0.5
	check(behaviour.wants_illuminator(enemy, "engage"), "closing under fire: lit")
	enemy.under_fire_timer = 0.0
	behaviour.stance = "attack"
	check(behaviour.wants_illuminator(enemy, "engage"), "trading shots: lit")
	behaviour.stance = "closing"
	# Flagged, it leaves dark.
	enemy.is_exposed = true
	check(not behaviour.wants_illuminator(enemy, "extract"), "leaving Flagged: dark")
	enemy.is_exposed = false
	# Hunters and Rats wander dark.
	enemy.personality.type = Personality.Type.HUNTER
	check(not behaviour.wants_illuminator(enemy, "roam") and not behaviour.wants_illuminator(enemy, "investigate"),
			"a Hunter roams and investigates dark")
	enemy.personality.type = Personality.Type.PROFESSIONAL
	# A setting is held for ILLUMINATOR_HOLD_TIME s.
	enemy.logic.g.set_state("ambush")
	enemy._illuminator_hold = 0.0
	enemy._update_illuminator()
	check(not enemy.illuminator_on, "dark in ambush")
	enemy.logic.g.set_state("roam")
	enemy._update_illuminator(0.1)
	check(not enemy.illuminator_on, "still dark right after the change (the hold)")
	enemy._update_illuminator(enemy.ILLUMINATOR_HOLD_TIME)
	check(enemy.illuminator_on, "lit once the hold is over")
	enemy.logic.g.set_state("ambush")
	enemy._update_illuminator(0.1)
	check(enemy.illuminator_on, "held lit")
	enemy.took_damage.emit(enemy, false)
	enemy._update_illuminator(0.0)
	check(not enemy.illuminator_on, "being hit ends the hold")
	enemy.auto_illuminator = false
	enemy._illuminator_hold = 0.0
	enemy.set_illuminator(true)
	enemy._update_illuminator()
	check(enemy.illuminator_on, "with auto_illuminator off the behaviour leaves it alone")


func _test_light_style() -> void:
	var enemy := _enemy(Vector2(-3000, -3000))
	var plain := _mecha(Vector2(3000, 3000), Vector2.UP, true)
	for mecha in [_player, enemy, plain]:
		var light := Illumination.light_of(mecha)
		check(light.blend_mode == Light2D.BLEND_MODE_ADD and is_equal_approx(light.energy, Illumination.LIGHT_ENERGY)
				and light.color == Color.WHITE, "%s's illuminator adds light at the shared energy" % mecha.name)
	var darkness: PointLight2D = _player.get_node(Illumination.DARKNESS_NODE)
	check(darkness.blend_mode == Light2D.BLEND_MODE_SUB and is_equal_approx(darkness.energy, Illumination.DARKNESS_ENERGY),
			"the player's darkness takes light away")
	check(not enemy.get_node(Illumination.DARKNESS_NODE).enabled and not plain.get_node(Illumination.DARKNESS_NODE).enabled,
			"an NPC's and a plain mecha's darkness are off (one per mecha would stack up)")
	var mix_lights := []
	for mecha in [_player, enemy, plain]:
		for light in mecha.find_children("*", "Light2D", true, false):
			if (light as Light2D).blend_mode == Light2D.BLEND_MODE_MIX:
				mix_lights.append(light.name)
	check_eq(mix_lights, [], "no light on a mecha mixes")
	var flare: Node = load("res://game/mecha/devices/Flare.tscn").instantiate()
	check((flare.get_node("Light") as Light2D).blend_mode == Light2D.BLEND_MODE_ADD, "a flare's light adds")
	flare.free()

	var glow: PointLight2D = plain.get_node("FireGlow")
	plain.set_physics_process(true)
	await get_tree().physics_frame
	check(not glow.enabled, "the fire glow is off while it isn't burning")
	plain.set_status("fire", 5.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(glow.enabled and glow.energy > 0.0, "and on while it burns")
	plain.set_status("fire", 0.0)
	await wait_until(func(): return glow.energy <= 0.0, 3.0)
	await get_tree().physics_frame
	check(not glow.enabled, "off again once it has faded")
