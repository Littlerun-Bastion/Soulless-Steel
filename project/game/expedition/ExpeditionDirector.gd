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
## How many spawns are squads (Expedition.add_squad), and how many of those
## are threes rather than pairs. Placeholders.
@export var squad_chance: float = 0.4
@export var squad_three_chance: float = 0.34
## Companions the player deploys with (Expedition.add_companion), for a
## mission that provides them. Placeholder.
@export var starting_companions: int = 0

@export_group("Map Size")
## The counts here (NPCs, Entities, their targets and caps) are for a map
## reference_map_size px across. A map with a larger navigation area
## multiplies them by its area over that one's, up to max_population_scale
## (population_scale()); the NPCs always on the map (the roaming ones and
## soft spawns) only up to max_npc_population_scale (scaled_npcs), the
## rest of a big map's people being roamers in camps.
@export var reference_map_size: float = 50000.0
@export var max_population_scale: float = 2.0
@export var max_npc_population_scale: float = 1.0
## On a map that tells open ground (Expedition.is_spawn_spot_open),
## initial_near_share of the starting NPCs and Entities spawn
## min_spawn_distance_from_player..max_spawn_distance_from_player px from the
## player, the rest anywhere on the map, and later arrivals (soft spawns and
## Entity newcomers) all come in that ring. Elsewhere they use the map's
## start positions and SpawnZones.
@export var initial_near_share: float = 0.5
@export var max_spawn_distance_from_player: float = 16000.0

# Soft-spawn tunables — the world replenishes itself as NPCs die or extract.
@export_group("Soft Spawns")
@export var target_population: int = 12                  # below this, soft-spawn engages
@export var critical_population: int = 3                 # below this, use the shorter cooldown
@export var soft_spawn_cooldown: float = 30.0            # seconds between spawns when above critical
@export var soft_spawn_critical_cooldown: float = 10.0   # seconds between spawns when at/below critical
@export var max_total_soft_spawns: int = 30              # hard cap (safety net)
@export var min_spawn_distance_from_player: float = 5000.0  # don't pop in next to the player
@export var soft_spawn_check_interval: float = 5.0       # how often to evaluate
## Nothing appears where the player can see it: spawn points (NPCs and
## Entities) within the player's sight circle (Mecha.sight_radius) plus this
## (px) are skipped, besides the distances above.
@export var spawn_sight_margin: float = 1500.0

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

# Entities (creatures, game/entities/) — Coyote packs (each with one or two
# Coyote Spitters) and a Fisher or two roam the map from the start, well
# away from the player. While the population is low, newcomers wander in now
# and then: mostly Coyote packs, sometimes a Fisher.
# With the Debug setting "entity_camps" on (the default), each is a Camp
# instead (CampField, the `camps` child): off the map until something that
# could notice it comes near, then on it until everyone has gone again.
# The first species (Stalker, Spitter, Brute and Cyst) have their scenes in
# game/entities/, but nothing here spawns them, and the map's cyst sites are
# unused.
@export_group("Entities")
@export var min_initial_packs: int = 2
@export var max_initial_packs: int = 4
## Coyotes in a pack, Spitters included.
@export var min_pack_size: int = 4
@export var max_pack_size: int = 6
@export var min_pack_spitters: int = 1
@export var max_pack_spitters: int = 2
@export var min_initial_fishers: int = 1
@export var max_initial_fishers: int = 2
@export var min_entity_distance_from_player: float = 3500.0
@export var target_entity_population: int = 10           # below this, newcomers may arrive
@export var pack_respawn_cooldown: float = 75.0          # seconds between arrivals
@export var max_pack_respawns: int = 6                   # hard cap per run
@export var arrival_fisher_chance: float = 0.25          # an arrival is a Fisher, else a Coyote pack
## Tick swarms at the start (placeholder). They don't arrive later; they
## breed (TickSwarm.spawn_brood comes through spawn_tick_brood).
@export var min_initial_tick_swarms: int = 3
@export var max_initial_tick_swarms: int = 5
## Most Entities on the map (tick swarms count). A brood that would go over
## it makes the oldest tick swarm the player can't see fade out
## (placeholder).
@export var entity_population_cap: int = 40

# Camps (CampField) and the encounters the tension (TensionMeter) arms: a
# fight under way at one of encounter_sites spots laid out over the map at
# the start, encounter_min_distance..encounter_max_distance px from the
# player, at most max_armed_encounters at once. Once a check interval, an
# encounter is armed with a chance of the pressure (TensionMeter.pressure)
# times encounter_chance, if the pressure is at least min_encounter_pressure.
# A site's district decides the kind: duel_chance of a duel (two NPCs),
# else a hunt (an NPC and a Coyote pack). awake_entity_budget is the most
# Entities on the map before a waking camp holds members back. Placeholders.
@export_group("Camps")
@export var awake_entity_budget: int = 24
@export var encounter_sites: int = 30
@export var encounter_min_distance: float = 6000.0
@export var encounter_max_distance: float = 24000.0
@export var max_armed_encounters: int = 2
@export var encounter_check_interval: float = 10.0
@export var min_encounter_pressure: float = 0.2
@export var encounter_chance: float = 0.5
@export var duel_chance := {"industrial": 0.6, "market": 0.6, "residential": 0.3, "farmland": 0.2}
## Roamers (CampField.add_roamer): NPCs and squads that travel the map off
## it until someone could notice them. min_initial_roamers..
## max_initial_roamers at the start, anywhere on the map like the starting
## NPCs; while fewer than target_roamers are dormant, a newcomer arrives
## every roamer_arrival_cooldown s, out of the player's sight. Each stays
## roamer_stay s (a random time in that range), then leaves the map. Squads
## as for NPCs (squad_chance, squad_three_chance). Counts are scaled to the
## map (scaled). Placeholders.
@export var min_initial_roamers: int = 2
@export var max_initial_roamers: int = 4
@export var target_roamers: int = 4
@export var roamer_arrival_cooldown: float = 150.0
@export var roamer_stay := Vector2(480.0, 1200.0)

const COYOTE = preload("res://game/entities/coyote/Coyote.tscn")
const COYOTE_SPITTER = preload("res://game/entities/coyote/CoyoteSpitter.tscn")
const FISHER = preload("res://game/entities/fisher/Fisher.tscn")
const TICK_SWARM = preload("res://game/entities/tick/TickSwarm.tscn")
const TICK_BROOD = preload("res://game/entities/tick/TickBrood.tscn")

## Random spots tried for one spawn before giving up.
const SPOT_TRIES := 40

var arena                                   # Ref to Expedition (acts as arena)
var initial_population_done: bool = false
var _population_scale: float = 1.0
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

# Camps and tension
var camps: CampField = null
var tension := TensionMeter.new()
var elapsed: float = 0.0
var encounters_armed: int = 0
var _tension_timer: float = 0.0
var _encounter_timer: float = 0.0
var total_roamer_arrivals: int = 0
var time_since_roamer_arrival: float = 0.0
var _roamer_index: int = 0


func start(arena_ref) -> void:
	arena = arena_ref
	_population_scale = _measure_population_scale()
	if uses_camps():
		camps = CampField.new()
		camps.name = "Camps"
		add_child(camps)
		camps.setup(arena, awake_entity_budget)
		camps.camp_woken.connect(_on_camp_woken)
	# Hits on the player's components end a lull (the redirect timer, the
	# tension).
	var player = arena.get("player")
	if is_instance_valid(player) and player.has_signal("component_damaged") \
			and not player.component_damaged.is_connected(_on_player_component_damaged):
		player.component_damaged.connect(_on_player_component_damaged)
	_populate_initial_world()
	if camps != null:
		_lay_out_encounter_sites()
	set_process(true)


## Whether Entities wait in camps (the Debug setting "entity_camps").
static func uses_camps() -> bool:
	return Debug.debug_settings.get("entity_camps", true) != false


func _on_player_component_damaged(_part, _component, _hp, _max_hp) -> void:
	notify_player_damaged()


## What the counts are multiplied by on this map (see reference_map_size).
func population_scale() -> float:
	return _population_scale


## A count from the exports, scaled to this map.
func scaled(count: int) -> int:
	return roundi(count * _population_scale)


## An NPC count from the exports, scaled to this map up to
## max_npc_population_scale.
func scaled_npcs(count: int) -> int:
	return roundi(count * minf(_population_scale, maxf(max_npc_population_scale, 0.0)))


func _measure_population_scale() -> float:
	if not arena.has_method("_get_map_nav_polygon"):
		return 1.0
	var navpoly = arena._get_map_nav_polygon()
	if navpoly == null or reference_map_size <= 0.0:
		return 1.0
	var size: Vector2 = arena._get_navpoly_bounds(navpoly).size
	return clampf(size.x * size.y / (reference_map_size * reference_map_size), 1.0, maxf(max_population_scale, 1.0))


func _populate_initial_world() -> void:
	var count = randi_range(scaled_npcs(min_initial_enemies), scaled_npcs(max_initial_enemies))
	var spawned := 0
	var spawn_index := 0
	while spawned < count:
		var pos = _pick_initial_spot(min_spawn_distance_from_player)
		if arena.has_method("add_squad") and randf() < squad_chance:
			var size := 3 if randf() < squad_three_chance else 2
			var squad: Squad = arena.add_squad(size, "NPC_" + str(spawn_index), pos)
			spawned += squad.members.size()
		else:
			arena.add_enemy(NPCManager.random_design_data(), "NPC_" + str(spawn_index), pos)
			spawned += 1
		spawn_index += 1
	if arena.has_method("add_companion"):
		for k in starting_companions:
			arena.add_companion()
	var packs := 0
	for i in randi_range(scaled(min_initial_packs), scaled(max_initial_packs)):
		var pos = _pick_entity_spawn_position()
		if pos != null:
			add_coyote_pack(pos)
			packs += 1
	var fishers := 0
	for i in randi_range(scaled(min_initial_fishers), scaled(max_initial_fishers)):
		var pos = _pick_entity_spawn_position()
		if pos != null:
			add_fisher(pos)
			fishers += 1
	var swarms := 0
	for i in randi_range(scaled(min_initial_tick_swarms), scaled(max_initial_tick_swarms)):
		var pos = _pick_entity_spawn_position()
		if pos != null:
			add_tick_swarm(pos)
			swarms += 1
	var roamers := 0
	if camps != null:
		for i in randi_range(scaled(min_initial_roamers), scaled(max_initial_roamers)):
			var pos = _pick_initial_spot(min_spawn_distance_from_player)
			if pos != null:
				add_roamer(pos)
				roamers += 1
	initial_population_done = true
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] World populated with ", spawned, " NPCs, ", roamers, " roamers, ", packs, " Coyote packs, ",
				fishers, " Fishers and ", swarms, " tick swarms (population scale ", _population_scale, ")")


# A starting spot at least min_distance px from the player: with chance
# initial_near_share in the ring out to max_spawn_distance_from_player,
# otherwise anywhere on the map. Null where the map can't tell open ground
# or nothing open was found, leaving the choice to the arena.
func _pick_initial_spot(min_distance: float):
	if randf() < initial_near_share:
		var near = _pick_open_spot(min_distance, max_spawn_distance_from_player)
		if near != null:
			return near
	return _pick_open_spot(min_distance, INF)


# A random spot min_distance..max_distance px from the player (INF: anywhere
# on the map), outside its sight, on open ground and away from the exits;
# null after SPOT_TRIES tries, or on a map that can't tell open ground.
func _pick_open_spot(min_distance: float, max_distance: float):
	if not is_instance_valid(arena) or not arena.has_method("is_spawn_spot_open") \
			or not is_instance_valid(arena.player):
		return null
	var from: Vector2 = arena.player.global_position
	for _i in SPOT_TRIES:
		var p: Vector2
		if is_inf(max_distance):
			p = arena.get_random_position()
			if p.distance_to(from) < min_distance:
				continue
		else:
			var r := sqrt(randf_range(min_distance * min_distance, max_distance * max_distance))
			p = from + Vector2.from_angle(randf() * TAU) * r
		if not _in_player_sight(p) and arena.is_spawn_spot_open(p) and not arena.is_near_exit(p):
			return p
	return null


func _process(dt: float) -> void:
	if not initial_population_done:
		return

	time_since_last_player_damage += dt
	time_since_last_spawn += dt
	time_since_last_redirect += dt
	time_since_pack_respawn += dt
	time_since_roamer_arrival += dt
	elapsed += dt

	_tension_timer -= dt
	if _tension_timer <= 0.0:
		_tension_timer = 1.0
		tension.advance(1.0, player_in_fight(), elapsed)
	if camps != null:
		_encounter_timer -= dt
		if _encounter_timer <= 0.0:
			_encounter_timer = encounter_check_interval
			_try_arm_encounter()

	print_timer -= dt
	if print_timer <= 0.0:
		print_timer = metrics_print_interval
		_print_metrics()

	soft_spawn_check_timer -= dt
	if soft_spawn_check_timer <= 0.0:
		soft_spawn_check_timer = soft_spawn_check_interval
		_try_soft_spawn()
		_try_pack_respawn()
		_try_roamer_arrival()

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
		"  entity_kills=", entity_kills,
		"  camps=", _camp_summary(),
		"  tension=", "%.2f" % tension.value,
		"  encounters=", encounters_armed)


func _camp_summary() -> String:
	if camps == null:
		return "off"
	var dormant := 0
	var awake := 0
	for camp in camps.camps:
		if camp.state == Camp.State.AWAKE:
			awake += 1
		elif camp.state == Camp.State.DORMANT:
			dormant += 1
	return "%d dormant/%d awake (%d roamers dormant)" % [dormant, awake, camps.dormant_roamers().size()]


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

# Replenish the world's NPC population when it dips below target, at a spot
# the player can't see (_pick_offscreen_spawn_position).
# Gated by cooldown + hard cap so it can't spam.
func _try_soft_spawn() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	if total_soft_spawns >= scaled_npcs(max_total_soft_spawns):
		return

	var pop = _alive_npc_count()
	if pop >= scaled_npcs(target_population):
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

	var enemy_name = "Soft_" + str(total_soft_spawns)
	if arena.has_method("add_squad") and randf() < squad_chance:
		var size := 3 if randf() < squad_three_chance else 2
		arena.add_squad(size, enemy_name, pos)
	else:
		var enemy = arena.add_enemy(NPCManager.random_design_data(), enemy_name, pos)
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


# A spot for a newcomer the player can't see: in the ring round the player
# (_pick_open_spot) on a map that tells open ground, else a SpawnZone far
# enough from the player with a small random jitter; null if none qualifies.
func _pick_offscreen_spawn_position():
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return null

	var near = _pick_open_spot(min_spawn_distance_from_player, max_spawn_distance_from_player)
	if near != null:
		return near

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
		if d >= min_spawn_distance_from_player and not _in_player_sight(zone.global_position):
			candidates.append(zone)

	if candidates.is_empty():
		return null

	var pick = candidates.pick_random()
	var jitter = Vector2(randf_range(-200, 200), randf_range(-200, 200))
	return pick.global_position + jitter


# ---- Entities ----

# A Coyote pack around center: size Coyotes (-1 = random, min_pack_size..
# max_pack_size), min_pack_spitters..max_pack_spitters of them Spitters, and
# always at least one Spitter and one Coyote to lead.
func spawn_coyote_pack(center: Vector2, size := -1) -> EntityPack:
	if size < 0:
		size = randi_range(min_pack_size, max_pack_size)
	size = maxi(size, 2)
	var spitters := clampi(randi_range(min_pack_spitters, max_pack_spitters), 1, size - 1)
	var pack := EntityPack.new()
	# The leader is the first living member: Coyotes go in first.
	for i in size:
		var offset := Vector2(randf_range(-250.0, 250.0), randf_range(-250.0, 250.0))
		var scene: PackedScene = COYOTE_SPITTER if i >= size - spitters else COYOTE
		pack.add(arena.add_entity(scene, center + offset))
	return pack


# A Fisher, dormant in its shell, on the nav mesh near pos.
func spawn_fisher(pos: Vector2) -> Entity:
	return arena.add_entity(FISHER, pos)


func spawn_tick_swarm(pos: Vector2) -> Entity:
	return arena.add_entity(TICK_SWARM, pos)


# The same three as camps when the director has them (a dormant Camp, sized
# like the spawns above), else on the map straight away.
func add_coyote_pack(center: Vector2) -> void:
	if camps == null:
		spawn_coyote_pack(center)
		return
	var size := randi_range(min_pack_size, max_pack_size)
	camps.add_camp(Camp.PACK, center, size, randi_range(min_pack_spitters, max_pack_spitters))


func add_fisher(pos: Vector2) -> void:
	if camps == null:
		spawn_fisher(pos)
	else:
		camps.add_camp(Camp.FISHER, pos)


func add_tick_swarm(pos: Vector2) -> void:
	if camps == null:
		spawn_tick_swarm(pos)
	else:
		camps.add_camp(Camp.TICK_SWARM, pos)


## A camp of `kind` for a quest's target: pinned (never held back, never
## dropped), at a spot like any Entity's. Null without camps or a spot.
## CampField.hint_circle gives the area to show the player.
func add_quest_camp(kind: String) -> Camp:
	if camps == null:
		return null
	var pos = _pick_entity_spawn_position()
	if pos == null:
		return null
	return camps.add_pinned_camp(kind, pos)


## Entities in the world: on the map, and in dormant camps' rosters.
func entity_population() -> int:
	var count: int = arena.get_entities().size()
	if camps != null:
		for camp in camps.camps:
			count += camp.roster.size()
	return count


# A brood (TickSwarm.spawn_brood), within the population cap: over it, the
# oldest tick swarm the player can't see fades out first. If the player can
# see every one, the brood forms anyway.
func spawn_tick_brood(pos: Vector2) -> Entity:
	if arena.get_entities().size() + 1 > scaled(entity_population_cap):
		var oldest: TickSwarm = null
		for entity in arena.get_entities():
			if entity is TickSwarm and not entity.is_dead and not _player_sees(entity) \
					and (oldest == null or entity.born < oldest.born):
				oldest = entity
		if oldest != null:
			oldest.fade_out()
	return arena.add_entity(TICK_BROOD, pos)


# Whether the player can see this body now: on screen and not hidden from
# its view (Player.is_hidden_from_view).
func _player_sees(body: Node2D) -> bool:
	var player = arena.get("player")
	if not is_instance_valid(player):
		return false
	if player.has_method("is_hidden_from_view") and player.is_hidden_from_view(body):
		return false
	return MapSenses.screen_rect(player).has_point(body.global_position)


func notify_entity_died(entity) -> void:
	var src = entity.last_damage_source
	if typeof(src) == TYPE_DICTIONARY and str(src.get("name", "")) == "Player":
		entity_kills += 1
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] ", entity.mecha_name, " died")


# A starting spot for an Entity far enough from the player and outside its
# sight: _pick_initial_spot on a map that tells open ground, else a random
# map point; null after a few tries.
func _pick_entity_spawn_position():
	var open = _pick_initial_spot(min_entity_distance_from_player)
	if open != null:
		return open
	for _i in 20:
		var pos: Vector2 = arena.get_random_position()
		if not is_instance_valid(arena.player) \
				or (pos.distance_to(arena.player.global_position) >= min_entity_distance_from_player \
				and not _in_player_sight(pos)):
			return pos
	return null


# Whether `pos` is within the player's sight circle plus spawn_sight_margin.
func _in_player_sight(pos: Vector2) -> bool:
	var player = arena.get("player") if is_instance_valid(arena) else null
	if not is_instance_valid(player) or not player.has_method("sight_radius"):
		return false
	return pos.distance_to(player.global_position) < player.sight_radius() + spawn_sight_margin


# Newcomers wander in (out of sight) while the population is low.
func _try_pack_respawn() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	if total_pack_respawns >= scaled(max_pack_respawns):
		return
	if entity_population() >= scaled(target_entity_population):
		return
	if time_since_pack_respawn < pack_respawn_cooldown:
		return
	var pos = _pick_offscreen_spawn_position()
	if pos == null:
		return
	var arrival := "Coyote pack"
	if randf() < arrival_fisher_chance:
		add_fisher(pos)
		arrival = "Fisher"
	else:
		add_coyote_pack(pos)
	total_pack_respawns += 1
	time_since_pack_respawn = 0.0
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] a ", arrival, " arrived at ", pos)


# ---- Roamers ----

## A dormant roamer at `pos`: one NPC, or a squad (squad_chance), staying
## roamer_stay s. Null without camps.
func add_roamer(pos: Vector2) -> Camp:
	if camps == null:
		return null
	_roamer_index += 1
	var designs: Array = []
	var squad := {}
	if arena.has_method("_free_squad_tag") and randf() < squad_chance:
		designs = NPCManager.pick_squad_designs(3 if randf() < squad_three_chance else 2)
		squad = {"tag": arena._free_squad_tag(), "anonymous": randf() < arena.SQUAD_ANONYMOUS_CHANCE}
		for design in designs:
			if squad.anonymous:
				design["anonymous"] = true
			else:
				design["squad_tag"] = squad.tag
	else:
		designs = [NPCManager.random_design_data()]
	var stay := randf_range(roamer_stay.x, roamer_stay.y)
	return camps.add_roamer(designs, pos, squad, camps.clock + stay)


# A newcomer, while few roamers are about (see the Camps exports).
func _try_roamer_arrival() -> void:
	if camps == null or not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	if camps.dormant_roamers().size() >= scaled(target_roamers) or time_since_roamer_arrival < roamer_arrival_cooldown:
		return
	var pos = _pick_offscreen_spawn_position()
	if pos == null:
		return
	add_roamer(pos)
	total_roamer_arrivals += 1
	time_since_roamer_arrival = 0.0
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] a roamer arrived at ", pos)


# With no distant idle NPC to redirect, a dormant roamer far enough away is
# sent toward the player instead.
func _redirect_roamer() -> void:
	if camps == null:
		return
	var from: Vector2 = arena.player.global_position
	var far := camps.dormant_roamers().filter(func(c): return c.site.distance_to(from) >= min_redirect_distance)
	if far.is_empty():
		return
	var dest := from + Vector2(randf_range(-redirect_destination_jitter, redirect_destination_jitter),
			randf_range(-redirect_destination_jitter, redirect_destination_jitter))
	camps.send_roamer(far.pick_random(), dest)
	total_redirects += 1
	time_since_last_redirect = 0.0


# ---- Tension and encounters ----

## Whether the player is in a fight: hit in the last few seconds, or hunted
## by something on the map (an NPC with it as its target, an Entity after
## it).
func player_in_fight() -> bool:
	var player = arena.get("player") if is_instance_valid(arena) else null
	if not is_instance_valid(player) or player.is_dead:
		return false
	if time_since_last_player_damage < 5.0:
		return true
	for m in arena.all_mechas:
		if is_instance_valid(m) and m != player and not m.is_dead and is_same(m.get("valid_target"), player):
			return true
	for entity in arena.get_entities():
		if is_instance_valid(entity) and not entity.is_dead and entity.target == player:
			return true
	return false


# Lays out the encounter sites (CampField.lay_out_sites): open ground away
# from the exits, anywhere on the map.
func _lay_out_encounter_sites() -> void:
	var points := []
	for i in scaled(encounter_sites):
		var p = _pick_open_spot(0.0, INF)
		if p != null:
			points.append(p)
	camps.lay_out_sites(points)


func _player_wholeness() -> float:
	var player = arena.get("player")
	if not is_instance_valid(player) or not (player is Mecha):
		return 1.0
	return NPCKnowledge._structural_health(player)


# Arms an encounter when the pressure calls for one (see the Camps exports).
func _try_arm_encounter() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	if camps.armed_encounters().size() >= max_armed_encounters:
		return
	var pressure := tension.pressure(_player_wholeness())
	if pressure < min_encounter_pressure or randf() >= pressure * encounter_chance:
		return
	var site = camps.pick_site(arena.player.global_position, encounter_min_distance, encounter_max_distance)
	if site == null or _in_player_sight(site.position):
		return
	var kind := Camp.DUEL if randf() < float(duel_chance.get(site.district, 0.3)) else Camp.HUNT
	camps.arm_encounter(kind, site, pressure)
	encounters_armed += 1
	if Debug.get_setting("verbose_logging"):
		print("[ExpeditionDirector] a ", kind, " began at ", site.position, " (", site.district, ", pressure ",
				"%.2f" % pressure, ")")


func _on_camp_woken(_camp: Camp, was_encounter: bool) -> void:
	if was_encounter:
		tension.found_encounter()


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
		_redirect_roamer()
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
