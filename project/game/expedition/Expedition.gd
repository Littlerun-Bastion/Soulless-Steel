extends "res://game/combat/CombatScene.gd"

# Expedition is the big-map living-world game mode. The ExpeditionDirector
# populates the map with NPCs and keeps it alive (respawns, redirects,
# ambient events). Arena (game/arena/) is the separate ladder mode.
#
# Combat plumbing shared with Arena (effects, deaths, pause, extraction,
# triggers, intro, prewarm, debug cam) lives in game/combat/CombatScene.gd.
# This script only does what's specific to Expedition: the map-driven layout,
# nav-aware spawning, the director, and the extraction flow.
#
# Required scene children (added in the .tscn), besides CombatScene's:
#   - Map (instance of database/maps/*.tscn)  provides BG, Walls, NavigationRegion2D,
#                                             StartPositions, Exits, Triggers and
#                                             (optionally) SpawnZones. The player
#                                             spawns at the first start position.
#   - ExpeditionDirector (Node)  the ExpeditionDirector.gd manager
#
# The map owns its layout: exits are found via the "exit_point" group, spawn
# zones via Map.get_spawn_zones(), and map triggers are connected on _ready
# ("story:..." triggers go to StoryDirector).
# Player.tscn has its own Camera2D — no scene-level camera required.

@onready var ExpeditionDirector = $ExpeditionDirector


func _ready() -> void:
	# FrameSpikeDetector is an autoload — its mark trail survives scene
	# changes and misattributes reload hitches to stale combat marks.
	# Stamp the boundary so teardown/load spikes are labeled correctly.
	FrameSpikeDetector.mark("scene_load:Expedition")
	randomize()
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)
	_setup_exits()
	_setup_triggers()
	_add_player()
	_setup_heatmap()

	# The intro cover must be up BEFORE the prewarm: _prewarm_fx awaits
	# several frames in which the scene actively renders (that's how the
	# pipelines compile), and those frames were visible as a flash of raw
	# scene + the player's force-emitted particles.
	IntroAnimation.play("Entrance")

	# Compile FX shader pipelines before anyone can shoot. NPCs fight each
	# other, so the first impact can happen before the player ever fires —
	# this must finish before ExpeditionDirector populates the world.
	await _prewarm_fx()

	ExpeditionDirector.start(self)

	# Freeze AI until the entrance animation finishes. Must run after
	# ExpeditionDirector.start (it iterates existing mechas), and the skip-intro stop
	# must come after the freeze — stop_animation fires the ending signal
	# that unfreezes everyone.
	set_mechas_block_status(true)
	if Debug.get_setting("skip_intro"):
		await get_tree().create_timer(.01).timeout
		IntroAnimation.stop_animation()

	# Tier 3: surface a clear goal via the standard mission system.
	# ExpeditionDirector still tracks its own kills for tuning; this adds player-facing
	# objectives on top.
	_setup_mission()


func _setup_triggers() -> void:
	# map_trigger instances under the Map's Triggers node. They only fire for
	# the player (see map_trigger.gd).
	if not (has_node("Map") and $Map.has_method("get_triggers")):
		return
	for trigger in $Map.get_triggers():
		if trigger.has_signal("trigger_entered"):
			trigger.connect("trigger_entered", Callable(self, "_on_player_trigger_entered"))


# ---- CombatScene hooks ----

# Tell ExpeditionDirector before removal so it can attribute the kill.
func _before_mecha_removed(mecha) -> void:
	if ExpeditionDirector:
		ExpeditionDirector.notify_mecha_died(mecha)


func _on_player_lost_health() -> void:
	super._on_player_lost_health()
	ExpeditionDirector.notify_player_damaged()


# ---- Spawning ----

func _add_player() -> void:
	player = PLAYER.instantiate()
	Mechas.add_child(player)
	# Player.setup() already restores PlayerProgress' current mecha as the
	# loadout (or falls back to the debug loadout). We additionally restore
	# the saved mech inventory so cargo carries over from the hangar.
	player.setup(self)
	player.mech_inventory = PlayerProgress.get_mech_inventory()
	player.position = _player_start_position()
	_connect_mecha_signals(player)
	player.connect("lost_health", Callable(self, "_on_player_lost_health"))
	player.connect("mecha_extracted", Callable(self, "_on_player_extracted"))
	all_mechas.append(player)
	# Player.tscn has its own Camera2D — no extra setup needed

	# Wire up the HUD (reload progress circle, lock-on, lifebar, etc.)
	PlayerHUD.setup(player, all_mechas)
	# Let MechOS know about the player so its windows can operate on the mech.
	MechOS.set_player(player)


func add_enemy(design_data, enemy_name: String, spawn_position = null) -> Mecha:
	var enemy = ENEMY.instantiate()
	Mechas.add_child(enemy)
	# Caller can pass an explicit position (used by ExpeditionDirector soft-spawns);
	# otherwise pick from Map start positions / SpawnZones via the helper.
	var pos: Vector2
	if spawn_position is Vector2:
		pos = spawn_position
	else:
		pos = _random_spawn_position()
	# Snap to a position inside the nav polygon. Spawning outside leaves the
	# NPC unable to path (NavAgent has no anchor) and they'd sit forever.
	pos = _ensure_position_on_nav(pos)
	enemy.position = pos
	_connect_mecha_signals(enemy)
	all_mechas.append(enemy)
	enemy.setup(self, design_data, enemy_name)
	return enemy


# ---- Positions (read by Enemy.gd / behaviours / ExpeditionDirector) ----

# Used by behaviours like default.gd for wandering points.
# Prefers (in order): instanced Map's nav polygon, scene POIs, fallback to origin.
func get_random_position() -> Vector2:
	# If a Map scene is instanced as a child, use its random-position logic
	if has_node("Map") and $Map.has_method("get_navigation_polygon"):
		var navpoly = $Map.get_navigation_polygon()
		if navpoly:
			var bounds = _get_navpoly_bounds(navpoly)
			for _i in 20:
				var p = Vector2(
					randf_range(bounds.position.x, bounds.end.x),
					randf_range(bounds.position.y, bounds.end.y)
				)
				if Geometry2D.is_point_in_polygon(p, navpoly.get_outline(0)):
					return p
	# Fallback to POI markers if present
	if has_node("POIs") and $POIs.get_child_count() > 0:
		var poi = $POIs.get_children().pick_random()
		var jitter = Vector2(randf_range(-200, 200), randf_range(-200, 200))
		return poi.global_position + jitter
	return global_position


func _get_navpoly_bounds(navpoly: NavigationPolygon) -> Rect2:
	var outline = navpoly.get_outline(0)
	if outline.size() == 0:
		return Rect2()
	var rect = Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		rect = rect.expand(p)
	return rect


# Returns the Map's NavigationPolygon if available, else null.
func _get_map_nav_polygon():
	if has_node("Map") and $Map.has_method("get_navigation_polygon"):
		return $Map.get_navigation_polygon()
	return null


# A position is "on the navmesh" if it's inside outline[0] (the outer
# boundary) AND not inside any other outline (those are holes — buildings,
# walls, etc.). Important for arena_oldgate which has many building footprints.
func _is_position_on_nav(pos: Vector2, navpoly) -> bool:
	if navpoly == null:
		return false
	var n = navpoly.get_outline_count()
	if n == 0:
		return false
	if not Geometry2D.is_point_in_polygon(pos, navpoly.get_outline(0)):
		return false
	# Reject if inside any hole
	for i in range(1, n):
		if Geometry2D.is_point_in_polygon(pos, navpoly.get_outline(i)):
			return false
	return true


# Walks an out-of-nav position toward the navmesh center until it lands inside
# the polygon (and outside any hole). Falls back to a Map StartPosition
# (guaranteed valid) and finally the bounds center as a last resort.
func _ensure_position_on_nav(pos: Vector2) -> Vector2:
	var navpoly = _get_map_nav_polygon()
	if navpoly == null:
		return pos  # no nav data — caller takes its chances
	if _is_position_on_nav(pos, navpoly):
		return pos

	# Walk toward the nav center and test at increasing fractions
	var center = _get_navpoly_bounds(navpoly).get_center()
	for t in [0.2, 0.4, 0.6, 0.8, 0.95]:
		var test = pos.lerp(center, t)
		if _is_position_on_nav(test, navpoly):
			return test

	# Fallback: a Map StartPosition is guaranteed valid
	return get_safe_position()


# Soft-spawn Marker2Ds owned by the Map (empty if the map has none). Used by
# _random_spawn_position and ExpeditionDirector's offscreen soft spawns.
func get_spawn_zones() -> Array:
	if has_node("Map") and $Map.has_method("get_spawn_zones"):
		return $Map.get_spawn_zones()
	return []


# Returns a position guaranteed to be reachable — used as a last-resort
# relocate target for NPCs that get stuck outside the navmesh somehow.
func get_safe_position() -> Vector2:
	if has_node("Map") and $Map.has_method("get_start_positions"):
		var spots = $Map.get_start_positions()
		if spots.size() > 0:
			return spots.pick_random().global_position
	var navpoly = _get_map_nav_polygon()
	if navpoly:
		return _get_navpoly_bounds(navpoly).get_center()
	return Vector2.ZERO


func _player_start_position() -> Vector2:
	# Prefer Map's first start position if a map is instanced
	if has_node("Map") and $Map.has_method("get_start_positions"):
		var spots = $Map.get_start_positions()
		if spots.size() > 0:
			return spots[0].global_position
	if has_node("PlayerStart"):
		return $PlayerStart.global_position
	return Vector2.ZERO


func _random_spawn_position() -> Vector2:
	# Prefer Map's other start positions for varied spawn spread
	if has_node("Map") and $Map.has_method("get_start_positions"):
		var spots = $Map.get_start_positions()
		if spots.size() > 1:
			# Skip index 0 (player) and pick from the rest
			var pool = spots.slice(1)
			var spot = pool.pick_random()
			var jitter = Vector2(randf_range(-200, 200), randf_range(-200, 200))
			return spot.global_position + jitter
	var zones := get_spawn_zones()
	if zones.size() > 0:
		var zone = zones.pick_random()
		var jitter = Vector2(randf_range(-100, 100), randf_range(-100, 100))
		return zone.global_position + jitter
	return Vector2(randf_range(-500, 500), randf_range(-500, 500))


# ---- Extraction and mission ----

func _on_player_extracted(_mecha) -> void:
	# Mission objective: extraction. Transition back to the main menu so the
	# player can start another expedition, customize their mech, etc. (Skipping the
	# Arena payout/ladder flow on purpose — Tier 3 default for this scene.)
	MissionManager.report_extraction()
	TransitionManager.transition_to(
		"res://game/start_menu/StartMenu.tscn",
		"Rebooting System..."
	)


# Standard "Survive and Extract" objectives mirrored from Arena's default.
# Kills are reported in CombatScene._on_mecha_died, extraction in _on_player_extracted.
func _setup_mission() -> void:
	var mission = MissionData.new()
	mission.mission_name = "Survive and Extract"
	mission.add_objective("kill", "Eliminate enemies", 3)
	mission.add_objective("extract", "Extract from the arena", 1)
	# Used only if no messenger contract is active (see MissionManager).
	MissionManager.start_default_mission(mission)
