extends TestSuite

# MapKindsTest: prop and salvage kinds the generator adds work by name, with
# no game code listing them. A props.json or salvage.json whose kind list
# has new names appended loads every point under its own name
# (PropSpawnSet.from_json and SalvageSpawnSet.from_json, which build_meshes.gd
# uses); a broken list is an error, never a wrong kind. A new heavy vehicle
# kind ("railcar") on a VehicleField gets boxes, mass and shot block from
# the field's per-kind values and is a hard obstacle for steering; a new
# small kind on a sprite layer is drawn; a new salvage kind is found, named
# on the HUD from its name, and comes up empty (with a warning) until it has
# a loot table.

const CONTAINER := preload("res://assets/images/map/props/vehicle_container_40ft.png")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")
const DRUMS := preload("res://assets/images/map/props/clutter_drums.png")
const OLD_KINDS := ["vehicle", "truck", "vehicle_wreck", "tree", "bush", "debris", "stall", "bus", "military",
		"container", "hut", "clutter"]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null


func run_tests() -> void:
	await case("props.json with kinds appended loads them by name", _test_props_json)
	await case("a broken kind list is an error, not a wrong kind", _test_broken_lists)
	await case("a new heavy vehicle kind gets bodies from its own values", _test_new_vehicle_kind)
	await case("a new small kind on a sprite layer is drawn", _test_new_layer_kind)
	await case("a new salvage kind is found and named by its name", _test_new_salvage_kind)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)


func _kinds_with(extra: Array) -> Array:
	var out := OLD_KINDS.duplicate()
	out.append_array(extra)
	return out


func _test_props_json() -> void:
	var data := {"kinds": _kinds_with(["railcar", "tombstone"]), "items": [
		[12, 100.0, 200.0, 0.5, 280.0, 60.0, 0],
		[13, -50.0, 10.0, 0.0, 30.0, 20.0],
		[0, 0.0, 0.0, 0.0, 88.0, 36.0, 2],
	]}
	var spawns := PropSpawnSet.from_json(data)
	check_eq(spawns.count(), 3, "every point loads")
	check_eq(spawns.kinds[spawns.kind[0]], "railcar", "the first is a railcar")
	check_eq(spawns.kinds[spawns.kind[1]], "tombstone", "the second a tombstone")
	check_eq(spawns.variant[1], -1, "a point with no variant lets the game pick")
	check(spawns.size[0].is_equal_approx(Vector2(280, 60)) and is_equal_approx(spawns.rotation[0], 0.5), "sizes and turns")
	var spawner := PropSpawner.new()
	spawner.spawn_set = spawns
	_arena.add_child(spawner)
	await wait_frames(1)
	check_eq(spawner.spawn_kind(0), "railcar", "the spawner gives the kind by name")
	check_eq(spawner.indices_of_kinds(PackedStringArray(["tombstone"])).size(), 1, "and finds it by name")
	check_eq(spawner.indices_of_kinds(PackedStringArray(["vehicle"])).size(), 1, "old kinds are where they were")
	var point := PropSpawnPoint.new()
	spawner.add_child(point)
	check(point.known_kinds().has("railcar"), "a hand-placed point can be given the new kind in the inspector")
	point.kind = "railcar"
	point.position = Vector2(5000, 5000)
	spawner.mark_dirty()
	var placed := Array(spawner.indices_of_kinds(PackedStringArray(["railcar"]))).filter(
			func(i: int) -> bool: return spawner.spawn_source(i) == "manual")
	check(placed.size() == 1 and spawner.spawn_size(placed[0]).is_equal_approx(Vector2(280, 60)),
			"a hand-placed railcar with no size is a railcar's 14 x 3 m (props.SIZE_M)")


func _test_broken_lists() -> void:
	var many := []
	for i in 257:
		many.append("kind_%d" % i)
	expect_error("at most 256 fit")
	check_eq(PropSpawnSet.from_json({"kinds": many, "items": [[0, 0, 0, 0, 1, 1]]}).count(), 0,
			"257 kinds don't fit in a byte: nothing loads")
	expect_error("has kind 14 of 14")
	check_eq(PropSpawnSet.from_json({"kinds": _kinds_with(["railcar", "tombstone"]), "items": [[14, 0, 0, 0, 1, 1]]}).count(),
			0, "an item naming a kind past the list: nothing loads")
	expect_error("has kind 3 of 2")
	check_eq(SalvageSpawnSet.from_json({"kinds": ["bus", "tank"], "items": [[3, 0, 0, 0, 1, 1, -1, 0, 0]]}).count(), 0,
			"the same for salvage")
	expect_error("no kinds or items")
	check_eq(SalvageSpawnSet.from_json({"items": []}).count(), 0, "a file with no kind list loads nothing")


func _test_new_vehicle_kind() -> void:
	var spawns := PropSpawnSet.from_json({"kinds": _kinds_with(["railcar"]), "items": [
		[0, 0.0, 0.0, 0.0, 88.0, 36.0, 0],
		[12, 0.0, 600.0, 0.0, 280.0, 60.0, 0],
	]})
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawns
	_arena.add_child(spawner)
	var layer := PropSpriteLayer.new()
	layer.name = "Vehicles"
	layer.kinds = PackedStringArray(["vehicle", "railcar"])
	layer.textures = {"vehicle": [HATCHBACK], "railcar": [CONTAINER]}
	layer.spans = {"vehicle": PackedFloat32Array([1.0]), "railcar": PackedFloat32Array([1.0])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
	var field := VehicleField.new()
	field.spawner_path = NodePath("../PropSpawner")
	field.layer_path = NodePath("../Vehicles")
	field.kinds = PackedStringArray(["vehicle", "railcar"])
	field.masses = {"vehicle": PackedFloat32Array([950.0]), "railcar": PackedFloat32Array([30000.0])}
	field.shot_blocks = {"vehicle": PackedFloat32Array([0.5]), "railcar": PackedFloat32Array([0.95])}
	field.stream = false
	_arena.add_child(field)
	await wait_until(func(): return field.is_built(), 2.0)
	check_eq(field.vehicle_count(), 2, "both vehicles are in the field")
	check_eq(layer.sprite_count(), 2, "and drawn")
	var rail := 0 if field.vehicle_kind(0) == "railcar" else 1
	check_eq(field.vehicle_kind(rail), "railcar", "under the new kind's name")
	check_eq(field.vehicle_mass(rail), 30000.0, "with its own mass")
	check(not field.is_car(rail), "too heavy to trample or destroy: a heavy vehicle")
	check_eq(field.static_body_count(), 2, "it has a box")
	check(is_equal_approx(field.shot_block_for(field, field._static_bodies[rail]), 0.95), "with its own shot block")
	field._block[rail] = 1.0
	var hit := MapSenses.trace_shot(_arena.get_world_2d(), Vector2(0, 300), Vector2(0, 900), 3)
	check(hit.by == "vehicle", "shots meet it like any vehicle")
	var obstacles := field.steering_obstacles(Vector2(0, 450), 400.0)
	var found := false
	for k in range(0, obstacles.size(), VehicleField.STEER_STRIDE):
		found = found or int(obstacles[k + 6]) == rail
	check(found, "NPC steering sees it")
	check(VehicleField.push_speed_fraction(VehicleField.pusher_mass(50.0), field.vehicle_mass(rail)) < 0.35,
			"and a mecha can't push it worth the name, so steering goes round")


func _test_new_layer_kind() -> void:
	var spawns := PropSpawnSet.from_json({"kinds": _kinds_with(["tombstone"]), "items": [
		[11, 0.0, 0.0, 0.0, 30.0, 24.0, 0],
		[12, 100.0, 0.0, 0.3, 30.0, 20.0],
		[12, 200.0, 0.0, 0.0, 30.0, 20.0],
	]})
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawns
	_arena.add_child(spawner)
	var layer := PropSpriteLayer.new()
	layer.kinds = PackedStringArray(["clutter", "tombstone"])
	layer.textures = {"clutter": [DRUMS], "tombstone": [DRUMS, HATCHBACK]}
	layer.spans = {"clutter": PackedFloat32Array([1.0]), "tombstone": PackedFloat32Array([1.0, 1.0])}
	layer.shadow_heights = {"tombstone": PackedFloat32Array([1.2, 1.2])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
	await wait_frames(2)
	check_eq(layer.sprite_count(), 3, "every point of both kinds is drawn")
	check(layer.variant_of_spawn(1) >= 0 and layer.variant_of_spawn(1) < 2, "a new kind's point picks one of its sprites")


func _test_new_salvage_kind() -> void:
	var spawns := SalvageSpawnSet.from_json({"kinds": ["bus", "tank", "rail_freight"], "items": [
		[2, 1000.0, 0.0, 0.0, 280.0, 60.0, -1, 0, 0],
		[0, 3000.0, 0.0, 0.0, 240.0, 50.0, -1, 0, 0],
	]})
	check_eq(spawns.kind_name(0), "rail_freight", "the new kind is named")
	var field := SalvageField.new()
	field.sources = spawns
	_arena.add_child(field)
	await wait_until(func(): return field.is_built(), 2.0)
	check_eq(field.source_count(), 2, "both sources are on the map")
	check_eq(field.kind_of(0), "rail_freight", "under the new kind's name")
	check_eq(SalvageField.display_name_of("rail_freight"), "RAIL FREIGHT", "the HUD names it from its name")
	field._ensure_rolled(0)
	check(field._loot.has("rail_freight") and field._loot["rail_freight"] == null,
			"with no loot table yet it comes up empty (make_source_loot.py adds one)")
	field._ensure_rolled(1)
	check(field._loot.get("bus") != null, "an old kind keeps its table")
