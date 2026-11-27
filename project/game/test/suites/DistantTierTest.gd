extends TestSuite

# DistantTierTest: the distant simulation tier (Enemy, Distant tier). An NPC
# alone and far from the player goes distant, and keeps following its route
# round a wall with no physics movement and no steering, moving only on its
# steps; it comes back to full simulation, where it stands, well before a
# mecha coming at it could see it, and senses on its first full think; two
# hostile NPCs far from everyone stay distant together and fight by the
# rough rules (rounds spent and armour hit, no projectile made); and the
# tier stays off with the setting at 0 and for an NPC on screen. An Entity
# keeps an NPC in full simulation only within how far it senses.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY_SCRIPT := preload("res://game/mecha/Enemy.gd")


class FakeArena extends Node2D:
	var mechas: Array = []
	var entities: Array = []
	var player = null
	var goal := Vector2.ZERO
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return entities
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2.ZERO
	func get_random_position() -> Vector2:
		return goal


var _arena: FakeArena = null
var _field: BuildingField = null
var _cam: Camera2D = null
var _saved_line = null


func run_tests() -> void:
	_saved_line = Debug.debug_settings.get("distant_tier_m")
	Debug.debug_settings["distant_tier_m"] = ENEMY_SCRIPT.DISTANT_DEFAULT_M
	await case("an NPC alone and far goes distant and keeps to its route", _test_goes_distant)
	await case("it comes back to full simulation before a mecha could see it", _test_comes_back)
	await case("two distant NPCs fight by the rough rules", _test_rough_fight)
	await case("the tier stays off at 0 and for an NPC on screen", _test_off)
	await case("an Entity keeps an NPC in full simulation only within its senses", _test_entity_reach)
	Debug.debug_settings["distant_tier_m"] = _saved_line


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-30000, -30000), Vector2(30000, -30000), Vector2(30000, 30000), Vector2(-30000, 30000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	var bounds := MapBounds.new()
	bounds.map_rect = Rect2(-32000, -32000, 64000, 64000)
	bounds.border = 2000.0
	_arena.add_child(bounds)
	# A wall across the NPC's way north to south, from x 16,000 to 24,000.
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8000, 300)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector2(20000, 3000)
	_arena.add_child(wall)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array([Vector2(-9000, -9000), Vector2(-8900, -9000), Vector2(-8900, -8900), Vector2(-9000, -8900)])
	footprints.starts = PackedInt32Array([0, 4])
	_field = BuildingField.new()
	_field.footprints = footprints
	_arena.add_child(_field)
	var player: Mecha = _mecha(Vector2.ZERO)
	_arena.player = player
	_cam = Camera2D.new()
	_arena.add_child(_cam)
	_cam.make_current()
	await wait_until(func(): return _field.routes_ready(), 10.0)


# A plain mecha standing still at `pos`.
func _mecha(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	return mecha


# An NPC that thinks for itself (it roams to arena.goal), a Hunter.
func _enemy(pos: Vector2) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["personality"] = NPCManager._personality_from_string("hunter")
	enemy.setup(_arena, design, "Distant test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.flag_grace = 0.0
	_arena.mechas.append(enemy)
	return enemy


func _test_goes_distant() -> void:
	_arena.goal = Vector2(20000, 6000)
	var enemy := _enemy(Vector2(20000, 0))
	var went := await wait_until(func(): return enemy.is_distant(), 3.0)
	if not check(went, "1 km from the player, alone, it goes distant"):
		return
	check_eq(enemy.lod_tier(), 3, "its LOD tier is the distant one")
	var built := int(enemy._steer_built_frame)
	var start: Vector2 = enemy.global_position
	var last := start
	var moves := 0
	var frames := 0
	var in_wall := false
	var crossed_at := Vector2.INF
	while frames < 3000 and enemy.global_position.y < 3600.0:
		await get_tree().physics_frame
		frames += 1
		var pos: Vector2 = enemy.global_position
		if pos != last:
			moves += 1
			if last.y < 3000.0 and pos.y >= 3000.0:
				crossed_at = pos
			last = pos
		in_wall = in_wall or _field.is_in_solid(pos)
	check(enemy.is_distant(), "it stays distant")
	check(enemy.global_position.distance_to(start) > 1500.0, "it keeps moving (%.0f px in %d frames)" % [enemy.global_position.distance_to(start), frames])
	check(moves <= frames / ENEMY_SCRIPT.DISTANT_STEP_INTERVAL + 2, "only on its steps (%d moves in %d frames)" % [moves, frames])
	check(int(enemy._steer_built_frame) == built, "it built no steering map (no steering rays)")
	check(enemy._sight_cache.is_empty(), "and cast no sight rays")
	check(not in_wall, "it never walks into the wall's outline")
	check(crossed_at != Vector2.INF and (crossed_at.x < 16000.0 or crossed_at.x > 24000.0),
			"it goes round the end of the wall, along its route (crossed at %s)" % str(crossed_at.round()))


func _test_comes_back() -> void:
	_arena.goal = Vector2(20000, -6000)
	var enemy := _enemy(Vector2(20000, 0))
	if not check(await wait_until(func(): return enemy.is_distant(), 3.0), "it goes distant"):
		return
	# Another NPC (held still, so in full simulation) comes at it at 150 m/s,
	# twice a sprint.
	var other := _enemy(Vector2(20000, 16000))
	other.paused = true
	var sight: float = other.sight_radius()
	var back_at := INF
	var seen_distant := false
	var jump := 0.0
	var before: Vector2 = enemy.global_position
	for _i in 600:
		var step := (enemy.global_position - other.global_position).normalized() * 3000.0 / 60.0
		other.global_position += step
		before = enemy.global_position
		await get_tree().physics_frame
		var d: float = other.global_position.distance_to(enemy.global_position)
		if enemy.is_distant() and d < sight:
			seen_distant = true
		if not enemy.is_distant() and back_at == INF:
			back_at = d
			jump = before.distance_to(enemy.global_position)
		if d < sight * 0.5:
			break
	check(back_at < INF, "it came back to full simulation")
	check(back_at > sight * 2.0, "with the other mecha still %.0f px off (its sight reaches %.0f px)" % [back_at, sight])
	check(not seen_distant, "it was never distant within the other's sight")
	check(jump < 400.0, "where it stood (it moved %.0f px as it came back)" % jump)
	check(await wait_until(func(): return enemy._has_sensed, 1.0), "it senses on its first full think")


func _test_rough_fight() -> void:
	_arena.goal = Vector2(20000, 0)
	var a := _enemy(Vector2(20000, 0))
	var b := _enemy(Vector2(21200, 0))
	a.mark_traitor(b)
	b.mark_traitor(a)
	var projectiles := [0]
	for m in [a, b]:
		m.create_projectile.connect(func(_by, _args, _weapon): projectiles[0] += 1)
	var both := await wait_until(func(): return a.is_distant() and b.is_distant(), 3.0)
	if not check(both, "two NPCs near each other and far from everyone go distant together"):
		return
	var armour := [_armour_pips(a), _armour_pips(b)]
	var fought := await wait_until(func(): return a.rough_rounds_fired + b.rough_rounds_fired >= 10, 20.0)
	check(fought, "they fight (%d rough rounds)" % [a.rough_rounds_fired + b.rough_rounds_fired])
	check_eq(projectiles[0], 0, "no projectile was made")
	var hit: bool = _armour_pips(a) < armour[0] or _armour_pips(b) < armour[1] or a.is_dead or b.is_dead
	check(hit, "and the rounds hit armour (%d -> %d, %d -> %d)" % [armour[0], _armour_pips(a), armour[1], _armour_pips(b)])
	check(a.is_distant() or a.is_dead, "the fight stays in the distant tier")


func _test_off() -> void:
	_arena.goal = Vector2(20000, 0)
	Debug.debug_settings["distant_tier_m"] = 0.0
	var enemy := _enemy(Vector2(20000, 0))
	await wait_frames(60)
	check(not enemy.is_distant(), "with the setting at 0 nothing goes distant")
	Debug.debug_settings["distant_tier_m"] = ENEMY_SCRIPT.DISTANT_DEFAULT_M
	_cam.global_position = Vector2(20000, 0)
	await wait_frames(60)
	check(not enemy.is_distant(), "an NPC on screen stays in full simulation, however far from the player")
	_cam.global_position = Vector2.ZERO
	check(await wait_until(func(): return enemy.is_distant(), 3.0), "off screen again, it goes distant")


func _armour_pips(mecha) -> int:
	var total := 0
	for part in mecha.armor:
		for facing in mecha.armor[part]:
			total += int(mecha.armor[part][facing].pips)
	return total


# Stands in for an Entity: what _update_distant_tiers reads of one.
class FakeEntity extends Node2D:
	var sight_range := 1800.0
	var heat_sense_scale := Vector2(0.5, 1.2)
	var is_dead := false


func _test_entity_reach() -> void:
	var enemy := _enemy(Vector2(20000, 0))
	enemy.set_pause(true)
	var entity := FakeEntity.new()
	_arena.add_child(entity)
	_arena.entities.append(entity)
	var reach: float = entity.sight_range * 1.2 + ENEMY_SCRIPT.DISTANT_SLACK
	# An NPC in full simulation goes distant only DISTANT_SLACK past a reach.
	entity.global_position = enemy.global_position + Vector2(reach + ENEMY_SCRIPT.DISTANT_SLACK + 400.0, 0)
	enemy.set_pause(false)
	ENEMY_SCRIPT._update_distant_tiers(_arena)
	check(enemy.is_distant(), "an Entity past its senses (%.0f px) doesn't keep the NPC in full simulation" % reach)
	entity.global_position = enemy.global_position + Vector2(reach - 400.0, 0)
	ENEMY_SCRIPT._update_distant_tiers(_arena)
	check(not enemy.is_distant(), "one within them does")
	entity.global_position = enemy.global_position + Vector2(reach + 400.0, 0)
	entity.sight_range = 20000.0
	ENEMY_SCRIPT._update_distant_tiers(_arena)
	check(not enemy.is_distant(), "a far-sighted Entity counts out to the line, no further")
	entity.global_position = enemy.global_position + Vector2(ENEMY_SCRIPT.distant_line() + ENEMY_SCRIPT.DISTANT_SLACK + 400.0, 0)
	ENEMY_SCRIPT._update_distant_tiers(_arena)
	check(enemy.is_distant(), "and past the line it doesn't")
