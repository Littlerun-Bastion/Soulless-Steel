extends TestSuite

const MECHA := preload("res://game/mecha/Mecha.tscn")
const WIREFRAME := preload("res://game/ui/WireframeDisplay.tscn")
const REPAIR_KIT := preload("res://game/items/RepairKit.tscn")
const TRACKED_CHASSIS := "MSV-M3-L"


class FakeArena extends Node2D:
	var mechas: Array = []
	var local_pilots := LocalPilots.new()

	func get_mechas() -> Array:
		return mechas

	func get_entities() -> Array:
		return []

	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null


func run_tests() -> void:
	await case("crippling takes the systems down and spares the weapons and the pilot", _test_cripple)
	await case("crippling raises the emergency Flag", _test_cripple_flags)
	await case("a repair brings every system back", _test_repair)
	await case("a repair ends the emergency and leaves the Flag to the pilot", _test_repair_ends_emergency)
	await case("a repair does not bring back a part that came off", _test_repair_keeps_lost_parts)
	await case("the frame readout shows the mecha whole after a repair", _test_repair_refreshes_readout)
	await case("a repair kit in reach is offered to the player", _test_kit_is_offered)
	await case("using a repair kit repairs the mecha and uses the kit up", _test_kit_repairs)
	await case("a repair kit out of reach is not offered", _test_kit_out_of_reach)
	await case("using a repair kit sets off a repair burst on the mecha, which clears", _test_kit_burst)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)


func _mecha(chassis := "") -> Mecha:
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	if chassis != "":
		design["chassis"] = chassis
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.arena = _arena
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	return mecha


func _player() -> Mecha:
	var mecha := _mecha()
	mecha.mecha_name = "Player"
	return mecha


func _kit(at: Vector2) -> RepairKit:
	var kit: RepairKit = REPAIR_KIT.instantiate()
	kit.position = at
	_arena.add_child(kit)
	return kit


func _all_components(mecha: Mecha) -> Array:
	var all := []
	for part in mecha.components.values():
		all.append_array(part.values())
	return all


func _test_cripple() -> void:
	var mecha := _mecha(TRACKED_CHASSIS)
	var full_speed: float = mecha.max_speed

	mecha.cripple_systems()

	check(mecha.disabled_systems.mobility < 1.0, "mobility is degraded")
	check(mecha.max_speed < full_speed, "and the mecha is slower for it")
	check(mecha.disabled_systems.sensors < 1.0, "the sensors are degraded")
	check(mecha.disabled_systems.heat_dispersion < 1.0, "heat dispersion is degraded")
	check_eq(mecha.disabled_systems.shield_regen, 0.0, "the shield no longer regenerates")

	check(not mecha.disabled_systems.left_arm_weapon and not mecha.disabled_systems.right_arm_weapon,\
	"both arm weapons still work")
	var weapon_parts := _all_components(mecha).filter(func(comp): return "weapon" in comp.tags)
	check(not weapon_parts.is_empty(), "the mecha has weapon components to spare")
	check(weapon_parts.all(func(comp): return not comp.disabled), "none of them was destroyed")

	check(not mecha.components.core.cockpit.disabled, "the cockpit is intact")
	check(not mecha.is_dead, "the pilot is alive")


func _test_cripple_flags() -> void:
	var mecha := _mecha()

	mecha.cripple_systems()

	check(mecha.is_exposed, "losing the core shell is the emergency state")
	check(mecha.is_flagged() and not mecha.flag_voluntary, "which raises the Flag, not by choice")


func _test_repair() -> void:
	var mecha := _mecha(TRACKED_CHASSIS)
	var full_speed: float = mecha.max_speed
	var healthy_systems: Dictionary = mecha.disabled_systems.duplicate()
	var repaired := [0]
	mecha.systems_repaired.connect(func(): repaired[0] += 1)
	mecha.cripple_systems()

	mecha.repair_systems()

	check(_all_components(mecha).all(func(comp): return comp.hp == comp.max_hp and not comp.disabled),\
	"every component is whole again")
	check_eq(mecha.disabled_systems, healthy_systems, "no system is degraded")
	check_eq(mecha.max_speed, full_speed, "the mecha moves at full speed again")
	check_eq(repaired[0], 1, "the repair was announced once")


func _test_repair_ends_emergency() -> void:
	var mecha := _mecha()
	mecha.cripple_systems()

	mecha.repair_systems()

	check(not mecha.is_exposed, "the capsule is no longer exposed")
	check(mecha.is_flagged(), "the Flag stays up until the pilot lowers it")


func _test_repair_keeps_lost_parts() -> void:
	var mecha := _mecha()
	check(mecha.lose_part("left_shoulder"), "a shoulder came off")

	mecha.repair_systems()

	check(mecha.is_part_lost("left_shoulder"), "the shoulder is still gone")
	check(mecha.disabled_systems.left_arm_weapon, "and so is the weapon it carried")
	check(mecha.components.left_shoulder.values().all(func(comp): return comp.disabled),\
	"its components stay destroyed")


func _test_repair_refreshes_readout() -> void:
	var mecha := _mecha()
	var wireframe: WireframeDisplay = WIREFRAME.instantiate()
	_arena.add_child(wireframe)
	wireframe.setup(mecha)
	var whole: int = wireframe.sprite_core.state
	mecha.cripple_systems()
	check(wireframe.sprite_core.state < whole, "the readout shows the core in a bad way")

	mecha.repair_systems()

	check_eq(wireframe.sprite_core.state, whole, "and whole again once repaired")
	check_eq(wireframe.sprite_head.state, whole, "the head too")


func _test_kit_is_offered() -> void:
	var player := _player()
	var kit := _kit(player.position + Vector2(60, 0))
	var reached := await wait_until(func(): return player.get_closest_interactable() == kit, 2.0)
	check(reached, "the kit is the thing the player would interact with")

	var prompt := InteractPrompt.new()
	add_child(prompt)
	prompt.setup(player)
	prompt._process(0.0)
	check_eq(prompt.get_text(), "[%s] USE — REPAIR KIT" % MechUI.key_name("interact"), "the prompt names the kit")
	prompt.queue_free()


func _test_kit_repairs() -> void:
	var player := _player()
	player.cripple_systems()
	var kit := _kit(player.position + Vector2(60, 0))
	await wait_until(func(): return player.get_closest_interactable() == kit, 2.0)
	var users := []
	kit.used.connect(func(by): users.append(by))

	kit.interact(player)

	check(not player.is_exposed and player.disabled_systems.sensors == 1.0, "the mecha was repaired")
	check_eq(users, [player], "the kit says who used it")
	check(player.get_closest_interactable() == null, "the player is no longer offered it")
	await wait_frames(2)
	check(not is_instance_valid(kit), "the kit is gone")


func _test_kit_out_of_reach() -> void:
	var player := _player()
	var kit := _kit(player.position + Vector2(4000, 0))
	await wait_frames(4)
	check(player.get_closest_interactable() == null, "a far kit is not offered")
	kit.queue_free()


func _test_kit_burst() -> void:
	var player := _player()
	player.cripple_systems()
	var kit := _kit(player.position + Vector2(60, 0))
	await wait_until(func(): return player.get_closest_interactable() == kit, 2.0)

	kit.interact(player)
	var bursts := player.get_children().filter(func(n): return n is RepairBurst)

	check_eq(bursts.size(), 1, "a burst goes off on the mecha")
	var cleared := await wait_until(func(): return not is_instance_valid(bursts[0]) if bursts.size() == 1 else true, RepairBurst.LIFETIME + 2.0)
	check(cleared, "and clears itself")
