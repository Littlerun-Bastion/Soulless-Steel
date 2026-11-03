extends TestSuite

# PlayerViewTest: what the player can see (Player.can_see_body,
# _update_view) and the lighting it matches. Only what is in the light cone
# or within 20 m all round is seen; a mecha behind a building wall is faded
# out and comes back once it is clear; from inside a building the player sees
# in it but not out of it; a hand-made building (Building.tscn's
# BuildingArea, no walls) hides its inside from outside and shows it from
# inside; an Entity behind a wall is hidden too; nothing is hidden while
# controls are locked (cutscenes); a map joins the sight light layer; and
# BuildingField gives the buildings near the player shadows and drops them
# when the player moves away.
#
# The player is held still (no physics) and faces a set way, and its view is
# stepped by hand, so what is in the cone is the same every run.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")

# A generated building spanning x 0..400, y 0..400; a hand-made one spanning
# x 2000..2400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]
const HAND_MADE := [Vector2(2000, 0), Vector2(2400, 0), Vector2(2400, 400), Vector2(2000, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null
var _field: BuildingField = null
var _player = null


func run_tests() -> void:
	await case("only the light cone and 20 m all round are seen", _test_cone)
	await case("a mecha behind a building is hidden until it comes out", _test_wall)
	await case("from inside a building: in it seen, out of it hidden", _test_inside)
	await case("a hand-made building hides its inside from outside", _test_hand_made)
	await case("an Entity behind a wall is hidden", _test_entity)
	await case("nothing is hidden while controls are locked", _test_locked)
	await case("a map joins the sight light layer", _test_light_layer)
	await case("buildings near the player cast shadows, far ones don't", _test_occluders)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	_field = BuildingField.new()
	_field.footprints = footprints
	_arena.add_child(_field)
	var hand_made := Node2D.new()
	var area := Area2D.new()
	area.monitorable = false
	area.add_to_group("building_area")
	var poly := CollisionPolygon2D.new()
	poly.polygon = PackedVector2Array(HAND_MADE)
	area.add_child(poly)
	hand_made.add_child(area)
	_arena.add_child(hand_made)
	_player = _mecha(Vector2(-600, 200), PLAYER)
	_player.mecha_name = "Player"
	_player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mecha(pos: Vector2, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	_arena.mechas.append(mecha)
	return mecha


# Puts the player at `pos` facing `facing`, then runs its view long enough
# for a full fade.
func _look(pos: Vector2, facing: Vector2) -> void:
	_player.global_position = pos
	_player.global_rotation = Vector2.UP.angle_to(facing)
	await get_tree().physics_frame
	for i in 12:
		_player._update_view(0.1)


func _hidden(body) -> bool:
	return _player.is_hidden_from_view(body) and body.modulate.a < 0.05


func _shown(body) -> bool:
	return not _player.is_hidden_from_view(body) and body.modulate.a > 0.95


func _test_cone() -> void:
	var o := Vector2(-4000, 4000)
	var reach: float = _player.get_view_reach()
	check(reach > 2000.0, "the cone reaches well past the screen (%.0f px)" % reach)
	var ahead := _mecha(o + Vector2(0, -1500))
	var edge := _mecha(o + Vector2.UP.rotated(deg_to_rad(_player.VIEW_CONE_HALF_ANGLE - 3.0)) * 1500.0)
	var aside := _mecha(o + Vector2.UP.rotated(deg_to_rad(40.0)) * 1500.0)
	var behind := _mecha(o + Vector2(0, 1500))
	var close_behind := _mecha(o + Vector2(0, _player.VIEW_PERIPHERAL - 50.0))
	var past_reach := _mecha(o + Vector2(0, -(reach + 300.0)))
	await _look(o, Vector2.UP)
	check(_shown(ahead), "a mecha ahead in the cone is seen")
	check(_shown(edge), "one just inside the cone's edge too")
	check(_hidden(aside), "one 40 degrees off is hidden")
	check(_hidden(behind), "one behind is hidden")
	check(_shown(close_behind), "one behind but within 20 m is seen")
	check(_hidden(past_reach), "one past the light's reach is hidden")
	await _look(o, Vector2.DOWN)
	check(_shown(behind) and _hidden(ahead), "turning round swaps them")


func _test_wall() -> void:
	var behind := _mecha(Vector2(800, 200))
	var open := _mecha(Vector2(800, 700))
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(behind), "the mecha behind the building is faded out")
	await _look(Vector2(-600, 200), Vector2(1400, 500).normalized())
	check(_shown(open), "one in the open in the cone is shown")
	behind.global_position = Vector2(800, 700)
	await _look(Vector2(-600, 200), Vector2(1400, 500).normalized())
	check(_shown(behind), "it fades back in once it comes out from behind")


func _test_inside() -> void:
	var same := _mecha(Vector2(300, 300))
	var outside := _mecha(Vector2(-300, 200))
	await _look(Vector2(100, 100), Vector2(200, 200).normalized())
	check(_shown(same), "a mecha in the same building is seen")
	await _look(Vector2(100, 100), Vector2(-400, 100).normalized())
	check(_hidden(outside), "one outside is hidden, even in the cone")


func _test_hand_made() -> void:
	var inside := _mecha(Vector2(2200, 200))
	await _look(Vector2(1700, 200), Vector2.RIGHT)
	check(_hidden(inside), "from outside, the mecha inside is hidden")
	await _look(Vector2(2100, 300), Vector2(100, -100).normalized())
	check(_shown(inside), "from inside, it is seen")


func _test_entity() -> void:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(800, 200)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(stalker), "the Entity behind the building is hidden")


func _test_locked() -> void:
	var behind := _mecha(Vector2(800, 200))
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(behind), "hidden while the player is in control")
	_player.lock_controls()
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_shown(behind), "shown while controls are locked")
	_player.unlock_controls()


func _test_light_layer() -> void:
	var root := Node2D.new()
	var ground := Polygon2D.new()
	ground.light_mask = 1 | 32
	root.add_child(ground)
	var internal := Sprite2D.new()
	root.add_child(internal, false, Node.INTERNAL_MODE_BACK)
	_arena.add_child(root)
	MapSenses.join_sight_light(root)
	check(ground.light_mask & MapSenses.SIGHT_LIGHT_MASK, "a map node joins the sight light layer")
	check(ground.light_mask & 32 and ground.light_mask & 1, "keeping the layers it had")
	check(internal.light_mask & MapSenses.SIGHT_LIGHT_MASK, "internal children too")


func _test_occluders() -> void:
	_player.global_position = Vector2(-600, 200)
	var made := await wait_until(func(): return _field.occluder_count() == 1, 2.0)
	check(made, "the building near the player has an occluder")
	_field.update_occluders(Vector2(-20000, 200))
	check_eq(_field.occluder_count(), 0, "it is dropped once the player is far away")
