class_name StageDemo
extends StageDirector

const OBSTACLE := preload("res://database/props/box1_prop.tscn")
const OBSTACLE_DISTANCE := 900.0
const NPC_SPAWN_DISTANCE := 1700.0
const NPC_ALIAS := "NPC"
const OBSTACLE_ALIAS := "OBSTACLE"

@export var npc_name := "Scene NPC"
@export var spawns_npc := true

var obstacle: Node2D = null
var npc: Node2D = null


func _ready() -> void:
	finished.connect(_clear_obstacle)


func start(with_npc: Node2D = null) -> void:
	cast(with_npc)
	play()


func cast(with_npc: Node2D = null) -> void:
	var player := get_player()
	npc = with_npc
	if npc == null and spawns_npc:
		npc = _spawn_npc(player)
	if npc == null:
		npc = find_nearest_npc()
	if npc != null:
		set_actor(NPC_ALIAS, npc)
		take_actor(npc)
	obstacle = _build_obstacle(npc if npc != null else player)
	set_actor(OBSTACLE_ALIAS, obstacle)


func _spawn_npc(player) -> Node2D:
	var scene := get_scene_root()
	if scene == null or not scene.has_method("add_enemy") or not player is Node2D:
		return null
	var design = NPCManager.get_design_data(NPCManager.get_random_npc())
	if design == null:
		return null
	var spot: Vector2 = player.global_position + Vector2.RIGHT.rotated(randf() * TAU) * NPC_SPAWN_DISTANCE
	if scene.has_method("_ensure_position_on_nav"):
		spot = scene._ensure_position_on_nav(spot)
	var spawned = scene.add_enemy(design, npc_name, spot)
	return spawned if spawned is Node2D else null


func find_nearest_npc() -> Node2D:
	var player := get_player()
	var best: Node2D = null
	var best_distance := INF
	for node in get_actors():
		if not node is Node2D or node == player or node.get("is_dead"):
			continue
		if node.has_method("is_player") and node.is_player():
			continue
		if player == null:
			return node
		var distance: float = node.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _build_obstacle(near) -> Node2D:
	var node := OBSTACLE.instantiate()
	node.name = "StageDemoObstacle"
	var host := get_scene_root()
	if host == null:
		host = self
	host.add_child(node)
	if near is Node2D:
		node.global_position = near.global_position + _away_from_player(near) * OBSTACLE_DISTANCE
	return node


func _clear_obstacle() -> void:
	if is_instance_valid(obstacle):
		obstacle.queue_free()
	obstacle = null


func _away_from_player(near: Node2D) -> Vector2:
	var player := get_player()
	if player is Node2D:
		var dir: Vector2 = player.global_position.direction_to(near.global_position)
		if dir.length() > 0.01:
			return dir
	return Vector2.RIGHT
