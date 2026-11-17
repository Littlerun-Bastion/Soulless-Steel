extends TestSuite

const ONBOARDING := preload("res://game/onboarding/Onboarding.tscn")
const ORDER: Array[String] = ["RemoteReboot", "DropKit", "GrabKit", "Drive", "Dash", "Shield", "LeaveMap", "FindTheExit", "LowerFlag"]
const IN_THE_DOORWAY := Vector2(-1000, 2470)
const CLEAR_OF_THE_PLAYER := 190.0
const CARD_READ_TIME := 2.5
const HEAVY_VCR := "IntroAnimation/VCREffect:visible"
const LIGHT_VCR := "IntroAnimation/VCREffect2:visible"
const STATIC_BURST := "IntroAnimation/Ent_misc4:playing"
const CALM_NOISE_QUALITY := 2000.0
const OPENING_FRAMES := 10
const ARENA_COLOUR_SPLIT := 0.026
const SCREEN_EDGE_MARGIN := 60.0
const INTRO := preload("res://game/ui/IntroAnimation.tscn")
const COMMAND_TEXT := "IntroAnimation/CommandLine:text"
const COMMAND_SHOWN := "IntroAnimation/CommandLine:visible_ratio"

var _scene = null
var _seen: Array[String] = []
var _gap_when_she_speaks := INF
var _sight_when_she_speaks := 0.0
var _seen_when_she_speaks := false
var _camera_off_player := INF
var _gap_at_the_kit := 0.0
var _hud_when_she_speaks_again := ""
var _ring_before_the_lesson := true
var _ring_at_the_lesson := false
var _camera_on_her_at_the_door := INF
var _in_frame_when_she_leaves := true
var _past_frame_when_she_leaves := INF
var _saved_skip_intro = null
var _noise_quality_at_start := 0.0
var _colour_split_at_start := 0.0


func _init() -> void:
	slow = true
	time_scale = 1.0
	case_timeout = 120


func run_tests() -> void:
	_saved_skip_intro = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true

	await _open()
	await case("the player wakes up wrecked and Flagged, and Trobairitz comes", _test_wakes_up)
	await case("the boot screen tells the onboarding's own story", _test_own_boot_screen)
	await case("the boot screen is readable all through, with time to read its card", _test_boot_screen_readable)
	await case("the boot text sits clear of the screen's edges", _test_boot_text_clear_of_edges)
	await case("each boot command is typed before what it brings up", _test_commands_lead)
	await case("before her lessons the player can't drive, dash or raise the shield", _test_lessons_first)
	await case("the onboarding plays through in order", _test_plays_through)
	await case("extracting finishes the onboarding and goes to the menu", _test_extract)
	await _close()

	await _open()
	await case("after the boot the screen shows the damage, and the repair clears it", _test_damaged_screen)
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
	_ring_before_the_lesson = true
	_ring_at_the_lesson = false
	_camera_on_her_at_the_door = INF
	_in_frame_when_she_leaves = true
	_past_frame_when_she_leaves = INF
	_scene = ONBOARDING.instantiate()
	add_child(_scene)
	_noise_quality_at_start = INF
	_colour_split_at_start = 0.0
	var screen: ShaderMaterial = ShaderEffects.VCREffect.material
	var booting := [true]
	_scene.IntroAnimation.animation_ending.connect(func(): booting[0] = false, CONNECT_ONE_SHOT)
	for i in OPENING_FRAMES:
		await wait_frames(1)
		if not booting[0]:
			break
		_noise_quality_at_start = minf(_noise_quality_at_start, screen.get_shader_parameter("noiseQuality"))
		_colour_split_at_start = maxf(_colour_split_at_start, screen.get_shader_parameter("colorOffsetIntensity"))
	var started := await wait_until(func(): return _stage() != null and _stage().is_playing, 20.0)
	check(started, "the onboarding scene started")
	if started:
		_stage().step_started.connect(_on_step_started)


func _on_step_started(step: StageStep) -> void:
	_seen.append(step.name)
	if step.name == "FindTheExit":
		_ring_before_the_lesson = _flag_ring_shown()
	elif step.name == "OneMoreThing":
		_ring_at_the_lesson = _flag_ring_shown()
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


func _flag_ring_shown() -> bool:
	var marker = _scene.player._flag_marker
	return is_instance_valid(marker) and marker.is_visible_in_tree()


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
		player.global_position = IN_THE_DOORWAY
		player.global_rotation = PI / 2.0
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


func _screen_texts(animation: Animation) -> Array:
	var track := animation.find_track(NodePath("IntroAnimation/ScreenText:text"), Animation.TYPE_VALUE)
	var texts := []
	for i in animation.track_get_key_count(track):
		texts.append(animation.track_get_key_value(track, i))
	return texts


func _test_own_boot_screen() -> void:
	var intro: AnimationPlayer = _scene.IntroAnimation.get_node("AnimationPlayer")
	var played := intro.get_animation(intro.assigned_animation)
	var texts := _screen_texts(played)
	var first_line: String = _screen_lines()[0]

	check(intro.assigned_animation != "Entrance", "it is not the usual boot")
	check(texts.any(func(t): return first_line in t), "it types the onboarding's boot text")
	check(texts.any(func(t): return _scene.boot_card in t), "and ends on its own card")
	check(not texts.any(func(t): return "Good hunting" in t), "with nothing of the usual boot's")
	check(_screen_texts(intro.get_animation("Entrance")).any(func(t): return "Good hunting" in t), "which is left as it was for the other modes")


func _test_boot_screen_readable() -> void:
	var intro: AnimationPlayer = _scene.IntroAnimation.get_node("AnimationPlayer")
	var played := intro.get_animation(intro.assigned_animation)
	var usual := intro.get_animation("Entrance")
	var lines := _screen_lines()
	var first_line: String = lines[0]
	var half_line := first_line.substr(0, first_line.length() / 2)
	var text_at := _first_time(played, func(t): return t != "")
	var typed_at := _first_time(played, func(t): return t.ends_with(lines[lines.size() - 1]))
	var card_at := _first_time(played, func(t): return _scene.boot_card in t)
	var ending := _method_time(played, &"entrance_animation_ending")

	check(_screen_texts(played).any(func(t): return t.ends_with(half_line)), "its lines type out")
	check(card_at - typed_at >= 0.5, "the last line is up a moment before the card (%.2fs)" % (card_at - typed_at))
	check(ending - card_at >= CARD_READ_TIME, "and the card %.1fs before the scene takes over (%.2fs)" % [CARD_READ_TIME, ending - card_at])
	check(not _ever_true(played, HEAVY_VCR), "the heavy VCR never smears it")
	check(_value_at(played, LIGHT_VCR, text_at) and _value_at(played, LIGHT_VCR, card_at), "the light one is on from its first line to its card")
	check(not played.track_is_enabled(played.find_track(NodePath(STATIC_BURST), Animation.TYPE_VALUE)), "without the static burst that marks a smeared screen clearing")
	check(_noise_quality_at_start >= CALM_NOISE_QUALITY, "and the screen isn't ramped in from noise (%d)" % _noise_quality_at_start)
	check(_colour_split_at_start <= ARENA_COLOUR_SPLIT, "or split in colour like a damaged screen (%.3f)" % _colour_split_at_start)
	check(_value_at(usual, HEAVY_VCR, 5.0) and usual.track_is_enabled(usual.find_track(NodePath(STATIC_BURST), Animation.TYPE_VALUE)),
			"the other modes keep their boot as it was")


func _test_boot_text_clear_of_edges() -> void:
	var screen := get_viewport().get_visible_rect().grow(-SCREEN_EDGE_MARGIN)
	for label_name in ["ScreenText", "CommandLine"]:
		var label: Control = _scene.IntroAnimation.get_node(label_name)
		var box := label.get_global_rect()
		check(box.position.x >= screen.position.x and box.end.y <= screen.end.y,
				"%s is %d px from the left and %d from the bottom" % [label_name, box.position.x, get_viewport().get_visible_rect().end.y - box.end.y])

	var usual: Node = INTRO.instantiate()
	add_child(usual)
	check(usual.get_node("ScreenText").get_global_rect().position.x < screen.position.x, "the other modes' boot text stays where it was")
	usual.free()


func _test_damaged_screen() -> void:
	var screen: ShaderMaterial = ShaderEffects.VCREffect.material
	var torn := await wait_until(func(): return screen.get_shader_parameter("noiseIntensity") > 0.0 \
			and screen.get_shader_parameter("colorOffsetIntensity") > ARENA_COLOUR_SPLIT, 3.0)
	check(torn, "the crippled mech's screen tears and splits (noise %.4f, split %.3f)" % [screen.get_shader_parameter("noiseIntensity"), screen.get_shader_parameter("colorOffsetIntensity")])

	_scene.player.repair_systems()
	var cleared := await wait_until(func(): return screen.get_shader_parameter("noiseIntensity") < 0.0001 \
			and screen.get_shader_parameter("colorOffsetIntensity") <= ARENA_COLOUR_SPLIT + 0.001, 3.0)
	check(cleared, "and settles back once it is repaired (noise %.4f, split %.3f)" % [screen.get_shader_parameter("noiseIntensity"), screen.get_shader_parameter("colorOffsetIntensity")])


func _screen_lines() -> Array:
	return Array(_scene.boot_text.split("\n")).filter(func(line): return not line.begins_with(_scene.IntroAnimation.COMMAND_MARK))


func _test_commands_lead() -> void:
	var intro: AnimationPlayer = _scene.IntroAnimation.get_node("AnimationPlayer")
	var played := intro.get_animation(intro.assigned_animation)
	var lines: PackedStringArray = _scene.boot_text.split("\n")
	var commands := 0
	for i in lines.size() - 1:
		if not lines[i].begins_with(_scene.IntroAnimation.COMMAND_MARK):
			continue
		commands += 1
		var command := lines[i].trim_prefix(_scene.IntroAnimation.COMMAND_MARK)
		var next_line := lines[i + 1]
		var typed_at := _command_typed_at(played, command)
		var output_at := _first_time(played, func(t): return t.ends_with(next_line.left(1)) and (t.count("\n") >= _screen_lines().find(next_line)))
		check(typed_at < output_at, "%s is typed (%.2fs) before \"%s\" comes up (%.2fs)" % [command, typed_at, next_line.left(20), output_at])

	check(commands >= 3, "the boot text has its commands (%d)" % commands)
	check(not _screen_texts(played).any(func(t): return _scene.IntroAnimation.COMMAND_MARK in t), "and none of them shows among the screen's lines")


func _command_typed_at(animation: Animation, command: String) -> float:
	var text_track := animation.find_track(NodePath(COMMAND_TEXT), Animation.TYPE_VALUE)
	var shown_track := animation.find_track(NodePath(COMMAND_SHOWN), Animation.TYPE_VALUE)
	for i in animation.track_get_key_count(text_track):
		if animation.track_get_key_value(text_track, i) != command:
			continue
		var start := animation.track_get_key_time(text_track, i)
		for k in animation.track_get_key_count(shown_track):
			if animation.track_get_key_time(shown_track, k) >= start and animation.track_get_key_value(shown_track, k) >= 1.0:
				return animation.track_get_key_time(shown_track, k)
	return INF


func _first_time(animation: Animation, matches: Callable) -> float:
	var track := animation.find_track(NodePath("IntroAnimation/ScreenText:text"), Animation.TYPE_VALUE)
	for i in animation.track_get_key_count(track):
		if matches.call(animation.track_get_key_value(track, i)):
			return animation.track_get_key_time(track, i)
	return INF


func _method_time(animation: Animation, method: StringName) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for i in animation.track_get_key_count(track):
			if animation.method_track_get_name(track, i) == method:
				return animation.track_get_key_time(track, i)
	return INF


func _ever_true(animation: Animation, path: String) -> bool:
	var track := animation.find_track(NodePath(path), Animation.TYPE_VALUE)
	for i in animation.track_get_key_count(track):
		if animation.track_get_key_value(track, i):
			return true
	return false


func _value_at(animation: Animation, path: String, time: float):
	return animation.value_track_interpolate(animation.find_track(NodePath(path), Animation.TYPE_VALUE), time)


func _test_wakes_up() -> void:
	var player = _scene.player
	check(player.is_exposed and player.is_flagged(), "the player is in the emergency state, Flag up")
	check(player.disabled_systems.sensors < 1.0 and player.disabled_systems.shield_regen == 0.0, "with its systems down")
	check(not player.disabled_systems.left_arm_weapon and not player.disabled_systems.right_arm_weapon, "but its weapons up")
	check(_trobairitz() != null, "Trobairitz is on the map")
	await wait_frames(2)
	check(_scene.PlayerHUD.is_dark(), "the HUD is dark")
	check(not _flag_ring_shown(), "and the player's Flag ring is kept off the screen")
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
	check(not _ring_before_the_lesson and _ring_at_the_lesson, "the Flag ring showed only once she came to the Flag")
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
	check(not _scene.player.hides_flag_marker, "its Flag ring is no longer kept hidden")
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
