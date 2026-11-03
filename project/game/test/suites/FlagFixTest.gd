extends TestSuite

# FlagFixTest: the emergency Flag, blood and wrecks. The core shell keeps the
# cockpit from being hit; both ways into the Flag (hp at 0, the core shell
# destroyed) start the same grace window, in which nothing hurts the mecha;
# after it the mecha can be killed; the emergency_flagged signal; the
# splatter and the pool (BloodStains) and their cap; bleeding from internal
# components, the small splatter a destroying hit throws and the droplet jet;
# the body a dead mecha leaves (MechaBody, Wreck), the parts that come off it
# and the loot, and the body being solid cover; the body being in the tree
# before the mecha is freed (CombatScene); and NPCs breaking off a Flagged
# target or holding fire through its grace window.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const WRECK := preload("res://game/mecha/Wreck.tscn")
const COMBAT_SCENE := preload("res://game/combat/CombatScene.gd")

const ROLLS := 3000


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
		return Vector2.ZERO
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-3000, 3000), randf_range(-3000, 3000))


var _arena: FakeArena = null


func run_tests() -> void:
	await case("a penetrating core hit never picks the cockpit while the core shell is intact", _test_cockpit_protected)
	await case("destroying the core shell enters the emergency Flag; the cockpit becomes eligible", _test_core_shell_flag)
	await case("hp reaching 0 enters the same emergency Flag", _test_hp_flag)
	await case("the grace window lasts three to five seconds", _test_grace_length)
	await case("in the grace window hits, blasts, overheat and status damage change nothing", _test_grace)
	await case("a blast that destroys the core shell doesn't also destroy the cockpit", _test_one_blast)
	await case("after the grace window the mecha can be killed", _test_killable_after)
	await case("the Flag locks the weapons", _test_weapons_locked)
	await case("the signal fires once, with the attacker", _test_signal_once)
	await case("the Flag spawns one splatter away from the attacker, death one pool, under a cap", _test_stains)
	await case("hits on internal components leak drops; a destroying hit throws a small splatter along it", _test_wounds)
	await case("a mecha bleeds from damaged internal components, not from low hp", _test_bleeding)
	await case("a wreck shows every fitted part except those shed, single chassis too", _test_wreck_parts)
	await case("a wreck is solid: it blocks movement, shots and sight lines; shed parts aren't", _test_wreck_solid)
	await case("a body left inside a physics callback is solid, with no errors", _test_solid_in_callback)
	await case("one or two parts are shed, never the core or chassis, not ones in the loot", _test_shed_choice)
	await case("the body is in the tree before the mecha is freed", _test_body_before_free)
	await case("an NPC drops a Flagged target; a Rat keeps it but holds fire through the grace window", _test_npcs)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-8000, -8000), Vector2(8000, -8000), Vector2(8000, 8000), Vector2(-8000, 8000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mecha(design: Dictionary = PlayerProgress.DEFAULT_MECHA, pos := Vector2.ZERO) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	_arena.mechas.append(mecha)
	return mecha


func _attacker(pos: Vector2) -> Mecha:
	return _mecha(PlayerProgress.DEFAULT_MECHA, pos)


func _source(attacker) -> Dictionary:
	return {"body": attacker, "name": attacker.mecha_name}


# Everything a hit could change: hp, shield, armour pips, component hp.
func _snapshot(mecha: Mecha) -> Dictionary:
	return {"hp": mecha.hp, "shield": mecha.shield, "armor": mecha.armor.duplicate(true),
			"components": mecha.components.duplicate(true), "dead": mecha.is_dead}


func _shell_and_cockpit_only(mecha: Mecha) -> void:
	for comp_name in mecha.components.core:
		if comp_name != "core_shell" and comp_name != "cockpit":
			mecha.components.core[comp_name].disabled = true


func _test_cockpit_protected() -> void:
	var mecha := _mecha()
	check("critical" in mecha.components.core.cockpit.tags, "the cockpit is tagged critical")
	var picked := {}
	for _i in ROLLS:
		for aoe in [false, true]:
			var eligible := mecha.get_eligible_components("core", "front", true, aoe)
			var comp := mecha.select_component_by_weight("core", eligible)
			picked[comp] = true
	check(not picked.has("cockpit"), "never picked by %d hits and %d blasts" % [ROLLS, ROLLS])
	check(picked.has("core_shell") and picked.has("radiator"), "other core components are")
	_shell_and_cockpit_only(mecha)
	check_eq(mecha.get_eligible_components("core", "front", true), ["core_shell"], "with only the shell and cockpit left, only the shell")
	check(not mecha.is_dead, "still alive")

	# Overheat ticks (with the radiator gone, so none redirect to it).
	mecha = _mecha()
	mecha.components.core.radiator.disabled = true
	mecha.disabled_systems.heat_dispersion = 0.5
	var reached := 0
	for _i in 300:
		mecha.overheat_damage_tick()
		if mecha.components.core.cockpit.hp < 1:
			reached += 1
		for part in mecha.components:
			for comp_name in mecha.components[part]:
				var comp: Dictionary = mecha.components[part][comp_name]
				if comp_name != "radiator":
					comp.hp = comp.max_hp
					comp.disabled = false
		mecha.is_exposed = false
		mecha.flag_grace = 0.0
		if is_instance_valid(mecha._flag_marker):
			mecha._flag_marker.free()
	check_eq(reached, 0, "overheat never reaches the cockpit through an intact shell")
	check(not mecha.is_dead, "no overheat tick killed it")


func _test_core_shell_flag() -> void:
	var mecha := _mecha()
	var attacker := _attacker(Vector2(-600, 0))
	mecha.last_damage_source = _source(attacker)
	check(mecha.is_protected("core", "cockpit"), "the cockpit is protected at the start")
	mecha.damage_component("core", "core_shell", 3)
	check(mecha.is_exposed, "Flagged")
	check(mecha.is_in_flag_grace(), "the grace window started")
	check(not mecha.is_protected("core", "cockpit"), "the cockpit is no longer protected")
	mecha.flag_grace = 0.0
	check("cockpit" in mecha.get_eligible_components("core", "front", true), "the cockpit is eligible once the window ends")
	check(is_instance_valid(mecha._flag_marker), "the Flag marker is on")


func _test_hp_flag() -> void:
	var mecha := _mecha()
	var attacker := _attacker(Vector2(600, 0))
	var flagged := []
	mecha.emergency_flagged.connect(func(m, a): flagged.append([m, a]))
	mecha.take_damage(99999, 1.0, 1.0, 0, 0, false, false, _source(attacker))
	check(mecha.hp <= 0 and mecha.is_exposed, "hp at 0 Flags the mecha")
	check(mecha.is_in_flag_grace(), "with the same grace window")
	check_eq(flagged.size(), 1, "the same signal")
	check(mecha.is_protected("core", "cockpit"), "the shell is intact, so the cockpit stays protected")
	# After the window the exposed_hits rule finishes it: one hp hit a second.
	mecha.flag_grace = 0.0
	for _i in int(mecha.exposed_hits):
		mecha.exposed_invuln_timer = mecha.EXPOSED_INVULN_WINDOW
		mecha.take_damage(10, 1.0, 1.0, 0, 0, false, false, _source(attacker))
	check(mecha.is_dead, "three hp hits a second apart kill it after the window")


func _test_grace_length() -> void:
	check(Mecha.FLAG_GRACE_TIME >= 3.0 and Mecha.FLAG_GRACE_TIME <= 5.0, "%.1f s" % Mecha.FLAG_GRACE_TIME)
	var mecha := _mecha()
	mecha.enter_flagged_state()
	check_eq(mecha.flag_grace, Mecha.FLAG_GRACE_TIME, "the window opens in full")


func _test_grace() -> void:
	var mecha := _mecha()
	var attacker := _attacker(Vector2(0, -800))
	mecha.last_damage_source = _source(attacker)
	mecha.enter_flagged_state()
	check(mecha.is_in_flag_grace(), "in the grace window")
	mecha.flag_grace = 100.0  # keep it open for the whole check
	var before := _snapshot(mecha)
	mecha.take_damage(99999, 1.0, 1.0, 500.0, 5.0, "fire", false, _source(attacker))
	for part in ["core", "head", "chassis", "left_shoulder", "right_shoulder"]:
		for _i in 20:
			var pen := mecha.armor_check(part, mecha.global_position + Vector2(0, -100), Vector2.DOWN, 10, 3)
			check(pen.component_name == "", "a hit on %s picks nothing" % part)
			var blast := mecha.armor_check(part, mecha.global_position + Vector2(0, -100), Vector2.DOWN, 10, 3, true)
			check(blast.component_name == "", "a blast on %s picks nothing" % part)
		for comp_name in mecha.components[part]:
			mecha.damage_component(part, comp_name, 5)
	for _i in 20:
		mecha.overheat_damage_tick()
	mecha.set_status("overheating", 1.0)
	mecha.set_status("electrified", 5.0)
	mecha.set_status("corrosion", 5.0)
	mecha.take_status_damage(5.0)
	check_eq(_snapshot(mecha), before, "hp, shield, armour pips and components unchanged")
	check(not mecha.is_dead, "alive")


# The order complex_projectile's blast uses: armour check, then damage, part
# by part, the core more than once.
func _test_one_blast() -> void:
	var mecha := _mecha()
	_shell_and_cockpit_only(mecha)
	mecha.components.core.core_shell.hp = 1
	for facing in mecha.armor.core:
		mecha.armor.core[facing].pips = 0
	for hit_name in ["core", "core", "head", "core", "left_shoulder", "core"]:
		var pen := mecha.armor_check(hit_name, mecha.global_position + Vector2(0, -60), Vector2.DOWN, 10, 3, true)
		if pen.penetrated and pen.component_name != "":
			mecha.damage_component(pen.part_name, pen.component_name, 3)
	check(mecha.components.core.core_shell.disabled, "the blast destroyed the core shell")
	check(mecha.is_exposed, "and Flagged the mecha")
	check_eq(mecha.components.core.cockpit.hp, 1, "the cockpit is untouched")
	check(not mecha.is_dead, "the mecha is alive")


func _test_killable_after() -> void:
	var mecha := _mecha()
	mecha.damage_component("core", "core_shell", 3)
	check(mecha.is_in_flag_grace(), "in the grace window")
	var ended := await wait_until(func(): return not mecha.is_in_flag_grace(), 8.0)
	check(ended, "the window ends by itself")
	_shell_and_cockpit_only(mecha)
	var pen := mecha.armor_check("core", mecha.global_position + Vector2(0, -60), Vector2.DOWN, 10, 3)
	check_eq(pen.component_name, "cockpit", "a penetrating core hit can now pick the cockpit")
	mecha.damage_component("core", "cockpit", 1)
	check(mecha.is_dead, "and destroying it kills the mecha")


func _test_weapons_locked() -> void:
	var mecha := _mecha()
	var shots := [0]
	mecha.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	mecha.enter_flagged_state()
	mecha.shoot("arm_weapon_left")
	mecha.shoot("arm_weapon_right")
	check_eq(shots[0], 0, "shoot does nothing while Flagged")
	check_eq(mecha.can_fire_at_point("arm_weapon_left", mecha.global_position + Vector2(0, -500)), "flagged",
			"designator fire gives the reason")


func _test_signal_once() -> void:
	var mecha := _mecha()
	var attacker := _attacker(Vector2(500, 500))
	var flagged := []
	mecha.emergency_flagged.connect(func(m, a): flagged.append([m, a]))
	mecha.last_damage_source = _source(attacker)
	mecha.damage_component("core", "core_shell", 3)
	mecha.flag_grace = 0.0
	mecha.take_damage(99999, 1.0, 1.0, 0, 0, false, false, _source(attacker))
	mecha.enter_flagged_state()
	check_eq(flagged.size(), 1, "fired once")
	check(flagged.size() == 1 and flagged[0][0] == mecha and flagged[0][1] == attacker, "with the mecha and its attacker")


func _test_stains() -> void:
	var stains := BloodStains.new()
	_arena.add_child(stains)
	check(BloodStains.find(_arena) == stains, "the scene's stains are found")
	var mecha := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(1000, 0))
	var attacker := _attacker(Vector2(400, 0))
	mecha.last_damage_source = _source(attacker)
	mecha.damage_component("core", "core_shell", 3)
	var found := stains.get_stains()
	check_eq(found.size(), 1, "one splatter on entering the Flag")
	if found.size() == 1:
		check_eq(found[0].kind, "splatter", "a splatter")
		var away: Vector2 = found[0].direction
		check(away.dot(Vector2.RIGHT) > 0.99, "thrown away from the attacker (%s)" % away)
		check_eq(found[0].color, BloodStains.HEAT_STEPS[0], "white-hot (G6)")
	mecha.flag_grace = 0.0
	mecha.damage_component("core", "cockpit", 1)
	check(mecha.is_dead, "dead")
	found = stains.get_stains()
	check(found.size() == 2 and found.filter(func(s): return s.kind == "pool").size() == 1, "death adds one pool")
	check_eq(BloodStains.heat_color(BloodStains.COOL_TIME), BloodStains.HEAT_STEPS[-1], "cold stains are G3")
	var over := false
	for i in BloodStains.MAX_STAINS * 3:
		if i % 2 == 0:
			stains.add_splatter(Vector2(i * 10, 0), Vector2.UP)
		else:
			stains.add_pool(Vector2(i * 10, 0))
		over = over or stains.stain_count() > BloodStains.MAX_STAINS
	check(not over, "never more than %d on the map" % BloodStains.MAX_STAINS)
	check_eq(stains.stain_count(), BloodStains.MAX_STAINS, "full at the cap")


func _active_sprays(stains: BloodStains) -> Array:
	return stains._sprays.filter(func(e): return e.emitting)


func _sprays_along(stains: BloodStains, dir: Vector2, ratio: float) -> int:
	return _active_sprays(stains).filter(func(e):
		return is_equal_approx(e.amount_ratio, ratio) and absf(angle_difference(e.global_rotation, dir.angle())) < 0.01).size()


func _test_wounds() -> void:
	var stains := BloodStains.new()
	_arena.add_child(stains)
	var mecha := _mecha()
	check(not "internal" in mecha.components.core.radiator.tags, "the radiator is external")
	# A hit that only damages an internal component: a few drops, no stain.
	mecha.damage_component("chassis", "chassis_shell", 1, Vector2.RIGHT)
	check_eq(_active_sprays(stains).size(), 1, "one jet")
	check_eq(_sprays_along(stains, Vector2.RIGHT, Mecha.WOUND_LEAK), 1, "of a few drops, along the hit")
	check_eq(stains.stain_count(), 0, "no stain")
	# Destroying one: a full jet and a small splatter along the hit, from the part.
	mecha.damage_component("left_shoulder", "arm_actuator", 2, Vector2.DOWN)
	var found := stains.get_stains()
	check_eq(found.size(), 1, "one stain")
	if found.size() == 1:
		check_eq(found[0].kind, "small", "a small splatter")
		var along: Vector2 = found[0].direction
		check(along.dot(Vector2.DOWN) > 0.99, "thrown along the hit (%s)" % along)
		check(found[0].position.distance_to(mecha.get_part_global_position("left_shoulder")) < 1.0, "from the part")
		check_eq(found[0].color, BloodStains.HEAT_STEPS[0], "white-hot (G6)")
	check_eq(_sprays_along(stains, Vector2.DOWN, 1.0), 1, "and a full jet along it")
	# External components, and damage with no direction, leave no stain.
	mecha.damage_component("core", "radiator", 5, Vector2.LEFT)
	mecha.damage_component("chassis", "suspension", 5)
	check_eq(stains.stain_count(), 1, "nothing for an external component or damage with no direction")
	# The Flag throws a full jet away from the attacker.
	var attacker := _attacker(Vector2(-700, 0))
	mecha.last_damage_source = _source(attacker)
	mecha.damage_component("core", "core_shell", 3)
	check(_sprays_along(stains, Vector2.RIGHT, 1.0) >= 1, "the Flag throws a full jet away from the attacker")


func _test_bleeding() -> void:
	var low := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(-1500, 0))
	low.hp = int(low.max_hp * 0.1)
	var hurt := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(1500, 0))
	check_eq(hurt.get_internal_wound(), 0.0, "a fresh mecha has no internal wound")
	for _round in 3:
		if hurt.get_internal_wound() >= Mecha.WOUND_BLEED:
			break
		for part in ["chassis", "left_shoulder", "right_shoulder"]:
			for comp_name in hurt.components[part]:
				var comp: Dictionary = hurt.components[part][comp_name]
				if "internal" in comp.tags and comp.hp > 1:
					hurt.damage_component(part, comp_name, 1)
	check(hurt.get_internal_wound() >= Mecha.WOUND_BLEED, "internal hits make a wound (%.2f)" % hurt.get_internal_wound())
	check_eq(hurt.hp, hurt.max_hp, "at full hp")
	for _i in 3:
		await get_tree().physics_frame
	check(hurt.Particle.blood[0].emitting, "the wounded mecha drips")
	check(not low.Particle.blood[0].emitting and not low.Particle.blood[1].emitting, "a mecha at low hp with sound internals doesn't")


func _full_design() -> Dictionary:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	var shoulder_ids: Array = PartManager.SHOULDER_WEAPONS.keys()
	shoulder_ids.sort()
	design.shoulder_weapon_left = shoulder_ids[0]
	design.shoulder_weapon_right = shoulder_ids[0]
	return design


func _single_chassis_id() -> String:
	var ids: Array = PartManager.CHASSIS.keys()
	ids.sort()
	for id in ids:
		if not PartManager.CHASSIS[id].is_legs:
			return id
	return ""


func _fitted(mecha: Mecha) -> Array:
	var fitted := ["chassis", "core", "head", "left_shoulder", "right_shoulder"]
	for slot in WreckLoot.WEAPON_SLOTS:
		if mecha.build.get(slot):
			fitted.append(slot)
	return fitted


func _test_wreck_parts() -> void:
	var single := _single_chassis_id()
	check(single != "", "a chassis drawn as a single sprite exists")
	for chassis in ["MSV-L3J-L", single]:
		var design := _full_design()
		design.chassis = chassis
		var mecha := _mecha(design, Vector2(300, 200))
		mecha.global_rotation = 0.7
		check(mecha.build.chassis.is_legs == (chassis == "MSV-L3J-L"), "%s: chassis type as expected" % chassis)
		var wreck: Wreck = WRECK.instantiate()
		wreck.position = mecha.global_position
		wreck.setup(mecha.mecha_name, [])
		wreck.copy_mecha_visuals(mecha)
		_arena.add_child(wreck)
		var body := wreck.body
		check(is_equal_approx(body.global_rotation, mecha.global_rotation), "%s: in the mecha's pose" % chassis)
		var fitted := _fitted(mecha)
		check_eq(body.get_part_slots().size(), fitted.size(), "%s: every fitted part is on the body before shedding" % chassis)
		check(body.find_child("Sub", true, false) != null, "%s: Sub layers are copied" % chassis)
		check(body.find_child("Glow", true, false) == null, "%s: glow layers go dark" % chassis)
		check(body.get_heat() >= MechaBody.START_HEAT, "%s: the body starts hot" % chassis)
		var core_copy := body.find_child("Core", false, false) as Sprite2D
		check(core_copy != null and core_copy.texture == mecha.Core.texture and core_copy.material != null,
				"%s: the core is there, with its heat material" % chassis)
		var shed := MechaBody.choose_shed(mecha)
		for slot in shed:
			body.shed(slot, false)
		var missing := []
		for slot in fitted:
			if not slot in body.get_part_slots():
				missing.append(slot)
		missing.sort()
		var expected := []
		expected.append_array(body.shed_slots)
		expected.sort()
		check_eq(missing, expected, "%s: only the shed parts are off the body (%s)" % [chassis, shed])
		check(body.find_child("Debris", false, false) != null, "%s: shed parts lie by the body" % chassis)


func _test_wreck_solid() -> void:
	var mecha := _mecha(_full_design())
	var wreck: Wreck = WRECK.instantiate()
	wreck.position = mecha.global_position
	wreck.setup(mecha.mecha_name, [])
	wreck.copy_mecha_visuals(mecha)
	var body := wreck.body
	for part in ["core", "chassis", "head", "left_shoulder", "right_shoulder"]:
		check(part in body.get_solid_parts(), "the %s is solid" % part)
	_arena.mechas.erase(mecha)
	mecha.queue_free()
	_arena.add_child(wreck)
	body.shed("left_shoulder", false)
	check(not "left_shoulder" in body.get_solid_parts(), "a shed shoulder isn't")
	check("core" in body.get_solid_parts(), "the rest still is")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _arena.get_world_2d()
	var space := world.direct_space_state
	var shot := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(-800, 0), Vector2(800, 0), MapSenses.SHOT_MASK))
	check(not shot.is_empty() and shot.collider == body.solid, "a shot's hit ray stops at it")
	check(MapSenses.solid_hit(world, Vector2(-800, 0), Vector2(800, 0)) != null, "so do lasers and designator lines")
	var sight := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(0, -800), Vector2(0, 800), MapSenses.SIGHT_MASK))
	check(not sight.is_empty() and sight.collider == body.solid, "and a blast's (or an NPC's) line to a mecha behind it")
	var mover := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(-900, 0))
	await get_tree().physics_frame
	var hit := mover.move_and_collide(Vector2(1800, 0))
	check(hit != null and hit.get_collider() == body.solid, "a mecha driving into it is stopped")
	check(mover.global_position.x < -100, "short of the hull (x %.0f)" % mover.global_position.x)


# A death can come inside a physics callback (a contact-fused round's
# body_shape_entered): leaving a solid body there must work. (Expedition adds
# its wrecks after the callback, as it does carcasses.)
func _test_solid_in_callback() -> void:
	var mecha := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(0, 4000))
	var area := Area2D.new()
	var circle := CollisionShape2D.new()
	circle.shape = CircleShape2D.new()
	circle.shape.radius = 50.0
	area.add_child(circle)
	area.position = Vector2(4000, 0)
	_arena.add_child(area)
	var left := []
	area.body_entered.connect(func(_entered):
		if not left.is_empty():
			return
		var body := MechaBody.new()
		body.position = Vector2(-4000, 0)
		body.copy_from(mecha)
		_arena.add_child(body)
		body.shed("head", false)
		left.append(body))
	await get_tree().physics_frame
	var trigger := CharacterBody2D.new()
	var box := CollisionShape2D.new()
	box.shape = RectangleShape2D.new()
	trigger.add_child(box)
	trigger.position = Vector2(4000, 0)
	_arena.add_child(trigger)
	var ran := await wait_until(func(): return not left.is_empty(), 3.0)
	check(ran, "the callback ran")
	await get_tree().physics_frame
	await get_tree().physics_frame
	if ran:
		var space := _arena.get_world_2d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(-4800, 0), Vector2(-3200, 0), MapSenses.SHOT_MASK))
		check(not hit.is_empty() and hit.collider == left[0].solid, "the body is solid")
		check(not "head" in left[0].get_solid_parts(), "less the part that came off")


func _test_shed_choice() -> void:
	var mecha := _mecha(_full_design())
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var counts := {}
	var bad := []
	var loot := [WreckLoot.weapon_stack("arm_weapon_left", mecha.build.arm_weapon_left.part_id, rng)]
	check(MechaBody.slots_in_loot(mecha, loot).has("arm_weapon_left"), "the dropped weapon is found in the loot")
	var in_loot := 0
	for _i in 500:
		var shed := MechaBody.choose_shed(mecha, loot, rng)
		counts[shed.size()] = true
		for slot in shed:
			if slot in ["core", "chassis"]:
				bad.append(slot)
			if slot in ["arm_weapon_left", "left_shoulder"]:
				in_loot += 1
	check(counts.has(1) and counts.has(2) and counts.size() == 2, "one or two parts")
	check(bad.is_empty(), "never the core or chassis")
	check_eq(in_loot, 0, "never the weapon in the loot (nor the shoulder carrying it)")
	for facing in mecha.armor.head:
		mecha.armor.head[facing].pips = 0
	var head_first := true
	for _i in 100:
		head_first = head_first and MechaBody.choose_shed(mecha, [], rng)[0] == "head"
	check(head_first, "the most damaged part comes off first")


func _test_body_before_free() -> void:
	var local_before := LocalPilots.current
	var scene = COMBAT_SCENE.new()
	for child_name in ["Mechas", "Projectiles", "Trails", "Flashes", "Smoke", "Explosions", "ScrapParts",
			"HeatmapEffects", "PlayerHUD", "PauseMenu", "GameOver", "ArenaCamera", "DebugNavigation"]:
		var child := Node2D.new()
		child.name = child_name
		scene.add_child(child)
	var intro := Node2D.new()
	intro.name = "Intro"
	scene.add_child(intro)
	var intro_animation := Node2D.new()
	intro_animation.name = "IntroAnimation"
	intro.add_child(intro_animation)
	_arena.add_child(scene)
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = Vector2(200, 0)
	scene.Mechas.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	scene.all_mechas.append(mecha)
	scene._connect_mecha_signals(mecha)
	var seen := {}
	mecha.died.connect(func(m):
		seen["body"] = scene.Bodies != null and scene.Bodies.get_child_count() == 1 and scene.Bodies.get_child(0).is_inside_tree()
		seen["mecha"] = is_instance_valid(m) and m.is_inside_tree())
	mecha.die({"name": "Test"}, "test")
	var done := await wait_until(func(): return seen.has("body"), 6.0)
	check(done, "the mecha reported its death")
	check(seen.get("body", false), "its body is in the tree")
	check(seen.get("mecha", false), "while the mecha still is")
	await wait_frames(2)
	check(not is_instance_valid(mecha), "then the mecha is freed")
	scene.queue_free()
	await wait_frames(1)
	LocalPilots.current = local_before


func _enemy(type: Personality.Type) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	_arena.add_child(enemy)
	var personality := Personality.new()
	personality.type = type
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["personality"] = personality
	enemy.setup(_arena, design, "Flag test")
	enemy.set_scripted(false)
	enemy.paused = true
	_arena.mechas.append(enemy)
	return enemy


func _test_npcs() -> void:
	# A default (Professional) NPC with no grudge against its target.
	var enemy = _enemy(Personality.Type.PROFESSIONAL)
	var victim := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(0, -700))
	enemy._remember(victim, victim.global_position)
	enemy.valid_target = victim
	enemy.current_target = victim
	var shots := [0]
	enemy.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	victim.last_damage_source = _source(enemy)
	victim.damage_component("core", "core_shell", 3)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = false
	await wait_frames(enemy.FAR_THINK_INTERVAL + 1)
	enemy.paused = true
	check(not enemy.valid_target and not enemy.current_target, "it drops the target within one think")
	check(not enemy.perceived(victim).is_empty(), "but stays wary of it")
	enemy.shoot_weapons(enemy.current_target)
	check_eq(shots[0], 0, "and doesn't fire at it")
	# Mid-fight it takes on someone else: attack and defend switch to them
	# from the dropped target (current_target false) without a script error.
	var other := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(700, 0))
	enemy._remember(other, other.global_position)
	for state in ["do_attack", "do_defend"]:
		enemy.valid_target = other
		enemy.current_target = false
		enemy.logic.behaviour.call(state, 0.016, enemy)
		check(is_same(enemy.current_target, other), "%s takes the new target" % state)

	# A Rat keeps it, but holds fire through the grace window.
	var rat = _enemy(Personality.Type.RAT)
	var prey := _mecha(PlayerProgress.DEFAULT_MECHA, Vector2(0, -700))
	rat.valid_target = prey
	rat.current_target = prey
	var rat_shots := [0]
	rat.create_projectile.connect(func(_m, _a, _w): rat_shots[0] += 1)
	prey.enter_flagged_state()
	rat.recheck_flagged_target()
	check(rat.valid_target == prey and rat.current_target == prey, "a Rat keeps its Flagged target")
	check(rat.holds_fire_at(prey), "holding fire in the grace window")
	rat.shoot_weapons(prey)
	check(not rat.blind_fire(prey), "no blind fire either")
	check_eq(rat_shots[0], 0, "no shots in the window")
	prey.flag_grace = 0.0
	check(not rat.holds_fire_at(prey), "free to fire once it ends")
