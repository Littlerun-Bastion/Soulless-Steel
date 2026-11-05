extends TestSuite

# SightCircleTest: every mecha's sight circle (Mecha.sight_radius: the head's
# visual_range in metres, shrunk by sensor damage, NO_HEAD_SIGHT with no
# head) and what follows it:
#   - the camera pans out to the circle and no further, not at all with no
#     head, and a shake doesn't move the pan;
#   - the screen is black past the circle (HeatmapEffects' sight mask), off
#     with no player, with controls locked and once the player is dead;
#   - the player sees nothing past the circle, and has no sight or IR track
#     past it;
#   - an NPC sees nothing past its circle, and heat only matters to IR: a cold
#     lit mecha is seen to the circle's edge as a hot one is;
#   - a mecha notices a light inside its circle, an Entity within a screen;
#   - the darkness sits on the camera's centre and sound is heard at the
#     player;
#   - building shadows and streamed scenes follow the panned camera;
#   - an NPC the player can see runs at full rate;
#   - nothing spawns where the player can see, and parts fly only where it
#     can see.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const HEATMAP := preload("res://game/ui/HeatmapEffects.tscn")
const STREAMED_PATH := "user://sight_circle_streamed.tscn"


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	var zones: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_lock_areas() -> Array:
		return []
	func get_entities() -> Array:
		return []
	func get_spawn_zones() -> Array:
		return zones
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null
var _player = null
var _saved_ranges := {}


func run_tests() -> void:
	await case("the sight radius: the head in metres, sensor damage, no head", _test_radius)
	await case("the pan stops at the circle; no head, no pan; a shake leaves the pan", _test_pan)
	await case("the black mask past the circle", _test_mask)
	await case("the player sees nothing past the circle, and tracks nothing past it", _test_player_view)
	await case("an NPC sees nothing past its circle; heat only matters to IR", _test_npc_sight)
	await case("lights are noticed inside the circle; Entities within a screen", _test_lights)
	await case("the darkness on the camera's centre, sound at the player", _test_darkness_and_sound)
	await case("shadows and streamed scenes follow the panned camera", _test_camera_followers)
	await case("an NPC the player can see runs at full rate", _test_lod)
	await case("nothing spawns, and no parts fly, where the player can't see", _test_spawns)
	await before_each()


func before_each() -> void:
	_restore_ranges()
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	_player = _mecha(Vector2.ZERO, PLAYER)
	_player.mecha_name = "Player"
	_player.set_physics_process(false)
	_arena.player = _player
	await get_tree().physics_frame


func _mecha(pos: Vector2, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	if scene == MECHA:
		mecha.set_illuminator(false)
	_arena.mechas.append(mecha)
	return mecha


func _enemy(pos: Vector2) -> Mecha:
	var enemy: Mecha = ENEMY.instantiate()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Sight test")
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.auto_illuminator = false
	_arena.mechas.append(enemy)
	return enemy


# Sets the head every mecha here wears to `metres` for this case (head parts
# are shared), put back by before_each.
func _set_range(mecha, metres: int) -> void:
	var head = mecha.build.head
	if not _saved_ranges.has(head):
		_saved_ranges[head] = head.visual_range
	head.visual_range = metres


func _restore_ranges() -> void:
	for head in _saved_ranges:
		head.visual_range = _saved_ranges[head]
	_saved_ranges.clear()


func _sense(enemy) -> void:
	await get_tree().physics_frame
	enemy.contacts.advance(0.1)
	enemy.update_senses(0.1)


func _test_radius() -> void:
	var metres: float = _player.build.head.visual_range
	check_eq(_player.sight_radius(), metres * MapSenses.PX_PER_METRE, "the head's visual_range, in metres")
	check_eq(metres, 150.0, "every head's 150 m for now")
	_player.disabled_systems.sensors = 0.5
	check_eq(_player.sight_radius(), metres * MapSenses.PX_PER_METRE * 0.5, "halved once the optics go")
	_player.disabled_systems.sensors = 1.0
	_player.lose_part("head")
	check_eq(_player.sight_radius(), Mecha.NO_HEAD_SIGHT, "the head shot off: NO_HEAD_SIGHT")
	var headless := _mecha(Vector2(5000, 0))
	headless.set_head(null)
	check_eq(headless.sight_radius(), Mecha.NO_HEAD_SIGHT, "no head fitted: the same")
	check_eq(Mecha.NO_HEAD_SIGHT, 400.0, "20 m")


func _test_pan() -> void:
	var cam = _player.get_cam()
	var limit: float = _player.sight_radius()
	cam.pan_offset = Vector2(limit * 3.0, 0.0)
	_player.update_camera_offset(0.016)
	check(cam.pan_offset.length() <= limit + 0.01, "the pan is held to the sight circle (%.0f px)" % cam.pan_offset.length())
	for i in 600:
		_player.update_camera_offset(0.1)
	check(cam.pan_offset.length() <= limit + 0.01, "however long the cursor pushes")
	cam.pan_offset = Vector2(1000, 0)
	cam.shake(0.2, 15, 60)
	# A tween's first step lands at the end of the frame after it is made.
	await wait_frames(3)
	check(cam.offset != cam.pan_offset, "a shake moves the view")
	await wait_seconds(0.8)
	await wait_frames(2)
	check(cam.offset.distance_to(Vector2(1000, 0)) < 0.5 and cam.pan_offset == Vector2(1000, 0),
			"and leaves it on the pan, not on the mecha (%s)" % str(cam.offset))
	_player.lose_part("head")
	_player.update_camera_offset(0.016)
	check_eq(cam.pan_offset, Vector2.ZERO, "with no head the camera doesn't pan")


func _test_mask() -> void:
	var effects = HEATMAP.instantiate()
	add_child(effects)
	await wait_frames(1)
	check(not effects.mask_state().on, "no mask with no player")
	effects.set_player(_player)
	await wait_frames(2)
	var state: Dictionary = effects.mask_state()
	var to_screen: Transform2D = _player.get_viewport().get_canvas_transform()
	check(state.on, "on for a player")
	check(Vector2(state.centre).distance_to(to_screen * _player.global_position) < 0.5, "centred on the player on the screen")
	check(absf(float(state.radius) - _player.sight_radius() * to_screen.get_scale().x) < 0.5,
			"its radius the sight radius times the zoom (%.0f)" % float(state.radius))
	_player.controls_locked = true
	await wait_frames(2)
	check(not effects.mask_state().on, "off while controls are locked")
	_player.controls_locked = false
	_player.is_dead = true
	await wait_frames(2)
	check(not effects.mask_state().on, "off once the player is dead")
	_player.is_dead = false
	effects.queue_free()


func _test_player_view() -> void:
	var r: float = _player.sight_radius()
	var inside := _mecha(Vector2(r * 0.95, 0))
	var outside := _mecha(Vector2(-r * 1.05, 0))
	inside.set_illuminator(true)
	outside.set_illuminator(true)
	await get_tree().physics_frame
	check(_player.can_see_body(inside), "a lit mecha just inside the circle is seen")
	check(not _player.can_see_body(outside), "one just past it isn't, lit or not")
	for i in 12:
		_player._update_view(0.1)
	check(_player.contacts.query({"body": inside, "source": "sight"}).size() == 1, "a sight track inside")
	check(_player.contacts.query({"body": outside, "source": "sight"}).is_empty(), "none past it")
	check(_player.is_hidden_from_view(outside) and outside.modulate.a < 0.05, "and it is faded out")

	inside.set_illuminator(false)
	outside.set_illuminator(false)
	inside.global_position = Vector2(0, r * 0.9)
	outside.global_position = Vector2(0, -r * 1.1)
	for body in [inside, outside]:
		body.paused = true
		body.external_temp = 100.0
	await get_tree().physics_frame
	_player.contacts.clear()
	for i in 3:
		_player._update_view(0.1)
	check(not _player.contacts.query({"body": inside, "source": IRSensing.SOURCE}).is_empty(), "IR tracks a hot body inside the circle")
	check(_player.contacts.query({"body": outside, "source": IRSensing.SOURCE}).is_empty(), "not past it")

	_player.controls_locked = true
	check(_player.can_see_body(outside), "a cutscene shows everything, as before")
	_player.controls_locked = false


func _test_npc_sight() -> void:
	var enemy := _enemy(Vector2(-6000, 0))
	enemy.set_illuminator(false)
	var r: float = enemy.sight_radius()
	var o: Vector2 = enemy.global_position
	var cold := _mecha(o + Vector2(0, -r * 0.95))
	var hot := _mecha(o + Vector2(0, r * 0.95))
	cold.set_illuminator(true)
	hot.set_illuminator(true)
	cold.external_temp = 0.0
	hot.external_temp = 150.0
	await _sense(enemy)
	check(enemy.is_seeing(cold), "a cold lit mecha is seen at the circle's edge")
	check(enemy.is_seeing(hot), "and a hot one")
	cold.global_position = o + Vector2(0, -r * 1.05)
	hot.global_position = o + Vector2(0, r * 1.05)
	await _sense(enemy)
	check(not enemy.knowledge.knows(cold) or not enemy.is_seeing(cold), "nothing past it, cold")
	check(not enemy.is_seeing(hot), "or hot")
	cold.set_illuminator(false)
	hot.set_illuminator(false)
	hot.global_position = o + Vector2(r * 0.8, 0)
	hot.paused = true
	hot.external_temp = 100.0
	enemy.contacts.clear()
	await _sense(enemy)
	check(not enemy.contacts.query({"body": hot, "source": IRSensing.SOURCE}).is_empty(), "IR picks up a hot body inside the circle")
	hot.global_position = o + Vector2(r * 1.2, 0)
	enemy.contacts.clear()
	await _sense(enemy)
	check(enemy.contacts.query({"body": hot, "source": IRSensing.SOURCE}).is_empty(), "not past it")
	enemy.disabled_systems.sensors = 0.5
	hot.set_illuminator(true)
	hot.global_position = o + Vector2(r * 0.7, 0)
	await _sense(enemy)
	check(not enemy.is_seeing(hot), "with its optics gone its circle is halved")


func _test_lights() -> void:
	var enemy := _enemy(Vector2(-6000, 0))
	var r: float = enemy.sight_radius()
	var lamp := _mecha(enemy.global_position + Vector2(r * 0.9, 0))
	lamp.set_illuminator(true)
	await get_tree().physics_frame
	check(Illumination.in_light_range(enemy, lamp), "a light inside the circle gives its mecha away")
	lamp.global_position = enemy.global_position + Vector2(r * 1.1, 0)
	await get_tree().physics_frame
	check(not Illumination.in_light_range(enemy, lamp), "one past it doesn't")
	var creature := Node2D.new()
	_arena.add_child(creature)
	creature.global_position = lamp.global_position + Vector2(Illumination.SCREEN_HALF.x * 0.9, 0)
	await get_tree().physics_frame
	check(Illumination.in_light_range(creature, lamp), "an Entity (no head) notices it within a screen")
	creature.global_position = lamp.global_position + Vector2(Illumination.SCREEN_HALF.x * 1.1, 0)
	await get_tree().physics_frame
	check(not Illumination.in_light_range(creature, lamp), "not past a screen")
	creature.queue_free()


func _test_darkness_and_sound() -> void:
	var cam = _player.get_cam()
	cam.pan_offset = Vector2(1500, -400)
	await wait_frames(3)
	var darkness: PointLight2D = _player.get_node("MechaShadowGen")
	check(darkness.top_level, "the darkness doesn't ride on the mecha")
	var view_centre: Vector2 = get_viewport().get_camera_2d().get_screen_center_position()
	check(darkness.global_position.distance_to(view_centre) < 1.0, "it sits on the camera's centre, panned (%s)" % str(darkness.global_position))
	check(_player.get_node("AudioListener").is_current(), "sound is heard at the player")


func _test_camera_followers() -> void:
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array([Vector2(7000, -200), Vector2(7400, -200), Vector2(7400, 200), Vector2(7000, 200)])
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	_set_range(_player, 400)
	var cam = _player.get_cam()
	cam.pan_offset = Vector2.ZERO
	await wait_frames(3)
	field.update_occluders(get_viewport().get_camera_2d().get_screen_center_position(), -1.0,
			_player.global_position, _player.sight_radius() + field.occluder_margin)
	check_eq(field.occluder_count(), 0, "a building far off screen casts no shadow")
	cam.pan_offset = Vector2(6000, 0)
	await wait_frames(3)
	field.update_occluders(get_viewport().get_camera_2d().get_screen_center_position(), -1.0,
			_player.global_position, _player.sight_radius() + field.occluder_margin)
	check_eq(field.occluder_count(), 1, "the camera panned to it: it does")
	field.update_occluders(get_viewport().get_camera_2d().get_screen_center_position(), -1.0,
			_player.global_position, 2000.0)
	check_eq(field.occluder_count(), 0, "but not past the player's sight circle")

	var content := Node2D.new()
	content.name = "Compound"
	var body := StaticBody2D.new()
	content.add_child(body)
	body.owner = content
	var packed := PackedScene.new()
	packed.pack(content)
	content.free()
	ResourceSaver.save(packed, STREAMED_PATH)
	var streamed := StreamedScene.new()
	streamed.scene_path = STREAMED_PATH
	streamed.position = Vector2(16000, 0)
	streamed.bounds = Rect2(-500, -500, 1000, 1000)
	_arena.add_child(streamed)
	var streamer := MapStreamer.new()
	streamer.chunks_root = NodePath("..")
	_arena.add_child(streamer)
	cam.pan_offset = Vector2.ZERO
	await wait_seconds(0.5)
	check(not streamed.is_loaded(), "a hand-made scene far from every mecha isn't loaded")
	cam.pan_offset = Vector2(13000, 0)
	await wait_frames(2)
	var view_centre: Vector2 = get_viewport().get_camera_2d().get_screen_center_position()
	var view_size: Vector2 = get_viewport().get_visible_rect().size / get_viewport().get_camera_2d().zoom
	var view_load := maxf(streamer.load_distance, view_size.length() * 0.5 + streamer.view_margin)
	check(streamed.distance_to_nearest([view_centre]) <= view_load, "the camera is panned near it")
	var loaded := await wait_until(func(): return streamed.is_loaded(), 3.0)
	check(loaded, "it loads round the panned camera")
	cam.pan_offset = Vector2.ZERO
	var gone := await wait_until(func(): return not streamed.is_loaded(), 3.0)
	check(gone, "and goes when the camera comes back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STREAMED_PATH))


func _test_lod() -> void:
	_set_range(_player, 400)
	var enemy := _enemy(Vector2(5000, 0))
	enemy.paused = false
	enemy.set_scripted(true)
	var cam = _player.get_cam()
	cam.pan_offset = Vector2.ZERO
	await wait_frames(2)
	await get_tree().physics_frame
	check(enemy.lod_tier() > 0, "an NPC 250 m away, off screen, runs at a lower rate")
	cam.pan_offset = Vector2(5000, 0)
	await wait_frames(2)
	await get_tree().physics_frame
	check(enemy.is_on_screen(), "panned to it, it is on screen")
	check_eq(enemy.lod_tier(), 0, "and inside the player's circle (400 m): full rate")
	_set_range(_player, 150)
	await get_tree().physics_frame
	check(enemy.lod_tier() > 0, "on screen but past the circle: not")


func _test_spawns() -> void:
	_set_range(_player, 400)
	var director = load("res://game/expedition/ExpeditionDirector.gd").new()
	director.arena = _arena
	var near := Marker2D.new()
	near.position = Vector2(7000, 0)
	var far := Marker2D.new()
	far.position = Vector2(12000, 0)
	_arena.add_child(near)
	_arena.add_child(far)
	_arena.zones = [near, far]
	check(director._in_player_sight(near.global_position), "a spot 350 m out is inside the 400 m circle plus the margin")
	var picks := {}
	for i in 30:
		var pos = director._pick_offscreen_spawn_position()
		if pos is Vector2:
			picks["far" if pos.distance_to(far.global_position) < 400.0 else "near"] = true
	check(picks.has("far") and not picks.has("near"), "only the zone the player can't see is used (%s)" % str(picks.keys()))
	director.free()

	var scene = load("res://game/combat/CombatScene.gd").new()
	scene.player = _player
	var cam = _player.get_cam()
	cam.pan_offset = Vector2.ZERO
	cam.zoom = Vector2(0.25, 0.25)
	_set_range(_player, 150)
	await wait_frames(2)
	await get_tree().physics_frame
	check(scene._player_can_see_point(Vector2(1000, 0)), "a point on screen inside the circle can be seen")
	check(not scene._player_can_see_point(Vector2(3500, 0)), "one on screen past the circle (zoomed out) can't")
	check(not scene._player_can_see_point(Vector2(0, 20000)), "nor one off screen")
	cam.zoom = Vector2(0.5, 0.5)
	scene.free()
