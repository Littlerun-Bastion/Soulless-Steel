extends Node2D

# LivingWorldTest is a minimal "arena-like" host for the Director system.
# It implements just enough of the Arena interface that Player.gd, Enemy.gd,
# and the AI behaviours work — without inheriting Arena's mission/ladder/
# exhibition coupling. Iterate the Director here freely.
#
# Required scene children (added in the .tscn):
#   - Map (instance of database/maps/*.tscn)  provides BG, Walls, NavigationRegion2D,
#                                             StartPositions; player spawns at the
#                                             Map's first start position
#   - Mechas (Node2D)        container for player + NPCs
#   - Projectiles (Node2D)   bullets, missiles, etc. land here
#   - SpawnZones (Node2D)    Marker2D children — fallback spawn points for the
#                            Director when the Map runs out of start positions
#   - Exits (Node2D)         ExitPoint instances (also auto-discovered via
#                            the "exit_point" group, even if inside Map)
#   - Director (Node)        the Director.gd manager
# Player.tscn has its own Camera2D — no scene-level camera required.

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")
const SCRAP_PART = preload("res://game/arena/ScrapPart.tscn")

@onready var Mechas = $Mechas
@onready var Projectiles = $Projectiles
@onready var Trails = $Trails
@onready var Flashes = $Flashes
@onready var Smoke = $Smoke
@onready var Explosions = $Explosions
@onready var ScrapParts = $ScrapParts
@onready var Heatmap = $HeatmapEffects
@onready var Director = $Director
@onready var PlayerHUD = $PlayerHUD

var player
var all_mechas: Array = []


func _ready() -> void:
	randomize()
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)
	_setup_exits()
	_add_player()
	Director.start(self)
	# Heatmap depends on the player's head part; configure after spawn.
	if player and player.build.head and player.build.head.heatmap:
		Heatmap.change_heatmap(player.build.head.heatmap)
	AudioManager.play_bgm("ambience", true, 40)


func _process(_dt: float) -> void:
	if player:
		ShaderEffects.update_shader_effect(player)


func _setup_exits() -> void:
	# Wire all ExitPoint instances (in this scene OR in the Map child) so any
	# mecha entering an exit area starts the extract timer, and leaving cancels.
	for exit in get_tree().get_nodes_in_group("exit_point"):
		if not exit.is_connected("mecha_extracting", Callable(self, "_on_exit_mecha_extracting")):
			exit.connect("mecha_extracting", Callable(self, "_on_exit_mecha_extracting"))
		if not exit.is_connected("extracting_cancelled", Callable(self, "_on_exit_extracting_cancelled")):
			exit.connect("extracting_cancelled", Callable(self, "_on_exit_extracting_cancelled"))


# ---- Spawning ----

func _add_player() -> void:
	player = PLAYER.instantiate()
	Mechas.add_child(player)
	player.setup(self)
	player.position = _player_start_position()
	player.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
	player.connect("create_casing", Callable(self, "_on_mecha_create_casing"))
	player.connect("died", Callable(self, "_on_mecha_died"))
	player.connect("exposed", Callable(self, "_on_mecha_exposed"))
	player.connect("made_sound", Callable(self, "_on_mecha_made_sound"))
	player.connect("lost_health", Callable(self, "_on_player_lost_health"))
	player.connect("mecha_extracted", Callable(self, "_on_player_extracted"))
	all_mechas.append(player)
	# Player.tscn has its own Camera2D — no extra setup needed

	# Wire up the HUD (reload progress circle, lock-on, lifebar, etc.)
	PlayerHUD.setup(player, all_mechas)


func add_enemy(design_data, enemy_name: String, spawn_position = null) -> Mecha:
	var enemy = ENEMY.instantiate()
	Mechas.add_child(enemy)
	# Caller can pass an explicit position (used by Director soft-spawns);
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
	enemy.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
	enemy.connect("create_casing", Callable(self, "_on_mecha_create_casing"))
	enemy.connect("died", Callable(self, "_on_mecha_died"))
	enemy.connect("exposed", Callable(self, "_on_mecha_exposed"))
	enemy.connect("made_sound", Callable(self, "_on_mecha_made_sound"))
	all_mechas.append(enemy)
	enemy.setup(self, design_data, enemy_name)
	return enemy


# ---- Arena interface (read by Player.gd / Enemy.gd / behaviours) ----

func get_mechas() -> Array:
	return all_mechas


func get_lock_areas() -> Array:
	var areas := []
	for m in all_mechas:
		if is_instance_valid(m) and m.has_method("get_lock_area"):
			areas.append(m.get_lock_area())
	return areas


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


# ---- Internal helpers ----

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
	if has_node("SpawnZones") and $SpawnZones.get_child_count() > 0:
		var zone = $SpawnZones.get_children().pick_random()
		var jitter = Vector2(randf_range(-100, 100), randf_range(-100, 100))
		return zone.global_position + jitter
	return Vector2(randf_range(-500, 500), randf_range(-500, 500))


# ---- Signal handlers ----

func _on_mecha_create_projectile(mecha, args, weapon) -> void:
	# Handle bullet-spread delay before spawning (some weapons have spread shots)
	if args.bullet_spread_delay > 0:
		var delay = randf_range(0, args.bullet_spread_delay)
		if delay > 0:
			await get_tree().create_timer(delay).timeout

	var data = ProjectileManager.create(mecha, args, weapon)
	if data and data.create_node:
		Projectiles.add_child(data.node)
		# Wire downstream FX signals so impacts spawn explosions and trails
		if data.node.has_signal("bullet_impact"):
			data.node.connect("bullet_impact", Callable(self, "_on_bullet_impact"))
		if data.node.has_signal("create_trail"):
			data.node.connect("create_trail", Callable(self, "_on_create_trail"))
		if data.node.has_signal("create_projectile"):
			data.node.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
		# Muzzle flash at the firing point
		if args.muzzle_flash != null and args.pos_reference != null and is_instance_valid(args.node_reference):
			var flash = ProjectileManager.create_muzzle_flash(args.node_reference, args.muzzle_flash, args.pos_reference, args.dir)
			Flashes.add_child(flash)


func _on_mecha_create_casing(args) -> void:
	# Ejects a spent bullet casing from the CasingsQueue particle pool.
	var next_casing = $Casings.get_next_particle()
	next_casing.global_position = args.casing_ejector_pos
	next_casing.rotation_degrees = args.casing_eject_angle
	$Casings.trigger(args.casing_size)


func _on_bullet_impact(projectile, effect, clear, body) -> void:
	if effect:
		var impact_effect = ProjectileManager.create_explosion(projectile, effect)
		var mecha_hit = false
		if body and body.is_in_group("mecha"):
			mecha_hit = true
		impact_effect.setup(projectile.impact_size, projectile.global_rotation, mecha_hit, projectile.shield_hit)
		Explosions.add_child(impact_effect)
	if clear:
		projectile.queue_free()


func _on_create_trail(projectile, trail) -> void:
	if trail:
		var created_trail = ProjectileManager.create_trail(projectile, trail)
		Trails.add_child(created_trail)


func _on_mecha_exposed(_mecha) -> void:
	# Hook point — Director already tracks downs via notify_mecha_died, so
	# nothing to do here yet. Kept for future "first-blood" / "exposed" UI.
	pass


func _on_mecha_died(mecha) -> void:
	mecha.is_dead = true
	# Tell Director before removal so it can attribute the kill
	if Director:
		Director.notify_mecha_died(mecha)
	create_mecha_scraps(mecha)
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove_at(idx)
	if mecha != player:
		mecha.queue_free()
	else:
		print("[LivingWorldTest] Player died")


# Spawns debris particles from a dead mecha — visual feedback for kills.
func create_mecha_scraps(mecha) -> void:
	if not mecha.has_method("get_scrapable_parts"):
		return
	for part in mecha.get_scrapable_parts():
		var scrap = SCRAP_PART.instantiate()
		scrap.setup(part.texture)
		scrap.position = mecha.position
		scrap.update_scale(mecha.scale)
		var mat = part.material
		if mat:
			scrap.set_heat_parameters(mat.get_shader_parameter("heat"), mat.get_shader_parameter("min_darkness"))

		var impulse_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var impulse_force = randf_range(400, 700)
		var impulse_torque = randf_range(10, 20)
		if randf() > 0.5:
			impulse_torque = -impulse_torque
		scrap.apply_impulse(impulse_dir * impulse_force, Vector2())
		scrap.apply_torque_impulse(impulse_torque)
		ScrapParts.call_deferred("add_child", scrap)


func _on_mecha_made_sound(sound_data) -> void:
	for m in all_mechas:
		if m == sound_data.source or not is_instance_valid(m):
			continue
		if not m.has_method("heard_sound"):
			continue
		if m.global_position.distance_to(sound_data.position) <= sound_data.max_distance:
			m.heard_sound(sound_data)


func _on_player_lost_health() -> void:
	ShaderEffects.damage_burst_effect()
	Director.notify_player_damaged()


func _on_player_extracted(_mecha) -> void:
	# Test scene end-of-match handling — just print for now.
	# Could route to a scoreboard or back to the main menu later.
	print("[LivingWorldTest] Player extracted — match end")


# ---- Exit handling (mirrors Arena's ExitPoint signal flow) ----

func _on_exit_mecha_extracting(extracting_mech) -> void:
	if not is_instance_valid(extracting_mech):
		return
	if extracting_mech.has_method("extracting"):
		extracting_mech.extracting()


func _on_exit_extracting_cancelled(extracting_mech) -> void:
	if not is_instance_valid(extracting_mech):
		return
	if extracting_mech.has_method("cancel_extract"):
		extracting_mech.cancel_extract()
