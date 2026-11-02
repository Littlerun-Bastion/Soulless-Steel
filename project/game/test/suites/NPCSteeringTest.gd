extends TestSuite

# NPCSteeringTest: how NPC mechas steer round map vehicles and buildings
# (Enemy.gd, Context Steering and Unstick) and how tanks trample vehicles
# (VehicleField). A light build goes round a car that a heavy build pushes
# through; nothing light or heavy chooses to push a fire engine; a gap
# narrower than the mecha counts as shut; NPCs go round buildings unless
# their destination is inside; a jammed car becomes a hard obstacle; a tank
# drives over a car after pushing it for a while but never over a fire
# engine; a trampled car is drawn with its trampled sprite, or darkened;
# heavier mechas are held back less by what they push; routes go round a
# building block through its gap; spawns keep clear of vehicles; in a fight
# NPCs circle their foe; on long clear trips they sprint; dashes respect
# their cooldown and heat; shots and blasts destroy cars after vehicle_hp;
# a dash destroys a car; a sprinting mecha passes over cars but not trucks,
# and never ends up inside one; and an NPC facing a wall of cars sprints
# over it.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")
const FIRE_ENGINE := preload("res://assets/images/map/props/vehicle_fire_engine.png")

const CAR_SIZE := Vector2(80, 40)
const TRUCK_SIZE := Vector2(190, 74)
const WALK := 480.0
const CRAWLER := "Crawler_C-type_Chassis"


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


var _arena: FakeArena = null
var _field: VehicleField = null
var _layer: PropSpriteLayer = null
var _buildings: BuildingField = null


func _init() -> void:
	# Movement cases depend on the physics step, so run at game speed.
	time_scale = 1.0


func run_tests() -> void:
	await case("heavier mechas are held back less by what they push", _test_mass_curve)
	await case("a light build steers round a car; a heavy build pushes through", _test_light_vs_heavy)
	await case("a fire engine ahead is never a way through", _test_fire_engine_hard)
	await case("a gap narrower than the mecha counts as shut", _test_narrow_gap)
	await case("a light NPC walks round a parked car without touching it", _test_walk_round_car)
	await case("NPCs go round buildings unless their destination is inside", _test_buildings)
	await case("a car that jammed becomes a hard obstacle", _test_jammed)
	await case("a blocked NPC picks a side to unstick", _test_unstick)
	await case("a tank drives over a car after pushing it for a while", _test_trample_car)
	await case("a tank can't drive over a fire engine", _test_no_trample_truck)
	await case("a trampled car uses its trampled sprite, or is darkened", _test_trampled_sprite)
	await case("a route goes round a building block through its gap", _test_route)
	await case("spawn points move clear of parked vehicles", _test_clear_spot)
	await case("in a fight an NPC circles its foe instead of moving on a line", _test_orbit)
	await case("an NPC sprints on a long clear trip", _test_cruise_sprint)
	await case("dashes wait for their cooldown and stop when hot", _test_dash_rules)
	await case("shots and blasts destroy cars, not trucks", _test_car_damage)
	await case("a dash destroys a car", _test_dash_destroys)
	await case("a sprinting mecha passes over cars but not trucks", _test_sprint_over)
	await case("an NPC facing a wall of cars sprints over it", _test_car_wall)
	await case("routes go round solid walls", _test_route_walls)
	await case("a blocked NPC routes even a short trip", _test_forced_route)


func before_each() -> void:
	await _clear()


func _clear() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)


# A map with vehicles ([kind, position, rotation]) and building footprints.
func _setup(vehicles: Array, buildings: Array = []) -> void:
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	var set := PropSpawnSet.new()
	set.kinds = PackedStringArray(["vehicle", "truck"])
	for v in vehicles:
		set.kind.append(0 if v[0] == "vehicle" else 1)
		set.position.append(v[1])
		set.rotation.append(v[2])
		set.size.append(CAR_SIZE if v[0] == "vehicle" else TRUCK_SIZE)
		set.variant.append(0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = set
	_arena.add_child(spawner)
	_buildings = null
	if not buildings.is_empty():
		var footprints := BuildingFootprints.new()
		var starts := PackedInt32Array([0])
		for b in buildings:
			footprints.points.append_array(PackedVector2Array(b))
			starts.append(footprints.points.size())
		footprints.starts = starts
		_buildings = BuildingField.new()
		_buildings.footprints = footprints
		_arena.add_child(_buildings)
	_layer = PropSpriteLayer.new()
	_layer.name = "Vehicles"
	_layer.kinds = PackedStringArray(["vehicle", "truck"])
	_layer.textures = {"vehicle": [HATCHBACK], "truck": [FIRE_ENGINE]}
	_layer.spans = {"vehicle": PackedFloat32Array([1.0]), "truck": PackedFloat32Array([1.0])}
	_layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(_layer)
	_field = VehicleField.new()
	_field.spawner_path = NodePath("../PropSpawner")
	_field.layer_path = NodePath("../Vehicles")
	_field.kinds = PackedStringArray(["vehicle", "truck"])
	_field.masses = {"vehicle": PackedFloat32Array([950.0]), "truck": PackedFloat32Array([14000.0])}
	_field.shot_blocks = {"vehicle": PackedFloat32Array([0.5]), "truck": PackedFloat32Array([0.85])}
	_field.stream = false
	_arena.add_child(_field)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _crawler_design() -> Dictionary:
	for npc in NPCManager.NPCS:
		var design: Dictionary = NPCManager.get_design_data(npc)
		if design.get("chassis") == CRAWLER:
			return design
	return {}


# An NPC at `pos` facing +x, driven by the scripted walk (no behaviour).
func _enemy(pos: Vector2, design: Dictionary) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, design, "Steer test")
	enemy.global_rotation = 0.0
	enemy.set_scripted(true)
	_arena.mechas.append(enemy)
	return enemy


# The steering direction an NPC at `pos` picks toward +x, from one map
# rebuild, as an angle in degrees (0 = straight ahead).
func _choice(enemy: Mecha) -> float:
	enemy.set_interest(Vector2.RIGHT, 0.0)
	enemy._build_context()
	enemy.chosen_dir = Vector2.ZERO
	enemy._steer_last_choice = Vector2.ZERO
	enemy.choose_direction(0.0)
	return rad_to_deg(absf(enemy.chosen_dir.angle()))


func _test_mass_curve() -> void:
	var light := VehicleField.pusher_mass(45.0)
	check(absf(light - 45.0 * VehicleField.MECHA_KG_PER_WEIGHT) < 1.0, "a weight-45 mecha counts as 50 kg per point (%.0f kg)" % light)
	var heavy := VehicleField.pusher_mass(80.0)
	check(heavy > 80.0 * VehicleField.MECHA_KG_PER_WEIGHT * 1.5, "a weight-80 mecha counts far heavier than linear (%.0f kg)" % heavy)
	var kept_light := VehicleField.push_speed_fraction(light, 2200.0)
	var kept_heavy := VehicleField.push_speed_fraction(heavy, 2200.0)
	check(kept_heavy > kept_light + 0.2, "pushing an SUV, the heavy mecha keeps much more speed (%.2f against %.2f)" % [kept_heavy, kept_light])


func _test_light_vs_heavy() -> void:
	await _setup([["vehicle", Vector2(500, 0), 0.0]])
	var light := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	var heavy := _enemy(Vector2(0, 3000), _crawler_design())
	if not check(heavy.get_total_weight() > light.get_total_weight() + 15.0, "the crawler build is much heavier (%.0f against %.0f)" % [heavy.get_total_weight(), light.get_total_weight()]):
		return
	# Weight, not the tank chassis, decides here: steer the crawler like legs.
	heavy.movement_type = "relative"
	heavy.global_position = Vector2.ZERO
	light.global_position = Vector2(0, 3000)
	var heavy_angle := _choice(heavy)
	light.global_position = Vector2.ZERO
	heavy.global_position = Vector2(0, 3000)
	var light_angle := _choice(light)
	check(light_angle > 12.0 and light_angle < 70.0, "the light build steers round the car (%.0f°)" % light_angle)
	check(heavy_angle < 12.0, "the heavy build keeps straight on and pushes (%.0f°)" % heavy_angle)


func _test_fire_engine_hard() -> void:
	await _setup([["truck", Vector2(500, 0), PI / 2.0]])
	var heavy := _enemy(Vector2.ZERO, _crawler_design())
	heavy.movement_type = "relative"
	var angle := _choice(heavy)
	check(angle > 20.0, "even the heavy build steers round a fire engine (%.0f°)" % angle)
	var light := _enemy(Vector2(0, 3000), PlayerProgress.DEFAULT_MECHA)
	heavy.global_position = Vector2(0, -3000)
	light.global_position = Vector2.ZERO
	check(_choice(light) > 20.0, "and so does the light build")


func _test_narrow_gap() -> void:
	# Two cars 140 px apart centre to centre: a 100 px gap for a 200 px mecha.
	await _setup([["vehicle", Vector2(550, -70), 0.0], ["vehicle", Vector2(550, 70), 0.0]])
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy._build_context()
	check(enemy._steer_soft[0] > 0.0 or enemy._steer_hard[0] > 0.0, "straight ahead, through the gap, is marked")
	var angle := _choice(enemy)
	check(angle > 12.0, "the NPC steers round the pair, not into the gap (%.0f°)" % angle)


func _test_walk_round_car() -> void:
	await _setup([["vehicle", Vector2(800, 0), 0.0]])
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	var start := _field.vehicle_transform(0).origin
	enemy.walk_to(Vector2(2000, 0))
	var arrived := await wait_until(func(): return enemy.global_position.distance_to(Vector2(2000, 0)) < 450.0, 10.0)
	check(arrived, "the NPC gets past the car (at %s)" % str(enemy.global_position.round()))
	check(not _field._moved[0] and not _field.is_awake(0) \
			and _field.vehicle_transform(0).origin.distance_to(start) < 1.0, "without moving it")


func _test_buildings() -> void:
	var house := [Vector2(450, -150), Vector2(750, -150), Vector2(750, 150), Vector2(450, 150)]
	await _setup([], [house])
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	var angle := _choice(enemy)
	check(angle > 12.0, "an NPC passing by steers round the building (%.0f°)" % angle)
	enemy.going_to_position = true
	enemy.NavAgent.target_position = Vector2(600, 0)
	angle = _choice(enemy)
	check(angle < 12.0, "an NPC going into it walks straight in (%.0f°)" % angle)
	enemy.going_to_position = false
	enemy.global_position = Vector2(600, 0)
	enemy.set_interest(Vector2.RIGHT, 0.0)
	enemy._build_context()
	check(enemy._steer_soft[0] == 0.0, "the building it is in costs nothing")


func _test_jammed() -> void:
	await _setup([["vehicle", Vector2(500, 0), 0.0]])
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.set_interest(Vector2.RIGHT, 0.0)
	enemy._build_context()
	check(enemy._steer_hard[0] == 0.0 and enemy._steer_soft[0] > 0.0, "a car is soft to begin with")
	_field._last_pushed[enemy.get_instance_id()] = [0, Engine.get_physics_frames()]
	enemy._on_blocked()
	check(enemy._jammed.has(0), "it jams")
	check(enemy._car_burst_time > 0.0 and enemy._unstick_stage == 1, "and the NPC sprints to pass over it")
	enemy._car_burst_time = 0.0
	enemy.is_sprinting = false
	enemy._build_context()
	check(enemy._steer_hard[0] > 0.0, "once it stops sprinting, the jammed car is hard")
	enemy._unstick_since = 0.0
	_field._last_pushed[enemy.get_instance_id()] = [0, Engine.get_physics_frames()]
	enemy._on_blocked()
	check(enemy._unstick_stage == 2 and enemy._last_dash_ms > 0, "stuck on it again, it dashes through it")


func _test_unstick() -> void:
	# A long wall across the path, with the destination behind it.
	await _setup([])
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 6000)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(500, 0)
	_arena.add_child(wall)
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.walk_to(Vector2(1500, 0))
	var reacted := await wait_until(func(): return enemy._unstick_stage >= 1, 8.0)
	check(reacted, "it notices it isn't getting anywhere and tries a side")
	check(enemy.global_position.x < 500.0, "it stays on its side of the wall")


func _tank(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(_crawler_design())
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


# Drives a mecha at `vel` for `seconds` with Mecha.move (no steering).
func _drive(mecha: Mecha, vel: Vector2, seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await get_tree().physics_frame
		mecha.move(vel)


func _test_trample_car() -> void:
	await _setup([["vehicle", Vector2(400, 0), PI / 2.0]])
	var tank := _tank(Vector2.ZERO)
	check(tank.movement_type == "tank", "the crawler moves like a tank")
	await _drive(tank, Vector2(WALK, 0), 0.4)
	check(not _field.is_trampled(0), "it pushes the car at first")
	await _drive(tank, Vector2(WALK, 0), 2.5)
	check(_field.is_trampled(0), "then drives over it")
	check(_field.static_body_count() == 0 and _field.awake_count() == 0, "the trampled car has no body")
	var x := tank.global_position.x
	await _drive(tank, Vector2(WALK, 0), 0.5)
	check(tank.global_position.x - x > WALK * 0.5 * 0.8, "and the tank carries on at speed")
	check(not (0 in _field.vehicles_near(Vector2(400, 0), 2000.0)), "steering no longer sees it")


func _test_no_trample_truck() -> void:
	await _setup([["truck", Vector2(400, 0), PI / 2.0]])
	var tank := _tank(Vector2.ZERO)
	await _drive(tank, Vector2(WALK, 0), 4.0)
	check(not _field.is_trampled(0), "the fire engine is never trampled")
	check(not _field.can_trample(0), "it is too heavy to drive over")


func _test_trampled_sprite() -> void:
	await _setup([["vehicle", Vector2(400, 0), 0.0], ["vehicle", Vector2(400, 600), 0.0]])
	var base: float = _layer._by_spawn[0][0][10]
	_field._trample(0, null)
	check(is_equal_approx(float(_layer._by_spawn[0][0][5]), base * VehicleField.TRAMPLED_TONE), "with no trampled sprite, the car is darkened")
	check(not _layer._by_spawn[0][0][8], "and still drawn on the layer")
	var tex := ImageTexture.create_from_image(Image.create(64, 32, false, Image.FORMAT_RGBA8))
	_field._flat_textures[HATCHBACK.resource_path.get_basename() + "_trampled.png"] = tex
	_field._trample(1, null)
	check(_field._flat_sprites.has(1), "with one, a sprite draws it")
	var sprite: Sprite2D = _field._flat_sprites.get(1)
	check(sprite != null and sprite.texture == tex and sprite.global_position.distance_to(Vector2(400, 600)) < 1.0, "in the car's place")
	check(_layer._by_spawn[1][0][8], "and the layer hides the normal sprite")
	_layer.mark_dirty()
	await wait_frames(2)
	check(_layer._by_spawn[1][0][8] and is_equal_approx(float(_layer._by_spawn[0][0][5]), base * VehicleField.TRAMPLED_TONE), "both survive a layer rebuild")


func _test_route() -> void:
	# A row of buildings 750 px deep across the way, from y -3000 to y 2400,
	# leaving a gap at the south end.
	var row := []
	for k in range(-6, 5):
		var y := k * 500.0
		row.append([Vector2(1900, y), Vector2(2650, y), Vector2(2650, y + 480), Vector2(1900, y + 480)])
	await _setup([], row)
	var ready := await wait_until(func(): return _buildings.routes_ready(), 5.0)
	if not check(ready, "the route grid builds"):
		return
	check(_buildings.route_cost_at(Vector2(2100, 100)) > 3.0, "a building square costs more")
	check(is_equal_approx(_buildings.route_cost_at(Vector2(0, 0)), 1.0), "open ground costs 1")
	var route: PackedVector2Array = _buildings.find_route(Vector2.ZERO, Vector2(4000, 0))
	var through_gap := false
	for p in route:
		if p.y > 2400.0:
			through_gap = true
	check(route.size() >= 2 and through_gap, "it goes round the row through the gap (%s)" % str(route))
	check(route[route.size() - 1] == Vector2(4000, 0), "it ends at the goal")
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	enemy.paused = true
	await get_tree().physics_frame
	var next: Vector2 = enemy._route_next(Vector2(4000, 0), 1.0 / 60.0)
	check(next != Vector2(4000, 0) and next.y > 0.0, "an NPC heading there aims for the route's first point (%s)" % str(next))


func _test_clear_spot() -> void:
	await _setup([["vehicle", Vector2(0, 0), 0.0], ["vehicle", Vector2(0, 90), 0.0]])
	var spot := _field.clear_spot(Vector2(10, 10), 160.0)
	check(spot.distance_to(Vector2(10, 10)) > 100.0, "a spot on a car moves (to %s)" % str(spot.round()))
	check(_field.is_clear(spot, 160.0), "to somewhere clear of both cars")
	check(_field.clear_spot(Vector2(2000, 0), 160.0) == Vector2(2000, 0), "a clear spot stays put")


func _test_orbit() -> void:
	await _setup([])
	var foe := _tank(Vector2(1600, 0))
	foe.set_pause(true)
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.current_target = foe
	enemy._orbit_side = 1.0
	enemy._orbit_time = 100.0
	var start_bearing := (enemy.global_position - foe.global_position).angle()
	for _i in 150:
		await get_tree().physics_frame
		enemy.going_to_position = true
		enemy.NavAgent.target_position = foe.global_position
		enemy.navigate_to_target(1.0 / 60.0, 0.0, 0.65)
	var bearing := (enemy.global_position - foe.global_position).angle()
	var turned := rad_to_deg(absf(angle_difference(start_bearing, bearing)))
	check(turned > 15.0, "it works round its foe (%.0f° round it)" % turned)
	check(enemy.global_position.distance_to(foe.global_position) < 1600.0, "while still closing in")


func _test_cruise_sprint() -> void:
	await _setup([])
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	enemy.paused = true
	var sprinted := false
	for _i in 120:
		await get_tree().physics_frame
		enemy.going_to_position = true
		enemy.NavAgent.target_position = Vector2(8000, 0)
		enemy.navigate_to_target(1.0 / 60.0, 0.0, 0.0)
		sprinted = sprinted or enemy.is_sprinting
	check(sprinted, "it sprints while cool and the way is clear")
	enemy.internal_temp = enemy.overheat_temp * 0.9
	for _i in 20:
		await get_tree().physics_frame
		enemy.navigate_to_target(1.0 / 60.0, 0.0, 0.0)
	check(not enemy.is_sprinting, "and stops when hot")


func _test_dash_rules() -> void:
	await _setup([])
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	if not check(enemy.build.thruster != null, "the test build has a thruster"):
		return
	check(enemy.try_dash(Vector2.UP), "a cool NPC dashes")
	check(enemy.dash_velocity.length() > 0.0, "and moves off")
	check(not enemy.try_dash(Vector2.DOWN), "not again straight away")
	enemy._last_dash_ms = -100000
	enemy.internal_temp = enemy.overheat_temp * 0.9
	check(not enemy.try_dash(Vector2.LEFT), "not when hot")
	enemy.internal_temp = 0.0
	enemy.set_scripted(true)
	check(not enemy.try_dash(Vector2.RIGHT), "never in a scripted scene")


func _test_car_damage() -> void:
	await _setup([["vehicle", Vector2(0, 0), 0.0], ["truck", Vector2(1000, 0), 0.0], ["vehicle", Vector2(3000, 0), 0.0]])
	_field._block[0] = 0.0
	var w := _arena.get_world_2d()
	for k in 4:
		MapSenses.trace_shot(w, Vector2(0, -300), Vector2(0, 300), 3, false, true)
	check(not _field.is_destroyed(0), "four shots don't destroy a car")
	MapSenses.trace_shot(w, Vector2(0, -300), Vector2(0, 300), 3, false, true)
	check(_field.is_destroyed(0), "the fifth does")
	check(_field.static_body_count() == 2, "and its body is gone")
	var r := MapSenses.trace_shot(w, Vector2(0, -300), Vector2(0, 300), 3, false, true)
	check(r.stop == null, "shots pass over the wreck")
	for k in 10:
		MapSenses.trace_shot(w, Vector2(1000, -300), Vector2(1000, 300), 3, false, true)
	check(not _field.is_destroyed(1), "a truck can't be destroyed")
	MapSenses.trace_shot(w, Vector2(3000, -300), Vector2(3000, 300), 3)
	check(_field._damage[2] == 0.0, "a trace without damage (not a real shot) does none")
	_field.damage_in_radius(Vector2(3100, 0), 300.0, VehicleField.BLAST_DAMAGE)
	check(not _field.is_destroyed(2), "one blast damages a car")
	_field.damage_in_radius(Vector2(3100, 0), 300.0, VehicleField.BLAST_DAMAGE)
	check(_field.is_destroyed(2), "two destroy it")
	check(is_equal_approx(float(_layer._by_spawn[2][0][5]), float(_layer._by_spawn[2][0][10]) * VehicleField.DESTROYED_TONE), "a wreck with no destroyed sprite is darkened")


func _test_dash_destroys() -> void:
	await _setup([["vehicle", Vector2(400, 0), PI / 2.0]])
	var mecha := _tank(Vector2.ZERO)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.global_rotation = 0.0
	await get_tree().physics_frame
	mecha.dash(Vector2(1, 0))
	for _i in 40:
		await get_tree().physics_frame
	check(_field.is_destroyed(0), "dashing into the car destroys it")
	check(mecha.global_position.x > 400.0, "and the mecha carries on through (x %.0f)" % mecha.global_position.x)


func _test_sprint_over() -> void:
	await _setup([["vehicle", Vector2(400, 0), PI / 2.0], ["truck", Vector2(400, 1500), PI / 2.0]])
	var mecha := _tank(Vector2.ZERO)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.global_rotation = 0.0
	var start := _field.vehicle_transform(0).origin
	mecha.is_sprinting = true
	await _drive(mecha, Vector2(WALK, 0), 0.9)
	check(mecha.global_position.x > 380.0, "a sprinting mecha goes on over the car (x %.0f)" % mecha.global_position.x)
	check(_field.vehicle_transform(0).origin.distance_to(start) < 1.0 and not _field.is_awake(0), "without pushing it")
	check(not mecha.get_collision_mask_value(MapSenses.VEHICLE_LAYER), "cars are off while sprinting")
	mecha.is_sprinting = false
	await _drive(mecha, Vector2.ZERO, 0.1)
	check(not mecha.get_collision_mask_value(MapSenses.VEHICLE_LAYER), "still off while it stands over the car")
	await _drive(mecha, Vector2(WALK, 0), 1.0)
	check(mecha.get_collision_mask_value(MapSenses.VEHICLE_LAYER), "back on once clear of it")
	mecha.global_position = Vector2(0, 1500)
	mecha.is_sprinting = true
	await _drive(mecha, Vector2(WALK, 0), 1.2)
	check(mecha.global_position.x < 400.0, "a truck still stops a sprinting mecha (x %.0f)" % mecha.global_position.x)


func _test_car_wall() -> void:
	var cars := []
	for k in range(-6, 7):
		cars.append(["vehicle", Vector2(700, k * 95), PI / 2.0])
	await _setup(cars)
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	enemy.paused = true
	var sprinted := false
	for _i in 240:
		await get_tree().physics_frame
		enemy.going_to_position = true
		enemy.NavAgent.target_position = Vector2(1900, 0)
		enemy.navigate_to_target(1.0 / 60.0, 0.0, 0.0)
		sprinted = sprinted or enemy._car_burst_time > 0.0
	check(sprinted, "it sprints at the wall")
	check(enemy.global_position.x > 800.0, "and gets over it (x %.0f)" % enemy.global_position.x)


func _test_route_walls() -> void:
	# One small building (so the field and its grid exist) and a long solid
	# wall across the way with a gap at the north end.
	await _setup([], [[Vector2(-3000, -3000), Vector2(-2900, -3000), Vector2(-2900, -2900), Vector2(-3000, -2900)]])
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(100, 6000)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(2000, 1000)
	_arena.add_child(wall)
	_buildings._route_grid = null
	_buildings._start_route_build()
	var ready := await wait_until(func(): return _buildings.routes_ready(), 5.0)
	if not check(ready, "the route grid builds"):
		return
	var route: PackedVector2Array = _buildings.find_route(Vector2.ZERO, Vector2(4000, 0))
	var round_north := false
	for p in route:
		if p.y < -2000.0:
			round_north = true
	check(round_north, "the route goes round the wall's north end (%s)" % str(route))
	var prev := Vector2.ZERO
	var crosses := false
	for p in route:
		if (prev.x < 1950.0) != (p.x < 1950.0) and lerpf(prev.y, p.y, (1950.0 - prev.x) / maxf(p.x - prev.x, 0.001)) > -2000.0:
			crosses = true
		prev = p
	check(not crosses, "and never through it")


func _test_forced_route() -> void:
	# A U of walls opening away from the NPC, its goal just behind the U.
	await _setup([], [[Vector2(-3000, -3000), Vector2(-2900, -3000), Vector2(-2900, -2900), Vector2(-3000, -2900)]])
	for r in [Rect2(500, -600, 100, 1200), Rect2(500, -600, 700, 100), Rect2(500, 500, 700, 100)]:
		var wall := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		wall.add_child(shape)
		wall.position = r.get_center()
		_arena.add_child(wall)
	_buildings._route_grid = null
	_buildings._start_route_build()
	await wait_until(func(): return _buildings.routes_ready(), 5.0)
	var enemy := _enemy(Vector2.ZERO, PlayerProgress.DEFAULT_MECHA)
	enemy.set_scripted(false)
	enemy.paused = true
	var goal := Vector2(1400, 0)
	check(enemy._route_next(goal, 1.0 / 60.0) == goal, "a short trip goes straight at first")
	enemy._on_blocked()
	var next: Vector2 = enemy._route_next(goal, 1.0 / 60.0)
	check(next != goal and absf(next.y) > 500.0, "once blocked it routes round the U (%s)" % str(next.round()))
