extends Node2D

# LivingWorldTest is a minimal "arena-like" host for the Director system.
# It implements just enough of the Arena interface that Player.gd, Enemy.gd,
# and the AI behaviours work — without inheriting Arena's mission/ladder/
# exhibition coupling. Iterate the Director here freely.
#
# Required scene children (added in the .tscn):
#   - Mechas (Node2D)         container for player + NPCs
#   - Projectiles (Node2D)    bullets, missiles, etc. land here
#   - PlayerStart (Marker2D)  where the player spawns
#   - POIs (Node2D)           Marker2D children — points of interest for NPCs
#   - SpawnZones (Node2D)     Marker2D children — Director uses these for soft spawns
#   - Director (Node)         the Director.gd manager
#   - PlayerCamera (Camera2D) follows the player

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")

@onready var Mechas = $Mechas
@onready var Projectiles = $Projectiles
@onready var Director = $Director

var player
var all_mechas: Array = []
var PlayerHUD = null  # Player.gd guards on `if arena.PlayerHUD` so null is OK


func _ready() -> void:
	randomize()
	_add_player()
	Director.start(self)


# ---- Spawning ----

func _add_player() -> void:
	player = PLAYER.instantiate()
	Mechas.add_child(player)
	player.setup(self)
	player.position = _player_start_position()
	player.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
	player.connect("died", Callable(self, "_on_mecha_died"))
	player.connect("made_sound", Callable(self, "_on_mecha_made_sound"))
	player.connect("lost_health", Callable(self, "_on_player_lost_health"))
	all_mechas.append(player)
	# Player.tscn has its own Camera2D — no extra setup needed


func add_enemy(design_data, enemy_name: String) -> Mecha:
	var enemy = ENEMY.instantiate()
	Mechas.add_child(enemy)
	enemy.position = _random_spawn_position()
	enemy.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
	enemy.connect("died", Callable(self, "_on_mecha_died"))
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
	var data = ProjectileManager.create(mecha, args, weapon)
	if data and data.create_node:
		Projectiles.add_child(data.node)


func _on_mecha_died(mecha) -> void:
	mecha.is_dead = true
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove_at(idx)
	if mecha != player:
		mecha.queue_free()
	else:
		print("[LivingWorldTest] Player died")


func _on_mecha_made_sound(sound_data) -> void:
	for m in all_mechas:
		if m == sound_data.source or not is_instance_valid(m):
			continue
		if not m.has_method("heard_sound"):
			continue
		if m.global_position.distance_to(sound_data.position) <= sound_data.max_distance:
			m.heard_sound(sound_data)


func _on_player_lost_health() -> void:
	Director.notify_player_damaged()
