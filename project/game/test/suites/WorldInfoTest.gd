extends TestSuite

# WorldInfoTest: what the world tells pilots (Phase 6). Heat trails: moving
# mechas leave footprints, hover washes or track smears by chassis, as warm
# as the mecha's thermal signature and speed, cooling over 20 to 40 s, in a
# fixed pool drawn unshaded off the darkness layer; NPC code finds them near
# a point. Car alarms: a push contact sets a car's alarm off by chance, once,
# never a truck or a wrecked car; it blinks and stops after its time or when
# the car is wrecked; the scene makes it a loud sound and an ALARM ping for
# everyone in earshot. Kill records: who killed a mecha, with what, from
# where, and what it knew, shown beside a wreck's loot and closed with it.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")
const FIRE_ENGINE := preload("res://assets/images/map/props/vehicle_fire_engine.png")
const COMBAT_SCENE := preload("res://game/combat/CombatScene.gd")
const CAR_SIZE := Vector2(80, 40)
const TRUCK_SIZE := Vector2(190, 74)
const DT := 1.0 / 60.0
const LEGS := "MSV-L3J-L"
const HOVER := "Lancelot-Chassis"
const TRACKS := "Crawler_C-type_Chassis"


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_random_position() -> Vector2:
		return Vector2.ZERO


var _arena: FakeArena = null
var _field: VehicleField = null


func _init() -> void:
	# Pushing depends on the physics step, so run at game speed.
	time_scale = 1.0


func run_tests() -> void:
	await case("footprints, washes and smears by chassis", _test_marks)
	await case("a mark's warmth: signature, speed, cooling", _test_warmth)
	await case("the pool, the drawing and the NPC query", _test_pool)
	await case("a push contact can set a car alarm off, once", _test_alarm_push)
	await case("an alarm blinks, ends, and dies with its car", _test_alarm_life)
	await case("the scene: a loud sound and an ALARM ping in earshot", _test_alarm_heard)
	await case("a kill record: killer, weapon, where, what it knew", _test_kill_record)
	await case("a mecha's death builds it", _test_die)
	await case("it shows beside the wreck's loot and closes with it", _test_window)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	_field = null
	MechOS.close_all()
	PlayerProgress.reset()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	await get_tree().physics_frame


func _mecha(pos: Vector2, chassis := LEGS) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["chassis"] = chassis
	mecha.set_parts_from_design(design)
	mecha.set_pause(true)
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


func _trails() -> HeatTrails:
	var trails := HeatTrails.new()
	_arena.add_child(trails)
	return trails


# Moves `mecha` to `to` and lets the trails see it.
func _step(mecha: Mecha, to: Vector2) -> void:
	mecha.global_position = to
	await get_tree().physics_frame


func _test_marks() -> void:
	var trails := _trails()
	var walker := _mecha(Vector2.ZERO)
	await get_tree().physics_frame
	check_eq(trails.marks_near(Vector2.ZERO, 500.0).size(), 0, "standing still leaves nothing")
	await _step(walker, Vector2(0, -40))
	check_eq(trails.marks_near(Vector2.ZERO, 500.0).size(), 0, "nor less than a stride")
	await _step(walker, Vector2(0, -80))
	await _step(walker, Vector2(0, -160))
	var marks := trails.marks_near(Vector2(0, -100), 300.0)
	check(marks.size() == 2 and marks.all(func(m): return m.kind == "foot"), "legs leave footprints, one a stride (%d)" % marks.size())
	if marks.size() == 2:
		check(signf(marks[0].position.x) != signf(marks[1].position.x) and absf(marks[0].position.x) == HeatTrails.FOOT_SPACING,
				"left and right in turn")
		check(marks[0].heading.is_equal_approx(Vector2.UP), "pointing the way it went")
	await _step(walker, Vector2(0, -5000))
	check(trails.marks_near(Vector2(0, -5000), 500.0).is_empty(), "a jump (a spawn, a teleport) leaves nothing")

	var tank := _mecha(Vector2(3000, 0), TRACKS)
	await get_tree().physics_frame
	await _step(tank, Vector2(3050, 0))
	var smears := trails.marks_near(Vector2(3050, 0), 200.0)
	check(smears.size() == 2 and smears.all(func(m): return m.kind == "track"), "tracks leave a smear under each side")
	var hover := _mecha(Vector2(6000, 0), HOVER)
	await get_tree().physics_frame
	await _step(hover, Vector2(6060, 0))
	var washes := trails.marks_near(Vector2(6060, 0), 200.0)
	check(washes.size() == 1 and washes[0].kind == "hover", "a hover chassis leaves one wash")
	walker.is_dead = true
	await _step(walker, Vector2(0, -5100))
	await _step(walker, Vector2(0, -5300))
	check(trails.marks_near(Vector2(0, -5200), 300.0).is_empty(), "a dead mecha leaves none")


func _test_warmth() -> void:
	check(is_equal_approx(HeatTrails.start_warmth(1.0, HeatTrails.FULL_WARMTH_SPEED), 1.0), "a hot mecha at speed: full warmth")
	check(is_equal_approx(HeatTrails.start_warmth(0.0, 0.0), HeatTrails.MIN_WARMTH * HeatTrails.SLOW_WARMTH), "a cold, slow one: faint")
	check(HeatTrails.start_warmth(0.5, 400.0) > HeatTrails.start_warmth(0.5, 100.0), "faster is warmer")
	check_eq(HeatTrails.cool_time(1.0), HeatTrails.MAX_COOL_TIME, "a full-warmth mark cools over 40 s")
	check_eq(HeatTrails.cool_time(0.0), HeatTrails.MIN_COOL_TIME, "a faint one over 20 s")

	var trails := _trails()
	var hot := _mecha(Vector2.ZERO)
	hot.external_temp = 150.0
	await get_tree().physics_frame
	hot.velocity = Vector2(0, -HeatTrails.FULL_WARMTH_SPEED)
	await _step(hot, Vector2(0, -100))
	var cold := _mecha(Vector2(2000, 0))
	cold.external_temp = 0.0
	await get_tree().physics_frame
	cold.velocity = Vector2.ZERO
	await _step(cold, Vector2(2000, -100))
	var hot_mark: Dictionary = trails.marks_near(Vector2(0, -100), 100.0)[0]
	var cold_mark: Dictionary = trails.marks_near(Vector2(2000, -100), 100.0)[0]
	check(hot_mark.warmth > 0.9 and cold_mark.warmth < 0.1, "a hot fast mecha's mark is warm, a cold slow one's faint (%.2f, %.2f)" % [hot_mark.warmth, cold_mark.warmth])
	trails.now += 20.0
	hot_mark = trails.marks_near(Vector2(0, -100), 100.0)[0]
	check(absf(hot_mark.warmth - 0.5) < 0.05 and absf(hot_mark.age - 20.0) < 0.5, "it cools in a straight line (half at 20 s of 40)")
	var faint := trails.marks_near(Vector2(2000, -100), 100.0)
	check(faint.is_empty() or faint[0].warmth < 0.01, "the faint one has all but cooled by then (it lasts %.1f s)" % HeatTrails.cool_time(cold_mark.warmth))
	trails.now += 21.0
	check_eq(trails.warm_count(), 0, "after 40 s, nothing is warm")


func _test_pool() -> void:
	var trails := _trails()
	for i in HeatTrails.MAX_MARKS + 50:
		trails.add_mark(Vector2(i, 0), Vector2.UP, HeatTrails.FOOT_SIZE, 1.0, HeatTrails.Kind.FOOT)
	check_eq(trails.warm_count(), HeatTrails.MAX_MARKS, "the pool holds MAX_MARKS; the oldest are reused")
	check(trails.marks_near(Vector2(10, 0), 5.0).is_empty(), "the first marks were reused")
	var drawn := trails.find_children("*", "MultiMeshInstance2D", true, false)
	check(drawn.size() == 1, "drawn by one MultiMesh, no node per mark")
	if drawn.size() == 1:
		var instance: MultiMeshInstance2D = drawn[0]
		check_eq(instance.multimesh.visible_instance_count, HeatTrails.MAX_MARKS, "every mark drawn")
		var material := instance.material as CanvasItemMaterial
		check(material != null and material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
				and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and instance.light_mask == 0,
				"added on, unshaded, off the darkness layer: seen in the dark")
	check(HeatTrails.find(_arena) == trails, "NPC code finds the scene's trails")


# A map with vehicles: each item is [kind, position].
func _vehicles(vehicles: Array) -> void:
	var set := PropSpawnSet.new()
	set.kinds = PackedStringArray(["vehicle", "truck"])
	for v in vehicles:
		set.kind.append(0 if v[0] == "vehicle" else 1)
		set.position.append(v[1])
		set.rotation.append(PI / 2.0)
		set.size.append(CAR_SIZE if v[0] == "vehicle" else TRUCK_SIZE)
		set.variant.append(0)
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = set
	_arena.add_child(spawner)
	var layer := PropSpriteLayer.new()
	layer.name = "Vehicles"
	layer.kinds = PackedStringArray(["vehicle", "truck"])
	layer.textures = {"vehicle": [HATCHBACK], "truck": [FIRE_ENGINE]}
	layer.spans = {"vehicle": PackedFloat32Array([1.0]), "truck": PackedFloat32Array([1.0])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
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


# Walks `mecha` right into whatever is in the way for `seconds`.
func _walk(mecha: Mecha, seconds: float) -> void:
	for _i in int(seconds / DT):
		await get_tree().physics_frame
		mecha.move(Vector2(480, 0))


func _test_alarm_push() -> void:
	await _vehicles([["vehicle", Vector2(400, 0)], ["truck", Vector2(400, 3000)]])
	var started := []
	_field.alarm_started.connect(func(i, at): started.append([i, at]))
	_field.alarm_chance = 1.0
	var pusher := _mecha(Vector2.ZERO)
	pusher.set_pause(false)
	await get_tree().physics_frame
	var car_at := _field.vehicle_transform(0).origin
	await _walk(pusher, 1.5)
	check_eq(started.size(), 1, "running into a car sets its alarm off (at chance 1)")
	check(_field.is_alarm_on(0) and not _field.can_alarm(0), "it sounds, and can't again")
	if started.size() == 1:
		check(started[0][1].distance_to(car_at) < 60.0, "where the car was hit")
	pusher.global_position = Vector2(-600, 0)
	await get_tree().physics_frame
	await _walk(pusher, 1.0)
	check_eq(started.size(), 1, "a car sounds once at most")
	var trucker := _mecha(Vector2(0, 3000))
	trucker.set_pause(false)
	await get_tree().physics_frame
	await _walk(trucker, 1.5)
	check(not _field.is_alarm_on(1) and not _field.can_alarm(1), "a truck never does")
	check_eq(VehicleField.ALARM_CHANCE, 0.05, "the chance per push contact is 5%")


func _test_alarm_life() -> void:
	await _vehicles([["vehicle", Vector2(400, 0)], ["vehicle", Vector2(400, 2000)]])
	_field.start_alarm(0)
	check(_field.is_alarm_on(0) and _field.sounding_alarms() == [0], "start_alarm sets one off")
	var lights := _field.get_children().filter(func(n): return n is Node2D and n.find_children("*", "PointLight2D", true, false).size() == 1)
	check_eq(lights.size(), 1, "with a light on the car")
	if lights.size() == 1:
		var lamp: PointLight2D = lights[0].find_children("*", "PointLight2D", true, false)[0]
		check(lamp.blend_mode == Light2D.BLEND_MODE_ADD, "which adds light (see Illumination)")
	var seen := {}
	for _i in int(VehicleField.ALARM_BLINK * 4.0 / DT):
		await get_tree().physics_frame
		if lights.size() == 1 and is_instance_valid(lights[0]):
			seen[lights[0].visible] = true
	check(seen.has(true) and seen.has(false), "that blinks")
	_field._alarm_left[0] = 0.05
	var ended := await wait_until(func(): return not _field.is_alarm_on(0), 1.0)
	check(ended and not _field.can_alarm(0), "it stops after its time, for good")
	_field.start_alarm(1)
	_field._flatten(1, VehicleField.DESTROYED, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not _field.is_alarm_on(1), "a car destroyed while sounding goes quiet")
	_field.start_alarm(1)
	check(not _field.is_alarm_on(1), "and a wrecked car can't start one")


func _test_alarm_heard() -> void:
	var listener = ENEMY.instantiate()
	listener.mech_inventory = Inventory.new()
	listener.position = Vector2(1000, 0)
	_arena.add_child(listener)
	listener.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Listener")
	listener.paused = true
	var far := _mecha(Vector2(5000, 0))
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(0, 2000)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(false)
	stalker.set_physics_process(false)
	var scene = COMBAT_SCENE.new()
	scene.all_mechas = [listener, far]
	scene.all_entities = [stalker]
	scene._on_car_alarm(0, Vector2.ZERO)
	var heard: Array = listener.senses.sounds
	check(heard.size() == 1 and heard[0].volume_type == "loud" and heard[0].type == "car_alarm" and heard[0].position == Vector2.ZERO,
			"an NPC within 150 m hears a loud car alarm")
	check_eq(stalker.state, Stalker.State.INVESTIGATE, "a creature goes to look")
	var contact: Dictionary = listener.contacts.query({"source": "alarm"})[0] if not listener.contacts.query({"source": "alarm"}).is_empty() else {}
	check(not contact.is_empty() and contact.body == null and contact.kind == "alarm" and contact.reveal == "ping" and contact.live,
			"and gets an ALARM ping at the car, no body")
	check(far.contacts.query({"source": "alarm"}).is_empty(), "a mecha out of earshot gets nothing")
	scene.free()


func _test_kill_record() -> void:
	var victim := _mecha(Vector2.ZERO)
	var killer := _mecha(Vector2(0, -1000))
	killer.callsign = "Ash"
	victim.contacts.report(killer, "mech", killer.global_position, "sight", 5.0)
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(1400, 0)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	victim.contacts.report(stalker, "Stalker", stalker.global_position, "ward", 1.0)
	victim.contacts.advance(3.0)
	var weapon_id: String = PartManager.get_parts("arm_weapon").keys()[0]
	var record := KillRecord.build(victim, {"body": killer, "name": "Ash"}, weapon_id)
	check_eq(record.killer, "Ash", "the killer's callsign")
	check_eq(record.killer_position, Vector2(0, -1000), "where it was")
	check_eq(record.weapon, str(PartManager.get_part("arm_weapon", weapon_id).part_name), "the weapon's name")
	check_eq(record.position, Vector2.ZERO, "where the victim died")
	var contacts: Array = record.contacts
	check(contacts.size() == 2 and contacts[0].live and contacts[0].kind == "mech" and not contacts[1].live and contacts[1].kind == "Stalker",
			"its contacts, live first, then ghosts")
	if contacts.size() == 2:
		check(absf(contacts[1].age - 3.0) < 0.01 and contacts[1].source == "ward", "with source and age")
	killer.is_anonymous = true
	check_eq(KillRecord.build(victim, {"body": killer}, weapon_id).killer, KillRecord.UNKNOWN, "an Anonymous killer is Unknown")
	check_eq(KillRecord.build(victim, {"body": stalker}, "").killer, "Stalker", "a creature by its species")
	var none := KillRecord.build(victim, {"name": "Player"}, "Test")
	check(none.killer == KillRecord.UNKNOWN and none.killer_position == null and none.weapon == "", "no killer body: Unknown, nowhere, no weapon")
	check_eq(KillRecord.bearing(Vector2.ZERO, Vector2(0, -1000)), "50 M N", "bearing north")
	check_eq(KillRecord.bearing(Vector2.ZERO, Vector2(700, 700)), "49 M SE", "bearing south-east")
	check_eq(KillRecord.bearing(Vector2.ZERO, Vector2(-1000, 0)), "50 M W", "bearing west")


func _test_die() -> void:
	var victim := _mecha(Vector2.ZERO)
	var killer := _mecha(Vector2(1000, 0))
	killer.callsign = "Ash"
	var died := []
	victim.died.connect(func(m): died.append(m))
	victim.die({"body": killer, "name": "Ash"}, "Test")
	check_eq(victim.kill_record.get("killer"), "Ash", "die() records it at once")
	await wait_until(func(): return not died.is_empty(), 4.0)
	check(not died.is_empty(), "and the mecha still reports its death as before")


func _test_window() -> void:
	var inventory := Inventory.new()
	inventory.initialize_grid(4, 4)
	var loot := MechOS.open_inventory("container", inventory, "WRECK - TEST")
	loot.position = Vector2(1200, 200)
	var record := {"victim": "Grob", "position": Vector2.ZERO, "killer": "Ash", "killer_position": Vector2(0, -1000),
			"weapon": "MA-L127", "contacts": [
				{"kind": "mech", "source": "sight", "position": Vector2(800, 0), "live": true, "age": 0.0},
				{"kind": "Stalker", "source": "ward", "position": Vector2(0, 2400), "live": false, "age": 6.2}]}
	var window := MechOS.open_kill_record(record, loot) as KillRecordWindow
	check(window != null and MechOS.is_app_open("kill_record"), "the kill record opens")
	if window == null:
		return
	check(window.position.x + window.size.x <= loot.position.x and window.position.y == loot.position.y, "to the left of the loot window")
	var lines := window.get_lines()
	check(lines.has("KILLED BY Ash") and lines.has("WEAPON MA-L127") and lines.has("FIRED FROM 50 M N"), "killer, weapon, where from (%s)" % [lines])
	check(lines.has("MECH · SIGHT · 40 M E · LIVE") and lines.has("STALKER · WARD · 120 M S · 6S OLD"), "and what it knew")
	check("kill_record" in FieldMode.PINNED_APPS, "it stays up while aiming, like the loot")
	MechOS.close_app("container")
	await wait_frames(2)
	check(not MechOS.is_app_open("kill_record"), "closing the loot closes it")
	var bare := MechOS.open_kill_record({"position": Vector2.ZERO, "killer": "Unknown", "killer_position": null, "weapon": "", "contacts": []}) as KillRecordWindow
	var bare_lines := bare.get_lines()
	check(bare_lines.has("WEAPON UNKNOWN") and bare_lines.has("FIRED FROM UNKNOWN") and bare_lines.has("NOTHING"), "unknowns say so")
	MechOS.close_all()
