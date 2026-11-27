extends TestSuite

# CampTest: Entity camps (Camp, CampField) on a small stand-in arena with
# real mechas and Entities. A dormant camp is off the map and wakes whole
# when the player, a device or an NPC in full simulation comes within its
# wake reach, and not before; with everyone gone it goes back to sleep,
# keeping its survivors' hp and losses, while a hunting member keeps it
# awake; a cleared camp never comes back. The awake budget holds members
# back until the camp next sleeps. A sweep counts dormant camps, and they
# wake up listening for it. A distant NPC fights a dormant pack on paper:
# hits on the NPC, members killed, and their carcasses there when it wakes.
# Loose Entities nobody is near become a camp. Encounters: gunfire at the
# site while the fight lasts; woken halfway, the NPC is hurt, part of the
# pack is dead and the rest hunt it; a duel nobody reached in time has one
# pilot dead; an abandoned hunt leaves its pack as a camp. The tension rises
# in a lull, falls in a fight, and eases off for a battered mecha.
# Roamers: in Local while dormant, walking on paper, waking as the same
# pilot with no Local lines; through a sleep a mecha keeps its damage and
# ammo; a squad wakes as one squad, tagged; a loud sound draws a dormant
# roamer, and it leaves Local when its time is up; its paper fight with a
# pack comes with it as wounds.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const WARD := preload("res://game/mecha/devices/Ward.tscn")
const WARD_PART := preload("res://database/parts/internals/WD-2.tres")


# The parts of an Expedition scene camps use.
class FakeArena extends Node2D:
	var mechas: Array = []
	var entities: Array = []
	var player = null
	var sounds: Array = []
	var dead: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return entities
	func get_random_position() -> Vector2:
		return Vector2.ZERO
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2.ZERO
	func add_entity(scene: PackedScene, pos: Vector2, prepare := Callable()) -> Entity:
		var entity: Entity = scene.instantiate()
		if prepare.is_valid():
			prepare.call(entity)
		entity.position = pos
		add_child(entity)
		entity.setup(self)
		entities.append(entity)
		entity.died.connect(_on_died)
		return entity
	func _on_died(entity) -> void:
		entities.erase(entity)
		dead.append(entity)
	func unregister_entity(entity) -> void:
		entities.erase(entity)
		entity.died.disconnect(_on_died)
	var enemy_maker: Callable
	func add_enemy(design, enemy_name: String, pos = null, join_local := true) -> Mecha:
		var enemy: Mecha = enemy_maker.call(design, enemy_name, pos)
		enemy.is_anonymous = design.get("anonymous", false) == true
		if str(design.get("squad_tag", "")) != "" and not enemy.is_anonymous:
			enemy.squad_tag = design.squad_tag
		if join_local:
			local_pilots.join(enemy)
		return enemy
	func _on_mecha_made_sound(sound_data) -> void:
		sounds.append(sound_data)
	var field: CampField = null
	func dormant_sweep_counts(sweeper, direction, width) -> Dictionary:
		return field.sweep_counts(sweeper, direction, width)
	var local_pilots := LocalPilots.new()
	var squads: Array = []
	func get_wander_point(from: Vector2) -> Vector2:
		return from + Vector2(8000, 0)
	func stow_mecha(mecha) -> void:
		for squad in squads.duplicate():
			if squad.is_in(mecha):
				squad.remove(mecha)
				if squad.members.is_empty():
					squads.erase(squad)
		mechas.erase(mecha)
		mecha.queue_free()


var _arena: FakeArena = null
var _field: CampField = null
var _player: Mecha = null


func run_tests() -> void:
	await case("a dormant camp is off the map until the player comes within its wake reach", _test_player_wakes)
	await case("a ward wakes a camp; an NPC wakes one only in full simulation", _test_other_wakers)
	await case("with everyone gone it sleeps with its losses; a cleared camp never comes back", _test_sleep_keeps_losses)
	await case("a hunting member keeps its camp awake", _test_hunting_stays)
	await case("the awake budget holds members back until the camp sleeps", _test_budget)
	await case("a sweep counts dormant camps, and they wake up listening for it", _test_sweep)
	await case("a distant NPC fights a dormant pack on paper; the dead lie there when it wakes", _test_paper_fight)
	await case("loose Entities nobody is near become a camp", _test_adopt)
	await case("an encounter makes gunfire while its fight lasts", _test_gunfire)
	await case("a hunt woken halfway: the NPC hurt, part of the pack dead, the rest on it", _test_hunt_halfway)
	await case("a duel nobody reached in time has one pilot dead", _test_duel_over)
	await case("an abandoned hunt leaves its pack as a camp", _test_abandoned)
	await case("the tension rises in a lull, falls in a fight, eases off for a battered mecha", _test_tension)
	await case("a roamer is in Local while dormant, walks on paper, and wakes as the same pilot", _test_roamer_wakes)
	await case("through a sleep a roamer's mecha keeps its damage and ammo", _test_roamer_keeps_state)
	await case("a roaming squad wakes as one squad, tagged", _test_roamer_squad)
	await case("a loud sound draws a dormant roamer; it leaves Local when its time is up", _test_roamer_hears_and_leaves)
	await case("a dormant roamer's paper fight with a pack comes with it as wounds", _test_roamer_paper_fight)
	await _clear()


func before_each() -> void:
	await _clear()
	_arena = FakeArena.new()
	add_child(_arena)
	_arena.enemy_maker = _make_enemy
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-60000, -60000), Vector2(60000, -60000), Vector2(60000, 60000), Vector2(-60000, 60000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	var bounds := MapBounds.new()
	bounds.map_rect = Rect2(-62000, -62000, 124000, 124000)
	bounds.border = 2000.0
	_arena.add_child(bounds)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array([Vector2(-50000, -50000), Vector2(-49900, -50000), Vector2(-49900, -49900), Vector2(-50000, -49900)])
	footprints.starts = PackedInt32Array([0, 4])
	var buildings := BuildingField.new()
	buildings.footprints = footprints
	_arena.add_child(buildings)
	_player = _mecha(Vector2.ZERO)
	_player.arena = _arena
	_arena.player = _player
	var cam := Camera2D.new()
	_player.add_child(cam)
	cam.make_current()
	_field = CampField.new()
	_arena.add_child(_field)
	_field.setup(_arena, 100)
	_field.set_process(false)
	_arena.field = _field
	await wait_frames(2)


func _clear() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = null


func _mecha(pos: Vector2) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	return mecha


func _make_enemy(design, enemy_name: String, pos) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos if pos is Vector2 else Vector2.ZERO
	_arena.add_child(enemy)
	enemy.setup(_arena, design, enemy_name)
	enemy.wait_for_map_sync = 0.0
	enemy.flag_grace = 0.0
	_arena.mechas.append(enemy)
	return enemy


func _design() -> Dictionary:
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["personality"] = NPCManager._personality_from_string("hunter")
	return design


# The player's wake reach: its head's sight plus the margin.
func _reach() -> float:
	return CampField.full_sight(_player) + CampField.WAKE_MARGIN


func _living() -> Array:
	return _arena.entities.filter(func(e): return is_instance_valid(e) and not e.is_dead)


# Moves the player far from everything (its camera follows on the next
# frames) and runs the field until camps sleep.
func _walk_away() -> void:
	_player.global_position = Vector2(55000, 55000)
	await wait_frames(2)
	for k in ceili((CampField.SLEEP_DELAY + 1.0) / CampField.TICK) + 1:
		_field.advance(CampField.TICK)


func _test_player_wakes() -> void:
	var at := Vector2(_reach() + 3000.0, 0.0)
	var camp := _field.add_camp(Camp.PACK, at, 5, 2)
	_field.update()
	check(_arena.entities.is_empty() and camp.state == Camp.State.DORMANT, "out of reach, nothing is on the map")
	check_eq(camp.size(), 5, "its five members are in its roster")
	_player.global_position = Vector2(at.x - _reach() + 200.0, 0.0)
	_field.update()
	check_eq(camp.state, Camp.State.AWAKE, "within its wake reach it wakes")
	check_eq(_living().size(), 5, "whole")
	check(camp.roster.is_empty(), "and its roster is all on the map")
	var spitters := _living().filter(func(e): return e is CoyoteSpitter).size()
	check_eq(spitters, 2, "two of them Spitters")
	var pack: EntityPack = _living()[0].pack
	check(pack != null and _living().all(func(e): return e.pack == pack), "one pack")
	check(not pack.leader() is CoyoteSpitter, "led by a Coyote")
	check(_living().all(func(e): return CampField.camp_of(e) == camp), "each knows its camp")
	check(_living().all(func(e): return e.global_position.distance_to(at) < CampField.SPREAD * 2.0), "round its site")
	check(_reach() > _player.sight_radius(), "the reach is beyond what the player can see")


func _test_other_wakers() -> void:
	var at := Vector2(_reach() + 8000.0, 0.0)
	var camp := _field.add_camp(Camp.FISHER, at)
	var ward: Device = WARD.instantiate()
	ward.setup(_player, WARD_PART)
	ward.position = at + Vector2(WARD_PART.sensor_range + CampField.WAKE_MARGIN + 500.0, 0.0)
	_arena.add_child(ward)
	_field.update()
	check_eq(camp.state, Camp.State.DORMANT, "a ward out of its reach leaves it dormant")
	ward.global_position = at + Vector2(WARD_PART.sensor_range + CampField.WAKE_MARGIN - 300.0, 0.0)
	_field.update()
	check_eq(camp.state, Camp.State.AWAKE, "a ward within its sensor range plus the margin wakes it")
	check(_living().size() == 1 and _living()[0] is Fisher, "its Fisher is on the map")
	ward.queue_free()
	await wait_frames(1)
	var far := Vector2(0.0, _reach() + 20000.0)
	var camp2 := _field.add_camp(Camp.TICK_SWARM, far)
	var npc := _make_enemy(_design(), "Waker", far + Vector2(1000.0, 0.0))
	npc.set_pause(true)
	npc._set_distant(true)
	_field.update()
	check_eq(camp2.state, Camp.State.DORMANT, "a distant NPC on top of it doesn't wake it")
	npc._set_distant(false)
	_field.update()
	check_eq(camp2.state, Camp.State.AWAKE, "the same NPC in full simulation does")


func _test_sleep_keeps_losses() -> void:
	var at := Vector2(_reach() - 500.0, 0.0)
	var camp := _field.add_camp(Camp.PACK, at, 4, 1)
	_field.update()
	var members := _living()
	check_eq(members.size(), 4, "awake with four")
	members[0].hp = members[0].max_hp * 0.5
	members[1].die()
	var middle := Vector2.ZERO
	for e in members.slice(0, 1) + members.slice(2):
		middle += e.global_position
	middle /= 3.0
	await _walk_away()
	check_eq(camp.state, Camp.State.DORMANT, "with nobody near for a while it sleeps")
	check(_living().is_empty(), "its members are off the map")
	check_eq(camp.roster.size(), 3, "three survivors in its roster")
	check(camp.roster.any(func(e): return absf(float(e.hp) - 0.5) < 0.01), "the hurt one keeps its hp")
	check(camp.site.distance_to(middle) < 100.0, "the site is where they ended up")
	_player.global_position = camp.site
	_field.update()
	check_eq(_living().size(), 3, "it wakes with three")
	check(_living().any(func(e): return absf(e.get_hp_fraction() - 0.5) < 0.01), "one of them still hurt")
	for e in _living():
		e.die()
	await _walk_away()
	check(not _field.camps.has(camp), "cleared, it is gone for good")
	_player.global_position = at
	_field.update()
	check(_living().is_empty(), "and nothing comes back")


func _test_hunting_stays() -> void:
	var camp := _field.add_camp(Camp.PACK, Vector2(_reach() - 500.0, 0.0), 3, 1)
	_field.update()
	var hunter: Entity = _living()[0]
	var prey := _mecha(Vector2(50000, 50000))
	# Held, so it doesn't give up on prey this far off by itself.
	hunter.set_pause(true)
	hunter.target = prey
	await _walk_away()
	check_eq(camp.state, Camp.State.AWAKE, "a member after prey keeps it on the map")
	hunter.target = null
	await _walk_away()
	check_eq(camp.state, Camp.State.DORMANT, "once it lets go, the camp sleeps")


func _test_budget() -> void:
	_field.awake_budget = 3
	var camp := _field.add_camp(Camp.PACK, Vector2(_reach() - 500.0, 0.0), 5, 1)
	_field.update()
	check_eq(_living().size(), 3, "it wakes with the budget's three")
	check_eq(camp.roster.size(), 2, "two wait in its roster")
	await _walk_away()
	check_eq(camp.roster.size(), 5, "asleep, all five are in its roster again")
	var pinned := _field.add_pinned_camp(Camp.PACK, Vector2(0.0, _reach() - 500.0))
	_player.global_position = Vector2.ZERO
	_field.awake_budget = 0
	_field.update()
	check(pinned.state == Camp.State.AWAKE and pinned.roster.is_empty(), "a pinned camp wakes whole, whatever the budget")


func _test_sweep() -> void:
	var at := Vector2(0.0, -(_reach() + 2000.0))
	var camp := _field.add_camp(Camp.PACK, at, 4, 1)
	_field.add_camp(Camp.FISHER, Vector2(0.0, _reach() + 2000.0))
	_player.global_rotation = 0.0
	var result: Dictionary = _player.sweep(Vector2.UP, 30.0)
	check(result.ok, "the sweep ran")
	check_eq(int(result.counts.get("Coyote", 0)), 3, "three Coyotes counted ahead")
	check_eq(int(result.counts.get("Coyote Spitter", 0)), 1, "and a Spitter")
	check(not result.counts.has("Fisher"), "the Fisher behind isn't in the cone")
	check(_arena.entities.is_empty(), "nothing woke")
	check_eq(camp.heard_at, _player.global_position, "the camp heard where it came from")
	_player.global_position = at + Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var coyotes := _living().filter(func(e): return e is Coyote and not e is CoyoteSpitter)
	check(not coyotes.is_empty() and coyotes.all(func(c): return c.state == Coyote.State.INVESTIGATE),
			"they wake up going to look")


func _test_paper_fight() -> void:
	seed(7)
	var at := Vector2(_reach() + 10000.0, 0.0)
	var camp := _field.add_camp(Camp.PACK, at, 6, 1)
	var npc := _mecha(at + Vector2(300.0, 0.0))
	var hits := [0]
	npc.component_damaged.connect(func(_p, _c, _hp, _max): hits[0] += 1)
	for k in 30:
		_field.paper_round(camp, npc)
	check(camp.roster.size() < 6, "members died (%d left)" % camp.roster.size())
	check_eq(camp.remains.size(), 6 - camp.roster.size(), "each one dead is in its remains")
	check(hits[0] > 0, "and the pack got hits in (%d)" % hits[0])
	var dead_before: int = _arena.dead.size()
	var dead_count := camp.remains.size()
	_player.global_position = at
	_field.update()
	check_eq(_arena.dead.size() - dead_before, dead_count, "woken, the dead are put there dead (carcasses)")
	check_eq(_living().size(), camp.living().size(), "the survivors alive")
	var swarm := _field.add_camp(Camp.TICK_SWARM, Vector2(-(_reach() + 10000.0), 0.0))
	_field.paper_round(swarm, npc)
	check_eq(swarm.roster.size(), 1, "a tick swarm doesn't fight on paper")


func _test_adopt() -> void:
	var at := Vector2(30000, 0)
	var loose: Entity = _arena.add_entity(CampField.FISHER, at)
	await _walk_away()
	check(not is_instance_valid(loose) or loose.is_queued_for_deletion(), "the loose Fisher is off the map")
	var camps := _field.camps.filter(func(c): return c.kind == Camp.FISHER)
	check(camps.size() == 1 and camps[0].roster.size() == 1, "in a camp of its own")
	check(camps[0].site.distance_to(at) < 400.0, "where it was")


func _test_gunfire() -> void:
	_field.lay_out_sites([Vector2(_reach() + 20000.0, 0.0)])
	var camp := _field.arm_encounter(Camp.DUEL, _field.sites[0], 0.5, [_design(), _design()])
	check(_field.sites[0].used, "its site is taken")
	for k in 20:
		_field.advance(0.5)
	check(not _arena.sounds.is_empty(), "gunfire sounds while it lasts (%d shots)" % _arena.sounds.size())
	check(_arena.sounds.all(func(s): return s.position == camp.site and s.volume_type == "loud"), "loud, at the site")
	check(_arena.mechas.size() == 1, "and nothing is on the map yet")
	check_eq(int(camp.sweep_counts().get("mech", 0)), 2, "a sweep would count its two mechs")
	_field.clock += camp.duration
	var shots: int = _arena.sounds.size()
	for k in 20:
		_field.advance(0.5)
	check_eq(_arena.sounds.size(), shots, "over, it falls quiet")


func _test_hunt_halfway() -> void:
	seed(3)
	var at := Vector2(_reach() + 20000.0, 0.0)
	_field.lay_out_sites([at])
	var camp := _field.arm_encounter(Camp.HUNT, _field.sites[0], 1.0, [_design()])
	var pack_size := camp.roster.size()
	check_eq(pack_size, 6, "at full intensity the pack is six")
	_field.clock += camp.duration * 0.5
	var dead_before: int = _arena.dead.size()
	_player.global_position = at - Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var npcs := _arena.mechas.filter(func(m): return m.mecha_name.begins_with("Camp_"))
	if not check_eq(npcs.size(), 1, "its NPC is on the map"):
		return
	var npc = npcs[0]
	check(NPCKnowledge._structural_health(npc) < 1.0, "hurt from the fight so far")
	var killed: int = _arena.dead.size() - dead_before
	check_eq(killed, floori(0.5 * CampField.HUNT_PACK_LOSS * pack_size), "part of the pack lies dead")
	check_eq(_living().size(), pack_size - killed, "the rest alive")
	check(_living().all(func(e): return e.target == npc), "and on the NPC")
	check(_living().all(func(e): return npc.knowledge.knows(e)), "which knows they're there")
	check(not npc.is_dead, "the NPC is alive")
	check_eq(camp.kind, Camp.PACK, "what's left of the pack is a pack camp")
	check(not _field.sites[0].used, "the site is free again")


func _test_duel_over() -> void:
	var at := Vector2(_reach() + 20000.0, 0.0)
	_field.lay_out_sites([at])
	var camp := _field.arm_encounter(Camp.DUEL, _field.sites[0], 0.5, [_design(), _design()])
	_field.clock += camp.duration + 1.0
	_player.global_position = at - Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var npcs := _arena.mechas.filter(func(m): return m.mecha_name.begins_with("Camp_"))
	check_eq(npcs.size(), 2, "both pilots are put on the map")
	check_eq(npcs.filter(func(m): return m.is_dead).size(), 1, "one of them dead")
	var winner = npcs.filter(func(m): return not m.is_dead)[0]
	check(NPCKnowledge._structural_health(winner) < 1.0, "the other hurt")
	check(not _field.camps.has(camp), "nothing is left of the camp")


func _test_abandoned() -> void:
	_field.lay_out_sites([Vector2(_reach() + 20000.0, 0.0)])
	var camp := _field.arm_encounter(Camp.HUNT, _field.sites[0], 0.0, [_design()])
	_field.clock += camp.duration
	for k in ceili(CampField.ABANDON_TIME / 2.0) + 1:
		_field.advance(2.0)
	check(camp.mechas.is_empty(), "its NPC is gone")
	check(not camp.is_encounter(), "no longer an encounter")
	check(not _field.sites[0].used, "its site is free")
	check(camp.state == Camp.State.CLEARED or camp.kind == Camp.PACK, "what's left of the pack stays as a pack camp")
	check(_arena.mechas.size() == 1, "nothing was put on the map")


func _test_tension() -> void:
	var t := TensionMeter.new()
	for k in 30:
		t.advance(1.0, false, 0.0)
	var early := t.value
	check(early > 0.0, "it rises once a lull has gone on")
	var t2 := TensionMeter.new()
	for k in 30:
		t2.advance(1.0, false, 1200.0)
	check(t2.value > early * 2.0, "faster an expedition in")
	t2.advance(5.0, true, 1200.0)
	check(t2.value < early * 3.0 and t2.since_fight == 0.0, "a fight brings it down")
	t.value = 0.8
	check(t.pressure(0.2) < t.pressure(1.0), "a battered mecha feels less of it")
	t.found_encounter()
	check(absf(t.value - (0.8 - TensionMeter.FOUND_DROP)) < 0.001, "finding an encounter drops it")


func _roamer_npcs() -> Array:
	return _arena.mechas.filter(func(m): return m.mecha_name.begins_with("Roamer_") and not m.is_dead)


func _named() -> Dictionary:
	var design := _design()
	design["anonymous"] = false
	return design


func _test_roamer_wakes() -> void:
	var at := Vector2(_reach() + 20000.0, 0.0)
	var camp := _field.add_roamer([_named()], at)
	var local: LocalPilots = _arena.local_pilots
	check_eq(local.get_roster().size(), 1, "its pilot is on the Local roster while it is off the map")
	check(_roamer_npcs().is_empty(), "and no mecha is on the map")
	var callsign: String = camp.mechas[0].pilot.callsign
	check(callsign != "", "with a callsign")
	var was := camp.site
	for k in 10:
		_field.advance(CampField.TICK)
	check(absf(camp.site.distance_to(was) - CampField.PAPER_SPEED * 10 * CampField.TICK) < 5.0, "it walks on paper at PAPER_SPEED")
	check(camp.site.x > was.x, "toward its destination")
	var lines := local.get_log().size()
	_player.global_position = camp.site - Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var npcs := _roamer_npcs()
	if not check_eq(npcs.size(), 1, "near, its mecha is on the map"):
		return
	check_eq(npcs[0].callsign, callsign, "flying the same callsign")
	check(local.is_in_local(npcs[0]) and local.get_roster().size() == 1, "in its pilot's place in Local")
	check_eq(local.get_log().size(), lines, "with no joined or left lines")


func _test_roamer_keeps_state() -> void:
	var camp := _field.add_roamer([_named()], Vector2(_reach() - 500.0, 0.0))
	_field.update()
	var npc: Mecha = _roamer_npcs()[0]
	npc.set_pause(true)
	for k in 6:
		CampField.paper_hit(npc, npc.global_position + Vector2(300, 0), 1, 3, "test")
	var health := NPCKnowledge._structural_health(npc)
	check(health < 1.0, "hurt (%.2f)" % health)
	var gun = npc.get_weapon_part("arm_weapon_right")
	var had_clip: bool = gun != null and not (gun.clip_ammo is bool)
	if had_clip:
		gun.clip_ammo = maxi(int(gun.clip_ammo) - 3, 0)
	var clip = gun.clip_ammo if gun != null else null
	var callsign := npc.callsign
	await _walk_away()
	check_eq(camp.state, Camp.State.DORMANT, "with nobody near it goes off the map")
	check(_roamer_npcs().is_empty(), "its mecha with it")
	check(_arena.local_pilots.get_roster().size() == 1, "its pilot still in Local")
	_player.global_position = camp.site - Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var back: Mecha = _roamer_npcs()[0]
	check_eq(back.callsign, callsign, "it comes back as the same pilot")
	check(absf(NPCKnowledge._structural_health(back) - health) < 0.01,
			"as hurt as it was (%.2f, %.2f)" % [NPCKnowledge._structural_health(back), health])
	if had_clip:
		check_eq(back.get_weapon_part("arm_weapon_right").clip_ammo, clip, "with the ammo it had")


func _test_roamer_squad() -> void:
	var designs := [_design(), _design()]
	for d in designs:
		d["squad_tag"] = "TST"
	var camp := _field.add_roamer(designs, Vector2(_reach() + 20000.0, 0.0), {"tag": "TST", "anonymous": false})
	check_eq(_arena.local_pilots.count_tag("TST"), 2, "both on the roster under their tag while dormant")
	_player.global_position = camp.site - Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var npcs := _roamer_npcs()
	check_eq(npcs.size(), 2, "both on the map")
	check(npcs.all(func(m): return m.squad_tag == "TST"), "tagged")
	check(_arena.squads.size() == 1 and _arena.squads[0].members.size() == 2, "as one squad")
	check(npcs.all(func(m): return m.knowledge.squad == _arena.squads[0]), "that each knows")


func _test_roamer_hears_and_leaves() -> void:
	var camp := _field.add_roamer([_named()], Vector2(_reach() + 20000.0, 0.0), {}, 30.0)
	var noise := camp.site + Vector2(0, 3000)
	seed(1)
	var drawn := false
	for k in 20:
		_field.hear({"volume_type": "loud", "type": "gunshot", "position": noise, "max_distance": 5000.0})
		if camp.destination == noise:
			drawn = true
			break
	check(drawn, "a loud sound in earshot sends it there")
	_field.hear({"volume_type": "loud", "type": "gunshot", "position": camp.site + Vector2(0, 9000), "max_distance": 5000.0})
	check_eq(camp.destination, noise, "one out of earshot doesn't")
	for k in 70:
		_field.advance(CampField.TICK)
	check(_arena.local_pilots.get_roster().is_empty(), "its time up, it has left Local")
	check(not _field.camps.has(camp), "and the map")


func _test_roamer_paper_fight() -> void:
	seed(5)
	var at := Vector2(_reach() + 20000.0, 0.0)
	var pack := _field.add_camp(Camp.PACK, at, 6, 1)
	var camp := _field.add_roamer([_named()], at + Vector2(500, 0))
	for k in 40:
		_field.paper_round_roamer(pack, camp)
	check(pack.roster.size() < 6, "it killed members (%d left)" % pack.roster.size())
	var pips := 0
	for hit in camp.mechas[0].hits:
		pips += int(hit[0])
	check(pips > 0 and pips <= CampField.PAPER_HITS_KEPT, "the pack's hits are noted (%d pips)" % pips)
	_player.global_position = camp.site - Vector2(_reach() - 500.0, 0.0)
	_field.update()
	var npc: Mecha = _roamer_npcs()[0]
	check(NPCKnowledge._structural_health(npc) < 1.0, "and it wakes with the wounds")
