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

# Soft-spawn tunables — the world replenishes itself as NPCs die or extract.
@export_group("Soft Spawns")
@export var target_population: int = 8                   # below this, soft-spawn engages
@export var critical_population: int = 3                 # below this, use the shorter cooldown
@export var soft_spawn_cooldown: float = 30.0            # seconds between spawns when above critical
@export var soft_spawn_critical_cooldown: float = 10.0   # seconds between spawns when at/below critical
@export var max_total_soft_spawns: int = 30              # hard cap (safety net)
@export var min_spawn_distance_from_player: float = 3000.0  # don't pop in next to the player
@export var soft_spawn_check_interval: float = 5.0       # how often to evaluate

var arena                                   # Ref to LivingWorldTest (acts as arena)
var initial_population_done: bool = false
var time_since_last_player_damage: float = 0.0
var print_timer: float = 0.0
var npc_vs_npc_kills: int = 0
var player_kills: int = 0
var player_deaths: int = 0

# Soft-spawn state
var total_soft_spawns: int = 0
var time_since_last_spawn: float = 0.0
var soft_spawn_check_timer: float = 0.0


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
	time_since_last_spawn += dt

	print_timer -= dt
	if print_timer <= 0.0:
		print_timer = metrics_print_interval
		_print_metrics()

	soft_spawn_check_timer -= dt
	if soft_spawn_check_timer <= 0.0:
		soft_spawn_check_timer = soft_spawn_check_interval
		_try_soft_spawn()

	# TODO interventions:
	# - Redirect a distant NPC toward the player when quiet
	# - Trigger ambient events (gunfire/sound at POI)
	# - Seed NPC-vs-NPC fights when player is far


func _print_metrics() -> void:
	if not is_instance_valid(arena.player):
		print("[Director] player gone")
		return

	var npc_count = _alive_npc_count()
	var nearest = _nearest_enemy_distance()
	print("[Director] npcs=", npc_count,
		"  nearest_enemy_dist=", int(nearest),
		"  quiet_for=", int(time_since_last_player_damage), "s",
		"  npc_kills=", npc_vs_npc_kills,
		"  player_kills=", player_kills,
		"  player_deaths=", player_deaths,
		"  soft_spawns=", total_soft_spawns)


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


# ---- Soft spawns ----

# Replenish the world's NPC population when it dips below target. Picks a
# SpawnZone that's far from the player so they don't see the spawn happen.
# Gated by cooldown + hard cap so it can't spam.
func _try_soft_spawn() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	if total_soft_spawns >= max_total_soft_spawns:
		return

	var pop = _alive_npc_count()
	if pop >= target_population:
		return  # population is healthy, leave it alone

	# Tighter cooldown when population gets desperate.
	var cooldown = soft_spawn_cooldown
	if pop <= critical_population:
		cooldown = soft_spawn_critical_cooldown
	if time_since_last_spawn < cooldown:
		return

	var pos = _pick_offscreen_spawn_position()
	if pos == null:
		return  # no zone is far enough from the player right now

	var npc = NPCManager.get_random_npc()
	if not npc:
		return
	var design = NPCManager.get_design_data(npc)
	var enemy_name = "Soft_" + str(total_soft_spawns)
	var enemy = arena.add_enemy(design, enemy_name, pos)
	if enemy == null:
		return

	total_soft_spawns += 1
	time_since_last_spawn = 0.0
	print("[Director] soft-spawned ", enemy_name, " at ", pos,
		"  [pop ", pop, " -> ", pop + 1, "]")


# Counts living NPCs (excludes player and dead-but-not-yet-removed mechas).
func _alive_npc_count() -> int:
	if not is_instance_valid(arena):
		return 0
	var count := 0
	for m in arena.all_mechas:
		if not is_instance_valid(m):
			continue
		if m == arena.player:
			continue
		if "is_dead" in m and m.is_dead:
			continue
		count += 1
	return count


# Returns a Vector2 from a SpawnZone that's far from the player, with a small
# random jitter, or null if no zone qualifies.
func _pick_offscreen_spawn_position():
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return null

	var spawn_zones = arena.get_node_or_null("SpawnZones")
	if spawn_zones == null:
		return null

	var player_pos = arena.player.global_position
	var candidates: Array = []
	for zone in spawn_zones.get_children():
		if not is_instance_valid(zone):
			continue
		var d = player_pos.distance_to(zone.global_position)
		if d >= min_spawn_distance_from_player:
			candidates.append(zone)

	if candidates.is_empty():
		return null

	var pick = candidates.pick_random()
	var jitter = Vector2(randf_range(-200, 200), randf_range(-200, 200))
	return pick.global_position + jitter
