extends TestSuite

const WALK_SPEED := 400.0
const WALK_DISTANCE := 1200.0
const SLOW_REVEAL_SECONDS := 3.0
const SLOW_CAMERA_SPEED := 1.0
const FREEZE_SWEEP_LONGER_THAN := StageDirector.FREEZE_SWEEP_INTERVAL


class RecordingStep extends StageStep:
	var order_log: Array = []
	var label := ""

	func _start() -> void:
		order_log.append(label)
		_finish()


class FakeActor extends Node2D:
	var mecha_name := ""

	func _ready() -> void:
		add_to_group("mecha")


class FakeSpeaker extends Node2D:
	var mecha_name := ""
	var heard: Array = []

	func _ready() -> void:
		add_to_group("mecha")

	func say(text: String, _seconds: float, _always_heard: bool) -> void:
		heard.append(text)


class FakeBystander extends Node2D:
	var paused := false

	func _ready() -> void:
		add_to_group("mecha")

	func set_pause(value: bool) -> void:
		paused = value


class FakeMech extends Node2D:
	var mecha_name := ""
	var scripted := false
	var scripted_destination = null
	var scripted_aim = null
	var walk_speed := 500.0
	var shots_fired: Array = []

	func _ready() -> void:
		add_to_group("mecha")

	func set_scripted(value: bool) -> void:
		scripted = value

	func walk_to(point) -> void:
		scripted_destination = point

	func stop_walking() -> void:
		scripted_destination = null

	func shoot(weapon_type, _is_auto_fire = false) -> void:
		shots_fired.append(weapon_type)

	func _process(dt: float) -> void:
		if scripted_destination == null:
			return
		global_position = global_position.move_toward(scripted_destination, walk_speed * dt)


class FlaggedMech extends FakeMech:
	var marker_shown := false

	func show_flag_marker() -> void:
		marker_shown = true


class SlidingMech extends FakeMech:
	var slide := 200.0

	func stopping_distance() -> float:
		return slide


class FakeHud extends Node:
	var booting := false

	func is_booting() -> bool:
		return booting

	func set_cinematic(_on: bool) -> void:
		pass


class FakeScene extends Node2D:
	var player = null
	var PlayerHUD = null

	func activate_arena_cam() -> void:
		pass


class FakePlayer extends Node2D:
	signal systems_repaired

	var controls_locked := false
	var flagged := false
	var cam: Camera2D = null
	var withheld := {}

	func _ready() -> void:
		add_to_group("mecha")
		cam = Camera2D.new()
		add_child(cam)

	func is_player() -> bool:
		return true

	func get_cam() -> Camera2D:
		return cam

	func is_flagged() -> bool:
		return flagged

	func lock_controls() -> void:
		controls_locked = true

	func unlock_controls() -> void:
		controls_locked = false

	func withhold(ability: String) -> void:
		withheld[ability] = true

	func grant(ability: String) -> void:
		withheld.erase(ability)


func run_tests() -> void:
	await case("an empty director plays and finishes", _test_empty_director)
	await case("steps run in tree order", _test_tree_order)
	await case("only StageStep children are steps", _test_ignores_other_children)
	await case("a wait holds back later steps", _test_wait_holds)
	await case("a wait releases on its own", _test_wait_releases)
	await case("skipping ends the run early", _test_skip_ends_run)
	await case("playing while already playing is ignored", _test_play_twice)
	await case("cinema bars come in and go out with the scene", _test_bars)
	await case("bars can be turned off", _test_bars_disabled)
	await case("the scene takes control and gives it back", _test_takes_control)
	await case("bystanders stay thawed while the bars go away", _test_thawed_after_bars)
	await case("a player turn hands control over and takes it back", _test_player_turn_hands_over)
	await case("a player turn ends when the player presses its action", _test_player_turn_action)
	await case("a player turn ends once the player has moved far enough", _test_player_turn_travel)
	await case("a player turn ends on a signal from the player", _test_player_turn_signal)
	await case("a player turn ends once the Flag is down, even if it already is", _test_player_turn_flag_down)
	await case("a player turn keeps its instruction on screen", _test_player_turn_hint)
	await case("a player turn holds until the HUD has booted", _test_player_turn_waits_for_the_hud)
	await case("a scene withholds what it hasn't taught; the turn that teaches it grants it", _test_withheld_until_taught)
	await case("whatever is still withheld comes back when the scene ends", _test_withheld_back_at_the_end)
	await case("taking control can be turned off", _test_control_disabled)
	await case("look-at drives the camera to its own position", _test_camera_look_at)
	await case("look-at can hold until the camera arrives", _test_camera_waits)
	await case("follow tracks an actor that keeps moving", _test_camera_follows_mover)
	await case("the camera is handed back when the scene ends", _test_camera_released)
	await case("a scene with no player leaves the camera alone", _test_camera_left_alone_without_a_player)
	await case("a line holds the scene until it is advanced", _test_say_waits)
	await case("the first press finishes the reveal, the second advances", _test_say_two_stage)
	await case("a player action button advances a line", _test_say_input)
	await case("a timed line advances on its own", _test_say_timed)
	await case("a timed line does not ask for a key", _test_timed_line_has_no_prompt)
	await case("a line names the key bound to an action", _test_say_names_keys)
	await case("an actor's spoken line names keys too", _test_actor_say_names_keys)
	await case("the dialogue is actually on screen", _test_dialogue_is_visible)
	await case("a line is a subtitle in the bottom bar, centred on a dark box", _test_dialogue_in_the_bar)
	await case("even a long line fits in the bottom bar", _test_long_line_in_the_bar)
	await case("a line ended early never clears a later one", _test_timed_line_does_not_bleed)
	await case("pausing holds the scene where it is", _test_pause_holds_the_scene)
	await case("aborting ends the scene without running the rest", _test_abort_ends_the_scene)
	await case("an actor walks to a mark and the scene waits", _test_move_actor)
	await case("an actor walks to another actor that keeps moving", _test_move_to_actor)
	await case("an actor that slides is stopped early enough to come to rest at the mark", _test_move_actor_slides)
	await case("a walk can end as soon as the actor is out of the camera's frame", _test_move_actor_out_of_frame)
	await case("an actor shoots a target a set number of times", _test_actor_shoot)
	await case("a scene can put a thing on the map, under a name", _test_spawn)
	await case("an overlay plays over the scene, which waits for it", _test_overlay)
	await case("a step shows an actor's Flag marker, skipped or not", _test_show_flag_marker)
	await case("skipping takes an overlay off at once", _test_overlay_skipped)


func _make_director() -> StageDirector:
	var director := StageDirector.new()
	add_child(director)
	return director


func _test_empty_director() -> void:
	var director := _make_director()
	var counts := {"started": 0, "finished": 0}
	director.started.connect(func(): counts["started"] += 1)
	director.finished.connect(func(): counts["finished"] += 1)

	await director.play()

	check_eq(counts["started"], 1, "emitted started once")
	check_eq(counts["finished"], 1, "emitted finished once")
	check(not director.is_playing, "not playing once it finished")
	director.queue_free()


func _test_tree_order() -> void:
	var director := _make_director()
	var order: Array = []
	for label in ["a", "b", "c"]:
		var step := RecordingStep.new()
		step.order_log = order
		step.label = label
		director.add_child(step)

	await director.play()

	check_eq(order, ["a", "b", "c"], "steps ran in tree order")
	director.queue_free()


func _test_ignores_other_children() -> void:
	var director := _make_director()
	director.add_child(Marker2D.new())
	var step := StageWait.new()
	step.seconds = 0.0
	director.add_child(step)

	check_eq(director.get_steps().size(), 1, "the Marker2D is not counted as a step")

	await director.play()

	check(not director.is_playing, "finished with a non-step child present")
	director.queue_free()


func _test_wait_holds() -> void:
	var director := _make_director()
	var step := StageWait.new()
	step.seconds = 30.0
	director.add_child(step)
	var order: Array = []
	var later := RecordingStep.new()
	later.order_log = order
	later.label = "after"
	director.add_child(later)

	director.play()
	await wait_frames(3)

	check(director.is_playing, "still playing while the wait holds")
	check(order.is_empty(), "the step after the wait has not run yet")

	director.skip()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_wait_releases() -> void:
	var director := _make_director()
	var step := StageWait.new()
	step.seconds = 0.2
	director.add_child(step)

	director.play()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)

	check(ended, "the wait released the run without a skip")
	check(not director.is_skipping, "released by its timer, not by skipping")
	director.queue_free()


func _test_skip_ends_run() -> void:
	var director := _make_director()
	for _i in 2:
		var step := StageWait.new()
		step.seconds = 30.0
		director.add_child(step)

	director.play()
	await wait_frames(2)
	check(director.is_playing, "running before the skip")

	director.skip()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "skipping ended the run without waiting the steps out")
	director.queue_free()


func _test_play_twice() -> void:
	var director := _make_director()
	var step := StageWait.new()
	step.seconds = 30.0
	director.add_child(step)

	director.play()
	await wait_frames(1)

	var restarts := [0]
	director.started.connect(func(): restarts[0] += 1)
	director.play()
	await wait_frames(1)
	check_eq(restarts[0], 0, "the second play was ignored")

	director.skip()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_bars() -> void:
	var director := _make_director()
	var step := StageWait.new()
	step.seconds = 30.0
	director.add_child(step)

	director.play()
	var built := await wait_until(func(): return director.get_bars() != null, 5.0)
	check(built, "the director built its bars")

	var grew := await wait_until(func(): return director.get_bars().is_shown(), 5.0)
	check(grew, "the bars came in while the scene ran")

	director.skip()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "the scene ended")

	var gone := await wait_until(func(): return not director.get_bars().is_shown(), 5.0)
	check(gone, "the bars went back out")
	director.queue_free()


func _test_bars_disabled() -> void:
	var director := _make_director()
	director.shows_bars = false
	var step := StageWait.new()
	step.seconds = 0.0
	director.add_child(step)

	await director.play()

	check(director.get_bars() == null, "no bars were built when they are turned off")
	director.queue_free()


func _player_turn_scene(turn: StageWaitForPlayer) -> Array:
	var alone := await wait_until(func(): return _players_left().is_empty(), 2.0)
	check(alone, "no player is left over from an earlier case")
	var player := FakePlayer.new()
	add_child(player)
	var director := _make_director()
	director.add_child(turn)
	var after := StageWait.new()
	after.seconds = 30.0
	director.add_child(after)
	return [director, player, after]


func _players_left() -> Array:
	return get_tree().get_nodes_in_group("mecha").filter(func(n): return n.has_method("is_player") and n.is_player())


func _end_player_turn_scene(scene: Array) -> void:
	scene[0].abort()
	await wait_until(func(): return not scene[0].is_playing, 5.0)
	scene[0].queue_free()
	scene[1].queue_free()


func _test_player_turn_hands_over() -> void:
	var turn := StageWaitForPlayer.new()
	turn.player_signal = "systems_repaired"
	var scene := await _player_turn_scene(turn)
	var director: StageDirector = scene[0]
	var player: FakePlayer = scene[1]

	director.play()
	await wait_frames(2)
	check(director.current_step == turn, "the scene is on the player's turn")
	check(not player.controls_locked, "the player has control during it")
	var bars_gone := await wait_until(func(): return not director.get_bars().is_shown(), 5.0)
	check(bars_gone, "the bars go away while the player plays")

	player.systems_repaired.emit()
	await wait_frames(2)
	check(director.current_step == scene[2], "the scene moved on")
	check(player.controls_locked, "control was taken back")
	var bars_back := await wait_until(func(): return director.get_bars().is_shown(), 5.0)
	check(bars_back, "and the bars came back")
	await _end_player_turn_scene(scene)


func _test_player_turn_waits_for_the_hud() -> void:
	var alone := await wait_until(func(): return _players_left().is_empty(), 2.0)
	check(alone, "no player is left over from an earlier case")
	var scene := FakeScene.new()
	scene.PlayerHUD = FakeHud.new()
	scene.add_child(scene.PlayerHUD)
	add_child(scene)
	var player := FakePlayer.new()
	scene.add_child(player)
	scene.player = player
	var director := StageDirector.new()
	scene.add_child(director)
	var turn := StageWaitForPlayer.new()
	turn.player_signal = "systems_repaired"
	director.add_child(turn)
	var after := StageWait.new()
	after.seconds = 30.0
	director.add_child(after)
	director.play()
	await wait_frames(2)

	scene.PlayerHUD.booting = true
	player.systems_repaired.emit()
	await wait_frames(4)
	check(director.current_step == turn, "the turn holds while the HUD boots")
	check(not player.controls_locked, "with the player still in control")

	scene.PlayerHUD.booting = false
	var moved := await wait_until(func(): return director.current_step == after, 2.0)
	check(moved, "and ends once it has booted")
	director.abort()
	await wait_until(func(): return not director.is_playing, 5.0)
	scene.queue_free()
	await wait_until(func(): return _players_left().is_empty(), 2.0)


func _test_withheld_until_taught() -> void:
	var turn := StageWaitForPlayer.new()
	turn.player_signal = "systems_repaired"
	turn.grants = ["move"]
	var scene := await _player_turn_scene(turn)
	var director: StageDirector = scene[0]
	var player: FakePlayer = scene[1]
	director.withholds = ["move", "dash"]

	director.play()
	await wait_frames(2)

	check(director.current_step == turn, "the scene is on the player's turn")
	check(not player.withheld.has("move"), "the turn grants what it teaches")
	check(player.withheld.has("dash"), "what no turn has taught yet stays withheld")
	await _end_player_turn_scene(scene)


func _test_withheld_back_at_the_end() -> void:
	var turn := StageWaitForPlayer.new()
	turn.player_signal = "systems_repaired"
	var scene := await _player_turn_scene(turn)
	var director: StageDirector = scene[0]
	var player: FakePlayer = scene[1]
	director.withholds = ["move", "dash"]
	director.play()
	await wait_frames(2)
	check(player.withheld.has("move") and player.withheld.has("dash"), "both are withheld in the scene")

	director.abort()
	await wait_until(func(): return not director.is_playing, 5.0)

	check(player.withheld.is_empty(), "an aborted scene gives them all back")
	director.queue_free()
	player.queue_free()


func _test_player_turn_action() -> void:
	var turn := StageWaitForPlayer.new()
	turn.action = "thruster_dash"
	var scene := await _player_turn_scene(turn)
	scene[0].play()
	await wait_frames(2)

	var other := InputEventAction.new()
	other.action = "shield"
	other.pressed = true
	Input.parse_input_event(other)
	await wait_frames(2)
	check(scene[0].current_step == turn, "another action does not end the turn")

	var dash := InputEventAction.new()
	dash.action = "thruster_dash"
	dash.pressed = true
	Input.parse_input_event(dash)
	var moved := await wait_until(func(): return scene[0].current_step == scene[2], 2.0)
	check(moved, "pressing its action ends the turn")
	var release := InputEventAction.new()
	release.action = "thruster_dash"
	Input.parse_input_event(release)
	await _end_player_turn_scene(scene)


func _test_player_turn_travel() -> void:
	var turn := StageWaitForPlayer.new()
	turn.travel = 500.0
	var scene := await _player_turn_scene(turn)
	var player: FakePlayer = scene[1]
	scene[0].play()
	await wait_frames(2)

	player.position += Vector2(300, 0)
	await wait_frames(2)
	check(scene[0].current_step == turn, "a short move is not enough")

	player.position += Vector2(0, 400)
	var moved := await wait_until(func(): return scene[0].current_step == scene[2], 2.0)
	check(moved, "moving far enough ends the turn")
	await _end_player_turn_scene(scene)


func _test_player_turn_signal() -> void:
	var turn := StageWaitForPlayer.new()
	turn.player_signal = "systems_repaired"
	var scene := await _player_turn_scene(turn)
	var player: FakePlayer = scene[1]
	scene[0].play()
	await wait_frames(2)
	check(scene[0].current_step == turn, "the turn waits for the signal")

	player.systems_repaired.emit()
	var moved := await wait_until(func(): return scene[0].current_step == scene[2], 2.0)
	check(moved, "the signal ends the turn")
	check(not player.systems_repaired.is_connected(turn._on_player_signal), "the turn let go of the signal")
	await _end_player_turn_scene(scene)


func _test_player_turn_flag_down() -> void:
	var turn := StageWaitForPlayer.new()
	turn.flag_down = true
	var scene := await _player_turn_scene(turn)
	var player: FakePlayer = scene[1]
	player.flagged = true
	scene[0].play()
	await wait_frames(3)
	check(scene[0].current_step == turn, "the turn waits while the Flag is up")

	player.flagged = false
	var moved := await wait_until(func(): return scene[0].current_step == scene[2], 2.0)
	check(moved, "lowering it ends the turn")
	await _end_player_turn_scene(scene)

	var again := StageWaitForPlayer.new()
	again.flag_down = true
	var down_already := await _player_turn_scene(again)
	down_already[0].play()
	var passed := await wait_until(func(): return down_already[0].current_step == down_already[2], 2.0)
	check(passed, "a Flag already down ends it at once")
	await _end_player_turn_scene(down_already)


func _test_player_turn_hint() -> void:
	var turn := StageWaitForPlayer.new()
	turn.player_signal = "systems_repaired"
	turn.speaker = "Trobairitz"
	turn.hint = "Grab the kit with {interact}."
	var scene := await _player_turn_scene(turn)
	var player: FakePlayer = scene[1]
	scene[0].play()
	var dialogue: StageDialogue = scene[0].get_dialogue()
	await wait_until(func(): return not dialogue.is_revealing(), 5.0)

	check_eq(dialogue.get_body_label().text, "Grab the kit with [%s]." % MechUI.key_name("interact"), "the instruction stays up, keys named")
	check_eq(dialogue.get_speaker_label().text, "Trobairitz", "with who said it")
	check(not dialogue.get_hint_label().visible, "with no prompt to press a key")

	player.systems_repaired.emit()
	await wait_frames(2)
	check_eq(dialogue.get_body_label().text, "", "it is cleared once the turn ends")
	await _end_player_turn_scene(scene)


func _test_thawed_after_bars() -> void:
	var bystander := FakeBystander.new()
	add_child(bystander)
	var director := _make_director()
	director.takes_control = false
	var wait := StageWait.new()
	wait.seconds = 0.5
	director.add_child(wait)

	director.play()
	await wait_frames(2)
	check(bystander.paused, "the scene froze the bystander")
	var ended := [false]
	director.finished.connect(func(): ended[0] = true)
	await wait_until(func(): return ended[0], 10.0)

	check(director.get_bars().transition_time > FREEZE_SWEEP_LONGER_THAN, "the bars took long enough to go that a sweep ran meanwhile")
	check(not bystander.paused, "it moves again once the scene is over")
	director.queue_free()
	bystander.queue_free()


func _test_takes_control() -> void:
	var player := FakePlayer.new()
	add_child(player)
	var director := _make_director()
	director.shows_bars = false
	var step := StageWait.new()
	step.seconds = 30.0
	director.add_child(step)

	check_eq(director.get_player(), player, "the director found the player by group")

	director.play()
	await wait_frames(1)
	check(player.controls_locked, "control was taken while the scene played")

	director.skip()
	await wait_until(func(): return not director.is_playing, 5.0)
	check(not player.controls_locked, "control came back when the scene ended")

	director.queue_free()
	player.queue_free()


func _test_control_disabled() -> void:
	var player := FakePlayer.new()
	add_child(player)
	var director := _make_director()
	director.shows_bars = false
	director.takes_control = false
	var step := StageWait.new()
	step.seconds = 0.0
	director.add_child(step)

	await director.play()

	check(not player.controls_locked, "control was left alone when taking it is turned off")
	director.queue_free()
	player.queue_free()


func _plain_director() -> StageDirector:
	var director := _make_director()
	director.shows_bars = false
	director.takes_control = false
	return director


func _test_camera_look_at() -> void:
	var director := _plain_director()
	var cam := Camera2D.new()
	add_child(cam)
	director.use_camera(cam)

	var step := StageCameraLookAt.new()
	step.global_position = Vector2(900, -400)
	step.snap = true
	director.add_child(step)

	await director.play()

	check_eq(cam.global_position, Vector2(900, -400), "snapping put the camera on the step")
	director.queue_free()
	cam.queue_free()


func _test_camera_waits() -> void:
	var director := _plain_director()
	var cam := Camera2D.new()
	add_child(cam)
	director.use_camera(cam)

	var step := StageCameraLookAt.new()
	step.global_position = Vector2(2000, 0)
	step.wait_until_reached = true
	director.add_child(step)
	director.get_camera().follow_speed = SLOW_CAMERA_SPEED
	var order: Array = []
	var later := RecordingStep.new()
	later.order_log = order
	later.label = "after"
	director.add_child(later)

	director.play()
	await wait_frames(2)
	check(order.is_empty(), "the next step waits while the camera travels")

	var arrived := await wait_until(func(): return not director.is_playing, 10.0)
	check(arrived, "the camera arrived and the scene moved on")
	check(cam.global_position.distance_to(Vector2(2000, 0)) <= step.reach_distance,\
	"the camera ended up at the step")
	director.queue_free()
	cam.queue_free()


func _test_camera_follows_mover() -> void:
	var director := _plain_director()
	var cam := Camera2D.new()
	add_child(cam)
	director.use_camera(cam)

	var mover := FakeActor.new()
	mover.mecha_name = "CamTarget"
	add_child(mover)

	var step := StageCameraFollow.new()
	step.actor = "CamTarget"
	step.snap = true
	director.add_child(step)
	var hold := StageWait.new()
	hold.seconds = 30.0
	director.add_child(hold)

	director.play()
	await wait_frames(1)
	check_eq(cam.global_position, mover.global_position, "the camera snapped onto the actor")

	var walked := 0.0
	for _i in 120:
		var dt := get_process_delta_time()
		mover.global_position += Vector2(WALK_SPEED * dt, 0.0)
		walked += WALK_SPEED * dt
		await get_tree().process_frame
		if walked >= WALK_DISTANCE:
			break

	check(walked >= WALK_DISTANCE, "the actor covered the ground the test needs")
	check(cam.global_position.x > WALK_DISTANCE * 0.5, "the camera travelled after the moving actor")
	check(cam.global_position.distance_to(mover.global_position) < WALK_DISTANCE * 0.5,\
	"the camera kept up instead of falling behind")

	director.skip()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()
	cam.queue_free()
	mover.queue_free()


func _test_camera_released() -> void:
	var director := _plain_director()
	var player := FakePlayer.new()
	add_child(player)
	var cam := Camera2D.new()
	cam.enabled = true
	add_child(cam)
	director.use_camera(cam)

	var step := StageWait.new()
	step.seconds = 0.0
	director.add_child(step)

	await director.play()

	check(not cam.enabled, "the stage camera switched itself off")
	check_eq(get_viewport().get_camera_2d(), player.get_cam(), "the player camera renders again")
	check(director.get_camera().get_target_position() == null, "the stage camera let go of its target")
	director.queue_free()
	cam.queue_free()
	player.queue_free()


func _test_camera_left_alone_without_a_player() -> void:
	var director := _plain_director()
	var alone := await wait_until(func(): return director.get_player() == null, 2.0)
	check(alone, "no player is left over from an earlier case")
	var cam := Camera2D.new()
	cam.enabled = true
	add_child(cam)
	director.use_camera(cam)

	var step := StageWait.new()
	step.seconds = 0.0
	director.add_child(step)

	await director.play()

	check(cam.enabled, "with no player to hand back to, the camera is left for the scene to keep")
	check(director.get_camera().get_target_position() == null, "it still let go of its target")
	director.queue_free()
	cam.queue_free()


func _say_step(director: StageDirector, line: String) -> StageSay:
	var step := StageSay.new()
	step.speaker = "NPC"
	step.text = line
	director.add_child(step)
	return step


func _slow_reveal(director: StageDirector, line: String) -> void:
	director.get_dialogue().reveal_speed = line.length() / SLOW_REVEAL_SECONDS


func _test_say_waits() -> void:
	var director := _plain_director()
	var step := _say_step(director, "hello player")
	var order: Array = []
	var later := RecordingStep.new()
	later.order_log = order
	later.label = "after"
	director.add_child(later)

	director.play()
	await wait_frames(2)

	check(director.is_playing, "the scene is held open by the line")
	check(order.is_empty(), "the next step waits for the line to be advanced")
	check_eq(director.get_dialogue().get_body_label().text, "hello player", "the line is on screen")
	check_eq(director.get_dialogue().get_speaker_label().text, "NPC", "the speaker is named")

	await wait_until(func(): return not director.get_dialogue().is_revealing(), 5.0)
	check(director.is_playing, "a fully revealed line still waits for the player")

	step.advance()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "advancing moved the scene on")
	check_eq(order, ["after"], "the step after the line ran")
	check_eq(director.get_dialogue().get_body_label().text, "", "the line was cleared")
	director.queue_free()


func _test_say_two_stage() -> void:
	var director := _plain_director()
	var step := _say_step(director, "a line long enough that it is still being revealed")
	_slow_reveal(director, step.text)

	director.play()
	await wait_frames(1)
	check(director.get_dialogue().is_revealing(), "the line starts out revealing")

	step.advance()
	check(not director.get_dialogue().is_revealing(), "the first press finished the reveal")
	check(director.is_playing, "the first press did not advance the scene")

	step.advance()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "the second press advanced the scene")
	director.queue_free()


func _test_say_input() -> void:
	var director := _plain_director()
	_say_step(director, "x")

	director.play()
	await wait_until(func(): return not director.get_dialogue().is_revealing(), 5.0)

	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)

	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "an action button advanced the line")
	director.queue_free()


func _test_say_timed() -> void:
	var director := _plain_director()
	var step := _say_step(director, "its ded")
	step.advance_on = StageSay.Advance.TIMED
	step.seconds = 0.3

	director.play()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)

	check(ended, "a timed line advanced without any input")
	director.queue_free()


func _test_timed_line_has_no_prompt() -> void:
	var director := _plain_director()
	var step := _say_step(director, "radio check")
	step.advance_on = StageSay.Advance.TIMED
	step.seconds = 30.0

	director.play()
	var dialogue := director.get_dialogue()
	var revealed := await wait_until(func(): return not dialogue.is_revealing(), 5.0)

	check(revealed, "the line finished revealing")
	check(dialogue.get_body_label().visible, "and stays on screen")
	check(not dialogue.get_hint_label().visible, "with no prompt to press a key")
	director.abort()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_say_names_keys() -> void:
	var director := _plain_director()
	var step := _say_step(director, "Press {interact} to grab it. {not_an_action} stays.")

	director.play()
	await wait_frames(2)

	check_eq(director.get_dialogue().get_body_label().text,	"Press [%s] to grab it. {not_an_action} stays." % MechUI.key_name("interact"),	"the action became its key and unknown names were left alone")
	step.advance()
	step.advance()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_actor_say_names_keys() -> void:
	var director := _plain_director()
	var speaker := FakeSpeaker.new()
	speaker.mecha_name = "KeyTeacher"
	add_child(speaker)
	var step := StageActorSay.new()
	step.actor = "KeyTeacher"
	step.text = "Dash with {thruster_dash}."
	step.seconds = 0.1
	director.add_child(step)

	await director.play()

	check_eq(speaker.heard, ["Dash with [%s]." % MechUI.key_name("thruster_dash")], "the spoken line names the key")
	director.queue_free()
	speaker.queue_free()


func _test_timed_line_does_not_bleed() -> void:
	var director := _plain_director()
	var timed := _say_step(director, "a timed line")
	timed.advance_on = StageSay.Advance.TIMED
	timed.seconds = 5.0
	var after := _say_step(director, "the line that follows it")

	director.play()
	await wait_frames(2)
	timed.advance()
	timed.advance()

	var moved := await wait_until(func(): return director.current_step == after, 5.0)
	check(moved, "the scene moved on to the next line")

	await wait_seconds(6.0)
	check_eq(director.get_dialogue().get_body_label().text, "the line that follows it",\
	"the ended line did not wipe the one now on screen")

	after.advance()
	after.advance()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_pause_holds_the_scene() -> void:
	var director := _plain_director()
	var wait := StageWait.new()
	wait.seconds = 0.6
	director.add_child(wait)
	var order: Array = []
	var later := RecordingStep.new()
	later.order_log = order
	later.label = "after"
	director.add_child(later)

	director.play()
	await wait_frames(1)
	director.set_paused(true)
	check(director.is_paused(), "the director reports itself paused")

	await wait_seconds(2.0)
	check(order.is_empty(), "the wait made no progress while paused")
	check(director.is_playing, "the scene is still open, just held")

	director.set_paused(false)
	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "it carried on once unpaused")
	check_eq(order, ["after"], "the step after the wait ran")
	director.queue_free()


func _test_abort_ends_the_scene() -> void:
	var director := _plain_director()
	var wait := StageWait.new()
	wait.seconds = 30.0
	director.add_child(wait)
	var order: Array = []
	var later := RecordingStep.new()
	later.order_log = order
	later.label = "after"
	director.add_child(later)

	director.play()
	await wait_frames(2)
	check(director.is_playing, "the scene is running before the abort")

	director.abort()
	var ended := await wait_until(func(): return not director.is_playing, 5.0)
	check(ended, "aborting ended the scene")
	check(director.is_aborted(), "it reports itself aborted")
	check(order.is_empty(), "the steps after it never ran")
	director.queue_free()


const LONG_LINE := "Being Flagged means you're waving your white flag, and can't shoot your guns! Your SAV Flags itself when you've taken severe systems damage, which is why it's been on."


func _box_in_the_bar(line: String) -> Array:
	var director := _make_director()
	director.takes_control = false
	var step := _say_step(director, line)
	director.play()
	var dialogue := director.get_dialogue()
	await wait_until(func(): return not dialogue.is_revealing() and director.get_bars().is_shown(), 5.0)
	await wait_frames(2)
	var screen := get_viewport().get_visible_rect().size
	var result := [dialogue.get_box().get_global_rect(), screen, screen.y * director.get_bars().height_ratio]
	step.advance()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()
	return result


func _test_dialogue_in_the_bar() -> void:
	var found := await _box_in_the_bar("hello player")
	var box: Rect2 = found[0]
	var screen: Vector2 = found[1]
	var bar: float = found[2]
	check(box.position.y >= screen.y - bar and box.end.y <= screen.y,
			"the box sits inside the bottom bar (%s, bar from %d)" % [box, roundi(screen.y - bar)])
	check(absf(box.get_center().x - screen.x / 2.0) < 2.0, "centred (%s)" % box)

	var director := _plain_director()
	var style = director.get_dialogue().get_box().get_theme_stylebox("panel")
	check(style is StyleBoxFlat and style.bg_color.a >= 0.6, "on a dark box, readable over the game when the bars are away")
	director.queue_free()


func _test_long_line_in_the_bar() -> void:
	var found := await _box_in_the_bar(LONG_LINE)
	var box: Rect2 = found[0]
	var screen: Vector2 = found[1]
	var bar: float = found[2]
	check(box.position.y >= screen.y - bar and box.end.y <= screen.y,
			"the longest onboarding line still fits (%s, bar from %d)" % [box, roundi(screen.y - bar)])
	check(box.size.x <= screen.x * 0.8, "without spanning the whole screen")


func _test_dialogue_is_visible() -> void:
	var director := _plain_director()
	var step := _say_step(director, "hello player")
	_slow_reveal(director, step.text)

	director.play()
	await wait_frames(2)

	var dialogue := director.get_dialogue()
	var screen := get_viewport().get_visible_rect()
	for label in [dialogue.get_body_label(), dialogue.get_speaker_label(), dialogue.get_hint_label()]:
		check(label.size.x > 0.0 and label.size.y > 0.0,\
		label.name + " has a real size on screen, not a collapsed box")
		check(screen.encloses(Rect2(label.global_position, label.size)),\
		label.name + " sits inside the screen")

	check(dialogue.get_body_label().visible, "the line itself is visible")
	check(dialogue.get_speaker_label().visible, "the speaker name is visible")
	check(not dialogue.get_hint_label().visible, "the prompt is held back while the line reveals")

	await wait_until(func(): return not dialogue.is_revealing(), 5.0)
	check(dialogue.get_hint_label().visible, "the prompt appears once the line is readable")

	step.advance()
	step.advance()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_move_actor() -> void:
	var director := _plain_director()
	var mech := FakeMech.new()
	mech.mecha_name = "Marcher"
	add_child(mech)

	var step := StageMoveActor.new()
	step.actor = "Marcher"
	step.global_position = Vector2(1500, 0)
	step.arrive_distance = 100.0
	director.add_child(step)

	director.play()
	await wait_frames(2)
	check(mech.scripted, "the actor was put under the scene's control")
	check(director.is_playing, "the scene waits for the walk")

	var arrived := await wait_until(func(): return not director.is_playing, 10.0)
	check(arrived, "the scene moved on once the actor arrived")
	check(mech.global_position.distance_to(Vector2(1500, 0)) <= step.arrive_distance,\
	"the actor ended up at the mark")
	check(mech.scripted_destination == null, "the actor was told to stop walking")
	director.queue_free()
	mech.queue_free()


func _test_move_actor_slides() -> void:
	var director := _plain_director()
	var mech := SlidingMech.new()
	mech.mecha_name = "Slider"
	mech.walk_speed = 150.0
	add_child(mech)
	var step := StageMoveActor.new()
	step.actor = "Slider"
	step.global_position = Vector2(600, 0)
	step.arrive_distance = 100.0
	director.add_child(step)

	director.play()
	var stopped := await wait_until(func(): return not director.is_playing, 10.0)

	var gap := mech.global_position.distance_to(Vector2(600, 0))
	check(stopped, "the walk ended")
	check(gap > step.arrive_distance + mech.slide - 30.0 and gap <= step.arrive_distance + mech.slide,
			"told to stop its slide short of the arrive distance (%d)" % roundi(gap))
	director.queue_free()
	mech.queue_free()


func _test_move_actor_out_of_frame() -> void:
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	var director := _plain_director()
	var mech := FakeMech.new()
	mech.mecha_name = "Leaver"
	mech.walk_speed = 600.0
	add_child(mech)
	var step := StageMoveActor.new()
	step.actor = "Leaver"
	step.global_position = Vector2(6000, 0)
	step.until_out_of_frame = true
	director.add_child(step)
	await wait_frames(2)
	var half_width: float = get_viewport().get_visible_rect().size.x / 2.0

	director.play()
	var ended := await wait_until(func(): return not director.is_playing, 10.0)

	check(ended, "the walk ended")
	check(mech.global_position.x > half_width, "once the actor was past the frame's edge (x %d)" % roundi(mech.global_position.x))
	check(mech.global_position.x < half_width + 600.0, "and not long after (x %d of edge %d)" % [roundi(mech.global_position.x), roundi(half_width)])
	check(mech.scripted_destination == null, "where it was told to stop")
	director.queue_free()
	mech.queue_free()
	cam.queue_free()


func _test_move_to_actor() -> void:
	var director := _plain_director()
	var mech := FakeMech.new()
	mech.mecha_name = "Chaser"
	add_child(mech)
	var goal := FakeActor.new()
	goal.mecha_name = "Runner"
	goal.global_position = Vector2(1200, 0)
	add_child(goal)

	var step := StageMoveActor.new()
	step.actor = "Chaser"
	step.destination_actor = "Runner"
	step.arrive_distance = 150.0
	director.add_child(step)

	director.play()
	await wait_frames(2)
	goal.global_position = Vector2(2400, 0)

	var arrived := await wait_until(func(): return not director.is_playing, 15.0)
	check(arrived, "the scene moved on once the actor caught up")
	check(mech.global_position.distance_to(goal.global_position) <= step.arrive_distance,\
	"the actor reached the target after it moved")
	director.queue_free()
	mech.queue_free()
	goal.queue_free()


func _test_actor_shoot() -> void:
	var director := _plain_director()
	var mech := FakeMech.new()
	mech.mecha_name = "Gunner"
	add_child(mech)
	var mark := FakeActor.new()
	mark.mecha_name = "Obstacle"
	mark.global_position = Vector2(700, 0)
	add_child(mark)

	var step := StageActorShoot.new()
	step.actor = "Gunner"
	step.target_actor = "Obstacle"
	step.weapon = "arm_weapon_right"
	step.shots = 3
	step.interval = 0.1
	step.aim_time = 0.1
	director.add_child(step)

	director.play()
	var ended := await wait_until(func(): return not director.is_playing, 10.0)

	check(ended, "the scene moved on after the shots")
	check_eq(mech.shots_fired.size(), 3, "it fired the number of shots asked for")
	check_eq(mech.shots_fired[0], "arm_weapon_right", "it fired the weapon asked for")
	check_eq(mech.scripted_aim, mark.global_position, "it was aimed at the target")
	director.queue_free()
	mech.queue_free()
	mark.queue_free()


func _test_spawn() -> void:
	var director := _plain_director()
	var step := StageSpawn.new()
	step.scene = preload("res://game/items/RepairKit.tscn")
	step.alias = "Kit"
	step.global_position = Vector2(700, -300)
	director.add_child(step)

	await director.play()

	var kit = director.find_actor("Kit")
	check(kit is RepairKit, "the thing was made and can be found by its name")
	check(kit != null and kit.global_position.is_equal_approx(Vector2(700, -300)), "where the step stands")
	check(kit != null and kit.get_parent() != director, "and it outlives the scene")
	director.queue_free()
	await wait_frames(2)
	check(is_instance_valid(kit), "it is still there once the scene is gone")
	if is_instance_valid(kit):
		kit.queue_free()


const OVERLAY_SOURCE := "extends CanvasLayer
signal finished
var played := false
func play() -> void:
	played = true
"


func _overlay_scene() -> PackedScene:
	var script := GDScript.new()
	script.source_code = OVERLAY_SOURCE
	script.reload()
	var root := CanvasLayer.new()
	root.set_script(script)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func _overlay_director() -> Array:
	var director := _plain_director()
	var step := StageOverlay.new()
	step.overlay = _overlay_scene()
	director.add_child(step)
	var after := StageWait.new()
	after.seconds = 30.0
	director.add_child(after)
	return [director, step, after]


func _shown_overlays(director: StageDirector) -> Array:
	return director.get_children().filter(func(n): return n is CanvasLayer and n.get("played") != null and not n.is_queued_for_deletion())


func _test_overlay() -> void:
	var parts := _overlay_director()
	var director: StageDirector = parts[0]
	director.play()
	await wait_frames(2)

	var shown := _shown_overlays(director)
	check(director.current_step == parts[1], "the scene waits on the overlay")
	check(shown.size() == 1 and shown[0].played, "which is on screen and playing")

	shown[0].finished.emit()
	await wait_frames(2)
	check(director.current_step == parts[2], "the scene moves on once it is over")
	check(_shown_overlays(director).is_empty(), "and takes it off")
	director.abort()
	await wait_until(func(): return not director.is_playing, 5.0)
	director.queue_free()


func _test_overlay_skipped() -> void:
	var parts := _overlay_director()
	var director: StageDirector = parts[0]
	director.play()
	await wait_frames(2)

	director.skip()
	await wait_frames(2)

	check(_shown_overlays(director).is_empty(), "the overlay is gone")
	director.queue_free()


func _test_show_flag_marker() -> void:
	for skipped in [false, true]:
		var director := _plain_director()
		var mech := FlaggedMech.new()
		mech.mecha_name = "Flagged %s" % skipped
		add_child(mech)
		if skipped:
			var hold := StageWait.new()
			hold.seconds = 30.0
			director.add_child(hold)
		var step := StageShowFlagMarker.new()
		step.actor = mech.mecha_name
		director.add_child(step)

		director.play()
		await wait_frames(2)
		if skipped:
			director.skip()
		await wait_until(func(): return not director.is_playing, 5.0)

		check(mech.marker_shown, "the marker is shown%s" % (" when the scene is skipped" if skipped else ""))
		director.queue_free()
		mech.queue_free()
