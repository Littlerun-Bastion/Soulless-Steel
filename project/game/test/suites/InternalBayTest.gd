extends TestSuite

# InternalBayTest: the internal bay (Mecha "INTERNAL BAY", Device, the ECM
# move). The slot is optional and runs through designs, saves, the stash,
# the Equipment window, stats and NPC designs; chipsets have no ECM and an
# ECM module gives it, switched on or off, plus sensor reduction against
# sweeps and devices; a ward goes down at the mecha or is thrown within its
# range, spends charges and waits its cooldown, and pings what is in range
# through walls into its owner's contacts; a drone flies toward its aim,
# pings round it and self-destructs at the end of its flight; mechas' shots,
# blasts and beams destroy devices and the owner hears of it, other damage
# doesn't; NPC code finds devices near a point and uses the same call as the
# player; the player taps, holds, aims, cancels and toggles with the internal
# key, sees its row on the HUD and its own devices always, others' only when
# in sight.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const PLAYER_HUD := preload("res://game/ui/PlayerHUD.tscn")
const SHOT := preload("res://database/parts/projectiles/DefaultSimpleProjectile.tscn")
const BLAST := preload("res://database/parts/projectiles/DefaultComplexProjectile.tscn")

# A generated building spanning x 0..400, y -200..200.
const BUILDING := [Vector2(0, -200), Vector2(400, -200), Vector2(400, 200), Vector2(0, 200)]


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


func run_tests() -> void:
	await case("the internal slot runs through designs, saves and the stash", _test_slot)
	await case("the Equipment window and stats know the slot", _test_equipment)
	await case("ECM comes from the ECM module, not the chipset", _test_ecm)
	await case("a ward: at the mecha or thrown, charges and cooldown", _test_ward_use)
	await case("a ward pings what is in range into its owner's contacts", _test_ward_pings)
	await case("a drone flies, pings round it and self-destructs", _test_drone)
	await case("mechas' shots and blasts destroy devices, the owner hears", _test_destroy)
	await case("NPC code finds devices and uses the same call", _test_npc_hooks)
	await case("the player taps, holds, aims, cancels and toggles", _test_player_input)
	await case("the HUD row, the alert, and who sees which devices", _test_hud_and_view)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	MechOS.close_all()
	MouseManager.reset()
	PlayerProgress.reset()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	await get_tree().physics_frame


func _mecha(pos: Vector2, internal = false) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["internal"] = internal
	mecha.set_parts_from_design(design)
	mecha.set_pause(true)
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


func _devices() -> Array:
	return get_tree().get_nodes_in_group("device").filter(func(d): return not d.is_gone())


func _test_slot() -> void:
	check(PlayerProgress.DEFAULT_MECHA.has("internal") and PlayerProgress.DEFAULT_MECHA.internal == false, "the default design has an empty internal bay")
	check(not "internal" in PlayerProgress.REQUIRED_SLOTS, "it isn't required to deploy")
	check("internal" in PlayerProgress.PART_TYPES, "it is a part type (stash, Fabricator)")
	var parts: Dictionary = PartManager.get_parts("internal")
	for id in ["WD-2", "DR-4", "ECM-20", "ECM-35", "ECM-50"]:
		check(parts.has(id), "%s is a part" % id)
	var mecha := _mecha(Vector2.ZERO, "WD-2")
	check_eq(mecha.get_design_data().get("internal"), "WD-2", "a fitted part is in the design")
	var old_design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	old_design.erase("internal")
	mecha.set_parts_from_design(old_design)
	check(mecha.build.internal == null, "a design from before the slot fits nothing there")
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["internal"] = "DR-4"
	PlayerProgress.set_current_mecha(design, false)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.reset()
	PlayerProgress.set_save_data(saved)
	check_eq(PlayerProgress.get_current_mecha().get("internal"), "DR-4", "the fitted part is saved")
	saved.current_mecha.erase("internal")
	PlayerProgress.set_save_data(saved)
	check_eq(PlayerProgress.get_current_mecha().get("internal"), false, "an older save gets an empty bay")
	check(PlayerProgress.add_part("internal", "WD-2", false), "an internal part goes into the stash")
	check_eq(PlayerProgress.count_part("internal", "WD-2"), 1, "and is counted there")
	var professional: Dictionary = NPCManager.get_design_data(NPCManager.NPCS[0])
	check_eq(professional.get("internal"), "ECM-20", "an NPC design can carry an internal part")
	var volk: Dictionary = NPCManager.get_design_data(NPCManager.get_special_npc("Lady Volk"))
	check_eq(volk.get("internal"), false, "a named NPC without one has an empty bay")


func _test_equipment() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var window := MechOS.open_equipment(mecha) as EquipmentWindow
	var slot: PartSlot = null
	for s in window.part_slots:
		if s.part_type == "internal":
			slot = s
	check(slot != null, "the Equipment window has an INTERNAL slot")
	if slot == null:
		return
	window._on_wetware_pressed()
	check(slot.visible, "on the WETWARE tab")
	window._set_mecha_part_for_slot(slot, "ECM-35")
	check(mecha.build.internal != null and mecha.build.internal.part_id == "ECM-35", "fitting it there equips it")
	check_eq(StatsPanel.sum_stat(mecha.build, "sensor_reduction"), 0.35, "the stats show its sensor reduction")
	check_eq(StatsPanel.sum_stat(mecha.build, "ECM"), 10.0, "and its ECM")
	window._set_mecha_part_for_slot(slot, null)
	check(mecha.build.internal == null, "and it can be taken out")


func _test_ecm() -> void:
	for chip_id in PartManager.get_parts("chipset"):
		check(PartManager.get_part("chipset", chip_id).get("ECM") == null, "chipset %s has no ECM" % chip_id)
	var plain := _mecha(Vector2.ZERO)
	check(plain.ecm == 0.0 and plain.sensor_reduction == 0.0, "a mecha with no module has no ECM")
	var ecm := _mecha(Vector2(0, -4000), "ECM-35")
	check(ecm.internal_on, "an ECM module is on when fitted")
	check(ecm.ecm == 10.0 and ecm.ecm_frequency > 0.0, "it gives ECM against lock-ons")
	check_eq(ecm.sensor_reduction, 0.35, "and sensor reduction")
	check_eq(ecm.use_internal(), "", "using it")
	check(not ecm.internal_on and ecm.ecm == 0.0 and ecm.sensor_reduction == 0.0, "switches it off")
	check_eq(ecm.use_internal(), "cooldown", "not again straight away")
	ecm.internal_cooldown = 0.0
	ecm.use_internal()
	check(ecm.internal_on and ecm.sensor_reduction == 0.35, "and back on")
	check_eq(ecm.internal_charges, 0, "a passive part has no charges")
	var far := _mecha(Vector2(0, -7000), "ECM-50")
	var near := _mecha(Vector2(300, -4900), "ECM-50")
	var found := plain.sweep_finds(Vector2.UP, 30.0)
	check(found.has(near) and not found.has(far), "a sweep finds an ECM-0.5 mecha within 250 m only")
	check(found.has(ecm), "and an ECM-0.35 one at 200 m")


func _test_ward_use() -> void:
	var mecha := _mecha(Vector2(100, 100), "WD-2")
	var part = mecha.build.internal
	check_eq(mecha.internal_charges, 2, "a ward part comes with 2 charges")
	check_eq(mecha.use_internal(), "", "a tap puts one out")
	var wards := _devices()
	check(wards.size() == 1 and wards[0].kind == "ward", "a ward")
	if wards.size() == 1:
		check(wards[0].global_position.distance_to(mecha.global_position) < 1.0, "at the mecha's feet")
		check(wards[0].owner_mecha == mecha, "owned by the mecha")
	check_eq(mecha.use_internal(Vector2(100, -5000)), "cooldown", "it waits its cooldown")
	mecha.internal_cooldown = 0.0
	check_eq(mecha.use_internal(Vector2(100, -5000)), "", "a held use throws one")
	wards = _devices()
	var thrown = wards.filter(func(d): return d.global_position.distance_to(mecha.global_position) > 1.0)
	check(thrown.size() == 1 and absf(thrown[0].global_position.distance_to(mecha.global_position) - part.throw_range) < 1.0,
			"as far as its throw range toward the aim")
	check_eq(mecha.internal_charges, 0, "two charges spent")
	mecha.internal_cooldown = 0.0
	check_eq(mecha.use_internal(), "no_charges", "then it is out")
	check_eq(_mecha(Vector2.ZERO).use_internal(), "no_part", "a mecha with nothing in the bay can't use it")
	check_eq(mecha.get_devices().size(), 2, "the mecha knows its devices")


func _test_ward_pings() -> void:
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var owner := _mecha(Vector2(-1000, 0), "WD-2")
	owner.use_internal()
	var ward: Device = _devices()[0]
	var behind_wall := _mecha(Vector2(200, 0))
	var out_of_range := _mecha(Vector2(-1000, -3200))
	var ecm := _mecha(Vector2(-1000, 2100), "ECM-35")
	var stalker: Entity = STALKER.instantiate()
	stalker.position = Vector2(-1500, 0)
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	ward.ping()
	var store := owner.contacts
	var seen: Dictionary = store.best_for(behind_wall)
	check(not seen.is_empty() and seen.source == "ward" and seen.reveal == "ping", "a mecha behind a wall is pinged")
	check(not store.best_for(stalker).is_empty() and store.best_for(stalker).kind == "Stalker", "a creature too, by species")
	check(store.best_for(out_of_range).is_empty(), "nothing past 150 m")
	check(store.best_for(ecm).is_empty(), "an ECM-0.35 mecha at 105 m isn't (it shows within 97 m)")
	check(store.best_for(owner).is_empty(), "never its owner")
	ecm.global_position = Vector2(-1000, 1800)
	ward.ping()
	check(not store.best_for(ecm).is_empty(), "closer in, it is")
	check(store.best_for(behind_wall).live, "a pinged contact is live")
	store.advance(ward.update_interval + Device.PING_SLACK + 0.1)
	check(not store.best_for(behind_wall).live, "a ghost if no ping comes")
	var before := store.size()
	store.clear()
	owner.set_pause(false)
	var pinged := await wait_until(func(): return store.size() > 0, ward.update_interval * 2.0 + 1.0)
	check(pinged, "the ward pings by itself every %ds (%d contacts before)" % [roundi(ward.update_interval), before])
	owner.set_pause(true)


func _test_drone() -> void:
	var owner := _mecha(Vector2.ZERO, "DR-4")
	check_eq(owner.internal_charges, 4, "a drone part comes with 4 charges")
	owner.use_internal(Vector2(3000, 0))
	var drone: Device = _devices()[0]
	check_eq(drone.kind, "drone", "a drone")
	check(drone.heading.is_equal_approx(Vector2.RIGHT), "heading for the aim")
	var target := _mecha(Vector2(1500, 300))
	var start := drone.global_position
	await wait_until(func(): return drone.global_position.x > 1300.0, 6.0)
	check(drone.global_position.x > start.x and absf(drone.global_position.y) < 1.0, "it flies straight")
	drone.ping()
	check(owner.contacts.best_for(target).source == "drone", "and pings what is within 100 m of it")
	drone.max_distance = drone.travelled + 50.0
	var gone := await wait_until(func(): return _devices().is_empty(), 3.0)
	check(gone, "it self-destructs at the end of its flight")
	owner.internal_cooldown = 0.0
	owner.use_internal()
	var ahead: Device = _devices()[0]
	check(ahead.heading.is_equal_approx(owner.get_facing()), "a tap sends it straight ahead")


func _test_destroy() -> void:
	var owner := _mecha(Vector2.ZERO, "WD-2")
	var shooter := _mecha(Vector2(0, -1000))
	var alerts := []
	owner.device_destroyed.connect(func(d): alerts.append(d.kind))
	owner.use_internal()
	var ward: Device = _devices()[0]
	ward.take_hit(5.0, 1, Vector2.ZERO, null)
	check(not ward.is_gone(), "damage with no source does nothing")
	var stalker: Entity = STALKER.instantiate()
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	ward.take_hit(5.0, 1, Vector2.ZERO, {"body": stalker, "name": "Stalker"})
	check(not ward.is_gone(), "a creature can't destroy it")
	var shot = SHOT.instantiate()
	shot.original_mecha_info = {"body": shooter, "name": shooter.mecha_name}
	shot.base_damage = 5
	shot.dir = Vector2.DOWN
	shot.hit_entity(ward)
	check(ward.is_gone(), "a mecha's shot destroys it")
	check_eq(alerts, ["ward"], "and the owner hears of it")
	shot.free()
	owner.internal_cooldown = 0.0
	owner.use_internal()
	var second: Device = _devices()[0]
	var blast = BLAST.instantiate()
	check(blast.is_blast_target(second) and not blast.is_fuse_target(second), "a blast hurts devices, which don't set fuses off")
	blast.free()
	check(MapSenses.solid_hit(_arena.get_world_2d(), Vector2(0, -300), Vector2(0, 300)) == null, "a device doesn't stop a designator line or a laser")
	second.destroy()
	check_eq(alerts.size(), 2, "destroy() from NPC code tells the owner too")


func _test_npc_hooks() -> void:
	var npc = ENEMY.instantiate()
	npc.mech_inventory = Inventory.new()
	npc.position = Vector2(500, 0)
	_arena.add_child(npc)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["internal"] = "WD-2"
	npc.setup(_arena, design, "Ward NPC")
	npc.paused = true
	_arena.mechas.append(npc)
	check_eq(npc.can_use_internal(), "", "an NPC with a ward part can use it")
	check_eq(npc.use_internal(Vector2(500, -200)), "", "through the same call as the player")
	var near := Device.find_near(self, Vector2(500, -200), 100.0)
	check(near.size() == 1 and near[0].owner_mecha == npc and near[0].kind == "ward", "find_near gives its owner and kind")
	check(Device.find_near(self, Vector2(5000, 0), 100.0).is_empty(), "and nothing where there is none")
	near[0].destroy()
	check(Device.find_near(self, Vector2(500, -200), 100.0).is_empty(), "a destroyed device is gone")


func _player(internal) -> Node:
	var player = PLAYER.instantiate()
	player.mech_inventory = Inventory.new()
	_arena.add_child(player)
	player.setup(_arena)
	player.set_internal(internal)
	player.set_physics_process(false)
	player.global_rotation = 0.0
	_arena.mechas.append(player)
	MouseManager.set_aim_available(true)
	return player


func _action(action: String, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _test_player_input() -> void:
	var player = _player("WD-2")
	player._input(_action("use_internal"))
	check(player.is_internal_held(), "pressing the key with a ward part starts a hold")
	player._input(_action("use_internal", false))
	var wards := _devices()
	check(wards.size() == 1 and wards[0].global_position.distance_to(player.global_position) < 1.0, "a tap puts a ward at its feet")
	player.internal_cooldown = 0.0
	player._input(_action("use_internal"))
	player._update_designators(player.TAP_TIME + 0.05)
	var marks: Array = player.designator.marks
	check(marks.size() == 1 and marks[0].shape == "circle" and marks[0].max_range == player.build.internal.throw_range,
			"held, the designator shows the landing circle and the throw range")
	player._input(_action("reload_mode"))
	check(not player.is_internal_held() and player.internal_charges == 1, "reload cancels; no charge spent")
	player._input(_action("use_internal"))
	player._update_designators(player.TAP_TIME + 0.05)
	player._input(_action("use_internal", false))
	wards = _devices()
	check(wards.size() == 2 and player.internal_charges == 0, "released after a hold, it puts the second one out")
	var thrown = wards.filter(func(d): return d.global_position.distance_to(player.global_position) >= 1.0)
	if not thrown.is_empty():
		check(thrown[0].global_position.distance_to(player.global_position) <= player.build.internal.throw_range + 1.0, "within its throw range")
	player.set_internal("ECM-20")
	check(player.internal_on, "an ECM module starts on")
	player._input(_action("use_internal"))
	check(not player.internal_on and not player.is_internal_held(), "pressing the key switches it off, no hold")


func _test_hud_and_view() -> void:
	var player = _player("WD-2")
	player.global_position = Vector2(-1000, 0)
	var hud = PLAYER_HUD.instantiate()
	add_child(hud)
	hud.setup(player, _arena.mechas)
	var weapons: HudWeapons = hud.hud_weapons
	weapons._update()
	var row := weapons.get_row_text("internal")
	check(row.contains("INT") and row.contains("WD-2 Ward") and row.ends_with("2 / CHARGES"), "the INT row shows the part and its charges (%s)" % row)
	player.use_internal()
	weapons._update()
	check(weapons.get_row_text("internal").contains("INT · 1S"), "and the cooldown (%s)" % weapons.get_row_text("internal"))
	var own: Device = _devices()[0]
	var other_owner := _mecha(Vector2(-1000, 2500), "WD-2")
	other_owner.use_internal()
	var other: Device = other_owner.get_devices()[0]
	for i in 12:
		player._update_view(0.1)
	check(own.modulate.a > 0.95, "the player always sees its own ward")
	check(other.modulate.a < 0.05, "another mecha's ward out of sight is hidden")
	var shooter := _mecha(Vector2(-1000, -1000))
	own.take_hit(10.0, 1, Vector2.ZERO, {"body": shooter, "name": "Shooter"})
	hud.hud_alerts._process(0.0)
	check_eq(hud.hud_alerts.get_current(), "WARD DESTROYED", "losing a ward raises the alert")
	var last: Dictionary = MechLog.lines[MechLog.lines.size() - 1]
	check_eq(last.text, "Ward destroyed", "and a log line")
	hud.queue_free()
