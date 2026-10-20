extends Node

# ExpeditionDirector is the "living world" manager for Expedition mode (not to
# be confused with StoryDirector, which tracks story progress). It populates
# the map with NPCs at start, monitors the player's experience, and intervenes
# (redirect, spawn, ambient events) to keep things interesting without
# overwhelming the player.
#
# This is a SKELETON — start small, add interventions as we validate each layer.

@export var min_initial_enemies: int = 6
@export var max_initial_enemies: int = 10
@export var metrics_print_interval: float = 5.0

# Soft-spawn tunables — the world replenishes itself as NPCs die or extract.
@export_group("Soft Spawns")
@export var target_population: int = 12                  # below this, soft-spawn engages
@export var critical_population: int = 3                 # below this, use the shorter cooldown
@export var soft_spawn_cooldown: float = 30.0            # seconds between spawns when above critical
@export var soft_spawn_critical_cooldown: float = 10.0   # seconds between spawns when at/below critical
@export var max_total_soft_spawns: int = 30              # hard cap (safety net)
@export var min_spawn_distance_from_player: float = 5000.0  # don't pop in next to the player
@export var soft_spawn_check_interval: float = 5.0       # how often to evaluate

# Redirect tunables — pull a distant NPC toward the player when nothing happens.
# Throttled by redirect_cooldown so the player isn't constantly being chased.
@export_group("Redirect")
@export var quiet_threshold: float = 90.0                # quiet seconds before intervening
@export var redirect_cooldown: float = 45.0              # seconds between redirects (the safety knob)
@export var min_redirect_distance: float = 6000.0        # NPC must be at least this far away
@export var redirect_destination_jitter: float = 800.0   # how far from exact player position
@export var redirect_check_interval: float = 5.0         # how often to evaluate

# Ambient event tunables — periodically synthesize a "gunfire" sound at a
# distant point on the map. NPCs in earshot investigate, creating emergent
# action at the spot. Adds life to the world even when nothing's converging
# on the player directly.
@export_group("Ambient Events")
@export var ambient_event_min_interval: float = 25.0     # min seconds between events
@export var ambient_event_max_interval: float = 60.0     # max seconds between events
@export var ambient_event_min_distance: float = 2000.0   # event must be at least this far from player
@export var ambient_event_max_distance: float = 8000.0   # but not so far it's pointless
@export var ambient_event_sound_radius: float = 4000.0   # how far NPCs can hear the synthetic gunshot

# Entities (creatures, game/entities/) — Stalker packs, a Spitter or two and
# sometimes a Brute roam the map from the start, well away from the player,
# and a Cyst (nest) grows on each of the map's cyst sites.
# While the population is low, newcomers wander in now and then: mostly
# Stalker packs, sometimes a Spitter or a Brute.
@export_group("Entities")
@export var min_initial_packs: int = 2
@export var max_initial_packs: int = 4
@export var min_pack_size: int = 3
@export var max_pack_size: int = 5
@export var min_initial_spitters: int = 1
@export var max_initial_spitters: int = 2
@export var initial_brute_chance: float = 0.5
@export var min_entity_distance_from_player: float = 3500.0
@export var target_entity_population: int = 10           # below this, newcomers may arrive
@export var pack_respawn_cooldown: float = 75.0          # seconds between arrivals
@export var max_pack_respawns: int = 6                   # hard cap per run
@export var arrival_spitter_chance: float = 0.2          # an arrival is a Spitter...
@export var arrival_brute_chance: float = 0.1            # ...or a Brute, else a Stalker pack

const STALKER = preload("res://game/entities/Stalker.tscn")
const SPITTER = preload("res://game/entities/Spitter.tscn")
const BRUTE = preload("res://game/entities/Brute.tscn")
const CYST = preload("res://game/entities/Cyst.tscn")

var arena                                   # Ref to Expedition (acts as arena)
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

# Redirect state
var total_redirects: int = 0
var time_since_last_redirect: float = 999.0  # large initial = ready as soon as quiet trips
var redirect_check_timer: float = 0.0

# Ambient event state
var total_ambient_events: int = 0
var ambient_event_timer: float = 10.0  # short initial delay before the first event

# Entity state
var entity_kills: int = 0             # Entities the player killed
var total_pack_respawns: int = 0
var time_since_pack_respawn: float = 0.0


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
	var packs := 0
	for i in randi_range(min_initial_packs, max_initial_packs):
		var pos = _pick_entity_spawn_position()
		if pos != null:
			spawn_stalker_pack(pos)
			packs += 1
	var loners := []
	for i in randi_range(min_initial_spitters, max_initial_spitters):
		loners.append(SPITTER)
	if randf() < initial_brute_chance:
		loners.append(BRUTE)
	for scene in loners:
		var pos = _pick_entity_spawn_position()
		if pos != null:
			arena.add_entity(scene, pos)
	# A Cyst (nest) on each of the map's sites; it hatches its guards itself.
	var cyst_sites: Array = arena.get_cyst_sites() if arena.has_method("get_cyst_sites") else []
	for site in cyst_sites:
		arena.add_entity(CYST, site.global_position)
	initial_population_done = true
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] World populated with ", count, " NPCs, ", packs, " Stalker packs, ",
				loners.size(), " Spitters/Brutes and ", cyst_sites.size(), " Cysts")


func _process(dt: float) -> void:
	if not initial_population_done:
		return

	time_since_last_player_damage += dt
	time_since_last_spawn += dt
	time_since_last_redirect += dt
	time_since_pack_respawn += dt

	print_timer -= dt
	if print_timer <= 0.0:
		print_timer = metrics_print_interval
		_print_metrics()

	soft_spawn_check_timer -= dt
	if soft_spawn_check_timer <= 0.0:
		soft_spawn_check_timer = soft_spawn_check_interval
		_try_soft_spawn()
		_try_pack_respawn()

	redirect_check_timer -= dt
	if redirect_check_timer <= 0.0:
		redirect_check_timer = redirect_check_interval
		_try_redirect()

	ambient_event_timer -= dt
	if ambient_event_timer <= 0.0:
		_try_ambient_event()
		# Randomized next interval so events feel unpredictable, not metronomic
		ambient_event_timer = randf_range(ambient_event_min_interval, ambient_event_max_interval)

	# TODO future interventions:
	# - Seed NPC-vs-NPC fights when player is far


func _print_metrics() -> void:
	if not Debug.get_setting("verbose_logging"):
		return
	if not is_instance_valid(arena.player):
		print("[ExpeditionDirector] player gone")
		return

	var npc_count = _alive_npc_count()
	var nearest = _nearest_enemy_distance()
	print("[ExpeditionDirector] fps=", Engine.get_frames_per_second(),
		"  frame_ms=", "%.1f" % (1000.0 / max(Engine.get_frames_per_second(), 1)),
		"  npcs=", npc_count,
		"  nearest_enemy_dist=", int(nearest),
		"  quiet_for=", int(time_since_last_player_damage), "s",
		"  npc_kills=", npc_vs_npc_kills,
		"  player_kills=", player_kills,
		"  player_deaths=", player_deaths,
		"  soft_spawns=", total_soft_spawns,
		"  redirects=", total_redirects,
		"  ambient=", total_ambient_events,
		"  entities=", arena.get_entities().size(),
		"  entity_kills=", entity_kills)


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
	# The "died" signal fires ~3s after death, so the killer may itself have
	# died and been freed by then — fall back to the name recorded at impact.
	var killer_name = str(src.get("name", "?"))
	var killer_valid = is_instance_valid(killer)
	if killer_valid and killer == mecha:
		return
	# Player getting killed is its own category — not a player kill, not NPC-vs-NPC.
	if mecha == arena.player:
		player_deaths += 1
		if Debug.get_setting("verbose_logging"):
			print("[ExpeditionDirector] player killed by ", killer_name)
	elif (killer_valid and killer == arena.player) or killer_name == "Player":
		player_kills += 1
		if Debug.get_setting("verbose_logging"):
			print("[ExpeditionDirector] player killed ", mecha.mecha_name)
	else:
		npc_vs_npc_kills += 1
		if Debug.get_setting("verbose_logging"):
			print("[ExpeditionDirector] npc-vs-npc: ", killer_name, " killed ", mecha.mecha_name)


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
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] soft-spawned ", enemy_name, " at ", pos,
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

	if not arena.has_method("get_spawn_zones"):
		return null
	var spawn_zones: Array = arena.get_spawn_zones()
	if spawn_zones.is_empty():
		return null

	var player_pos = arena.player.global_position
	var candidates: Array = []
	for zone in spawn_zones:
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


# ---- Entities ----

# A Stalker pack around center. size -1 = random (min_pack_size..max_pack_size).
func spawn_stalker_pack(center: Vector2, size := -1) -> EntityPack:
	if size < 0:
		size = randi_range(min_pack_size, max_pack_size)
	var pack := EntityPack.new()
	for i in size:
		var offset := Vector2(randf_range(-250.0, 250.0), randf_range(-250.0, 250.0))
		pack.add(arena.add_entity(STALKER, center + offset))
	return pack


func notify_entity_died(entity) -> void:
	var src = entity.last_damage_source
	if typeof(src) == TYPE_DICTIONARY and str(src.get("name", "")) == "Player":
		entity_kills += 1
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] ", entity.mecha_name, " died")


# A random map point far enough from the player, or null after a few tries.
func _pick_entity_spawn_position():
	for _i in 20:
		var pos: Vector2 = arena.get_random_position()
		if not is_instance_valid(arena.player) \
				or pos.distance_to(arena.player.global_position) >= min_entity_distance_from_player:
			return pos
	return null


# Newcomers wander in (out of sight) while the population is low.
func _try_pack_respawn() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	if total_pack_respawns >= max_pack_respawns:
		return
	if arena.get_entities().size() >= target_entity_population:
		return
	if time_since_pack_respawn < pack_respawn_cooldown:
		return
	var pos = _pick_offscreen_spawn_position()
	if pos == null:
		return
	var roll := randf()
	var arrival := "Stalker pack"
	if roll < arrival_brute_chance:
		arena.add_entity(BRUTE, pos)
		arrival = "Brute"
	elif roll < arrival_brute_chance + arrival_spitter_chance:
		arena.add_entity(SPITTER, pos)
		arrival = "Spitter"
	else:
		spawn_stalker_pack(pos)
	total_pack_respawns += 1
	time_since_pack_respawn = 0.0
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] a ", arrival, " arrived at ", pos)


# ---- Redirect ----

# When the player has been quiet for too long, gently nudge a distant idle NPC
# toward them by injecting a synthetic "loud noise" into the NPC's senses. The
# AI's existing roam → seek → alert flow handles the rest, so this never bypasses
# normal behaviour — it just feeds it new sensory data.
func _try_redirect() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return

	# Quiet check: only intervene during a real lull.
	if time_since_last_player_damage < quiet_threshold:
		return

	# Cooldown check: the central knob — never redirect more often than this.
	if time_since_last_redirect < redirect_cooldown:
		return

	var candidate = _find_distant_idle_npc()
	if candidate == null:
		return

	# Synthesize a "loud" noise event near the player. The NPC will path toward
	# it via roam_to_seek / alert transitions and pick up real targets when close.
	var dest = arena.player.global_position + Vector2(
		randf_range(-redirect_destination_jitter, redirect_destination_jitter),
		randf_range(-redirect_destination_jitter, redirect_destination_jitter)
	)
	candidate.heard_sound({
		"volume_type": "loud",
		"type": "gunshot",
		"position": dest,
		"source": null,  # synthetic — no source body
	})

	total_redirects += 1
	time_since_last_redirect = 0.0
	var dist_was = int(arena.player.global_position.distance_to(candidate.global_position))
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] redirected ", candidate.mecha_name,
			" toward player area (was ", dist_was, " away)")


# ---- Ambient events ----

# Fakes a "loud gunshot" sound at a distant point on the map. NPCs within
# ambient_event_sound_radius investigate via their normal roam → seek transition,
# creating emergent action at the spot. The player perceives this as "something
# happening over there" — life happening independent of them.
func _try_ambient_event() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return

	var pos = _pick_ambient_event_position()
	if pos == null:
		return

	# Broadcast a synthetic sound through the host's normal sound dispatcher
	# so distance gating, valid-listener filtering, etc. all work uniformly.
	var sound_data := {
		"volume_type": "loud",
		"type": "gunshot",
		"position": pos,
		"source": null,  # synthetic — no source body
		"max_distance": ambient_event_sound_radius,
	}
	if arena.has_method("_on_mecha_made_sound"):
		arena._on_mecha_made_sound(sound_data)

	total_ambient_events += 1
	var dist_from_player = int(arena.player.global_position.distance_to(pos))
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] ambient gunfire at ", pos,
			"  (", dist_from_player, " from player)")


# Picks a random valid point ambient_event_min_distance..max_distance from the
# player. Validates the candidate is on the navmesh so NPCs can actually reach
# the noise source. Returns null if no valid spot found in a few tries.
func _pick_ambient_event_position():
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return null

	var player_pos = arena.player.global_position
	var navpoly = null
	if arena.has_method("_get_map_nav_polygon"):
		navpoly = arena._get_map_nav_polygon()

	for _i in 10:
		var angle = randf() * TAU
		var dist = randf_range(ambient_event_min_distance, ambient_event_max_distance)
		var candidate = player_pos + Vector2(cos(angle), sin(angle)) * dist
		# If we have nav data, ensure the candidate is reachable
		if navpoly != null and arena.has_method("_is_position_on_nav"):
			if arena._is_position_on_nav(candidate, navpoly):
				return candidate
		else:
			# No nav data available — trust the random pick
			return candidate
	return null  # gave up after 10 tries


# Picks a random NPC that:
#   - is alive
#   - is far enough from the player to need pulling
#   - isn't already engaged with anyone
#   - isn't extracting (committed to leaving the world)
# Returns null if none qualify.
func _find_distant_idle_npc():
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return null

	var player_pos = arena.player.global_position
	var candidates: Array = []
	for m in arena.all_mechas:
		if not is_instance_valid(m):
			continue
		if m == arena.player:
			continue
		if "is_dead" in m and m.is_dead:
			continue
		# Skip NPCs already in a fight — pulling them out would be jarring.
		if "valid_target" in m and m.valid_target:
			continue
		# Skip NPCs that are extracting (committed to leaving).
		if m.has_method("get") and m.get("logic") != null:
			var state = m.logic.get_current_state()
			if typeof(state) == TYPE_STRING and state == "extract":
				continue
		# Heard_sound is on Enemy.gd — skip mechas that don't have it (e.g., player).
		if not m.has_method("heard_sound"):
			continue

		var d = player_pos.distance_to(m.global_position)
		if d >= min_redirect_distance:
			candidates.append(m)

	if candidates.is_empty():
		return null

	return candidates.pick_random()
