extends TestSuite

const ONBOARDING := preload("res://game/onboarding/Onboarding.tscn")
const ORDER: Array[String] = ["RemoteReboot", "DropKit", "GrabKit", "Drive", "Dash", "Shield", "LeaveMap", "FindTheExit", "LowerFlag"]
const CLEAR_OF_THE_PLAYER := 190.0

var _scene = null
var _seen: Array[String] = []
var _gap_when_she_speaks := INF
var _sight_when_she_speaks := 0.0
var _seen_when_she_speaks := false
var _camera_off_player := INF
var _gap_at_the_kit := 0.0
var _hud_when_she_speaks_again := ""
var _camera_on_her_at_the_door := INF
var _in_frame_when_she_leaves := true
var _past_frame_when_she_leaves := INF
var _saved_skip_intro = null


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 120


func run_tests() -> void:
	_saved_skip_intro = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true

	await _open()
	await case("the player wakes up wrecked and Flagged, and Trobairitz comes", _test_wakes_up)
	await case("before her lessons the player can't drive, dash or raise the shield", _test_lessons_first)
	await case("the onboarding plays through in order", _test_plays_through)
	await case("extracting finishes the onboarding and goes to the menu", _test_extract)
	await _close()

	await _open()
	await case("dying in the onboarding loses nothing and starts it again", _test_death)
	await _close()

	await _open()
	await case("shooting Trobairitz stops the scene and she fights back", _test_shot_at)
	await case("killing Trobairitz takes her out for good; her kit stays for the player", _test_killed)
	await _close()

	Debug.debug_settings["skip_intro"] = _saved_skip_intro


func _open() -> void:
	PlayerProgress.reset()
	StoryDirector.reset(false)
	TransitionManager.captured.clear()
	_seen = []
	_gap_when_she_speaks = INF
	_sight_when_she_speaks = 0.0
	_seen_when_she_speaks = false
	_camera_off_player = INF
	_gap_at_the_kit = 0.0
	_hud_when_she_speaks_again = ""
	_camera_on_her_at_the_door = INF
	_in_frame_when_she_leaves = true
	_past_frame_when_she_leaves = INF
	_scene = ONBOARDING.instantiate()
	add_child(_scene)
	var started := await wait_until(func(): return _stage() != null and _stage().is_playing, 20.0)
	check(started, "the onboarding scene started")
	if started:
		_stage().step_started.connect(_on_step_started)


func _on_step_started(step: StageStep) -> void:
	_seen.append(step.name)
	if step.name == "Repaired":
		var hud = _scene.PlayerHUD
		_hud_when_she_speaks_again = "booting" if hud.is_booting() else ("dark" if hud.is_dark() else "up")
	var trobairitz = _trobairitz()
	if trobairitz == null:
		return
	var player = _scene.player
	var gap: float = trobairitz.global_position.distance_to(player.global_position)
	if step.name == "FindsThePlayer":
		_gap_when_she_speaks = gap
		_sight_when_she_speaks = player.sight_radius()
		_seen_when_she_speaks = player.can_see_body(trobairitz)
		_camera_off_player = get_viewport().get_camera_2d().get_screen_center_position().distance_to(player.global_position)
	elif step.name == "GrabKit":
		_gap_at_the_kit = gap
	elif step.name == "OutOfSight":
		_camera_on_her_at_the_door = _camera_centre().distance_to(trobairitz.global_position)
	elif step.name == "LeaveMap":
		_in_frame_when_she_leaves = _camera_frame().has_point(trobairitz.global_position)
		var frame := _camera_frame()
		_past_frame_when_she_leaves = frame.position.y - trobairitz.global_position.y


func _camera_centre() -> Vector2:
	return get_viewport().get_camera_2d().get_screen_center_position()


func _camera_frame() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	return Rect2(_camera_centre() - size / 2.0, size)


func _close() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		await wait_frames(2)
	_scene = null


func _stage() -> StageDirector:
	if not is_instance_valid(_scene):
		return null
	var stage = _scene.current_stage
	return stage if is_instance_valid(stage) else null


func _trobairitz():
	if not is_instance_valid(_scene):
		return null
	for mecha in _scene.all_mechas:
		if is_instance_valid(mecha) and mecha.mecha_name == Onboarding.TROBAIRITZ:
			return mecha
	return null


func _play_through(timeout := 90.0, until := "") -> bool:
	var director := _stage()
	var handled: Array = []
	var waited := 0.0
	while is_instance_valid(director) and director.is_playing:
		if waited >= timeout:
			return false
		var step = director.current_step
		if until != "" and step != null and step.name == until:
			return true
		if step is StageSay and not director.get_dialogue().is_revealing():
			step.advance()
		elif step is StageWaitForPlayer and step.is_running() and not step in handled:
			handled.append(step)
			_take_turn(step, director)
		await get_tree().process_frame
		waited += get_process_delta_time()
	return true


func _take_turn(turn: StageWaitForPlayer, director: StageDirector) -> void:
	var player = _scene.player
	if turn.player_signal == "systems_repaired":
		var kit = director.find_actor("Kit")
		if kit != null:
			kit.interact(player)
	elif turn.travel > 0.0:
		player.global_position += Vector2.LEFT * (turn.travel + 50.0)
	elif turn.action != "":
		_send(turn.action, true)
		await wait_until(func(): return not turn.is_running(), 5.0)
		await wait_frames(2)
		_send(turn.action, false)
	elif turn.flag_down:
		player.lower_flag()


func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _test_wakes_up() -> void:
	var player = _scene.player
	check(player.is_exposed and player.is_flagged(), "the player is in the emergency state, Flag up")
	check(player.disabled_systems.sensors < 1.0 and player.disabled_systems.shield_regen == 0.0, "with its systems down")
	check(not player.disabled_systems.left_arm_weapon and not player.disabled_systems.right_arm_weapon, "but its weapons up")
	check(_trobairitz() != null, "Trobairitz is on the map")
	await wait_frames(2)
	check(_scene.PlayerHUD.is_dark(), "the HUD is dark")
	check(not _trobairitz().get_node("Debug/StateLabel").visible, "and Trobairitz shows no AI debug label")
	check(_scene.Heatmap.mask_state().on, "the scene keeps the player's view cut to its sight circle")
	check(not StoryDirector.has_flag(Onboarding.DONE_FLAG), "the onboarding isn't done yet")


func _test_lessons_first() -> void:
	var player = _scene.player
	var turn := await _play_through(60.0, "GrabKit")
	var handed := await wait_until(func(): return not player.controls_locked, 5.0)
	check(turn and handed, "the player has a turn, to grab the kit")
	var start: Vector2 = player.global_position

	Input.action_press("right")
	Input.action_press("down")
	await wait_seconds(1.0)
	for pressed in [true, false]:
		var dash := InputEventAction.new()
		dash.action = "thruster_dash"
		dash.pressed = pressed
		Input.parse_input_event(dash)
		await wait_frames(2)
	Input.action_release("right")
	Input.action_release("down")
	var shield := InputEventAction.new()
	shield.action = "shield"
	shield.pressed = true
	Input.parse_input_event(shield)
	await wait_frames(2)
	shield.pressed = false
	Input.parse_input_event(shield)

	check(player.global_position.distance_to(start) < 5.0, "neither driving nor dashing moved it (%d px)" % roundi(player.global_position.distance_to(start)))
	check(not player.shield_wanted, "and the shield stayed down")


func _test_plays_through() -> void:
	var finished := await _play_through()
	check(finished, "the scene ran to its end")

	var player = _scene.player
	var order := _seen.filter(func(step_name): return step_name in ORDER)
	check_eq(order, ORDER, "the reboot, kit, lessons, her leaving, the way out and the Flag came in that order")
	check(_gap_when_she_speaks < _sight_when_she_speaks, "Trobairitz walked into the player's sight before speaking (gap %d of %d)" % [roundi(minf(_gap_when_she_speaks, 99999.0)), roundi(_sight_when_she_speaks)])
	check(_seen_when_she_speaks, "where the player sees her")
	check(_gap_at_the_kit > CLEAR_OF_THE_PLAYER, "and she stopped clear of the player (gap %d)" % roundi(_gap_at_the_kit))
	check(_camera_off_player < 100.0, "with the camera on the player (%d off)" % roundi(minf(_camera_off_player, 99999.0)))
	check(not player.is_exposed, "the kit repaired the player")
	check_eq(_hud_when_she_speaks_again, "up", "and the HUD booted in the player's turn, before she spoke again")
	check(not player.is_flagged(), "the player lowered the Flag")
	check(not player.is_shielding and not player.is_sprinting, "the shield and dash held through a lesson's end were let go")
	check(_trobairitz() == null, "Trobairitz left the map")
	check(_camera_on_her_at_the_door < 200.0, "the camera followed her to the door (%d off)" % roundi(minf(_camera_on_her_at_the_door, 99999.0)))
	check(not _in_frame_when_she_leaves, "and she walked out of its frame before she went")
	check(_past_frame_when_she_leaves < 400.0, "going as soon as she was out of it (%d past the edge)" % roundi(minf(_past_frame_when_she_leaves, 99999.0)))
	check(not player.controls_locked, "the player has control")
	var mission = MissionManager.current_mission
	check(mission != null and mission.objectives.any(func(o): return o.type == "extract"), "the goal now is to extract")


func _test_extract() -> void:
	var player = _scene.player
	player.emit_signal("mecha_extracted", player)
	var left := await wait_until(func(): return TransitionManager.captured.has("res://game/start_menu/StartMenu.tscn"), 10.0)

	check(left, "extracting goes to the main menu")
	check(StoryDirector.has_flag(Onboarding.DONE_FLAG), "and the onboarding is done")
	check(not PlayerProgress.is_in_expedition(), "it was never an expedition")


func _test_death() -> void:
	var design: Dictionary = PlayerProgress.get_current_mecha().duplicate()
	_scene.player.die({"name": "Test"}, "test")
	var restarted := await wait_until(func(): return TransitionManager.captured.has(Onboarding.SCENE_PATH), 15.0)

	check(restarted, "dying starts the onboarding again")
	check_eq(PlayerProgress.get_current_mecha(), design, "the mecha was not lost")
	check(not PlayerProgress.has_loss_report(), "nothing was reported lost")
	check(not StoryDirector.has_flag(Onboarding.DONE_FLAG), "the onboarding is still to do")



func _test_shot_at() -> void:
	var player = _scene.player
	var trobairitz = _trobairitz()
	var turn := await _play_through(60.0, "GrabKit")
	check(turn and not player.controls_locked, "the player has a turn, and control")
	player.lower_flag()
	var down := await wait_until(func(): return not player.is_flagged(), Mecha.FLAG_LOWER_TIME + 2.0)
	check(down, "the player lowered the Flag to shoot")

	EntityAttack.hit_through(player, trobairitz, 1)
	trobairitz.add_hostility(player, 1.0)
	var stopped := await wait_until(func(): return _stage() == null, 10.0)

	check(stopped, "the scene stopped")
	check(not trobairitz.scripted and not trobairitz.paused, "she is her own pilot again")
	check(not _scene.player.controls_locked, "the player has control")
	check(not _scene.player.is_withheld("move") and not _scene.player.is_withheld("shield"), "all of it, lessons or not")
	var fights := await wait_until(func(): return is_same(trobairitz.valid_target, _scene.player), 10.0)
	check(fights, "she turns on the player")


func _test_killed() -> void:
	var trobairitz = _trobairitz()
	trobairitz.die({"name": "Player"}, "test")
	var gone := await wait_until(func(): return _trobairitz() == null, 10.0)

	check(gone, "she died")
	check(StoryDirector.has_flag(Onboarding.TROBAIRITZ_DEAD), "she is marked dead for good")
	var kits: Array = _scene.get_children().filter(func(n): return n is RepairKit)
	check_eq(kits.size(), 1, "the repair kit she dropped is still there for the player")
