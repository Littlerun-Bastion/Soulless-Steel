extends TestSuite

# NpcLightShadowTest: an NPC's illuminator (MechaLight) shadows walls with
# PCF5, and casts shadows only while its drawn glow could be on screen: the
# light within its glow's radius plus Enemy.gd's LIGHT_SHADOW_BUFFER px of the
# screen rectangle (Enemy.update_light_shadows, every LIGHT_SHADOW_INTERVAL
# frames). A plain mecha (the player's) keeps its scene's PCF13 shadows.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2(-5000, -5000)
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null


func run_tests() -> void:
	await case("an NPC's light shadows with PCF5, the player's with PCF13", _test_filters)
	await case("an NPC's light casts shadows only while its glow could be on screen", _test_near_screen)
	await case("the check runs by itself", _test_runs)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	await get_tree().physics_frame


func _enemy(pos: Vector2) -> Mecha:
	var enemy: Mecha = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Shadow test")
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.auto_illuminator = false
	_arena.mechas.append(enemy)
	return enemy


# Moves `enemy` so its light sits at `point`.
func _light_to(enemy: Mecha, point: Vector2) -> void:
	var light := Illumination.light_of(enemy)
	enemy.global_position += point - light.global_position


func _test_filters() -> void:
	var player: Mecha = MECHA.instantiate()
	player.mech_inventory = Inventory.new()
	_arena.add_child(player)
	player.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	var enemy := _enemy(Vector2(3000, 0))
	await get_tree().physics_frame
	check_eq(Illumination.light_of(enemy).shadow_filter, Light2D.SHADOW_FILTER_PCF5, "an NPC's light: PCF5")
	check_eq(Illumination.light_of(player).shadow_filter, Light2D.SHADOW_FILTER_PCF13, "the player's: PCF13")
	var light := Illumination.light_of(enemy)
	var glow: float = (light.texture.get_size() * light.texture_scale * 0.5).length()
	check(glow > Illumination.reach(light), "the glow's radius (%.0f px) is past the senses' reach (%.0f px)" % [glow, Illumination.reach(light)])
	check_eq(enemy.light_glow_radius(), glow, "the NPC works out its glow's radius at its current scale")


func _test_near_screen() -> void:
	var enemy := _enemy(Vector2.ZERO)
	await get_tree().physics_frame
	var light := Illumination.light_of(enemy)
	var screen := MapSenses.screen_rect(enemy)
	var margin: float = enemy.light_glow_radius() + enemy.LIGHT_SHADOW_BUFFER
	var y := screen.get_center().y
	_light_to(enemy, screen.get_center())
	enemy.update_light_shadows()
	check(light.shadow_enabled, "on screen: shadows")
	_light_to(enemy, Vector2(screen.end.x + margin - 50.0, y))
	enemy.update_light_shadows()
	check(light.shadow_enabled, "just inside the glow's radius and buffer off screen: shadows")
	_light_to(enemy, Vector2(screen.end.x + margin + 50.0, y))
	enemy.update_light_shadows()
	check(not light.shadow_enabled, "just past it: none")
	_light_to(enemy, Vector2(screen.position.x - margin - 50.0, y))
	enemy.update_light_shadows()
	check(not light.shadow_enabled, "past it on the other side: none")
	_light_to(enemy, screen.get_center())
	enemy.update_light_shadows()
	check(light.shadow_enabled, "back on screen: shadows again")


func _test_runs() -> void:
	var enemy := _enemy(Vector2.ZERO)
	await get_tree().physics_frame
	var light := Illumination.light_of(enemy)
	var screen := MapSenses.screen_rect(enemy)
	_light_to(enemy, Vector2(screen.end.x + enemy.light_glow_radius() + enemy.LIGHT_SHADOW_BUFFER + 500.0, screen.get_center().y))
	await wait_frames(enemy.LIGHT_SHADOW_INTERVAL + 1)
	check(not light.shadow_enabled, "far off screen, its shadows go off within %d frames" % enemy.LIGHT_SHADOW_INTERVAL)
	_light_to(enemy, screen.get_center())
	await wait_frames(enemy.LIGHT_SHADOW_INTERVAL + 1)
	check(light.shadow_enabled, "back on screen, they come back")
