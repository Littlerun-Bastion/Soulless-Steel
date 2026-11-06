extends TestSuite

# EnergyWeaponTest: energy weapons and the generator's battery and weapon
# power (Mecha, ENERGY WEAPONS). The WPOR improvement (0, 0.66, 1, clamped
# above 1); at WPOR 1 an energy weapon's times between shots and reload time
# divided by 1.5 and its clip 1.5 times as big, rounded down, and a normal
# weapon unchanged; a reload paying battery_drain kWh a shot, a partial one
# when the battery runs short, none with less than one shot's kWh; the
# battery refilling at the power output up to its capacity, never while
# electrified; a weapon under its minimum WPOR fitted but neither firing nor
# reloading (and the HUD, the Equipment window and NPCs knowing it), working
# at the minimum; a generator swap cutting a clip and refunding its kWh; the
# generators' battery values by tech tier; an NPC seeing an empty clip on an
# empty battery as no ammo.

const MECHA := preload("res://game/mecha/Mecha.tscn")

const CARNWEN := "Carnwen-02A"
const CLARENT := "Clarent-01"
const NORMAL := "MA-L127"
const TIER_BATTERY := {0: 250.0, 1: 250.0, 2: 500.0, 3: 750.0}
const TIER_POWER := {0: 20.0, 1: 20.0, 2: 30.0, 3: 40.0}
const TIER_WPOR := {0: 0.33, 1: 0.33, 2: 0.66, 3: 1.0}

var _arena: Node2D = null


func run_tests() -> void:
	await case("the WPOR improvement", _test_boost)
	await case("at WPOR 1 an energy weapon fires, reloads and holds 1.5 times as much", _test_full_power)
	await case("a reload is paid for from the battery", _test_reload)
	await case("the battery refills at the power output", _test_recharge)
	await case("under its minimum WPOR a weapon is fitted but dead", _test_minimum)
	await case("a smaller clip after a generator swap refunds its kWh", _test_swap)
	await case("generator battery values by tech tier", _test_tiers)
	await case("an NPC sees an empty clip on an empty battery as no ammo", _test_npc_ammo)
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


# A generator id of this tech tier.
func _generator(tier: int) -> String:
	for gen_id in PartManager.get_parts("generator"):
		if int(PartManager.get_part("generator", gen_id).tech_tier) == tier:
			return str(gen_id)
	return ""


# The default mecha with `left` and `right` arm weapons (false: none) and a
# generator of `tier`, paused (nothing runs by itself).
func _mecha(left = CARNWEN, right = NORMAL, tier := 2) -> Mecha:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["arm_weapon_left"] = left
	design["arm_weapon_right"] = right
	design["generator"] = _generator(tier)
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.global_rotation = 0.0
	mecha.paused = true
	return mecha


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005


# Pulls the trigger until a projectile comes out (spool-up weapons need a few
# tries), or `seconds` pass.
func _fires(mecha: Mecha, slot: String, seconds := 1.0) -> bool:
	var shots := [0]
	var count := func(_m, _a, _w): shots[0] += 1
	mecha.create_projectile.connect(count)
	var fired := await wait_until(func():
		mecha.shoot(slot)
		return shots[0] > 0, seconds)
	mecha.create_projectile.disconnect(count)
	return fired


func _test_boost() -> void:
	var mecha := _mecha()
	mecha.weapon_power_rating = 0.0
	check_eq(mecha.weapon_power_boost(), 0.0, "WPOR 0: no improvement")
	mecha.weapon_power_rating = 0.66
	check(_near(mecha.weapon_power_boost(), 0.33), "WPOR 0.66: 33%")
	mecha.weapon_power_rating = 1.0
	check(_near(mecha.weapon_power_boost(), 0.5), "WPOR 1: 50%")
	mecha.weapon_power_rating = 1.7
	check(_near(mecha.weapon_power_boost(), 0.5), "above 1 is clamped")
	var gen = mecha.build.generator
	var saved: float = gen.weapon_power_rating
	gen.weapon_power_rating = 1.5
	mecha.set_generator(gen.part_id)
	check_eq(mecha.weapon_power_rating, 1.0, "a generator's WPOR over 1 reads as 1")
	gen.weapon_power_rating = -0.2
	mecha.set_generator(gen.part_id)
	check_eq(mecha.weapon_power_rating, 0.0, "and under 0 as 0")
	gen.weapon_power_rating = saved


func _test_full_power() -> void:
	var mecha := _mecha(CARNWEN, NORMAL)
	var other := _mecha(CLARENT, false)
	for m in [mecha, other]:
		m.weapon_power_rating = 1.0
		m._apply_weapon_power()
	var carnwen = mecha.get_weapon_part("arm_weapon_left")
	var data = carnwen.data
	check(_near(carnwen.get_fire_rate(), data.fire_rate / 1.5), "fire interval / 1.5 (%.4f)" % carnwen.get_fire_rate())
	check(_near(carnwen.get_reload_time(), data.reload_speed / 1.5), "reload time / 1.5 (%.4f)" % carnwen.get_reload_time())
	check_eq(carnwen.get_clip_size(), int(floor(data.clip_size * 1.5)), "clip x 1.5, rounded down")
	var clarent = other.get_weapon_part("arm_weapon_left")
	check(_near(clarent.get_burst_fire_rate(), clarent.data.burst_fire_rate / 1.5), "the burst interval too")
	check_eq(clarent.get_clip_size(), int(floor(clarent.data.clip_size * 1.5)), "the Clarent's clip too")
	carnwen.clip_ammo = carnwen.get_clip_size()
	carnwen.timer = 0.0
	if check(await _fires(mecha, "arm_weapon_left"), "the Carnwen fires"):
		check(_near(carnwen.timer, carnwen.get_fire_rate() + carnwen.get_burst_fire_rate()), "and waits the shorter interval (%.4f)" % carnwen.timer)
	var normal = mecha.get_weapon_part("arm_weapon_right")
	check_eq(normal.power_boost, 0.0, "a normal weapon gets no boost")
	check_eq(normal.get_fire_rate(), normal.data.fire_rate, "its fire rate is its own")
	check_eq(normal.get_reload_time(), normal.data.reload_speed, "its reload time")
	check_eq(normal.get_clip_size(), normal.data.clip_size, "its clip")
	mecha.weapon_power_rating = 0.33
	mecha._apply_weapon_power()
	check(carnwen.get_fire_rate() < data.fire_rate and carnwen.get_clip_size() >= data.clip_size,
			"a low WPOR still never makes it worse than its base")


func _test_reload() -> void:
	var mecha := _mecha(CARNWEN, NORMAL)
	mecha.weapon_power_rating = 0.0
	mecha._apply_weapon_power()
	var node = mecha.get_weapon_part("arm_weapon_left")
	var drain: float = node.data.battery_drain
	var size: int = node.get_clip_size()
	check_eq(size, node.data.clip_size, "WPOR 0: the base clip")
	node.clip_ammo = 6
	mecha.battery = 500.0
	node.reload()
	check(node.is_reloading(), "a reload starts")
	await wait_until(func(): return not node.is_reloading(), 5.0)
	check_eq(node.clip_ammo, size, "it fills the clip")
	check(_near(mecha.battery, 500.0 - drain * (size - 6)), "taking %.0f kWh a shot (%.1f left)" % [drain, mecha.battery])
	check_eq(mecha.get_total_ammo("arm_weapon_left"), floori(mecha.battery / drain), "the reserve is the shots the battery pays for")
	node.clip_ammo = 0
	mecha.battery = drain * 5.0 + 1.0
	node.reload()
	await wait_until(func(): return not node.is_reloading(), 5.0)
	check_eq(node.clip_ammo, 5, "a partial reload: only what the battery pays for")
	check(_near(mecha.battery, 1.0), "the battery left with less than a shot (%.2f)" % mecha.battery)
	check_eq(node.can_reload(), "empty", "so it can't reload again")
	node.clip_ammo = 0
	node.reload()
	check(not node.is_reloading(), "and no reload starts")
	check(node.total_ammo == node.data.total_ammo, "total_ammo isn't used")


func _test_recharge() -> void:
	var mecha := _mecha()
	var power: float = mecha.build.generator.power_output
	check_eq(mecha.power_output, power, "the power output from the generator (%.0f kW)" % power)
	check_eq(mecha.battery, mecha.battery_capacity, "the battery starts full")
	mecha.battery = 100.0
	for _i in 20:
		mecha._recharge_battery(0.1)
	check(_near(mecha.battery, 100.0 + power * 2.0), "%.0f kWh a second (%.1f)" % [power, mecha.battery])
	for _i in 100:
		mecha._recharge_battery(1.0)
	check_eq(mecha.battery, mecha.battery_capacity, "up to the capacity")
	mecha.battery = 100.0
	mecha.set_status("electrified", 3.0)
	mecha._recharge_battery(1.0)
	check_eq(mecha.battery, 100.0, "none while electrified")
	var node = mecha.get_weapon_part("arm_weapon_left")
	node.clip_ammo = node.get_clip_size()
	check(not await _fires(mecha, "arm_weapon_left", 0.3), "and an energy weapon can't fire then")


func _test_minimum() -> void:
	var mecha := _mecha(CLARENT, NORMAL, 1)
	var node = mecha.get_weapon_part("arm_weapon_left")
	check_eq(node.data.min_power_rating, 0.5, "the Clarent needs WPOR 0.5")
	check(mecha.weapon_power_rating < 0.5, "a low-tech generator has %.2f" % mecha.weapon_power_rating)
	check(mecha.build.arm_weapon_left != null and mecha.build.arm_weapon_left.part_id == CLARENT, "it is fitted")
	check(mecha.is_weapon_underpowered("arm_weapon_left"), "but underpowered")
	check(not mecha.is_weapon_underpowered("arm_weapon_right"), "a normal weapon never is")
	check(not await _fires(mecha, "arm_weapon_left", 0.5), "it doesn't fire")
	node.clip_ammo = 0
	check_eq(node.can_reload(), "no", "nor reload")
	node.reload()
	check(not node.is_reloading(), "no reload starts")
	var hud := HudWeapons.new()
	_arena.add_child(hud)
	hud.setup(mecha)
	hud._update()
	check(hud.get_row_text("arm_weapon_left").ends_with("/ UNDERPOWERED"), "the HUD shows UNDERPOWERED (%s)" % hud.get_row_text("arm_weapon_left"))
	var window := EquipmentWindow.new()
	window.mecha_ref = mecha
	check_eq(window.power_warning("arm_weapon_left"), "UNDERPOWERED: needs WPOR 0.50", "the Equipment window's warning")
	check_eq(window.power_warning("arm_weapon_right"), "", "none on a normal weapon")
	var knowledge := NPCKnowledge.new()
	knowledge.setup(mecha)
	var state: Dictionary = knowledge._compute_self_state(0.75, 0.9)
	check_eq(state.weapons_working, 1, "an NPC counts it out of the working weapons")
	mecha.weapon_power_rating = 0.5
	check(not mecha.is_weapon_underpowered("arm_weapon_left"), "at the minimum it works")
	check_eq(window.power_warning("arm_weapon_left"), "", "and the warning goes")
	mecha.set_generator(_generator(2))
	check(not mecha.is_weapon_underpowered("arm_weapon_left"), "with a mid-tech generator")
	node.clip_ammo = node.get_clip_size()
	check(await _fires(mecha, "arm_weapon_left", 1.0), "it fires")
	hud._update()
	check(hud.get_row_text("arm_weapon_left").contains("/ BAT "), "the HUD shows BAT and the shots (%s)" % hud.get_row_text("arm_weapon_left"))
	node.clip_ammo = 0
	node.reload()
	check(node.is_reloading(), "and it reloads")
	window.free()
	hud.queue_free()


func _test_swap() -> void:
	var mecha := _mecha(CARNWEN, NORMAL, 2)
	var node = mecha.get_weapon_part("arm_weapon_left")
	var mid_clip: int = node.get_clip_size()
	check_eq(node.clip_ammo, mid_clip, "a fitted weapon starts with a full clip (%d)" % mid_clip)
	mecha.battery = 100.0
	mecha.set_generator(_generator(1))
	var low_clip: int = node.get_clip_size()
	check(low_clip < mid_clip, "a lower WPOR, a smaller clip (%d -> %d)" % [mid_clip, low_clip])
	check_eq(node.clip_ammo, low_clip, "the clip is cut to it")
	check(_near(mecha.battery, 100.0 + (mid_clip - low_clip) * node.data.battery_drain),
			"the cut shots' kWh go back into the battery (%.1f)" % mecha.battery)
	var low_capacity := mecha.battery_capacity
	mecha.set_generator(_generator(2))
	node.clip_ammo = node.get_clip_size()
	mecha.battery = low_capacity - 1.0
	mecha.set_generator(_generator(1))
	check_eq(node.clip_ammo, low_clip, "cut again")
	check_eq(mecha.battery, mecha.battery_capacity, "the refund only up to the battery's capacity")


func _test_tiers() -> void:
	for gen_id in PartManager.get_parts("generator"):
		var gen = PartManager.get_part("generator", gen_id)
		var tier := int(gen.tech_tier)
		check(gen.battery_capacity == TIER_BATTERY[tier] and gen.power_output == TIER_POWER[tier]
				and _near(gen.weapon_power_rating, TIER_WPOR[tier]),
				"%s (tier %d): %s kWh, %s kW, WPOR %s" % [gen_id, tier, gen.battery_capacity, gen.power_output, gen.weapon_power_rating])
		check(gen.get("battery_recharge_rate") == null, "%s has no battery_recharge_rate" % gen_id)
	for weapon_id in [CARNWEN, CLARENT]:
		var weapon = PartManager.get_part("arm_weapon", weapon_id)
		var clip_kwh: float = weapon.clip_size * weapon.battery_drain
		check(weapon.uses_battery and clip_kwh >= 125.0 and clip_kwh <= 167.0,
				"a full %s clip is a quarter to a third of 500 kWh (%.0f kWh)" % [weapon_id, clip_kwh])


func _test_npc_ammo() -> void:
	var mecha := _mecha(CARNWEN, false)
	var knowledge := NPCKnowledge.new()
	knowledge.setup(mecha)
	var node = mecha.get_weapon_part("arm_weapon_left")
	var drain: float = node.data.battery_drain
	node.clip_ammo = 0
	mecha.battery = 0.0
	var state: Dictionary = knowledge._compute_self_state(0.75, 0.9)
	check_eq(state.weapons_working, 1, "the energy weapon works")
	check(state.no_ammo, "empty clip, empty battery: no ammo")
	mecha.battery = drain
	check(not knowledge._compute_self_state(0.75, 0.9).no_ammo, "a battery with one shot's kWh: ammo")
	mecha.battery = 0.0
	node.clip_ammo = 2
	state = knowledge._compute_self_state(0.75, 0.9)
	check(not state.no_ammo, "a shot in the clip: ammo")
	check(state.low_ammo, "low on an all but empty battery")
