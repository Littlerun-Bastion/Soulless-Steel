extends TestSuite

const WALK_SPEED := 400.0
const WALK_DISTANCE := 1200.0
const SLOW_REVEAL_SECONDS := 3.0
const SLOW_CAMERA_SPEED := 1.0


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


class FakePlayer extends Node2D:
	var controls_locked := false

	func _ready() -> void:
		add_to_group("mecha")

	func is_player() -> bool:
		return true

	func lock_controls() -> void:
		controls_locked = true

	func unlock_controls() -> void:
		controls_locked = false


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
	await case("taking control can be turned off", _test_control_disabled)
	await case("look-at drives the camera to its own position", _test_camera_look_at)
	await case("look-at can hold until the camera arrives", _test_camera_waits)
	await case("follow tracks an actor that keeps moving", _test_camera_follows_mover)
	await case("the camera is handed back when the scene ends", _test_camera_released)
	await case("a line holds the scene until it is advanced", _test_say_waits)
	await case("the first press finishes the reveal, the second advances", _test_say_two_stage)
	await case("a player action button advances a line", _test_say_input)
	await case("a timed line advances on its own", _test_say_timed)
	await case("the dialogue is actually on screen", _test_dialogue_is_visible)
	await case("a line ended early never clears a later one", _test_timed_line_does_not_bleed)
	await case("pausing holds the scene where it is", _test_pause_holds_the_scene)
	await case("an actor walks to a mark and the scene waits", _test_move_actor)
	await case("an actor walks to another actor that keeps moving", _test_move_to_actor)
	await case("an actor shoots a target a set number of times", _test_actor_shoot)


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
	var cam := Camera2D.new()
	cam.enabled = true
	add_child(cam)
	director.use_camera(cam)

	var step := StageWait.new()
	step.seconds = 0.0
	director.add_child(step)

	await director.play()

	check(not cam.enabled, "the stage camera switched itself off so the player camera resumes")
	check(director.get_camera().get_target_position() == null, "the stage camera let go of its target")
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
