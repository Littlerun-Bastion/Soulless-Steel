extends TestSuite

# SquadTest: NPC squads (Phase 4 of the AI brief, Squad). A squad's designs
# have a direct-fire build first and a support build third, and
# personalities are drawn by the weights; its members show its tag before
# their callsigns in Local, none when it is Anonymous. The members take
# slots beside and behind the leader, spaced and never in a line, and a
# member follows its leader into its slot. In a fight the roles are dealt
# (anchor, flanker, support) and the flanker reaches its angle off the
# anchor's bearing. A contact called out lands in squadmates' stores after
# the share delay, and a squadmate may take it as its target. The leader's
# death passes the lead on, raises panic, and is judged by loyalty: a
# Guardian hunts the killer, a Scavenger breaks, a Professional fights on,
# a treacherous Rat leaves and turns on a hurt mate. Shooting a member turns
# the whole squad on the shooter; a squadmate's stray round is forgiven. A
# fallen member's wreck names its killer, and the squad bears the grudge.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const SMOKE_LAUNCHER := "MA-SL6"


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	var local_pilots := LocalPilots.new()
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2(-5000, -5000)
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-3000, 3000), randf_range(-3000, 3000))


# A round's area as the NPC's proximity sensor sees it.
class FakeRound extends RefCounted:
	var original_mecha_info = null


# A wreck for the kill-record case (group "loot_container").
class FakeWreck extends Node2D:
	var is_open := false
	var npc_searched := false
	var kill_record := {}
	func interact(_by) -> void:
		npc_searched = true


var _arena: FakeArena = null


func run_tests() -> void:
	await case("a squad's designs and personalities; the tag in Local, none when Anonymous", _test_composition)
	await case("members take spaced slots beside and behind the leader, and follow it there", _test_formation)
	await case("roles are dealt; the flanker reaches its angle off the anchor's bearing", _test_roles)
	await case("a callout lands in squadmates' stores after the delay; a mate takes the target", _test_callout)
	await case("the leader's death: the lead passes on, panic, and loyalty decides", _test_leader_death)
	await case("a treacherous Rat leaves the squad and turns on a hurt mate", _test_rat)
	await case("shooting a member turns the squad on the shooter; a mate's stray round is forgiven", _test_hostility)
	await case("a fallen member's wreck names its killer: the squad bears the grudge", _test_grudge)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	Barks.reset_cooldown()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	LocalPilots.current = _arena.local_pilots
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


# A design with `weapon` on the left shoulder (a core that has one).
func _design(weapon := "") -> Dictionary:
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	if weapon != "":
		for core_id in PartManager.get_parts("core"):
			if PartManager.get_part("core", core_id).has_left_shoulder:
				design["core"] = core_id
				break
		design["shoulder_weapon_left"] = weapon
	return design


# An NPC that thinks for itself, held still (paused) unless `run`, facing +x.
func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, run := false, design: Dictionary = PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var d: Dictionary = design.duplicate()
	d["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, d, "Squad test %s %d" % [Personality.Type.keys()[type], _arena.mechas.size()])
	enemy.is_anonymous = false
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = not run
	_arena.mechas.append(enemy)
	_arena.local_pilots.join(enemy)
	return enemy


# A plain mecha standing at `pos`, hot (seen at full range), that every
# member of `squad` is set on attacking.
func _foe(pos: Vector2, squad: Squad = null, callsign := "") -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(false)
	mecha.external_temp = 250.0
	mecha.set_pause(true)
	mecha.arena = _arena
	if callsign != "":
		mecha.callsign = callsign
	_arena.mechas.append(mecha)
	_arena.local_pilots.join(mecha)
	if squad != null:
		for m in squad.members:
			m.mark_traitor(mecha)
	return mecha


func _squad(members: Array, tag := "HLX", anonymous := false) -> Squad:
	var squad := Squad.new()
	squad.setup(tag, anonymous)
	for m in members:
		m.squad_tag = "" if anonymous else tag
		m.is_anonymous = anonymous
		squad.add(m)
	return squad


func _test_composition() -> void:
	var designs: Array = NPCManager.pick_squad_designs(3)
	check_eq(designs.size(), 3, "three designs for a squad of three")
	check(NPCManager.is_direct_fire(designs[0]), "the first is a direct-fire build")
	check(NPCManager.is_support(designs[2]), "the third is a support build")
	for d in designs:
		check(d.get("personality") is Personality, "each has a personality")
	var seen := {}
	for i in 300:
		seen[NPCManager.pick_personality_name()] = true
	check_eq(seen.size(), NPCManager.PERSONALITY_WEIGHTS.size(), "the personality draw covers every type (%s)" % str(seen.keys()))
	var types := {}
	for npc in NPCManager.NPCS:
		types[npc.personality] = true
	check(types.has("guardian") and types.has("hunter") and types.has("rat"), "generic designs exist for the Guardian, the Hunter and the Rat")
	# The tag in Local.
	var a := _enemy(Vector2.ZERO)
	var b := _enemy(Vector2(600, 0))
	var squad := _squad([a, b])
	check(LocalPilots.name_of(a).begins_with("[HLX] "), "a member's name carries the tag (%s)" % LocalPilots.name_of(a))
	check(_arena.local_pilots.pilot_named(LocalPilots.name_of(b)) == b, "and it is found on the roster by that name")
	check(squad.is_leader(a) and squad.mates_of(a) == [b], "the first member leads; the other is its mate")
	check(a.knowledge.squad == squad and b.knowledge.leads() == false, "each member knows its squad")
	var c := _enemy(Vector2(0, 600))
	var d := _enemy(Vector2(600, 600))
	_squad([c, d], "KRV", true)
	check_eq(LocalPilots.name_of(c), LocalPilots.UNKNOWN, "an Anonymous squad's members show no name and no tag")


func _test_formation() -> void:
	var leader := _enemy(Vector2.ZERO)
	var b := _enemy(Vector2(0, 2500), Personality.Type.PROFESSIONAL, true)
	var c := _enemy(Vector2(0, -2500))
	var d := _enemy(Vector2(2500, 0))
	var squad := _squad([leader, b, c, d])
	var goals: Array[Vector2] = [squad.travel_goal(b), squad.travel_goal(c), squad.travel_goal(d)]
	check_eq(squad.travel_goal(leader), Vector2.INF, "the leader has no slot")
	var forward: Vector2 = leader.get_facing()
	for g in goals:
		var d_px: float = g.distance_to(leader.global_position)
		check(d_px >= 500.0 and d_px <= 800.0, "a slot is 25 to 40 m from the leader (%.0f px)" % d_px)
		check(forward.dot(leader.global_position.direction_to(g)) < 0.0, "and behind it")
	for i in goals.size():
		for j in range(i + 1, goals.size()):
			check(goals[i].distance_to(goals[j]) >= 500.0, "slots are spaced apart (%.0f px)" % goals[i].distance_to(goals[j]))
	var line: Vector2 = goals[0] - goals[1]
	var other: Vector2 = goals[2] - goals[1]
	check(absf(line.normalized().cross(other.normalized())) > 0.2, "and not in a line")
	# A member follows its leader into its slot.
	var scored := await wait_until(func(): return str(b.logic.get_current_state()) == "follow", 4.0)
	check(scored, "a member with nothing else to do follows (%s)" % str(b.logic.get_current_state()))
	var goal: Vector2 = squad.travel_goal(b)
	var arrived := await wait_until(func(): return b.global_position.distance_to(squad.travel_goal(b)) < 400.0, 30.0)
	check(arrived, "and gets to its slot (%.0f px off)" % b.global_position.distance_to(goal))
	check(b.illuminator_on, "lit on the way, as roaming")
	# A straggler is called back.
	b.paused = true
	b.global_position = Vector2(0, 4000)
	leader.paused = false
	check(squad.strayed(b), "a member that far off has strayed")
	leader.logic.behaviour._lead_squad(leader)
	check(squad._regroup_said_ms > 0, "the leader calls a regroup when a member strays")
	leader.paused = true


func _test_roles() -> void:
	var a := _enemy(Vector2.ZERO, Personality.Type.PROFESSIONAL, true)
	var b := _enemy(Vector2(0, 400), Personality.Type.HUNTER, true)
	var c := _enemy(Vector2(100, -300), Personality.Type.SCAVENGER, false, _design(SMOKE_LAUNCHER))
	var squad := _squad([a, b, c])
	check_eq(squad.role_of(a), Squad.ROLE_ANCHOR, "the leader with guns anchors")
	check_eq(squad.role_of(b), Squad.ROLE_FLANKER, "the next gun build flanks")
	check_eq(squad.role_of(c), Squad.ROLE_SUPPORT, "the third, with smoke, supports")
	check(squad.anchor() == a, "the anchor is found")
	# The flanker gets to its angle while the anchor holds its band.
	var foe := _foe(Vector2(1500, 0), squad)
	foe.flag_grace = 1.0e9
	for m in [a, b]:
		m.knowledge.see(foe, foe.global_position)
	var engaged := await wait_until(func(): return str(b.logic.get_current_state()) == "engage" and str(a.logic.get_current_state()) == "engage", 5.0)
	check(engaged, "both fight")
	check(not b.illuminator_on or str(b.logic.get_current_state()) != "engage", "the flanker runs dark")
	var reached := await wait_until(func():
		return b.logic.behaviour.flank_angle(b.global_position, foe.global_position, a.global_position) >= Squad.FLANK_ANGLE, 30.0)
	var angle: float = b.logic.behaviour.flank_angle(b.global_position, foe.global_position, a.global_position)
	check(reached, "the flanker reaches at least 60 degrees off the anchor's bearing (%.0f; anchor %s %s, flanker %s %s %s, pick %s)" % [
			rad_to_deg(angle), str(a.global_position), str(a.logic.get_current_state()), str(b.global_position),
			str(b.logic.get_current_state()), b.logic.behaviour.stance, str(b.positioning.pick_position())])
	await wait_seconds(1.0)
	check(a.illuminator_on, "the anchor is lit, the squad's spotter")
	# The spotter's cone: a foe in it is lit, and a dark squadmate sees a lit
	# body wherever its light shows (IlluminationTest covers the walls).
	a.global_rotation = Vector2.UP.angle_to(a.global_position.direction_to(foe.global_position))
	await wait_frames(1)
	check(Illumination.is_lit(foe) and Illumination.seen_lit(b, foe), "the foe in the spotter's cone is lit, and the dark flanker sees it by that light")
	var eff: Dictionary = a.logic.behaviour._get_effective_distances(a)
	var dist: float = a.global_position.distance_to(foe.global_position)
	check(dist > eff.cqb * 0.5, "the anchor holds its range (%.0f px)" % dist)
	# The support member screens a mate that breaks off.
	c.paused = false
	c.knowledge.see(foe, foe.global_position)
	var shots := [0]
	c.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	await wait_until(func(): return str(c.logic.get_current_state()) == "engage" and c.logic.behaviour.stance != "closing", 8.0)
	b.logic.force_intent(b, "disengage")
	var covered := await wait_until(func(): return shots[0] > 0, 8.0)
	var point: Vector2 = c.fire.reach_toward(b.global_position)
	check(covered, "the support member turns and fires smoke to cover a mate that is falling back (%s, %s, %.0f px off, '%s')" % [
			str(c.logic.get_current_state()), str(b.logic.get_current_state()), c.global_position.distance_to(b.global_position),
			c.can_fire_at_point("shoulder_weapon_left", point)])


func _test_callout() -> void:
	var a := _enemy(Vector2.ZERO)
	var b := _enemy(Vector2(0, 600))
	var squad := _squad([a, b])
	var foe := _foe(Vector2(1500, 0), squad)
	check(not b.knowledge.knows(foe), "the mate knows nothing of the foe")
	a.knowledge.see(foe, foe.global_position)
	a.logic.behaviour._check_targets(a)
	check(a.valid_target == foe, "the first member takes the foe as its target")
	squad.deliver()
	check(not b.knowledge.knows(foe), "the callout hasn't landed yet")
	var landed := await wait_until(func():
		squad.deliver()
		return b.knowledge.knows(foe), 5.0)
	check(landed, "it lands after the share delay")
	var contact: Dictionary = b.knowledge.best(foe)
	check_eq(contact.get("source"), "squad", "as a squad contact")
	check(b.knowledge.squad_bodies().has(foe), "the mate lists it among the squad's bodies")
	b.logic.behaviour._check_targets(b)
	check(b.valid_target == foe, "and may take it as its target")
	check(not a.knowledge.knows(b) or not a.should_attack(b), "a squadmate is never a target")


func _test_leader_death() -> void:
	var leader := _enemy(Vector2.ZERO)
	var guardian := _enemy(Vector2(0, 600), Personality.Type.GUARDIAN)
	var scavenger := _enemy(Vector2(600, 0), Personality.Type.SCAVENGER)
	var pro := _enemy(Vector2(600, 600), Personality.Type.PROFESSIONAL)
	var squad := _squad([leader, guardian, scavenger, pro])
	var killer := _foe(Vector2(3000, 0), null, "Drifter")
	for m in squad.members:
		m.knowledge.panic = 0.0
	leader.is_dead = true
	squad.on_member_died(leader, killer, true)
	check(squad.leader == guardian, "the next member leads")
	check(not squad.is_member(leader) and squad.is_fallen(LocalPilots.name_of(leader)), "the dead leader is among the fallen")
	for m in [guardian, scavenger, pro]:
		check(m.knowledge.panic > 0.0, "%s's panic rose" % m.mecha_name)
	check_eq(guardian.get_relationship(killer).hostility, 1.0, "the Guardian (loyal) hunts the killer")
	check(guardian.knowledge.knows(killer), "and knows where it was")
	check_eq(str(scavenger.logic.get_current_state()), "flee", "the Scavenger (disloyal, timid) breaks and flees")
	check_eq(str(pro.logic.get_current_state()), "roam", "the Professional fights on as it was")
	check_eq(pro.get_relationship(killer).hostility, 0.0, "without a grudge")


func _test_rat() -> void:
	var leader := _enemy(Vector2.ZERO)
	var rat := _enemy(Vector2(0, 600), Personality.Type.RAT)
	var hurt := _enemy(Vector2(600, 0), Personality.Type.SCAVENGER)
	var squad := _squad([leader, rat, hurt])
	hurt.raise_flag(true)
	leader.is_dead = true
	squad.on_member_died(leader, null, true)
	check(not squad.is_member(rat) and rat.knowledge.squad == null, "the Rat leaves the squad")
	check_eq(rat.get_relationship(hurt).hostility, 1.0, "and turns on the Flagged mate")
	check(squad.is_member(hurt) and squad.leader == hurt, "the mate is left leading itself")


func _test_hostility() -> void:
	var a := _enemy(Vector2.ZERO)
	var b := _enemy(Vector2(0, 600))
	var squad := _squad([a, b])
	var shooter := _foe(Vector2(2000, 0), null, "Drifter")
	var shot := FakeRound.new()
	shot.original_mecha_info = {"name": shooter.mecha_name, "body": shooter}
	a._on_nearby_projectile_area_entered(shot)
	check_eq(b.get_relationship(shooter).hostility, Squad.MEMBER_SHOT_HOSTILITY, "the mate turns on whoever shot a member")
	check_eq(a.get_relationship(shooter).hostility, Squad.MEMBER_SHOT_HOSTILITY + 0.25, "the one shot, more")
	var stray := FakeRound.new()
	stray.original_mecha_info = {"name": b.mecha_name, "body": b}
	a._on_nearby_projectile_area_entered(stray)
	check_eq(a.get_relationship(b).hostility, 0.0, "a squadmate's stray round is forgiven")
	check(not a.should_attack(b), "and a squadmate is never attacked")
	check(squad.is_member(b), "the squad holds")


func _test_grudge() -> void:
	var a := _enemy(Vector2.ZERO)
	var b := _enemy(Vector2(0, 600))
	var fallen := _enemy(Vector2(600, 0))
	var squad := _squad([a, b, fallen])
	var killer := _foe(Vector2(3000, 0), null, "Drifter")
	fallen.is_dead = true
	squad.on_member_died(fallen, null, true)
	var wreck := FakeWreck.new()
	wreck.position = Vector2(200, 0)
	wreck.kill_record = {"victim": LocalPilots.name_of(fallen), "killer": "Drifter", "weapon": "", "position": wreck.position, "killer_position": null, "contacts": []}
	wreck.add_to_group("loot_container")
	_arena.add_child(wreck)
	a.logic.behaviour._read_kill_record(a, wreck)
	check_eq(a.get_relationship(killer).hostility, 1.0, "the member that read the record hates the killer")
	check_eq(b.get_relationship(killer).hostility, 1.0, "so does its squadmate")
	check(a.knowledge.killers.has("Drifter"), "the killer's callsign is remembered")
	# Someone else's wreck is no business of the squad's.
	var c := _enemy(Vector2(0, -600))
	var other := FakeWreck.new()
	other.kill_record = {"victim": "Nobody", "killer": "Drifter"}
	c.logic.behaviour._read_kill_record(c, other)
	check_eq(c.get_relationship(killer).hostility, 0.0, "a stranger's wreck gives no grudge")
	other.free()
