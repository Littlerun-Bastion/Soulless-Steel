extends Node
class_name Director

# Director is the "living world" manager. It populates the test scene with NPCs
# at start, monitors the player's experience, and intervenes (redirect, spawn,
# ambient events) to keep things interesting without overwhelming the player.
#
# This is a SKELETON — start small, add interventions as we validate each layer.

@export var min_initial_enemies: int = 8
@export var max_initial_enemies: int = 12
@export var metrics_print_interval: float = 5.0

var arena                                   # Ref to LivingWorldTest (acts as arena)
var initial_population_done: bool = false
var time_since_last_player_damage: float = 0.0
var print_timer: float = 0.0


func start(arena_ref) -> void:
	arena = arena_ref
	_populate_initial_world()
	set_process(true)


func _populate_initial_world() -> void:
	var count = randi_range(min_initial_enemies, max_initial_enemies)
	for i in count:
		var npc = NPCManager.get_random_npc()
		if not npc:
			continue
		var design = NPCManager.get_design_data(npc)
		arena.add_enemy(design, "NPC_" + str(i))
	initial_population_done = true
	print("[Director] World populated with ", count, " NPCs")


func _process(dt: float) -> void:
	if not initial_population_done:
		return

	time_since_last_player_damage += dt
	print_timer -= dt
	if print_timer <= 0.0:
		print_timer = metrics_print_interval
		_print_metrics()

	# TODO interventions:
	# - Redirect a distant NPC toward the player when quiet
	# - Trigger ambient events (gunfire/sound at POI)
	# - Soft-spawn a new NPC from a SpawnZone if pop is low
	# - Seed NPC-vs-NPC fights when player is far


func _print_metrics() -> void:
	if not is_instance_valid(arena.player):
		print("[Director] player gone")
		return

	var npc_count = arena.all_mechas.size() - 1
	var nearest = _nearest_enemy_distance()
	print("[Director] npcs=", npc_count,
		"  nearest_enemy_dist=", int(nearest),
		"  time_since_player_damage=", int(time_since_last_player_damage), "s")


func _nearest_enemy_distance() -> float:
	var p = arena.player
	if not is_instance_valid(p):
		return -1.0
	var best := INF
	for m in arena.all_mechas:
		if m == p or not is_instance_valid(m):
			continue
		var d = p.global_position.distance_to(m.global_position)
		if d < best:
			best = d
	return best


# Called by arena when the player takes damage — resets the quiet timer
func notify_player_damaged() -> void:
	time_since_last_player_damage = 0.0
