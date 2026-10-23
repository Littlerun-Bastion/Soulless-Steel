class_name StageDirector
extends Node

signal started
signal finished
signal step_started(step: StageStep)

@export var shows_bars := true
@export var takes_control := true
@export var takes_camera := true
@export var freezes_world := true

var is_playing := false
var is_skipping := false
var current_step: StageStep = null

var _bars: StageBars = null
var _camera: StageCamera = null
var _dialogue: StageDialogue = null
var _actors := {}
var _frozen: Array = []


func play() -> void:
	if is_playing:
		return
	is_playing = true
	is_skipping = false
	_show_bars()
	_set_control_locked(true)
	_take_camera()
	_freeze_world()
	started.emit()
	for step in get_steps():
		current_step = step
		step_started.emit(step)
		await step.run(self)
	current_step = null
	if _dialogue != null:
		_dialogue.clear()
	_thaw_world()
	await _hide_bars()
	_release_camera()
	_set_control_locked(false)
	is_playing = false
	finished.emit()


func skip() -> void:
	if not is_playing or is_skipping:
		return
	is_skipping = true
	if current_step != null:
		current_step.skip()


func get_steps() -> Array[StageStep]:
	var steps: Array[StageStep] = []
	for child in get_children():
		if child is StageStep:
			steps.append(child)
	return steps


func get_bars() -> StageBars:
	return _bars


func get_player() -> Node:
	var scene := get_scene_root()
	if scene != null:
		var known = scene.get("player")
		if known != null and is_instance_valid(known):
			return known
	for node in get_actors():
		if node.has_method("is_player") and node.is_player():
			return node
	return null


func get_actors() -> Array:
	var scene := get_scene_root()
	if scene != null and scene.has_method("get_mechas") and scene.has_method("get_entities"):
		return scene.get_mechas() + scene.get_entities()
	var all: Array = []
	for group in ["mecha", "entity"]:
		all += get_tree().get_nodes_in_group(group)
	return all


func get_camera() -> StageCamera:
	return _camera


func get_dialogue() -> StageDialogue:
	if _dialogue == null:
		_dialogue = StageDialogue.new()
		add_child(_dialogue)
	return _dialogue


func use_camera(cam: Camera2D) -> void:
	if _camera == null:
		_camera = StageCamera.new()
		add_child(_camera)
	_camera.setup(cam)


func get_scene_root() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("activate_arena_cam"):
			return node
		node = node.get_parent()
	return null


func set_actor(alias: String, node: Node) -> void:
	_actors[alias] = node


func find_actor(actor_name: String) -> Node:
	if actor_name == "":
		return null
	var bound = _actors.get(actor_name)
	if bound != null and is_instance_valid(bound):
		return bound
	for node in get_actors():
		if is_instance_valid(node) and node.get("mecha_name") == actor_name:
			return node
	var scene := get_scene_root()
	if scene != null:
		return scene.find_child(actor_name, true, false)
	return null


func _freeze_world() -> void:
	_frozen = []
	if not freezes_world:
		return
	var player := get_player()
	for node in get_actors():
		if not is_instance_valid(node) or node == player:
			continue
		if node.get("scripted") or node.get("paused"):
			continue
		if node.has_method("set_pause"):
			node.set_pause(true)
			_frozen.append(node)


func _thaw_world() -> void:
	for node in _frozen:
		if is_instance_valid(node) and node.has_method("set_pause"):
			node.set_pause(false)
	_frozen = []


func _take_camera() -> void:
	if not takes_camera:
		return
	var scene := get_scene_root()
	if scene == null:
		return
	scene.activate_arena_cam()
	var cam = scene.get("ArenaCam")
	if cam is Camera2D:
		use_camera(cam)
		cam.make_current()


func _release_camera() -> void:
	if _camera == null:
		return
	_camera.clear_target()
	var cam := _camera.get_camera()
	if cam != null:
		cam.enabled = false
	var player := get_player()
	if player != null and player.has_method("get_cam"):
		var player_cam = player.get_cam()
		if player_cam is Camera2D:
			player_cam.make_current()


func _set_control_locked(locked: bool) -> void:
	if not takes_control:
		return
	var player := get_player()
	if player == null:
		return
	var method := "lock_controls" if locked else "unlock_controls"
	if player.has_method(method):
		player.call(method)


func _show_bars() -> void:
	if not shows_bars:
		return
	if _bars == null:
		_bars = StageBars.new()
		add_child(_bars)
	_bars.show_bars()


func _hide_bars() -> void:
	if _bars == null:
		return
	await _bars.hide_bars().finished
