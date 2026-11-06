extends TestSuite

# ShieldTest: the shield (Mecha, SHIELDS). The SC damage rule against the
# shield's strength with the brief's worked examples and both edges; SS as
# the average of the core, the shoulders and the generator, to two places,
# with a part missing and no shield without a generator; the three
# projectors (full, two thirds, a third, then offline, a lost shoulder
# taking its own, a raised shield dropping and shield_up doing nothing); the
# 2 s toggle lock both ways and forced drops ignoring it; regen (none while
# up, the generator's rate while down, the break cooldown after SC hits 0,
# none while electrified, which drains it, or with the generator component
# destroyed); a blast from outside the bubble counting once per part it
# reaches and one from inside reaching the armour; the generators' and
# parts' values by tech tier; a real round deflected off the bubble or
# stopped by it, the hull untouched either way; the HUD's SHIELD row and the
# projectors in the frame readout.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const SHOT := preload("res://database/parts/projectiles/DefaultSimpleProjectile.tscn")
const SHELL := preload("res://database/parts/projectiles/GL44_projectile.tscn")

const TIER_SC := {0: 15.0, 1: 15.0, 2: 20.0, 3: 25.0}
const TIER_SS := {0: 2.0, 1: 2.0, 2: 3.0, 3: 4.0}
const TIER_REGEN := {0: 1.0, 1: 1.0, 2: 1.5, 3: 2.0}
const SHOOTER_POS := Vector2(-4000, 0)

var _arena: Node2D = null


func run_tests() -> void:
	await case("the SC damage rule and the worked examples", _test_damage_rule)
	await case("the shield check on a mecha: deflect, impact, from inside", _test_check)
	await case("base SS is the parts' average, to two places", _test_base_strength)
	await case("projectors: full, two thirds, a third, then offline", _test_projectors)
	await case("the toggle lock, both ways, and forced drops", _test_toggle_lock)
	await case("regen, the break cooldown, electrified and the generator", _test_regen)
	await case("a blast counts once per part it reaches; from inside it hits the armour", _test_blasts)
	await case("generator, core and shoulder values by tech tier", _test_tiers)
	await case("a round off a raised shield: deflected or stopped, hull untouched", _test_round)
	await case("the HUD's SHIELD row and the frame readout", _test_hud)
	await _clear_arena()


func before_each() -> void:
	await _clear_arena()
	PlayerProgress.reset()
	_arena = Node2D.new()
	add_child(_arena)


func _clear_arena() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = null


# A default mecha that runs nothing by itself (paused): the tests step its
# shield with _update_shield.
func _mecha(pos := Vector2.ZERO) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.global_rotation = 0.0
	mecha.paused = true
	return mecha


func _step(mecha: Mecha, seconds: float, dt := 0.05) -> void:
	var left := seconds
	while left > 0.0001:
		var step := minf(dt, left)
		mecha.take_status_damage(step)
		mecha._update_shield(step)
		left -= step


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


# Every armour pip and component hp on the mecha.
func _hull(mecha: Mecha) -> Array:
	var pips := 0
	for part in mecha.armor:
		for facing in mecha.armor[part]:
			pips += int(mecha.armor[part][facing].pips)
	var hp := 0
	for part in mecha.components:
		for comp in mecha.components[part].values():
			hp += int(comp.hp)
	return [pips, hp]


# The third worked example reads "AP 3, D 2 into SS 2.5: shortfall 0.5, so
# 1"; by the rule (shortfall = SS - AP) AP 3 there is above SS and full, and
# the shortfall of 0.5 is AP 2's. Both are checked.
func _test_damage_rule() -> void:
	check_eq(Mecha.shield_damage(2.0, 3, 2), 2.0, "AP 3, D 2 into SS 2: full, 2")
	check_eq(Mecha.shield_damage(2.0, 6, 3), 3.0, "AP 6, D 3 into SS 2: full, 3")
	check(_near(Mecha.shield_damage(2.5, 3, 2), 2.0), "AP 3, D 2 into SS 2.5: AP above SS, full (%s)" % Mecha.shield_damage(2.5, 3, 2))
	check(_near(Mecha.shield_damage(2.5, 2, 2), 1.0), "AP 2, D 2 into SS 2.5: shortfall 0.5, so 1 (%s)" % Mecha.shield_damage(2.5, 2, 2))
	check(_near(Mecha.shield_damage(0.67, 1, 1), 1.0), "AP 1, D 1 into SS 0.67: full, 1")
	check(_near(Mecha.shield_damage(1.67, 1, 1), 0.33), "AP 1, D 1 into SS 1.67: shortfall 0.67, so 0.33 (%s)" % Mecha.shield_damage(1.67, 1, 1))
	check_eq(Mecha.shield_damage(2.0, 1, 1), 0.0, "AP 1, D 1 into SS 2: shortfall 1, a deflect")
	check_eq(Mecha.shield_shortfall(2.0, 1), 1.0, "that shortfall is exactly 1")
	check_eq(Mecha.shield_damage(2.0, 2, 3), 3.0, "shortfall exactly 0: full")
	check_eq(Mecha.shield_damage(3.0, 1, 2), 0.0, "shortfall over 1: a deflect")
	check(_near(Mecha.shield_damage(2.25, 2, 3), 2.25), "shortfall 0.25, D 3: 2.25")


func _test_check() -> void:
	var mecha := _mecha()
	mecha.shield_up()
	check(mecha.is_shielding, "the shield goes up")
	var outside := mecha.global_position + Vector2(-600, 0)
	mecha.shield_strength = 2.0
	var hull := _hull(mecha)
	var sc := mecha.shield
	check_eq(mecha.shield_check(outside, 1, 1), "deflect", "AP 1 into SS 2: deflect")
	check_eq(mecha.shield, sc, "a deflect takes no SC")
	check_eq(mecha.shield_check(outside, 3, 2), "impact", "AP 3, D 2 into SS 2: impact")
	check(_near(mecha.shield, sc - 2.0), "and takes 2 SC (%.2f -> %.2f)" % [sc, mecha.shield])
	mecha.shield_strength = 1.67
	sc = mecha.shield
	check_eq(mecha.shield_check(outside, 1, 1), "impact", "AP 1, D 1 into SS 1.67: impact")
	check(_near(mecha.shield, sc - 0.33), "and takes 0.33 SC (%.2f -> %.2f)" % [sc, mecha.shield])
	check_eq(mecha.shield_check(outside, 3, 2, 4), "impact", "four hits at once")
	check(_near(mecha.shield, sc - 0.33 - 8.0), "take four times the SC (%.2f)" % mecha.shield)
	sc = mecha.shield
	check_eq(mecha.shield_check(mecha.global_position + Vector2(100, 0), 10, 3), "", "from inside the bubble: no shield")
	check_eq(mecha.shield, sc, "and no SC")
	check(_hull(mecha) == hull, "the hull took nothing")
	check(not mecha.armor_check("shield", outside, Vector2.RIGHT, 10, 3).penetrated, "the bubble's shape is no armour part")


func _test_base_strength() -> void:
	var mecha := _mecha()
	var core = mecha.build.core
	var shoulders = mecha.build.shoulders
	var generator = mecha.build.generator
	var saved := [core.shield_strength, shoulders.shield_strength, generator.shield_strength]
	core.shield_strength = 2.0
	shoulders.shield_strength = 3.0
	generator.shield_strength = 3.0
	mecha.update_shield_strength()
	check(_near(mecha.shield_base_strength, 2.67), "core 2, shoulders 3, generator 3: 2.67 (%s)" % mecha.shield_base_strength)
	check(_near(mecha.shield_strength, 2.67), "with all three projectors working")
	core.shield_strength = 1.0
	shoulders.shield_strength = 2.0
	generator.shield_strength = 2.0
	mecha.update_shield_strength()
	check(_near(mecha.shield_base_strength, 1.67), "1, 2, 2: 1.67 (%s)" % mecha.shield_base_strength)
	mecha.set_shoulders(null)
	check(_near(mecha.shield_base_strength, 1.5), "no shoulders: the core and the generator, 1.5 (%s)" % mecha.shield_base_strength)
	mecha.set_shoulders(PlayerProgress.DEFAULT_MECHA.shoulders)
	mecha.set_generator(null)
	check_eq(mecha.shield_base_strength, 0.0, "no generator: no shield")
	check(mecha.is_shield_offline() and not mecha.can_raise_shield(), "and it can't go up")
	mecha.shield_up()
	check(not mecha.is_shielding, "shield_up does nothing")
	core.shield_strength = saved[0]
	shoulders.shield_strength = saved[1]
	generator.shield_strength = saved[2]


func _test_projectors() -> void:
	var mecha := _mecha()
	for part in ["core", "left_shoulder", "right_shoulder"]:
		var comp: Dictionary = mecha.components[part].get(Mecha.SHIELD_PROJECTOR, {})
		check(comp.get("max_hp") == 2 and comp.get("tags") == ["external", "shield"] and comp.get("weight") == 1.0,
				"a shield projector on the %s (%s)" % [part, str(comp)])
	var core = mecha.build.core
	var shoulders = mecha.build.shoulders
	var generator = mecha.build.generator
	var saved := [core.shield_strength, shoulders.shield_strength, generator.shield_strength]
	core.shield_strength = 1.0
	shoulders.shield_strength = 1.0
	generator.shield_strength = 1.0
	mecha.update_shield_strength()
	check_eq(mecha.shield_projectors, 3, "three projectors")
	check(_near(mecha.shield_strength, 1.0), "SS 1 with all three")
	mecha.shield_up()
	mecha.damage_component("core", Mecha.SHIELD_PROJECTOR, 2)
	check(_near(mecha.shield_strength, 0.67), "two left: 0.67 (%s)" % mecha.shield_strength)
	mecha.damage_component("left_shoulder", Mecha.SHIELD_PROJECTOR, 2)
	check(_near(mecha.shield_strength, 0.33), "one left: 0.33 (%s)" % mecha.shield_strength)
	check(mecha.is_shielding, "the shield stays up on one")
	mecha.armor.right_shoulder.rear.pips = 0
	for comp_name in mecha.components.right_shoulder.keys():
		var comp: Dictionary = mecha.components.right_shoulder[comp_name]
		if "internal" in comp.tags and not comp.disabled:
			mecha.damage_component("right_shoulder", comp_name, 10, Vector2.UP)
	check(mecha.is_part_lost("right_shoulder"), "the right shoulder came off")
	check_eq(mecha.shield_projectors, 0, "taking its projector with it")
	check_eq(mecha.shield_strength, 0.0, "SS 0")
	check(mecha.is_shield_offline(), "the shield is offline")
	check(not mecha.is_shielding, "a raised shield drops at once")
	mecha.shield_lock = 0.0
	mecha.shield_up()
	_step(mecha, 0.1)
	check(not mecha.is_shielding, "and shield_up does nothing")
	core.shield_strength = saved[0]
	shoulders.shield_strength = saved[1]
	generator.shield_strength = saved[2]


# Times are game seconds from the first raise; a step is 0.05 s, so a lock
# ends within a step of its 2 s.
func _test_toggle_lock() -> void:
	var mecha := _mecha()
	mecha.shield_up()
	check(mecha.is_shielding, "up at once")
	_step(mecha, 0.5)
	mecha.shield_down()
	check(mecha.is_shielding, "lowered 0.5 s later: still up")
	_step(mecha, 1.4)
	check(mecha.is_shielding, "still up at 1.9 s")
	_step(mecha, 0.2)
	check(not mecha.is_shielding, "down at 2 s")
	_step(mecha, 0.9)
	mecha.shield_up()
	check(not mecha.is_shielding, "raised 1 s after the drop: not yet")
	_step(mecha, 0.8)
	check(not mecha.is_shielding, "not 1.8 s after the drop")
	_step(mecha, 0.3)
	check(mecha.is_shielding, "up 2 s after the drop, still wanted")
	_step(mecha, 2.1)
	check(mecha.is_shielding, "and it stays up while wanted")
	mecha.shield_down()
	check(not mecha.is_shielding, "lowered past the lock: down at once")
	_step(mecha, 0.5)
	mecha.shield_up()
	_step(mecha, 0.5)
	mecha.shield_down()
	_step(mecha, 1.5)
	check(not mecha.is_shielding, "pressed and let go during the lock: stays down when it ends")
	_step(mecha, 0.5)
	mecha.shield_up()
	check(mecha.is_shielding, "up again")
	_step(mecha, 0.5)
	mecha.take_shield_damage(mecha.shield)
	check(not mecha.is_shielding, "SC at 0 drops it at once, lock or not")
	check(not mecha.shield_wanted, "and the want is forgotten")
	mecha.shield = mecha.max_shield
	mecha.shield_break_timer = 0.0
	_step(mecha, 2.1)
	mecha.shield_up()
	check(mecha.is_shielding, "up again after the lock")
	_step(mecha, 0.3)
	for part in ["core", "left_shoulder", "right_shoulder"]:
		mecha.damage_component(part, Mecha.SHIELD_PROJECTOR, 2)
	check(not mecha.is_shielding, "the last projector lost drops it at once too")


func _test_regen() -> void:
	var mecha := _mecha()
	var rate: float = mecha.build.generator.shield_regen_rate
	var cooldown: float = mecha.build.generator.shield_break_cooldown
	check_eq(mecha.shield, mecha.max_shield, "SC starts full")
	mecha.shield = 5.0
	mecha.shield_up()
	_step(mecha, 1.0)
	check_eq(mecha.shield, 5.0, "no regen while up")
	mecha.shield_down()
	_step(mecha, 1.1)
	check(not mecha.is_shielding, "down")
	var before := mecha.shield
	_step(mecha, 2.0)
	check(_near(mecha.shield, before + rate * 2.0), "%.1f SC a second while down (%.2f -> %.2f)" % [rate, before, mecha.shield])
	_step(mecha, 60.0)
	check_eq(mecha.shield, mecha.max_shield, "up to the capacity")
	mecha.take_shield_damage(mecha.shield)
	check_eq(mecha.shield, 0.0, "SC to 0")
	check_eq(mecha.shield_break_timer, cooldown, "the break cooldown starts")
	_step(mecha, cooldown - 0.1)
	check_eq(mecha.shield, 0.0, "no regen during it")
	_step(mecha, 0.3)
	check(mecha.shield > 0.0, "regen once it is over (%.2f)" % mecha.shield)
	mecha.shield = 10.0
	mecha.set_status("electrified", 3.0)
	_step(mecha, 1.0)
	check(_near(mecha.shield, 10.0 - Mecha.ELECTRIFIED_SHIELD_DRAIN), "electrified drains %.0f a second and blocks regen (%.2f)" % [Mecha.ELECTRIFIED_SHIELD_DRAIN, mecha.shield])
	mecha.set_status("electrified", 0.0)
	mecha.damage_component("core", "generator", 3)
	check_eq(mecha.disabled_systems.shield_regen, 0.0, "the generator component destroyed")
	before = mecha.shield
	_step(mecha, 1.0)
	check_eq(mecha.shield, before, "no regen with it gone")
	mecha.set_generator(PlayerProgress.DEFAULT_MECHA.generator)
	check_eq(mecha.shield, mecha.max_shield, "a part fitted: SC full again")


# A GL44 shell at `pos` that only goes off: AP 6 (above any SS, so every
# hit takes its full pips) and 1 pip, blast radius `radius`.
func _blast(shooter: Mecha, pos: Vector2, radius: float):
	var shell = SHELL.instantiate()
	shell.payload_explosion_radius = radius
	shell.setup(shooter, {"pos": pos, "dir": Vector2.RIGHT, "align_dir": Vector2.RIGHT,
			"seeker_target": null, "inherited_velocity": Vector2.ZERO}, "MA-GL44")
	shell.armor_pen = 6
	shell.base_damage = 1
	shell.monitoring = false
	shell.get_node("Fuse").monitoring = false
	_arena.add_child(shell)
	shell.set_physics_process(false)
	for _i in 3:
		await get_tree().physics_frame
	return shell


# The parts the blast's code counts: get_explosion_parts round where the line
# from the blast to the mecha meets it.
func _parts_reached(shell, mecha: Mecha, radius: float) -> Array:
	var query := PhysicsRayQueryParameters2D.create(shell.position, mecha.position, MapSenses.SIGHT_MASK)
	var hit := _arena.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != mecha:
		return []
	return shell.get_explosion_parts(mecha, hit.position, radius)


func _test_blasts() -> void:
	var shooter := _mecha(SHOOTER_POS)
	var mecha := _mecha()
	mecha.shield_up()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hull := _hull(mecha)
	var big = await _blast(shooter, Vector2(230, 0), 300.0)
	var parts := _parts_reached(big, mecha, 300.0)
	check(parts.size() >= 2, "a big blast outside the bubble reaches several parts (%s)" % str(parts))
	var sc := mecha.shield
	big.explosion()
	check(_near(sc - mecha.shield, float(parts.size())), "one hit for each: %d SC (%.2f -> %.2f)" % [parts.size(), sc, mecha.shield])
	check(_hull(mecha) == hull, "the armour and components take nothing")
	sc = mecha.shield
	var small = await _blast(shooter, Vector2(230, 0), 70.0)
	check(_parts_reached(small, mecha, 70.0).is_empty(), "a small one there reaches the bubble but no part")
	small.explosion()
	check(_near(sc - mecha.shield, 1.0), "and is one hit (%.2f -> %.2f)" % [sc, mecha.shield])
	sc = mecha.shield
	var inside = await _blast(shooter, Vector2(140, 0), 200.0)
	inside.explosion()
	check_eq(mecha.shield, sc, "a blast centred inside the bubble ignores the shield")
	check(_hull(mecha) != hull, "and reaches the armour")


func _test_tiers() -> void:
	for gen_id in PartManager.get_parts("generator"):
		var gen = PartManager.get_part("generator", gen_id)
		var tier := int(gen.tech_tier)
		check(gen.shield_capacity == TIER_SC[tier] and gen.shield_strength == TIER_SS[tier]
				and gen.shield_regen_rate == TIER_REGEN[tier] and gen.shield_break_cooldown == 3.0,
				"%s (tier %d): SC %s, SS %s, regen %s, break %s" % [gen_id, tier, gen.shield_capacity,
				gen.shield_strength, gen.shield_regen_rate, gen.shield_break_cooldown])
		for old in ["shield", "shield_regen_speed", "shield_regen_delay", "shield_project_cooldown"]:
			check(gen.get(old) == null, "%s has no %s" % [gen_id, old])
	for type in ["core", "shoulders"]:
		for part_id in PartManager.get_parts(type):
			var part = PartManager.get_part(type, part_id)
			check_eq(part.shield_strength, TIER_SS[int(part.tech_tier)], "%s %s SS by its tier" % [type, part_id])
			check(part.get("shield") == null, "%s has no old shield" % part_id)


# A real round from far off into a raised shield.
func _fire_at(shooter: Mecha, mecha: Mecha, pen: int, damage: int):
	var shot = SHOT.instantiate()
	shot.setup(shooter, {"pos": mecha.global_position + Vector2(-700, 0), "dir": Vector2.RIGHT, "seeker_target": null}, "test")
	shot.armor_pen = pen
	shot.base_damage = damage
	_arena.add_child(shot)
	return shot


func _test_round() -> void:
	var shooter := _mecha(SHOOTER_POS)
	var mecha := _mecha()
	mecha.shield_up()
	mecha.shield_strength = 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hull := _hull(mecha)
	var sc := mecha.shield
	var bounced = _fire_at(shooter, mecha, 0, 1)
	var ref: WeakRef = weakref(bounced)
	var hit := await wait_until(func(): return ref.get_ref() == null or ref.get_ref().shield_hit == true, 3.0)
	check(hit and ref.get_ref() != null, "AP 0 into SS 2 meets the bubble and bounces off")
	if ref.get_ref() != null:
		var shot = ref.get_ref()
		check(shot.position.x < mecha.position.x - mecha.shield_radius() + 1.0, "it never got inside (x %.0f)" % shot.position.x)
		check(shot.dir.dot(Vector2.LEFT) >= 0.0, "it heads back out (dir %s)" % str(shot.dir))
	check_eq(mecha.shield, sc, "a deflect takes no SC")
	await wait_frames(3)
	check(_hull(mecha) == hull, "nor anything from the hull")
	var stopped = _fire_at(shooter, mecha, 3, 2)
	ref = weakref(stopped)
	var impacts := []
	stopped.bullet_impact.connect(func(p, _e, clear, _b): impacts.append([p.position, p.shield_hit, clear]))
	await wait_until(func(): return ref.get_ref() == null, 3.0)
	check(ref.get_ref() == null, "AP 3 into SS 2 stops at the bubble")
	check(_near(mecha.shield, sc - 2.0), "and takes D 2 from SC (%.2f -> %.2f)" % [sc, mecha.shield])
	check(not impacts.is_empty() and impacts[-1][1] == true, "with the shield's impact effect")
	if not impacts.is_empty():
		var at: Vector2 = impacts[-1][0]
		check(absf(at.distance_to(mecha.position) - mecha.shield_radius()) < 3.0, "at the bubble (%.0f px out)" % at.distance_to(mecha.position))
	check(_hull(mecha) == hull, "the hull takes nothing")


func _test_hud() -> void:
	var mecha := _mecha()
	var hud := HudStatus.new()
	_arena.add_child(hud)
	hud.setup(mecha)
	var row: Dictionary = hud._rows.shield
	check(row.box.get_index() < hud._rows.coolant.box.get_index(), "the SHIELD row is above INT COOLANT")
	hud._update()
	check(row.box.visible, "shown with a generator")
	check_eq(row.name.text, "SHIELD · READY", "ready")
	check_eq(row.name.theme_type_variation, &"LabelDim", "dim")
	check_eq(row.value.text, HudStatus.format_shield(mecha.shield, mecha.max_shield, mecha.shield_strength), "its value")
	check_eq(HudStatus.format_shield(12.34, 20.0, 2.67), "12.3/20 · SS 2.67", "the format")
	mecha.shield_up()
	hud._update()
	check_eq(row.name.text, "SHIELD · UP", "up")
	check_eq(row.name.theme_type_variation, &"LabelMetaBright", "bright")
	mecha.take_shield_damage(mecha.shield)
	hud._update()
	check(row.name.text.begins_with("SHIELD · RECHARGING 3"), "recharging with the seconds left (%s)" % row.name.text)
	check_eq(row.gauge.ratio, 0.0, "an empty gauge")
	for part in ["core", "left_shoulder", "right_shoulder"]:
		mecha.damage_component(part, Mecha.SHIELD_PROJECTOR, 2)
	hud._update()
	check_eq(row.name.text, "SHIELD · OFFLINE", "offline with no projector")
	mecha.set_generator(null)
	hud._update()
	check(not row.box.visible, "hidden with no generator, like BATTERY")
	var fresh := _mecha(Vector2(2000, 0))
	check_eq(WireframeDisplay.part_state(fresh.components, "core"), 3, "the frame readout: a whole core with its projector")
	fresh.damage_component("core", Mecha.SHIELD_PROJECTOR, 1)
	check_eq(WireframeDisplay.part_state(fresh.components, "core"), 3, "a scratched projector is still most of it")
	fresh.damage_component("core", Mecha.SHIELD_PROJECTOR, 1)
	check_eq(WireframeDisplay.part_state(fresh.components, "core"), 1, "a destroyed one shows the part CRIT, like any component")
	hud.queue_free()
