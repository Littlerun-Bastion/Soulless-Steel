extends TestSuite

# IlluminatorTest: the illuminator's reach, its turning with the head, sight
# with the light off, the illuminator key, and lock head tracking.
#   - A light reaches as far as its head sees (Illumination.reach_of: the
#     head's visual_range, whatever the sensors' damage; NO_HEAD_SIGHT with no
#     head). One texture per (angle, reach), drawn to its reach with the
#     circle round the mecha and the fades the same size in px.
#   - The cone points where the head points (Mecha._aim_light), so what it
#     lights turns with the head, within the head's rotation_range.
#   - With its own light off, an NPC sees a body only if it is lit, made out
#     by IR, or within PERIPHERAL_SIGHT; the player the same.
#   - The key (Player.press_illuminator_key / release_illuminator_key): held,
#     on while held; two presses within ILLUMINATOR_DOUBLE_TAP latch it; any
#     press while latched goes dark. The HUD's IR row says which. C lights,
#     B sweeps.
#   - While the player holds a lock, its head turns to the target within its
#     range (Player.aim_at), the body to the cursor; the setting turns it off.
#     An NPC's lock still turns its whole body.
#
# Mechas are held still (no physics) and stepped by hand. Illumination works
# out each body once per physics frame, so every change waits a frame.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const SYSTEM_WINDOW := preload("res://game/ui/mech_os/windows/SystemWindow.tscn")

# A generated building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]
# Steps of aim_at, and its dt: long enough for any part to settle.
const AIM_STEPS := 120
const AIM_DT := 0.05


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
		return Vector2.ZERO


var _arena: FakeArena = null
var _player = null
var _saved_ranges := {}
var _saved_tracking = null


func run_tests() -> void:
	await case("the reach is the head's visual range, drawn to scale", _test_reach)
	await case("the cone follows the head, within its range", _test_follows_head)
	await case("with its light off an NPC sees only lit, IR and peripheral", _test_npc_dark)
	await case("with its light off the player sees the same", _test_player_dark)
	await case("the key: hold, release, double-tap latch, one press dark", _test_key)
	await case("the key's HUD row, its binding and the controls list", _test_key_hud)
	await case("lock head tracking: the head to the target, the body to the cursor", _test_head_tracking)
	await case("the setting: on by default, saved, in SYS", _test_setting)
	await before_each()


func before_each() -> void:
	_restore()
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	_player = _mecha(Vector2(-6000, 6000), Vector2.UP, true, PLAYER)
	_player.mecha_name = "Player"
	_arena.player = _player
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
	var enemy: Mecha = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Illuminator test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.auto_illuminator = false
	_arena.mechas.append(enemy)
	return enemy


# Sets the head a mecha wears to `metres` for this case (head parts are
# shared), put back by before_each.
func _set_range(mecha, metres: int) -> void:
	var head = mecha.build.head
	if not _saved_ranges.has(head):
		_saved_ranges[head] = head.visual_range
	head.visual_range = metres


func _restore() -> void:
	for head in _saved_ranges:
		head.visual_range = _saved_ranges[head]
	_saved_ranges.clear()
	if _saved_tracking != null:
		Profile.options["lock_head_tracking"] = _saved_tracking
		_saved_tracking = null


func _sense(enemy) -> void:
	await get_tree().physics_frame
	enemy.contacts.advance(0.1)
	enemy.update_senses(0.1)


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


# The texture's alpha `offset` px from a light's centre, in the light's own
# frame (forward is -y).
func _alpha_at(light: PointLight2D, offset: Vector2) -> float:
	var image: Image = light.texture.get_image()
	var texel: float = light.texture_scale
	var half := image.get_width() * 0.5
	var px := Vector2(half, half) + offset / texel
	return image.get_pixel(clampi(int(px.x), 0, image.get_width() - 1), clampi(int(px.y), 0, image.get_height() - 1)).a


# Degrees between where `node` points (its -y) and `point`.
func _off_by(node: Node2D, point: Vector2) -> float:
	var forward := Vector2.UP.rotated(node.global_rotation)
	return absf(rad_to_deg(forward.angle_to(point - node.global_position)))


func _test_reach() -> void:
	var lamp := _mecha(Vector2(3000, 3000), Vector2.UP, true)
	var light := Illumination.light_of(lamp)
	var metres: float = lamp.build.head.visual_range
	check(not "illuminator_range" in lamp.build.head, "a head has no illuminator range of its own")
	check_eq(Illumination.reach(light), metres * MapSenses.PX_PER_METRE, "the light reaches the head's visual range (%.0f m)" % metres)
	check_eq(Illumination.reach(light), lamp.sight_radius(), "as far as the mecha sees")
	var soft := Illumination.range_soft(Illumination.reach(light))
	check(is_equal_approx(light.texture_scale * Illumination.LIGHT_TEXTURE_SIZE * 0.5, Illumination.reach(light) + soft),
			"its texture is scaled to the reach and its fade")
	check(absf(_alpha_at(light, Vector2(0, -Illumination.reach(light))) - 0.5) < 0.1, "half light at the reach")
	check(_alpha_at(light, Vector2(0, -(Illumination.reach(light) + soft * 0.9))) < 0.05, "none past it")

	_set_range(lamp, 50)
	Illumination.shape_light(lamp)
	var near := Illumination.reach(light)
	check_eq(near, 50.0 * MapSenses.PX_PER_METRE, "a 50 m head reaches 50 m")
	check(absf(_alpha_at(light, Vector2(0, -near)) - 0.5) < 0.1, "half light at its reach too")
	check(_alpha_at(light, Vector2(0, -(near + Illumination.range_soft(near) * 0.9))) < 0.05, "and none past it")
	check(_alpha_at(light, Vector2(0, Illumination.LOCAL_RADIUS - Illumination.LOCAL_SOFT - 30.0)) > 0.95,
			"the circle round the mecha keeps its size")
	check(_alpha_at(light, Vector2(0, Illumination.LOCAL_RADIUS + Illumination.LOCAL_SOFT + 30.0)) < 0.02, "and its edge")
	var other := _mecha(Vector2(3000, -3000), Vector2.UP, true)
	check(Illumination.light_of(other).texture == light.texture, "two lights with the same angle and reach share a texture")
	_set_range(lamp, 150)
	Illumination.shape_light(lamp)
	check(Illumination.light_of(other).texture != light.texture, "a different reach gets its own")
	_set_range(lamp, 50)
	Illumination.shape_light(lamp)

	# What is lit follows the reach.
	var o := Vector2(-3000, -3000)
	lamp.global_position = o
	var inside := _mecha(o + Vector2(0, -near * 0.9), Vector2.UP, false)
	var past := _mecha(o + Vector2(0, -near * 3.0), Vector2.UP, false)
	var reaching := _mecha(o + Vector2(0, -near * 4.0), Vector2.UP, false)
	var radius := Illumination.body_radius(past)
	past.global_position = o + Vector2(0, -(near + radius + 50.0))
	reaching.global_position = o + Vector2(0, -(near + radius * 0.5))
	await get_tree().physics_frame
	check(Illumination.is_lit(inside), "a dark mecha just inside the reach is lit")
	check(Illumination.is_lit(reaching), "one whose near edge is inside it too")
	check(not Illumination.is_lit(past), "one wholly past it isn't")

	# The lamp, not the optics: sensor damage leaves the reach.
	lamp.disabled_systems.sensors = 0.5
	Illumination.shape_light(lamp)
	check_eq(Illumination.reach(light), near, "sensor damage doesn't shorten it")
	lamp.disabled_systems.sensors = 1.0
	check(lamp.lose_part("head"), "(the head comes off)")
	check_eq(Illumination.reach(light), Mecha.NO_HEAD_SIGHT, "with the head shot off it reaches NO_HEAD_SIGHT")
	var headless := _mecha(Vector2(-3000, 3000), Vector2.UP, true)
	headless.set_head(null)
	check_eq(Illumination.reach(Illumination.light_of(headless)), Mecha.NO_HEAD_SIGHT, "and with no head fitted")
	check(Illumination.light_of(headless).texture_scale * Illumination.LIGHT_TEXTURE_SIZE * 0.5
			>= Illumination.LOCAL_RADIUS + Illumination.LOCAL_SOFT, "still drawing the whole circle round it")


func _test_follows_head() -> void:
	var o := Vector2(-3000, -3000)
	var lamp := _mecha(o, Vector2.UP, true)
	var light := Illumination.light_of(lamp)
	var head_range: float = lamp.build.head.rotation_range
	var half: float = Illumination.cone_angle(light) * 0.5
	check(head_range > half + 5.0, "(the head turns further than half the cone: %.0f against %.0f degrees)" % [head_range, half])
	var turn := minf(head_range, 60.0)
	var aside: Vector2 = o + Vector2.UP.rotated(deg_to_rad(turn)) * 1500.0
	var ahead: Vector2 = o + Vector2(0, -1500)
	var dark_aside := _mecha(aside, Vector2.UP, false)
	var dark_ahead := _mecha(ahead, Vector2.UP, false)
	await get_tree().physics_frame
	check(Illumination.is_lit(dark_ahead) and not Illumination.is_lit(dark_aside), "facing ahead, the cone lights ahead")
	for i in AIM_STEPS:
		lamp.apply_rotation_by_point(AIM_DT, aside, true)
	check(is_equal_approx(lamp.global_rotation, 0.0), "(the body stays put)")
	check(_off_by(lamp.Head, aside) < 2.0, "the head turns %.0f degrees to the side" % turn)
	check(is_equal_approx(light.rotation, lamp.Head.rotation), "and the light with it")
	await get_tree().physics_frame
	check(Illumination.in_cone(light, aside), "the cone points where the head points")
	check(Illumination.is_lit(dark_aside), "so it lights what the head looks at")
	check(not Illumination.is_lit(dark_ahead), "and no longer what the body faces")

	var behind: Vector2 = o + Vector2(0, 1500)
	for i in AIM_STEPS:
		lamp.apply_rotation_by_point(AIM_DT, behind + Vector2(1, 0), true)
	check(absf(absf(lamp.Head.rotation_degrees) - head_range) < 0.5, "the head stops at its range (%.0f degrees)" % head_range)
	check(is_equal_approx(light.rotation, lamp.Head.rotation), "and so does the light")
	check(not Illumination.in_cone(light, behind), "so the cone can't point behind")

	lamp.Head.rotation_degrees = 10.0
	lamp._aim_light()
	check(is_equal_approx(light.rotation_degrees, 10.0), "a head turned any other way takes the light too")


func _test_npc_dark() -> void:
	var enemy := _enemy(Vector2(-3000, -3000))
	var o := Vector2(-3000, -3000)
	var foe := _mecha(o + Vector2(0, -1200), Vector2.UP, false)
	foe.paused = true
	enemy.mark_traitor(foe)
	enemy.set_illuminator(true)
	await _sense(enemy)
	check(enemy.is_seeing(foe), "with its light on it sees a dark mecha in its cone")
	enemy.set_illuminator(false)
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "with it off, not a dark one ahead in the open")
	foe.global_position = o + Vector2(0, -(enemy.PERIPHERAL_SIGHT - 50.0))
	await _sense(enemy)
	check(enemy.is_seeing(foe), "but one within PERIPHERAL_SIGHT, yes")
	foe.global_position = o + Vector2(0, enemy.PERIPHERAL_SIGHT - 50.0)
	await _sense(enemy)
	check(enemy.is_seeing(foe), "behind it too")
	foe.global_position = o + Vector2(0, -(enemy.PERIPHERAL_SIGHT + 50.0))
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "and not just past it")
	foe.global_position = o + Vector2(0, -2500)
	foe.set_illuminator(true)
	await _sense(enemy)
	check(enemy.is_seeing(foe), "a lit mecha far ahead is seen")
	foe.global_position = o + Vector2(0, 2500)
	await _sense(enemy)
	check(enemy.is_seeing(foe), "and far behind")
	foe.set_illuminator(false)
	var lamp := _mecha(o + Vector2(1500, 2500), Vector2.LEFT, true)
	await _sense(enemy)
	check(enemy.is_seeing(foe), "a dark one that another's light falls on is seen")
	lamp.set_illuminator(false)
	foe.external_temp = IRSensing.identification_of(enemy) - Mecha.AMBIENT_TEMP + 50.0
	await _sense(enemy)
	check(enemy.is_seeing(foe), "a dark one hot enough for IR identification is seen")
	foe.external_temp = 0.0
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "once it cools, it isn't")

	# Peripheral sight still stops at walls; light doesn't come through them.
	enemy.global_position = Vector2(-250, 200)
	foe.global_position = Vector2(450, 200)
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "dark, it doesn't see through the building")
	enemy.set_illuminator(true)
	await _sense(enemy)
	check(not enemy.is_seeing(foe), "nor lit: the walls shadow its own cone")
	check(not "DARK_SIGHT_MULT" in enemy, "there is no half-range dark sight")


func _test_player_dark() -> void:
	var o := Vector2(-6000, 6000)
	var ahead := _mecha(o + Vector2(0, -1500), Vector2.UP, false)
	var close := _mecha(o + Vector2(0, _player.VIEW_PERIPHERAL - 50.0), Vector2.UP, false)
	_player.set_illuminator(true)
	await _look(o, Vector2.UP)
	check(_shown(ahead), "lit, the player sees a dark mecha in its cone")
	_player.set_illuminator(false)
	await _look(o, Vector2.UP)
	check(_hidden(ahead), "dark, it doesn't")
	check(_shown(close), "only one close by")
	ahead.external_temp = IRSensing.identification_of(_player) - Mecha.AMBIENT_TEMP + 50.0
	await _look(o, Vector2.UP)
	check(_shown(ahead), "or one hot enough to make out")
	ahead.external_temp = 0.0
	ahead.set_illuminator(true)
	await _look(o, Vector2.UP)
	check(_shown(ahead), "or a lit one")


func _test_key() -> void:
	_player.set_illuminator(false)
	var t := 100.0
	_player.press_illuminator_key(t)
	check(_player.illuminator_on and _player.is_illuminator_held(), "pressed: on while held")
	check(not _player.is_illuminator_latched(), "not latched")
	_player.release_illuminator_key()
	check(not _player.illuminator_on, "released: off")

	t += 1.0
	_player.press_illuminator_key(t)
	_player.release_illuminator_key()
	_player.press_illuminator_key(t + _player.ILLUMINATOR_DOUBLE_TAP * 0.5)
	check(_player.illuminator_on and _player.is_illuminator_latched(), "two quick presses latch it on")
	_player.release_illuminator_key()
	check(_player.illuminator_on and _player.is_illuminator_latched(), "and it stays on once let go")

	t += 1.0
	_player.press_illuminator_key(t)
	check(not _player.illuminator_on and not _player.is_illuminator_latched(), "one press while latched: off and unlatched")
	_player.release_illuminator_key()
	check(not _player.illuminator_on, "and still off once let go")
	_player.press_illuminator_key(t + _player.ILLUMINATOR_DOUBLE_TAP * 0.5)
	check(_player.illuminator_on and not _player.is_illuminator_latched(), "a quick press after going dark is a fresh hold")
	_player.release_illuminator_key()
	check(not _player.illuminator_on, "off when let go")

	t += 1.0
	_player.press_illuminator_key(t)
	_player.release_illuminator_key()
	_player.press_illuminator_key(t + _player.ILLUMINATOR_DOUBLE_TAP * 1.5)
	check(_player.illuminator_on and not _player.is_illuminator_latched(), "two slow presses are two holds")
	_player.release_illuminator_key()
	check(not _player.illuminator_on, "the second ends when let go")

	_player.set_illuminator(true)
	check(_player.is_illuminator_latched(), "a light switched on some other way reads as latched")
	_player.press_illuminator_key(t + 10.0)
	check(not _player.illuminator_on, "and one press puts it out")

	# Through the input events, the way the game sends them.
	var press := InputEventAction.new()
	press.action = Illumination.KEY_ACTION
	press.pressed = true
	var release := InputEventAction.new()
	release.action = Illumination.KEY_ACTION
	release.pressed = false
	_player._input(press)
	check(_player.illuminator_on, "the key's press lights it")
	_player.stun(5.0)
	_player._input(release)
	check(not _player.illuminator_on, "and its release puts it out, stunned or not")
	_player.StunTimer.stop()


func _test_key_hud() -> void:
	MouseManager.set_aim_available(true)
	var weapons := HudWeapons.new()
	add_child(weapons)
	weapons.setup(_player)
	_player.set_illuminator(false)
	weapons._update()
	check(weapons.get_row_text("illuminator").ends_with("OFF / DARK"), "off: OFF / DARK (%s)" % weapons.get_row_text("illuminator"))
	_player.press_illuminator_key(200.0)
	weapons._update()
	check(weapons.get_row_text("illuminator").ends_with("ON / HELD"), "held: ON / HELD (%s)" % weapons.get_row_text("illuminator"))
	_player.release_illuminator_key()
	_player.press_illuminator_key(200.1)
	weapons._update()
	check(weapons.get_row_text("illuminator").ends_with("ON / LATCHED"), "latched: ON / LATCHED (%s)" % weapons.get_row_text("illuminator"))
	weapons.queue_free()

	var key := func(action: String) -> int:
		var events := InputMap.action_get_events(action)
		return (events[0] as InputEventKey).physical_keycode if not events.is_empty() and events[0] is InputEventKey else -1
	check_eq(key.call(Illumination.KEY_ACTION), KEY_C, "the illuminator is on C")
	check_eq(key.call("sweep"), KEY_B, "the sweep on B")
	check_eq(Illumination.DEFAULT_KEY, KEY_C, "and C is the default when the project lacks the action")
	var actions := SystemWindow.CONTROLS.map(func(c): return c.action)
	check(Illumination.KEY_ACTION in actions and "sweep" in actions, "both are under SYS, CONTROLS")


func _test_head_tracking() -> void:
	_saved_tracking = Profile.get_option("lock_head_tracking")
	Profile.options["lock_head_tracking"] = true
	MouseManager.set_aim_available(true)
	var o := Vector2(-6000, 6000)
	_player.global_position = o
	_player.global_rotation = 0.0
	var head_range: float = _player.build.head.rotation_range
	var cursor: Vector2 = o + Vector2(0, -2000)
	var turn := minf(head_range * 0.6, 50.0)
	var target := _mecha(o + Vector2.UP.rotated(deg_to_rad(turn)) * 1800.0, Vector2.UP, false)
	_player.locked_to = target
	_player.lock_timer = 0.0
	_player.lock_on_duration = 1000.0
	for i in AIM_STEPS:
		_player.aim_at(AIM_DT, cursor)
	check(_off_by(_player, cursor) < 2.0, "locked, the body faces the cursor")
	check(_off_by(_player.Head, target.global_position) < 2.0, "the head the target, %.0f degrees off" % turn)
	check(is_equal_approx(Illumination.light_of(_player).rotation, _player.Head.rotation), "and the light follows the head")
	if _player.build.arm_weapon_left:
		check(_off_by(_player.LeftArmWeapon, cursor) < 10.0, "the arms to the cursor")

	target.global_position = o + Vector2(0, 1800)
	for i in AIM_STEPS:
		_player.aim_at(AIM_DT, cursor)
	check(absf(absf(_player.Head.rotation_degrees) - head_range) < 0.5, "a target behind: the head stops at its range")
	check(_off_by(_player, cursor) < 2.0, "and the body still faces the cursor")

	target.global_position = o + Vector2.UP.rotated(deg_to_rad(turn)) * 1800.0
	for i in AIM_STEPS:
		_player.aim_at(AIM_DT, _player.global_position + Vector2(1, 0))
	check(_off_by(_player.Head, target.global_position) < 2.0, "with the cursor on the mecha, the head still tracks")

	Profile.options["lock_head_tracking"] = false
	for i in AIM_STEPS:
		_player.aim_at(AIM_DT, cursor)
	check(_off_by(_player.Head, cursor) < 2.0, "with the setting off, the head follows the cursor")
	Profile.options["lock_head_tracking"] = true
	_player.locked_to = false
	for i in AIM_STEPS:
		_player.aim_at(AIM_DT, cursor)
	check(_off_by(_player.Head, cursor) < 2.0, "and with no lock")
	check(not _player.faces_lock, "the player's lock never turns its body")

	var npc := _mecha(o + Vector2(3000, 0), Vector2.UP, false)
	npc.locked_to = target
	npc.lock_timer = 0.0
	npc.lock_on_duration = 1000.0
	target.global_position = npc.global_position + Vector2(1500, 0)
	npc.set_physics_process(true)
	await wait_frames(60)
	npc.set_physics_process(false)
	check(npc.faces_lock and _off_by(npc, target.global_position) < 10.0, "another mecha's lock turns it whole, as before")


func _test_setting() -> void:
	check(Profile.options.has("lock_head_tracking") and Profile.get_option("lock_head_tracking") == true,
			"Lock Head Tracking is an option, on by default")
	check(Profile.get_save_data().options.has("lock_head_tracking"), "saved with the other options")
	var defaults: Dictionary = Profile.options.duplicate()
	var old_save := {"options": {"screen_shake": defaults.screen_shake}}
	Profile.set_data(old_save, "options", defaults)
	check_eq(defaults.lock_head_tracking, true, "a save from before it loads with it on")
	var labels := SystemWindow.TOGGLES.map(func(t): return t.option)
	var at: int = labels.find("lock_head_tracking")
	check(at >= 0 and at == labels.find("designator_look_limits") + 1, "SYS lists it after Designator Look Limits")
	var window: Node = SYSTEM_WINDOW.instantiate()
	add_child(window)
	await get_tree().process_frame
	var button: Button = window._toggle_buttons.get("lock_head_tracking")
	check(button != null and button.button_pressed == bool(Profile.get_option("lock_head_tracking")), "its toggle shows the option")
	window.queue_free()
