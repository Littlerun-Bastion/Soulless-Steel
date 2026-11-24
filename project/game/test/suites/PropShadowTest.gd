extends TestSuite

# PropShadowTest: light shadows of map props (PropSpriteLayer.shadow_heights).
# A shadow's length follows the light's height and the prop's, capped at a
# few metres; the light's strength at a point follows its drawn cone and
# circle; a prop in a shining illuminator's light casts one shadow, away from
# the light; none with the illuminator off, out of the cone, behind a
# building wall, for a kind with no height, for a hidden sprite or with no
# camera; two lights give two shadows.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")

const CAR_SIZE := Vector2(80, 40)
const CAR_HEIGHT := 1.45
# A building wall across x 250..350, y -300..300.
const WALL := [Vector2(250, -300), Vector2(350, -300), Vector2(350, 300), Vector2(250, 300)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _layer: PropSpriteLayer = null


func run_tests() -> void:
	await case("a shadow's length follows the heights, capped", _test_length)
	await case("a light's strength follows its cone and circle", _test_strength)
	await case("a lit prop casts one shadow away from the light", _test_lit_prop)
	await case("no shadow dark, out of the cone, behind a wall, hidden or without a height", _test_no_shadow)
	await case("two lights give two shadows", _test_two_lights)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
		await wait_frames(2)


func _test_length() -> void:
	check_eq(PropSpriteLayer.shadow_length_m(10.0, 0.0), 0.0, "nothing tall casts nothing")
	var near := PropSpriteLayer.shadow_length_m(2.0, 1.0)
	check(is_equal_approx(near, 2.0 / (PropSpriteLayer.LIGHT_HEIGHT_M - 1.0)), "close to the light, as far as the light's line throws it")
	check_eq(PropSpriteLayer.shadow_length_m(100.0, 1.0), PropSpriteLayer.SHADOW_PER_HEIGHT, "far off, at most SHADOW_PER_HEIGHT times the height")
	check_eq(PropSpriteLayer.shadow_length_m(100.0, 3.5), PropSpriteLayer.MAX_SHADOW_M, "and never past MAX_SHADOW_M")
	check(PropSpriteLayer.shadow_length_m(20.0, 1.0) < PropSpriteLayer.shadow_length_m(20.0, 2.0), "a taller prop throws a longer shadow")


func _test_strength() -> void:
	await _setup([])
	var mecha := _mecha(Vector2.ZERO, Vector2.RIGHT, true)
	await wait_frames(2)
	var light := Illumination.light_of(mecha)
	var reach := Illumination.reach(light)
	check(Illumination.light_strength(light, Vector2(reach * 0.5, 0)) > 0.99, "full light down the middle of the cone")
	check(Illumination.light_strength(light, Vector2(reach * 2.0, 0)) < 0.01, "none past the reach")
	check(Illumination.light_strength(light, Vector2(0, -reach * 0.5)) < 0.01, "none beside the cone")
	check(Illumination.light_strength(light, Vector2(-100, 0)) > 0.99, "full light in the circle round the mecha, behind it too")
	for point in [Vector2(reach * 0.5, 0), Vector2(0, -reach * 0.5), Vector2(-100, 0)]:
		check_eq(Illumination.light_strength(light, point) > 0.5, Illumination.in_cone(light, point) or point.length() < Illumination.LOCAL_RADIUS,
				"lit where in_cone or the circle says, at %s" % point)


func _test_lit_prop() -> void:
	await _setup([Vector2(600, 0)])
	_mecha(Vector2.ZERO, Vector2.RIGHT, true)
	await wait_frames(3)
	check_eq(_layer.shadow_count(), 1, "one shadow")
	var shadow: Dictionary = _layer.get_shadows()[0]
	var away: Vector2 = (shadow.transform.origin - Vector2(600, 0)).normalized()
	check(away.dot(Vector2.RIGHT) > 0.99, "drawn on the far side of the car from the light")
	var length := PropSpriteLayer.shadow_length_m(30.0, CAR_HEIGHT) * PropSpriteLayer.PX_PER_M
	check(is_equal_approx(shadow.offset.x * CAR_SIZE.x, length), "as long as shadow_length_m says (%.1f px)" % length)
	check(shadow.alpha > 0.5, "dark in full light")


func _test_no_shadow() -> void:
	await _setup([Vector2(600, 0)])
	var mecha := _mecha(Vector2.ZERO, Vector2.RIGHT, false)
	await wait_frames(3)
	check_eq(_layer.shadow_count(), 0, "none with the illuminator off")
	mecha.set_illuminator(true)
	mecha.global_rotation = Vector2.UP.angle_to(Vector2.LEFT)
	await wait_frames(3)
	check_eq(_layer.shadow_count(), 0, "none out of the cone")
	mecha.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	await wait_frames(3)
	check_eq(_layer.shadow_count(), 1, "one once the cone is on it")
	_layer.hide_sprite(0)
	await wait_frames(2)
	check_eq(_layer.shadow_count(), 0, "none for a hidden sprite (a moving vehicle)")
	_layer.place_sprite(0, Vector2(600, 0), 0.0)
	_layer.shadow_heights = {}
	await wait_frames(2)
	check_eq(_layer.shadow_count(), 0, "none for a kind with no height")
	_layer.shadow_heights = {"vehicle": PackedFloat32Array([CAR_HEIGHT])}
	_arena.get_node("Camera").enabled = false
	await wait_frames(2)
	check_eq(_layer.shadow_count(), 0, "none with no camera")

	await _setup([Vector2(600, 0)], [WALL])
	_mecha(Vector2.ZERO, Vector2.RIGHT, true)
	await wait_frames(3)
	check_eq(_layer.shadow_count(), 0, "none behind a building wall")


func _test_two_lights() -> void:
	await _setup([Vector2(600, 0)])
	_mecha(Vector2.ZERO, Vector2.RIGHT, true)
	_mecha(Vector2(600, 600), Vector2.UP, true)
	await wait_frames(3)
	check_eq(_layer.shadow_count(), 2, "one shadow per light")


# A map with hatchbacks at `cars`, a camera on the first and building walls.
func _setup(cars: Array, buildings: Array = []) -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var spawn_set := PropSpawnSet.new()
	spawn_set.kinds = PackedStringArray(["vehicle"])
	for pos in cars:
		spawn_set.kind.append(0)
		spawn_set.position.append(pos)
		spawn_set.rotation.append(0.0)
		spawn_set.size.append(CAR_SIZE)
		spawn_set.variant.append(0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawn_set
	_arena.add_child(spawner)
	if not buildings.is_empty():
		var footprints := BuildingFootprints.new()
		var starts := PackedInt32Array([0])
		for b in buildings:
			footprints.points.append_array(PackedVector2Array(b))
			starts.append(footprints.points.size())
		footprints.starts = starts
		var field := BuildingField.new()
		field.footprints = footprints
		_arena.add_child(field)
	_layer = PropSpriteLayer.new()
	_layer.name = "Vehicles"
	_layer.kinds = PackedStringArray(["vehicle"])
	_layer.textures = {"vehicle": [HATCHBACK]}
	_layer.spans = {"vehicle": PackedFloat32Array([1.0])}
	_layer.shadow_heights = {"vehicle": PackedFloat32Array([CAR_HEIGHT])}
	_layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(_layer)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = cars[0] if not cars.is_empty() else Vector2.ZERO
	_arena.add_child(camera)
	camera.make_current()


func _mecha(pos: Vector2, facing: Vector2, lit: bool) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_physics_process(false)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.global_rotation = Vector2.UP.angle_to(facing)
	mecha.set_illuminator(lit)
	_arena.mechas.append(mecha)
	return mecha
