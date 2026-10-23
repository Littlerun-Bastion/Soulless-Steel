extends TestSuite

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const DEMO := preload("res://game/stage/scenes/demo.tscn")

const NPC_START_OFFSET := Vector2(1500, 0)
const ENTITY_WALK_START := Vector2(650, 0)
const ENTITY_WALK_MARK := Vector2(250, 0)
const LIVE_NPC_MAX_GAP := 4000.0
const BEATS: Array[String] = [
	"WatchPlayer",
	"HoldOnPlayer",
	"WatchNPC",
	"NPCWalksToPlayer",
	"NPCGreets",
	"WatchPlayerAgain",
	"PlayerReplies",
	"WatchObstacle",
	"BeforeTheShot",
	"NPCShootsObstacle",
	"WatchNPCAgain",
	"NPCGloats",
]
const RUN_TIMEOUT := 120.0

var _scene = null
var _demo: StageDemo = null
var _npc: Mecha = null
var _saved_skip_intro = null
var _seen: Array[String] = []


func _init() -> void:
	slow = true
	time_scale = 2.0


func run_tests() -> void:
	_saved_skip_intro = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true

	await _open()
	await case("the stage camera is the one rendering", _test_camera_is_the_one_rendering)
	await _close()

	await _open()
	await case("the demo scene plays every beat in order", _test_beats)
	await case("the scene leaves the player in control again", _test_handback)
	await _close()

	await _open()
	await case("skipping runs the whole scene out safely", _test_skip)
	await _close()

	await _open()
	await case("playing it the way F4 does runs it through", _test_played_like_f4)
	await _close()

	await _open()
	await case("playing it in a live world, like F4 in game", _test_played_live)
	await case("everything it does not direct is frozen", _test_world_frozen)
	await _close()

	await _open()
	await case("the scene spawns its own NPC near the player", _test_spawns_npc)
	await _close()

	await _open()
	await case("the obstacle it places stops bullets", _test_obstacle_blocks)
	await case("an Entity can be walked by a scene too", _test_entity_directed)
	await case("a map trigger plays a scene by name", _test_trigger_plays)
	await _close()

	Debug.debug_settings["skip_intro"] = _saved_skip_intro


func _open() -> void:
	PlayerProgress.reset()
	TransitionManager.captured.clear()
	_scene = EXPEDITION.instantiate()
	add_child(_scene)
	var populated := await wait_until(func(): return _enemies().size() > 0, 20.0)
	check(populated, "the expedition populated")
	_scene.ExpeditionDirector.set_process(false)
	await wait_frames(2)
	for entity in _scene.get_entities():
		entity.set_pause(true)
	for enemy in _enemies():
		enemy.set_pause(true)

	_npc = _enemies()[0]
	_npc.set_pause(false)
	_npc.global_position = _scene.player.global_position + NPC_START_OFFSET

	_demo = DEMO.instantiate()
	_scene.add_child(_demo)
	_seen = []
	_demo.step_started.connect(func(step: StageStep): _seen.append(step.name))


func _close() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		await wait_frames(2)
	_scene = null
	_demo = null
	_npc = null


func _enemies() -> Array:
	if not is_instance_valid(_scene):
		return []
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


func _run_to_end(timeout: float) -> bool:
	var waited := 0.0
	while is_instance_valid(_demo) and _demo.is_playing:
		if waited >= timeout:
			return false
		var step = _demo.current_step
		if step is StageSay and not _demo.get_dialogue().is_revealing():
			step.advance()
		await get_tree().process_frame
		waited += get_process_delta_time()
	return true


func _test_beats() -> void:
	_demo.cast(_npc)
	check_eq(_demo.find_actor("NPC"), _npc, "the NPC alias was bound to the real mech")
	check(_demo.find_actor("OBSTACLE") != null, "the obstacle was placed")

	_demo.play()
	await wait_frames(2)

	check(_scene.player.controls_locked, "the player lost control when the scene started")
	check(_demo.get_bars() != null and _demo.get_bars().is_shown(), "the cinema bars came in")

	var taken := await wait_until(func(): return _npc.scripted, 30.0)
	check(taken, "the NPC came under the scene's control once its beat started")

	var finished := await _run_to_end(RUN_TIMEOUT)
	check(finished, "the scene reached its end")

	check_eq(_seen, BEATS, "every beat ran once, in the order it is authored in")


func _test_camera_is_the_one_rendering() -> void:
	var player_cam: Camera2D = _scene.player.get_cam()
	check_eq(get_viewport().get_camera_2d(), player_cam, "the player camera renders before the scene")

	_demo.cast(_npc)
	_demo.play()
	await wait_frames(2)

	check_eq(get_viewport().get_camera_2d(), _scene.ArenaCam,\
	"the stage camera is the one actually rendering during the scene")

	var target_before = _demo.get_camera().get_target_position()
	var step := _demo.get_node("WatchNPC") as StageCameraFollow
	check(step != null, "the demo has a follow step to check")

	var moved := await wait_until(func():
		var now = _demo.get_camera().get_target_position()
		return now != null and target_before != null and now.distance_to(target_before) > 100.0, 30.0)
	check(moved, "the camera target moved off the player to the NPC")

	_demo.skip()
	await wait_until(func(): return not _demo.is_playing, 30.0)
	check_eq(get_viewport().get_camera_2d(), player_cam, "the player camera renders again afterwards")


func _test_handback() -> void:
	check(not _scene.player.controls_locked, "the player has control again")
	check(not _demo.get_bars().is_shown(), "the cinema bars went back out")
	check(not _scene.ArenaCam.enabled, "the arena camera was handed back to the player camera")
	check_eq(_demo.get_dialogue().get_body_label().text, "", "no dialogue was left on screen")


func _test_skip() -> void:
	_demo.cast(_npc)
	_demo.play()
	await wait_frames(2)
	check(_demo.is_playing, "the scene is running before the skip")

	_demo.skip()
	var finished := await wait_until(func(): return not _demo.is_playing, 30.0)

	check(finished, "skipping ended the scene")
	check(not _scene.player.controls_locked, "a skipped scene still hands control back")
	check(not _scene.ArenaCam.enabled, "a skipped scene still hands the camera back")
	check_eq(_demo.get_dialogue().get_body_label().text, "", "a skipped scene leaves no dialogue up")


func _test_played_like_f4() -> void:
	_demo.queue_free()
	await wait_frames(2)

	var played = _scene.play_stage("demo")
	check(played != null, "play_stage built the scene")
	if played == null:
		return
	_demo = played
	var reached: Array[String] = []
	_demo.step_started.connect(func(step: StageStep): reached.append(step.name))

	await wait_frames(2)
	check(_demo.find_actor("NPC") != null, "it found or made an NPC with no help")
	check(_demo.find_actor("OBSTACLE") != null, "it placed an obstacle")

	var finished := await _run_to_end(RUN_TIMEOUT)
	check(finished, "it ran to the end")
	check_eq(reached, BEATS.slice(2), "every beat after the two that run synchronously")


func _test_played_live() -> void:
	for enemy in _enemies():
		enemy.set_pause(false)
	for entity in _scene.get_entities():
		entity.set_pause(false)
	_scene.ExpeditionDirector.set_process(true)

	var played = _scene.play_stage("demo")
	check(played != null, "play_stage built the scene in a live world")
	if played == null:
		return
	_demo = played
	var reached: Array[String] = []
	_demo.step_started.connect(func(step: StageStep): reached.append(step.name))

	var npc = _demo.find_actor("NPC")
	check(npc != null, "it found or made an NPC in a live world")
	if npc is Node2D:
		var gap: float = npc.global_position.distance_to(_scene.player.global_position)
		check(gap < LIVE_NPC_MAX_GAP, "the NPC it picked is near the player, not across the map (gap " + str(round(gap)) + ")")

	var finished := await _run_to_end(RUN_TIMEOUT)
	check(finished, "it ran to the end in a live world; reached " + str(reached))
	check_eq(reached, BEATS.slice(2), "every beat ran in a live world")


func _test_world_frozen() -> void:
	for enemy in _enemies():
		enemy.set_pause(false)
	for entity in _scene.get_entities():
		entity.set_pause(false)

	var director := StageDirector.new()
	director.shows_bars = false
	director.takes_camera = false
	_scene.add_child(director)
	var hold := StageWait.new()
	hold.seconds = 30.0
	director.add_child(hold)

	var bystanders: Array = _enemies().filter(func(m): return not m.scripted)
	var creatures: Array = _scene.get_entities().filter(func(e): return is_instance_valid(e))
	check(not creatures.is_empty(), "there are Entities around to be frozen")

	director.play()
	await wait_frames(2)

	for enemy in bystanders:
		check(enemy.paused, enemy.mecha_name + " stopped moving during the scene")
	for creature in creatures:
		check(creature.paused, "an Entity stopped moving during the scene")

	var scripted = bystanders[0] if not bystanders.is_empty() else null
	if scripted != null:
		scripted.set_scripted(true)
		check(not scripted.paused, "an actor the scene takes over starts moving again")

	director.skip()
	await wait_until(func(): return not director.is_playing, 10.0)

	for creature in creatures:
		check(is_instance_valid(creature) and not creature.paused,\
		"the Entity moves again once the scene is over")
	if scripted != null:
		scripted.set_scripted(false)
	director.queue_free()


func _test_spawns_npc() -> void:
	_demo.queue_free()
	await wait_frames(2)
	var before := _enemies().size()

	var played = _scene.play_stage("demo")
	check(played != null, "the scene played")
	if played == null:
		return
	_demo = played
	await wait_frames(2)

	check_eq(_enemies().size(), before + 1, "it spawned one NPC of its own")
	var spawned = _demo.npc
	check(spawned != null, "it kept a reference to the NPC it made")
	if spawned == null:
		return
	check_eq(spawned.mecha_name, _demo.npc_name, "the NPC carries the name the scene gave it")
	check_eq(_demo.find_actor("NPC"), spawned, "the NPC alias points at it")
	check(spawned.scripted, "it is under the scene's control from the start, so it will not shoot")

	var gap: float = spawned.global_position.distance_to(_scene.player.global_position)
	check(gap < StageDemo.NPC_SPAWN_DISTANCE * 1.5,\
	"it spawned near the player so the camera has something to cut to (gap " + str(round(gap)) + ")")

	_demo.skip()
	await wait_until(func(): return not _demo.is_playing, 30.0)


func _test_obstacle_blocks() -> void:
	_demo.cast(_npc)
	var obstacle := _demo.obstacle

	check(obstacle != null, "the demo placed an obstacle")
	check(obstacle.get_parent() == _scene, "it was placed in the world, not inside the director")
	var body := obstacle.get_node_or_null("StaticBody2D")
	check(body is StaticBody2D, "it has a static body, so bullets stop on it")
	check(body != null and body.get_child_count() > 0, "the static body has a collision shape")


func _test_entity_directed() -> void:
	var entities = _scene.get_entities().filter(func(e): return is_instance_valid(e) and not e.is_dead)
	if entities.is_empty():
		check(false, "the expedition spawned an Entity to direct")
		return
	var entity = entities[0]
	entity.set_pause(false)
	entity.global_position = _scene.player.global_position + ENTITY_WALK_START

	var director := StageDirector.new()
	director.shows_bars = false
	director.takes_control = false
	director.takes_camera = false
	_scene.add_child(director)
	director.set_actor("Beast", entity)

	var mark: Vector2 = _scene.player.global_position + ENTITY_WALK_MARK
	var step := StageMoveActor.new()
	step.actor = "Beast"
	step.global_position = mark
	step.arrive_distance = 150.0
	director.add_child(step)

	director.play()
	await wait_frames(2)
	check(entity.scripted, "the Entity came under the scene's control")
	check(entity.target == null, "it dropped whatever it was hunting")

	var arrived := await wait_until(func(): return not director.is_playing, 30.0)
	check(arrived, "the scene moved on once the Entity arrived")
	check(entity.global_position.distance_to(mark) <= step.arrive_distance,\
	"the Entity walked to the mark")

	entity.set_scripted(false)
	director.queue_free()


func _test_trigger_plays() -> void:
	check(_scene.current_stage == null or not _scene.current_stage.is_playing,\
	"nothing is playing before the trigger")

	_scene._on_player_trigger_entered("stage:demo")
	await wait_frames(2)

	var playing = _scene.current_stage
	check(playing != null, "the trigger built a scene")
	check(playing != null and playing.is_playing, "the trigger started it")
	check(_scene.player.controls_locked, "the triggered scene took control")

	check(_scene.play_stage("does_not_exist") == null, "an unknown scene name is refused")

	if playing != null:
		playing.skip()
		await wait_until(func(): return not playing.is_playing, 30.0)
