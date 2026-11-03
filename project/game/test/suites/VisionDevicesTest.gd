extends TestSuite

# VisionDevicesTest: the vision parts of the internal bay (Mecha "INTERNAL
# BAY", Device, Decoy). A Seeker hovers round its owner in a match only,
# drifting and lagging, shows it what is near through walls (ECM shortens
# that), hums for NPCs nearby,
# switches on and off, and once shot down is lost until refitted; a Spotter
# Flare goes ahead or to a point, shows everything near it to every mecha
# whatever their ECM, lights the ground, can't be shot and burns out; a
# Biosensor shows creatures only; a decoy passes for a mecha to sweeps,
# wards and NPC sight, which may target and shoot it, never to its owner,
# and burns out. The player sees the outlines of mechas the Seeker sees
# (creatures and flare-lit mechas in full), others' flares always, and the
# INT row says when the Seeker is lost.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const PLAYER_HUD := preload("res://game/ui/PlayerHUD.tscn")
const SHOT := preload("res://database/parts/projectiles/DefaultSimpleProjectile.tscn")
const COMBAT_SCENE := preload("res://game/combat/CombatScene.gd")

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
	await case("the four parts", _test_parts)
	await case("a Seeker follows its owner, in a match only", _test_seeker_follows)
	await case("a Seeker shows what is near it, hums, toggles", _test_seeker_senses)
	await case("a Seeker shot down is lost until refitted", _test_seeker_lost)
	await case("the player sees what the Seeker sees; the INT row", _test_seeker_player)
	await case("a flare: ahead or at a point, shows everyone, lights, burns out", _test_flare)
	await case("a Biosensor shows creatures only", _test_biosensor)
	await case("a decoy passes for a mecha to sweeps and wards", _test_decoy_sensors)
	await case("NPCs see, target and shoot a decoy", _test_decoy_npc)
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


# A mecha in the arena; in_match gives it the arena, as a match does.
func _mecha(pos: Vector2, internal = false, in_match := true) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA.duplicate())
	if in_match:
		mecha.arena = _arena
	mecha.set_internal(internal)
	mecha.set_pause(true)
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	return mecha


func _npc(pos: Vector2, internal = false) -> Node:
	var npc = ENEMY.instantiate()
	npc.mech_inventory = Inventory.new()
	npc.position = pos
	_arena.add_child(npc)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["internal"] = internal
	npc.setup(_arena, design, "Watcher")
	npc.paused = true
	_arena.mechas.append(npc)
	return npc


func _player(internal) -> Node:
	var player = PLAYER.instantiate()
	player.mech_inventory = Inventory.new()
	_arena.add_child(player)
	player.setup(_arena)
	player.set_physics_process(false)
	player.global_rotation = 0.0
	player.set_internal(internal)
	_arena.mechas.append(player)
	MouseManager.set_aim_available(true)
	return player


func _stalker(pos: Vector2) -> Entity:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = pos
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	return stalker


func _building() -> void:
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _devices(kind := "") -> Array:
	return get_tree().get_nodes_in_group("device").filter(
			func(d): return not d.is_gone() and (kind == "" or d.kind == kind))


# Gone, or already freed.
func _gone(device) -> bool:
	return not is_instance_valid(device) or device.is_gone()


func _shoot(device, shooter) -> void:
	var shot = SHOT.instantiate()
	shot.original_mecha_info = {"body": shooter, "name": shooter.mecha_name}
	shot.base_damage = 5
	shot.dir = Vector2.DOWN
	shot.hit_entity(device)
	shot.free()


func _test_parts() -> void:
	var parts: Dictionary = PartManager.get_parts("internal")
	var expected := {"SK-1": "seeker", "FL-2": "flare", "BS-1": "biosensor", "DC-2": "decoy"}
	for id in expected:
		check(parts.has(id) and parts[id].function == expected[id], "%s is a %s part" % [id, expected[id]])
	if not parts.has("SK-1") or not parts.has("FL-2") or not parts.has("BS-1") or not parts.has("DC-2"):
		return
	check(parts["SK-1"].is_passive() and parts["BS-1"].is_passive(), "the Seeker and Biosensor switch on and off")
	check(parts["FL-2"].charges == 2 and parts["DC-2"].charges == 2, "flares and decoys come two to a part")
	check_eq(parts["FL-2"].device_lifetime, 10.0, "a flare burns 10 s")
	check_eq(parts["DC-2"].device_lifetime, 30.0, "a decoy lasts 30 s")


func _test_seeker_follows() -> void:
	var display := _mecha(Vector2(0, -3000), "SK-1", false)
	check(_devices("seeker").is_empty(), "a mecha outside a match (a Hangar display) puts out no Seeker")
	var owner := _mecha(Vector2(500, 500), "SK-1")
	var seekers := _devices("seeker")
	check(seekers.size() == 1 and seekers[0].owner_mecha == owner and seekers[0].follows_owner, "fitted in a match, a Seeker comes out, switched on")
	if seekers.size() != 1:
		return
	var seeker: Device = seekers[0]
	var nearest := Device.FOLLOW_RADIUS - Device.FOLLOW_RADIUS_SWAY - 40.0
	var furthest := Device.FOLLOW_RADIUS + Device.FOLLOW_RADIUS_SWAY + 40.0
	await get_tree().create_timer(1.5).timeout
	var off := seeker.global_position.distance_to(owner.global_position)
	check(off >= nearest and off <= furthest, "it hovers by its owner (%d px off)" % roundi(off))
	var was := seeker.global_position
	await get_tree().create_timer(1.0).timeout
	check(seeker.global_position.distance_to(was) > 10.0, "and drifts about while its owner stands still")
	owner.global_position = Vector2(1500, 500)
	owner.global_rotation = PI * 0.5
	await get_tree().physics_frame
	check(seeker.global_position.distance_to(owner.global_position) > furthest, "it lags behind a sudden move")
	await get_tree().create_timer(2.0).timeout
	off = seeker.global_position.distance_to(owner.global_position)
	check(off >= nearest and off <= furthest and seeker.global_position.distance_to(seeker.follow_point()) < 60.0,
			"then catches up and wanders round it again, turned with it")
	var local := (seeker.global_position - owner.global_position).rotated(-owner.global_rotation)
	check(local.y > -furthest * 0.5, "keeping mostly beside or behind it")
	owner.set_internal(false)
	check(_devices("seeker").is_empty(), "taking the part out takes it in")
	owner.set_internal("SK-1")
	var again: Device = _devices("seeker")[0]
	owner.is_dead = true
	await wait_frames(3)
	check(_gone(again), "it goes when its owner dies")
	display.queue_free()

	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["internal"] = "SK-1"
	PlayerProgress.set_current_mecha(design, false)
	var player = PLAYER.instantiate()
	player.mech_inventory = Inventory.new()
	_arena.add_child(player)
	player.setup(_arena)
	player.set_physics_process(false)
	check_eq(Device.owned_by(player).size(), 1, "a player deploying with one has it out")
	var npc = _npc(Vector2(0, 3000), "SK-1")
	check_eq(Device.owned_by(npc).size(), 1, "so does an NPC")


func _test_seeker_senses() -> void:
	await _building()
	var owner := _mecha(Vector2(-600, 0), "SK-1")
	var seeker: Device = _devices("seeker")[0]
	await get_tree().physics_frame
	var behind_wall := _mecha(Vector2(200, 0))
	var far := _mecha(Vector2(-600, -3500))
	var ecm := _mecha(seeker.global_position + Vector2(0, 1200), "ECM-50")
	seeker.ping()
	var seen: Dictionary = owner.contacts.best_for(behind_wall)
	check(not seen.is_empty() and seen.source == "seeker" and seen.reveal == "vision", "a mecha behind a wall within 100 m is seen")
	check(owner.contacts.best_for(far).is_empty(), "nothing further out")
	check(owner.contacts.best_for(ecm).is_empty(), "an ECM-0.5 mecha at 60 m isn't (it shows within 50 m)")
	ecm.global_position = seeker.global_position + Vector2(0, 800)
	seeker.ping()
	check(not owner.contacts.best_for(ecm).is_empty(), "closer in, it is")

	var listener = _npc(owner.global_position + Vector2(0, 150))
	var deaf = _npc(owner.global_position + Vector2(-2000, 0))
	var scene = COMBAT_SCENE.new()
	scene.all_mechas = [owner, listener, deaf]
	owner.made_sound.connect(scene._on_mecha_made_sound)
	seeker.make_sound()
	var heard: Array = listener.senses.sounds
	check(heard.size() == 1 and heard[0].volume_type == "quiet" and heard[0].position == seeker.global_position and heard[0].source == owner,
			"an NPC within 30 m hears its quiet hum, from the Seeker, as the owner's")
	check(deaf.senses.sounds.is_empty(), "one further off doesn't")
	listener.senses.sounds.clear()
	var hummed := await wait_until(func(): return not listener.senses.sounds.is_empty(), seeker.sound_interval + 1.0)
	check(hummed, "it hums by itself every %ds" % roundi(seeker.sound_interval))
	owner.made_sound.disconnect(scene._on_mecha_made_sound)
	scene.free()

	check_eq(owner.use_internal(), "", "the internal key")
	check(not owner.internal_on and _devices("seeker").is_empty(), "switches it off and takes it in")
	owner.internal_cooldown = 0.0
	owner.use_internal()
	check(owner.internal_on and _devices("seeker").size() == 1, "and back out")


func _test_seeker_lost() -> void:
	var owner := _mecha(Vector2.ZERO, "SK-1")
	var shooter := _mecha(Vector2(0, -1500))
	var alerts := []
	owner.device_destroyed.connect(func(d): alerts.append(d.kind))
	_shoot(_devices("seeker")[0], shooter)
	check(_devices("seeker").is_empty(), "a mecha's shot brings it down")
	check_eq(alerts, ["seeker"], "the owner hears of it")
	check(owner.internal_lost and not owner.internal_on, "it is lost, and the part is off")
	owner.internal_cooldown = 0.0
	check_eq(owner.use_internal(), "lost", "the key can't bring it back")
	check(_devices("seeker").is_empty(), "no new one")
	owner.set_internal("SK-1")
	check(not owner.internal_lost and _devices("seeker").size() == 1, "fitting the part again does")


func _test_seeker_player() -> void:
	await _building()
	var player = _player(false)
	player.global_position = Vector2(-600, 0)
	var target := _mecha(Vector2(200, 0))
	for i in 12:
		player._update_view(0.1)
	check(target.modulate.a < 0.05, "without a Seeker a mecha behind a wall is hidden")
	player.set_internal("SK-1")
	var seeker: Device = _devices("seeker")[0]
	await get_tree().physics_frame
	var creature := _stalker(Vector2(200, 100))
	seeker.ping()
	for i in 12:
		player._update_view(0.1)
	check(target.modulate.a < 0.05 and player.is_hidden_from_view(target), "with one near it, the mecha itself stays hidden")
	check(player.get_outlined_bodies() == [target], "and is outlined instead")
	check(creature.modulate.a > 0.95 and not player.get_outlined_bodies().has(creature), "a creature it sees is shown in full")

	var hud = PLAYER_HUD.instantiate()
	add_child(hud)
	hud.setup(player, _arena.mechas)
	var sprites := HudVisionOutlines.outline_sprites(target)
	check(not sprites.is_empty() and sprites.all(func(s): return not HudVisionOutlines.SKIP_SPRITES.has(String(s.name))),
			"its sprites are outlined, glows left out (%d)" % sprites.size())
	await get_tree().process_frame
	await get_tree().process_frame
	check_eq(hud.hud_vision_outlines.get_drawn(), sprites.size(), "the HUD draws them")
	check(not hud.hud_world_labels._shows_tag(target), "an outlined mecha shows no name tag")
	player.contacts.report(target, "mech", target.global_position, "flare", 1.0)
	for i in 12:
		player._update_view(0.1)
	check(target.modulate.a > 0.95 and player.get_outlined_bodies().is_empty(), "under a flare too, it is shown in full")
	var weapons: HudWeapons = hud.hud_weapons
	weapons._update()
	var row := weapons.get_row_text("internal")
	check(row.contains("SK-1 Seeker") and row.ends_with("ON / SEEKER"), "the INT row shows it on (%s)" % row)
	_shoot(seeker, target)
	hud.hud_alerts._process(0.0)
	check_eq(hud.hud_alerts.get_current(), "SEEKER DESTROYED", "shot down, the alert says so")
	weapons._update()
	row = weapons.get_row_text("internal")
	check(row.ends_with("LOST / SEEKER"), "and the row reads LOST (%s)" % row)
	hud.queue_free()


func _test_flare() -> void:
	var owner := _mecha(Vector2.ZERO, "FL-2")
	var part = owner.build.internal
	check_eq(owner.use_internal(), "", "a tap fires one")
	var flare: Device = _devices("flare")[0]
	check(flare.global_position.distance_to(owner.global_position + owner.get_facing() * part.throw_range) < 1.0,
			"straight ahead, as far as it goes")
	flare.expire()
	owner.internal_cooldown = 0.0
	owner.use_internal(Vector2(600, 0))
	flare = _devices("flare")[0]
	check(flare.global_position.distance_to(Vector2(600, 0)) < 1.0, "aimed, at the point")
	check_eq(owner.internal_charges, 0, "two charges spent")

	var light := flare.find_children("*", "PointLight2D")
	check(not light.is_empty() and light[0].enabled, "it lights the ground")
	check_eq(flare.collision_layer, 0, "shots pass through it")
	var shooter := _mecha(Vector2(0, -3000))
	flare.take_hit(50.0, 1, Vector2.ZERO, {"body": shooter, "name": shooter.mecha_name})
	check(not flare.is_gone(), "and a hit does nothing")

	var near := _mecha(Vector2(600, 400))
	var ecm := _mecha(Vector2(600, -700), "ECM-50")
	var outside := _mecha(Vector2(600, 2000))
	owner.global_position = Vector2(300, 0)
	flare.ping()
	check_eq(owner.contacts.best_for(near).get("source"), "flare", "it shows its owner what is near it")
	check_eq(owner.contacts.best_for(near).get("reveal"), "vision", "as vision")
	check(not shooter.contacts.best_for(near).is_empty() and not shooter.contacts.best_for(owner).is_empty(),
			"and every other mecha, its owner included")
	check(not owner.contacts.best_for(ecm).is_empty(), "ECM doesn't hide a mecha from it")
	check(owner.contacts.best_for(outside).is_empty(), "nothing past 80 m")
	check(near.contacts.best_for(near).is_empty(), "no mecha is shown itself")

	var alerts := []
	owner.device_destroyed.connect(func(d): alerts.append(d.kind))
	flare.lifetime = 0.05
	var flare_ref: WeakRef = weakref(flare)
	var out := await wait_until(func(): return _gone(flare_ref.get_ref()), 1.0)
	check(out and alerts.is_empty(), "it burns out, and nobody is told")

	var player = _player(false)
	player.global_position = Vector2(-600, 3000)
	owner.internal_charges = 1
	owner.internal_cooldown = 0.0
	owner.use_internal(Vector2(600, 0))
	var burning: Device = _devices("flare")[0]
	var ward_owner := _mecha(Vector2(600, 100), "WD-2")
	ward_owner.use_internal()
	var ward: Device = Device.owned_by(ward_owner)[0]
	for i in 12:
		player._update_view(0.1)
	check(ward.modulate.a < 0.05, "out of the player's sight another's ward is hidden")
	check(burning.modulate.a > 0.95 and not player.is_hidden_from_view(burning), "but another's flare is always shown")


func _test_biosensor() -> void:
	var mecha := _mecha(Vector2.ZERO, "BS-1")
	var part = mecha.build.internal
	var stalker := _stalker(Vector2(0, -700))
	var far := _stalker(Vector2(0, -2500))
	var other := _mecha(Vector2(300, 0))
	mecha._update_biosensor(part.update_interval + 1.0)
	var seen: Dictionary = mecha.contacts.best_for(stalker)
	check(not seen.is_empty() and seen.source == "biosensor" and seen.reveal == "vision" and seen.kind == "Stalker",
			"a creature within 100 m is seen, by species")
	check(mecha.contacts.best_for(far).is_empty(), "not one further out")
	check(mecha.contacts.best_for(other).is_empty(), "never a mecha")
	mecha.use_internal()
	mecha.contacts.clear()
	mecha._update_biosensor(part.update_interval + 1.0)
	check(mecha.contacts.best_for(stalker).is_empty(), "switched off, nothing")
	check(_devices().is_empty(), "it puts out no device")


func _test_decoy_sensors() -> void:
	var owner := _mecha(Vector2.ZERO, "DC-2")
	check_eq(owner.use_internal(), "", "a tap puts a decoy out")
	var decoys := _devices("decoy")
	check(decoys.size() == 1 and decoys[0] is Decoy and decoys[0].global_position.distance_to(owner.global_position) < 1.0,
			"at the mecha's feet")
	if decoys.size() != 1:
		return
	var decoy: Decoy = decoys[0]
	check(decoy.is_in_group("decoy") and decoy.is_in_group("device"), "a device, in the decoy group")
	check_eq(ContactStore.kind_of(decoy), "mech", "contacts call it a mech")
	check_eq(decoy.get_thermal_signature(), owner.build.internal.decoy_heat, "it gives off a mecha's heat")
	owner.internal_cooldown = 0.0
	owner.use_internal(Vector2(0, -5000))
	var thrown = _devices("decoy").filter(func(d): return d != decoy)
	check(thrown.size() == 1 and absf(thrown[0].global_position.length() - owner.build.internal.throw_range) < 1.0,
			"a held use throws one as far as its throw range")

	var sweeper := _mecha(Vector2(0, 1500))
	check(sweeper.sweep_finds(Vector2.UP, 30.0).has(decoy), "another mecha's sweep finds it")
	check(not owner.sweep_finds(Vector2.DOWN, 360.0).has(decoy), "its owner's doesn't")
	sweeper.set_internal("WD-2")
	sweeper.use_internal(Vector2(0, 800))
	var ward: Device = Device.owned_by(sweeper)[0]
	ward.ping()
	check_eq(sweeper.contacts.best_for(decoy).get("kind"), "mech", "another mecha's ward pings it as a mech")
	owner.set_internal("WD-2")
	owner.use_internal()
	Device.owned_by(owner).filter(func(d): return d.kind == "ward")[0].ping()
	check(owner.contacts.best_for(decoy).is_empty(), "its owner's ward leaves it out")

	var alerts := []
	owner.device_destroyed.connect(func(d): alerts.append(d.kind))
	decoy.lifetime = 0.05
	var decoy_ref: WeakRef = weakref(decoy)
	var out := await wait_until(func(): return _gone(decoy_ref.get_ref()), 1.0)
	check(out and alerts.is_empty(), "it burns out (dead to NPCs), nobody told")


func _test_decoy_npc() -> void:
	var owner := _mecha(Vector2(-2500, 0), "DC-2")
	owner.use_internal(Vector2(-2200, 0))
	var decoy: Decoy = _devices("decoy")[0]
	decoy.global_position = Vector2(0, -300)
	var npc = _npc(Vector2.ZERO)
	npc.global_rotation = 0.0
	npc.update_senses(0.1)
	check(npc.is_seeing(decoy), "an NPC in sight of a decoy sees it")
	check_eq(npc.contacts.best_for(decoy).get("kind"), "mech", "and keeps it as a mech contact")
	npc.add_hostility(decoy, 1.0)
	check(npc.should_attack(decoy), "a hostile NPC is willing to attack it")
	npc.check_for_targets(npc.engage_distance * 2.0, 100000.0)
	check(npc.valid_target == decoy, "and picks it as its target")

	var alerts := []
	owner.device_destroyed.connect(func(d): alerts.append(d.kind))
	_shoot(decoy, npc)
	check(decoy.is_dead and _gone(decoy), "an NPC's shot destroys it")
	check_eq(alerts, ["decoy"], "and its owner hears of it")
	npc.update_senses(0.1)
	check(npc.perceived(decoy).is_empty(), "the NPC forgets it")

	npc.set_internal("DC-2")
	npc.use_internal()
	var own: Array = Device.owned_by(npc)
	check(own.size() == 1 and not npc._get_decoys().has(own[0]), "an NPC never takes its own decoy for a mecha")
