extends TestSuite

# ObserverArenaTest: the observer arena (game/arena/ObserverArena.tscn, opened
# by the main menu's OBSERVE button) loads with no player and nothing at
# stake; spawns an NPC of each personality type, a squad and a dummy at a
# point; sets off each event (a car alarm, a loud noise, a round and a sweep
# from the phantom, a ward and a drone); runs each dummy behaviour; picks and
# places by clicks; pauses the NPCs and changes the game speed; and deletes
# and clears what is on the map.

const OBSERVER_ARENA := preload("res://game/arena/ObserverArena.tscn")
const DUMMY := preload("res://game/arena/observer/ObserverDummy.gd")
const TYPES := ["scavenger", "rat", "guardian", "professional", "hunter"]
# How far (px) a gun's muzzle can be from the mecha holding it.
const MUZZLE_SLACK := 120.0

var _scene = null


# A rifle round moves its speed x the time scale / 60 px a physics frame: at
# the runner's 4x it would cross an NPC's NearbyProjectile area between two
# frames.
func _init() -> void:
	time_scale = 2.0


func run_tests() -> void:
	await case("the scene loads with no player", _test_load)
	await case("it spawns an NPC of each type, a squad and a dummy", _test_spawn)
	await case("each event happens", _test_events)
	await case("each dummy behaviour", _test_dummy)
	await case("clicks pick, place and cancel", _test_clicks)
	await case("a real mouse click on the map gets through to it", _test_real_clicks)
	await case("think tags and barks over the NPCs", _test_tags_and_barks)
	await case("pause stops the NPCs; the speeds set the game speed", _test_time)
	await case("delete and clear", _test_delete)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	await wait_frames(2)


func _start() -> void:
	PlayerProgress.reset()
	_scene = OBSERVER_ARENA.instantiate()
	add_child(_scene)
	await wait_frames(3)
	await get_tree().physics_frame


func _npc(type_name := "professional", at := Vector2(-800, 600)) -> Mecha:
	return _scene.spawn_npc(type_name, 0, 1, at)[0]


func _test_load() -> void:
	await _start()
	check(_scene.player == null, "there is no player")
	check(not PlayerProgress.is_in_expedition(), "nothing is at stake")
	check(_scene.panel != null and _scene.panel.is_inside_tree(), "the control panel is up")
	check(_scene.overlay != null and _scene.overlay.is_inside_tree(), "and the overlays")
	check(_scene.get_viewport().get_camera_2d() == _scene.ArenaCam, "the spectator camera is the current camera")
	check(_scene.has_node("Darkness") and _scene.get_node("Darkness").blend_mode == Light2D.BLEND_MODE_SUB, "the arena has its own darkness")
	var buildings := BuildingField.find(_scene)
	check(buildings != null and buildings.footprints.count() == 3, "three buildings")
	var vehicles := VehicleField.find(_scene)
	check(vehicles != null and vehicles.vehicle_count() >= 8, "parked cars")
	check(not get_tree().get_nodes_in_group("foliage_layer").is_empty(), "trees and bushes that hide what is under them")
	var phantom = _scene.get_phantom()
	check(phantom != null and not phantom.is_in_group("mecha") and not (phantom in _scene.all_mechas), "the phantom is in no list of mechas")
	await wait_seconds(1.0)


func _test_spawn() -> void:
	await _start()
	for i in TYPES.size():
		var npc := _npc(TYPES[i], Vector2(-3000 + i * 1200, 1500))
		check_eq(Personality.Type.keys()[npc.personality.type].to_lower(), TYPES[i], "a %s" % TYPES[i])
	check(_scene.observed_npcs().all(func(n): return n.lod_tier() == 0), "every NPC runs at full rate")
	var squad: Array = _scene.spawn_npc("hunter", 3, 3, Vector2(2000, 2000))
	check_eq(squad.size(), 3, "a squad of three")
	var squads: Array = _scene.squads.filter(func(s): return s.is_in(squad[0]))
	check(squads.size() == 1 and squad.all(func(m): return squads[0].is_in(m)), "all in one squad")
	var skilled: Array = _scene.spawn_npc("scavenger", 0, 1, Vector2(-2000, 2500), 0.95)
	check(is_equal_approx(skilled[0].personality.skill, 0.95), "the panel's skill overrides the type's draw")
	var drawn: Array = _scene.spawn_npc("scavenger", 0, 1, Vector2(-1000, 2500))
	var span: Vector2 = Personality.SKILL_RANGES[Personality.Type.SCAVENGER]
	check(drawn[0].personality.skill >= span.x and drawn[0].personality.skill <= span.y, "AUTO draws it for the type")
	var dummy: Mecha = _scene.spawn_dummy(Vector2(0, -600))
	check(dummy.scripted and _scene.is_dummy(dummy), "a dummy: a scripted mecha")
	check(_scene.dummy_control(dummy) != null, "with its controls")
	check(is_same(_scene.selected_dummy, dummy), "and selected")
	await wait_seconds(1.0)
	check(_scene.observed_npcs().any(func(n): return str(n.logic.get_current_state()) != ""), "the NPCs think")


func _test_tags_and_barks() -> void:
	await _start()
	var overlay = _scene.overlay
	check(overlay.show_tags and overlay.show_barks, "think tags and barks are on to begin with")
	check(not Debug.get_setting("enemy_state"), "(the NPCs' own world-size state labels stay off)")
	var npc := _npc("professional", Vector2(-800, 600))
	await wait_seconds(0.5)
	var lines: PackedStringArray = overlay.tag_lines(npc, false)
	var state := str(npc.logic.get_current_state()).to_upper()
	check(lines.size() >= 2 and npc.mecha_name.to_upper() in lines[0] and state in lines[0],
			"a tag names the NPC and its intent, then its scores (%s)" % " | ".join(lines))
	var detail: PackedStringArray = overlay.tag_lines(npc, true)
	check(detail.size() > lines.size() and ("lit" in "\n".join(detail) or "dark" in "\n".join(detail)),
			"the selected one's has the whole detail (%s)" % " | ".join(detail))
	npc.paused = true
	await wait_seconds(overlay.STILL_SHOW + 0.5)
	check(overlay.still_time(npc) >= overlay.STILL_SHOW and "STILL" in overlay.tag_lines(npc, false)[0],
			"one standing still says for how long (%s)" % overlay.tag_lines(npc, false)[0])
	npc.paused = false
	check(npc._player_in_earshot(), "with no player, every pilot is in earshot")
	npc.say("Testing.")
	check_eq(overlay.speech_of(npc), "Testing.", "what it says shows over it")
	overlay.show_barks = false
	check(not npc._player_in_earshot(), "barks off: nobody hears them")
	overlay.show_barks = true
	await wait_seconds(npc.SPEECH_TIME + 0.5)
	check_eq(overlay.speech_of(npc), "", "and goes when the speech is over")


# Whether a shot wedge points back at `fired_from`, give or take the few px
# between the phantom and its gun's muzzle (where the round set off).
func _round_wedge(wedge: Dictionary, fired_from: Vector2) -> bool:
	var offset: Vector2 = fired_from - Vector2(wedge.origin)
	var off_by := absf(rad_to_deg(angle_difference(float(wedge.bearing), offset.angle())))
	var slack := rad_to_deg(atan2(MUZZLE_SLACK, offset.length()))
	return off_by <= float(wedge.width) * 0.5 + slack \
			and offset.length() >= float(wedge.min_range) - MUZZLE_SLACK and offset.length() <= float(wedge.max_range) + MUZZLE_SLACK


func _test_events() -> void:
	await _start()
	var npc := _npc("hunter", Vector2(-600, 600))
	_scene.select(npc)
	await get_tree().physics_frame

	check(_scene.trigger_event("car_alarm", Vector2(-600, 1300)), "a car alarm goes off")
	await get_tree().physics_frame
	check(not npc.contacts.query({"source": "alarm"}).is_empty(), "and the NPC has an alarm track")

	# What the NPC can't see, it places by a wedge's estimate point.
	var noise_at := Vector2(-600, 2500)
	check(_scene.trigger_event("noise", noise_at), "a loud noise")
	var heard: Array = npc.contacts.wedges({"source": "sound"})
	check(heard.size() == 1 and ContactStore.wedge_contains(heard[0], noise_at)
			and npc.senses.sounds.any(func(s): return s.volume_type == "loud" and s.position == ContactStore.estimate_point(heard[0])),
			"the NPC hears it: a sound wedge round it, and the sound at the wedge's estimate point")

	var from := Vector2(-600, -1000)
	check(_scene.trigger_event("round", from), "a round from the cursor at the selected NPC")
	var shot := await wait_until(func():
		var phantom = _scene.get_phantom()
		var wedges: Array = npc.contacts.wedges({"source": "shot"})
		return is_same(npc.most_recent_attacker, phantom) and npc.last_attack_position is Vector2 \
				and wedges.size() == 1 and _round_wedge(wedges[0], from) \
				and npc.last_attack_position == ContactStore.estimate_point(wedges[0]), 4.0)
	check(shot, "it is fired, and the NPC makes out where from: a shot wedge round the cursor, and its estimate point")

	check(_scene.trigger_event("sweep", Vector2(-600, -2000)), "a sweep from the cursor toward the selected NPC")
	check(npc.knowledge.swept_count >= 1, "it finds the NPC")

	check(not _scene.trigger_event("ward", Vector2(400, 400)), "no ward without a dummy")
	var dummy: Mecha = _scene.spawn_dummy(Vector2(1500, -800))
	check(_scene.trigger_event("ward", Vector2(400, 400)), "a ward at the cursor")
	check(_scene.trigger_event("drone", Vector2(800, 400)), "a drone at the cursor")
	await get_tree().physics_frame
	var devices: Array = Device.owned_by(dummy)
	check(devices.any(func(d): return d.kind == "ward" and d.global_position.distance_to(Vector2(400, 400)) < 50.0), "the ward is the dummy's, where it was put")
	check(devices.any(func(d): return d.kind == "drone"), "and the drone")


func _test_dummy() -> void:
	await _start()
	var npc := _npc("professional", Vector2(-2000, 1500))
	var dummy: Mecha = _scene.spawn_dummy(Vector2(0, 600))
	var control = _scene.dummy_control(dummy)
	_scene.select(npc)
	_scene.select(dummy)
	check(is_same(_scene.selected_npc, npc) and is_same(_scene.selected_dummy, dummy), "the NPC and the dummy are both remembered")

	control.add_patrol_point(Vector2(1500, 600))
	control.add_patrol_point(Vector2(1500, 1600))
	control.set_move(DUMMY.Move.PATROL)
	var walked := await wait_until(func(): return dummy.global_position.distance_to(Vector2(1500, 600)) < 400.0, 20.0)
	check(walked, "it walks its patrol")
	control.set_move(DUMMY.Move.STAND)

	control.set_light(DUMMY.Light.ON)
	check(dummy.illuminator_on, "its light on")
	control.set_light(DUMMY.Light.OFF)
	check(not dummy.illuminator_on, "and off")
	control.set_light(DUMMY.Light.FLASH)
	var flashed := await wait_until(func(): return dummy.illuminator_on, DUMMY.FLASH_TIME * 2.5)
	check(flashed, "flashing comes on")
	var dark := await wait_until(func(): return not dummy.illuminator_on, DUMMY.FLASH_TIME * 2.5)
	check(dark, "and goes off again")
	control.set_light(DUMMY.Light.OFF)

	control.fire_interval = 1.0
	control.set_fire(DUMMY.Fire.NPC)
	var fired := await wait_until(func(): return control.shots >= 1, 6.0)
	check(fired, "it fires at the selected NPC")
	control.set_fire(DUMMY.Fire.POINT)
	control.fire_point = Vector2(0, 2000)
	var before: int = control.shots
	# Long enough for a reload after the shots at the NPC.
	var fired_point := await wait_until(func(): return control.shots > before, 12.0)
	check(fired_point, "and at a point")
	control.set_fire(DUMMY.Fire.OFF)

	control.set_flag(true)
	check(dummy.is_flagged(), "its Flag up")
	before = control.shots
	control.set_fire(DUMMY.Fire.POINT)
	await wait_seconds(2.5)
	check_eq(control.shots, before, "it doesn't fire with the Flag up")
	control.set_flag(false)
	check(dummy.is_lowering_flag() or not dummy.is_flagged(), "and lowers it")


func _test_clicks() -> void:
	await _start()
	_scene.panel.npc_type_index = TYPES.find("rat")
	_scene.panel.squad_size = 1
	_scene.set_place_mode("npc")
	_scene.click_world(Vector2(-1000, 1800))
	var rats: Array = _scene.observed_npcs().filter(func(n): return n.personality.type == Personality.Type.RAT)
	check_eq(rats.size(), 1, "a click in PLACE NPC mode spawns one")
	_scene.click_world(Vector2(1000, 1800))
	check_eq(_scene.observed_npcs().size(), 2, "and keeps spawning until cancelled")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	check(_scene.handle_world_input(right), "a right click ends the mode")
	check_eq(_scene.place_mode, "", "back to selecting")
	_scene.click_world(rats[0].global_position + Vector2(60, 0))
	check(is_same(_scene.selected, rats[0]), "a click near a mecha selects it")
	_scene.click_world(Vector2(3500, -2500))
	check(_scene.selected == null, "a click on nothing clears the selection")
	_scene.select(rats[0])
	_scene.toggle_follow()
	_scene.update_camera(0.1, true)
	check(_scene.ArenaCam.position.distance_to(rats[0].global_position) < 1.0, "following puts the camera on it")
	var zoom: float = _scene.ArenaCam.zoom.x
	_scene.zoom_by(_scene.ZOOM_STEP)
	check(_scene.ArenaCam.zoom.x > zoom, "the wheel zooms")
	for i in 60:
		_scene.zoom_by(_scene.ZOOM_STEP)
	check(is_equal_approx(_scene.ArenaCam.zoom.x, _scene.ZOOM_MAX), "within its limit")


# A left click at `at` (viewport px) pushed through the viewport
# (Viewport.push_input) goes the way the mouse's does: every node's _input,
# the GUI (where a control that stops the mouse would take it), then
# _unhandled_input, where the panel hands it to the arena.
func _push_click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_viewport().push_input(click, true)
		await get_tree().process_frame


func _test_real_clicks() -> void:
	await _start()
	var middle: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var where: Vector2 = _scene.screen_to_world(middle)
	_scene.panel.npc_type_index = TYPES.find("hunter")
	_scene.panel.squad_size = 1
	_scene.set_place_mode("npc")
	await _push_click(middle)
	check(get_viewport().gui_get_hovered_control() == null, "nothing on screen over the map takes the mouse (%s)" % str(get_viewport().gui_get_hovered_control()))
	var hunters: Array = _scene.observed_npcs().filter(func(n): return n.personality.type == Personality.Type.HUNTER)
	check_eq(hunters.size(), 1, "PLACE NPC: a click in the middle of the screen spawns one")
	if not hunters.is_empty():
		check(hunters[0].global_position.distance_to(where) < 300.0, "where the click was, or next to it (%.0f px off)" % hunters[0].global_position.distance_to(where))
	_scene.set_place_mode("dummy")
	await _push_click(middle + Vector2(-300, 120))
	check_eq(_scene.dummies.size(), 1, "PLACE DUMMY: a click spawns a dummy")
	await _push_click(middle, MOUSE_BUTTON_RIGHT)
	check_eq(_scene.place_mode, "", "a right click ends the mode")
	if not hunters.is_empty():
		await _push_click(_scene.get_viewport().get_canvas_transform() * hunters[0].global_position)
		check(is_same(_scene.selected, hunters[0]), "a click on an NPC selects it")


func _test_time() -> void:
	await _start()
	var npc := _npc()
	await wait_seconds(0.5)
	_scene.set_paused(true)
	await wait_frames(2)
	var clock: float = npc.contacts.now
	var at: Vector2 = npc.global_position
	await wait_frames(30)
	check(is_equal_approx(npc.contacts.now, clock) and npc.global_position == at, "paused, the NPC stands still and its clock stops")
	_scene.set_paused(false)
	await wait_frames(10)
	check(npc.contacts.now > clock, "unpaused, it goes on")
	var base := Engine.time_scale
	_scene.set_speed(0.5)
	check(is_equal_approx(Engine.time_scale, base * 0.5), "half speed")
	_scene.set_speed(2.0)
	check(is_equal_approx(Engine.time_scale, base * 2.0), "double speed")
	_scene.set_speed(1.0)
	check(is_equal_approx(Engine.time_scale, base), "back to normal")


func _test_delete() -> void:
	await _start()
	var npc := _npc()
	_scene.spawn_npc("guardian", 2, 2, Vector2(1500, 1500))
	_scene.spawn_dummy(Vector2(0, -1500))
	_scene.select(npc)
	_scene.remove_mecha(_scene.selected)
	check(not (npc in _scene.all_mechas) and _scene.selected == null, "the selected NPC is deleted")
	_scene.clear_all()
	check(_scene.all_mechas.is_empty() and _scene.dummies.is_empty(), "clear takes everything off")
	check(_scene.squads.is_empty(), "squads included")
	await wait_frames(2)
