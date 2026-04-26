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
var npc_vs_npc_kills: int = 0
var player_kills: int = 0
var player_deaths: int = 0


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
		"  quiet_for=", int(time_since_last_player_damage), "s",
		"  npc_kills=", npc_vs_npc_kills,
		"  player_kills=", player_kills,
		"  player_deaths=", player_deaths)


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


# Called by arena when any mecha dies — categorize so we can tell the difference
# between player kills and emergent NPC-vs-NPC violence.
# `last_damage_source` is a dict {body, name} populated by projectile impacts.
func notify_mecha_died(mecha) -> void:
	if not is_instance_valid(arena):
		return
	var src = mecha.last_damage_source if "last_damage_source" in mecha else null
	# No clear attacker (extracted, fall damage, despawn, etc.)
	if src == null or typeof(src) != TYPE_DICTIONARY or not src.has("body"):
		return
	var killer = src.body
	if not is_instance_valid(killer) or killer == mecha:
		return
	# Player getting killed is its own category — not a player kill, not NPC-vs-NPC.
	if mecha == arena.player:
		player_deaths += 1
		print("[Director] player killed by ", killer.mecha_name)
	elif killer == arena.player:
		player_kills += 1
		print("[Director] player killed ", mecha.mecha_name)
	else:
		npc_vs_npc_kills += 1
		print("[Director] npc-vs-npc: ", killer.mecha_name, " killed ", mecha.mecha_name)
