extends TestSuite

# EntityTest: the Entities (creatures, game/entities/) on a small stand-in
# arena with real mechas: real bullets and grenade blasts hurt them, armour
# halves weak weapons, their bites go through a mecha's armour from behind but
# not from the front, a Stalker pack hunts and bites, a hurt Stalker flees, a
# broken pack scatters and regroups, gunfire draws a pack in, and a dead
# Entity cleans up after itself. (In the real Expedition: ExpeditionRunTest.)

const STALKER := preload("res://game/entities/Stalker.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")


# The parts of a combat scene Entities use.
class FakeArena extends Node2D:
	var mechas: Array = []
	var entities: Array = []
	var player = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return entities


var _arena: FakeArena = null


func run_tests() -> void:
	await case("a Stalker is ready to hunt", _test_ready)
	await case("bullets hurt an Entity", _test_bullet)
	await case("a grenade blast hurts an Entity", _test_blast)
	await case("armour halves weak weapons", _test_armor)
	await case("bites get through rear armour, not front", _test_bite_facing)
	await case("a Stalker pack hunts and bites", _test_pack_hunt)
	await case("a badly hurt Stalker flees", _test_flee)
	await case("a pack that loses half scatters, then regroups", _test_pack_breaks)
	await case("gunfire draws a pack in", _test_gunfire)
	await case("a dead Entity cleans up", _test_death)
	await _clear_arena()


func before_each() -> void:
	await _clear_arena()
	_arena = FakeArena.new()
	add_child(_arena)


func _clear_arena() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = null


func _stalker(pos: Vector2, paused := true) -> Stalker:
	var stalker: Stalker = STALKER.instantiate()
	stalker.position = pos
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(paused)
	_arena.entities.append(stalker)
	return stalker


func _mecha(pos: Vector2, design := PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	_arena.mechas.append(mecha)
	return mecha


# Physics (movement, area overlaps) only steps on physics frames; a couple of
# drawn frames can pass without one when the runner is fast.
func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _pack(stalkers: Array) -> EntityPack:
	var pack := EntityPack.new()
	for stalker in stalkers:
		pack.add(stalker)
	return pack


# ---- Cases ----

func _test_ready() -> void:
	var stalker := _stalker(Vector2.ZERO)
	check(stalker.is_in_group("entity"), "in the entity group (projectiles look for it)")
	check_eq(stalker.hp, stalker.max_hp, "starts at full hp")
	check_eq(stalker.mecha_name, "Stalker", "named after its species")
	check(stalker.collision_layer & 1, "on the layer projectiles and mechas collide with")
	check(stalker.components.has("body"), "has a body 'component' for NPC combat AI")
	check(stalker.get_thermal_signature() > 0.1 and stalker.internal_temp / stalker.overheat_temp > 0.1,
			"warm enough for IR seekers")


# A real mecha fires its arm weapon; as each shot leaves the barrel the
# Stalker is put in its path, so the real projectile has to fly and hit.
func _test_bullet() -> void:
	var shooter := _mecha(Vector2.ZERO)
	shooter.battery = 1000000.0
	var stalker := _stalker(Vector2(0, -400))
	shooter.create_projectile.connect(func(m, args, weapon):
		stalker.global_position = args["pos"] + args["dir"] * 400.0
		var data = ProjectileManager.create(m, args, weapon)
		_arena.add_child(data.node))
	var hit := await wait_until(func():
		shooter.shoot("arm_weapon_left")
		return stalker.hp < stalker.max_hp, 6.0)
	if not check(hit, "a bullet hurt the Stalker"):
		return
	var source = stalker.last_damage_source
	check(typeof(source) == TYPE_DICTIONARY and source.get("body") == shooter, "the damage is credited to the shooter")
	check(stalker.last_attacker == shooter, "it knows who shot it")


# A grenade's blast (not a direct hit) next to a Stalker.
func _test_blast() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "MA-GL44"
	for core_id in PartManager.get_parts("core"):
		if PartManager.get_part("core", core_id).has_left_shoulder:
			design["core"] = core_id
			break
	var shooter := _mecha(Vector2(-2000, 0), design)
	shooter.battery = 1000000.0
	var shots := []
	shooter.create_projectile.connect(func(_m, args, weapon): shots.append([args, weapon]))
	var fired := await wait_until(func():
		shooter.shoot("shoulder_weapon_left")
		return not shots.is_empty(), 3.0)
	if not check(fired, "the grenade launcher fires"):
		return
	var stalker := _stalker(Vector2.ZERO)
	var args: Dictionary = shots[0][0].duplicate()
	args["pos"] = Vector2(80, 0)
	var grenade = ProjectileManager.create(shooter, args, shots[0][1]).node
	_arena.add_child(grenade)
	grenade.set_physics_process(false)  # stay put: this tests the blast, not a contact hit
	await _physics_frames(3)
	check(stalker in grenade.explosion_targets, "the Stalker is inside the blast radius")
	grenade.explosion()
	check(stalker.hp < stalker.max_hp, "the blast hurt the Stalker")


func _test_armor() -> void:
	var stalker := _stalker(Vector2.ZERO)
	stalker.armor_rating = 2
	stalker.take_hit(2.0, 1)
	check_eq(stalker.hp, stalker.max_hp - 1.0, "pen 1 against armour 2: half damage")
	stalker.take_hit(2.0, 2)
	check_eq(stalker.hp, stalker.max_hp - 3.0, "pen 2 against armour 2: full damage")


# Mechas face -Y (rotated). A pen 2 bite can't get through front armour 3 but always
# gets through rear armour 1. (Every part ships with armour 1 on all sides
# today, so the mecha gets a front-heavy layout here to check facing counts.)
func _test_bite_facing() -> void:
	var mecha := _mecha(Vector2.ZERO)
	for part_name in mecha.armor:
		mecha.armor[part_name]["front"].level = 3
		mecha.armor[part_name]["side"].level = 2
		mecha.armor[part_name]["rear"].level = 1
	var damaged := [0]
	mecha.component_damaged.connect(func(_p, _c, _hp, _max): damaged[0] += 1)
	var forward := Vector2(0, -1).rotated(mecha.global_rotation)
	var stalker := _stalker(mecha.global_position + forward * 150.0)
	check_eq(EntityAttack.facing_toward(mecha, stalker.global_position), "front", "a Stalker ahead of the mecha is in front of it")
	var front_through := 0
	for _i in 6:
		if EntityAttack.hit_mecha(stalker, mecha, 1, 2):
			front_through += 1
	check_eq(front_through, 0, "no front bite gets through")
	stalker.global_position = mecha.global_position - forward * 150.0
	check_eq(EntityAttack.facing_toward(mecha, stalker.global_position), "rear", "the other side is behind it")
	var rear_through := 0
	for _i in 6:
		if EntityAttack.hit_mecha(stalker, mecha, 1, 2):
			rear_through += 1
	check(rear_through > 0, "rear bites get through (%d of 6)" % rear_through)
	check(damaged[0] > 0, "the mecha's components took damage")
	var source = mecha.last_damage_source
	check(typeof(source) == TYPE_DICTIONARY and source.get("body") == stalker, "the damage is credited to the Stalker")


# A pack 900 away from a mecha that stands still: they spot it, circle round
# behind it and bite.
func _test_pack_hunt() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var damaged := [0]
	mecha.component_damaged.connect(func(_p, _c, _hp, _max): damaged[0] += 1)
	var stalkers := [_stalker(Vector2(900, 0), false), _stalker(Vector2(950, 100), false), _stalker(Vector2(950, -100), false)]
	var pack := _pack(stalkers)
	var hunting := await wait_until(func(): return stalkers.all(func(s): return s.target == mecha), 3.0)
	check(hunting, "the whole pack goes after the mecha")
	check(pack.target == mecha, "the pack shares the target")
	var bit := await wait_until(func(): return stalkers.any(func(s): return s.bites > 0), 20.0)
	check(bit, "a Stalker lunged and bit")
	var hurt := await wait_until(func(): return damaged[0] > 0, 20.0)
	check(hurt, "bites got through to the mecha's components")
	var attackers := stalkers.filter(func(s): return s.state == Stalker.State.WINDUP or s.state == Stalker.State.LUNGE)
	check(attackers.size() <= 1, "one attacks at a time")


func _test_flee() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var stalker := _stalker(Vector2(500, 0), false)
	stalker.acquire_target(mecha)
	stalker.take_hit(7.0, 5, Vector2.ZERO, {"body": mecha, "name": "Shooter"})
	check_eq(stalker.state, Stalker.State.FLEE, "below a third of its hp it flees")
	check(stalker.target == null and not stalker.wants_prey(), "and drops the hunt")
	await wait_seconds(1.0)
	check(stalker.global_position.distance_to(mecha.global_position) > 600.0, "it runs away from its attacker")
	check(stalker.find_prey() == null or not stalker.wants_prey(), "it won't pick a fight while hurt")


func _test_pack_breaks() -> void:
	var stalkers := []
	for i in 4:
		stalkers.append(_stalker(Vector2(i * 120, 0), false))
	var pack := _pack(stalkers)
	stalkers[0].take_hit(100.0, 5)
	await _physics_frames(2)
	check(not pack.broken, "losing one of four doesn't break the pack")
	stalkers[1].take_hit(100.0, 5)
	await _physics_frames(2)
	check(pack.broken, "losing half breaks it")
	check(stalkers[2].state == Stalker.State.FLEE and stalkers[3].state == Stalker.State.FLEE, "the survivors scatter")
	var regrouped := await wait_until(func(): return not pack.broken, 10.0)
	check(regrouped, "they regroup after running")
	check_eq(pack.alive().size(), 2, "as a pack of two")


func _test_gunfire() -> void:
	var stalkers := [_stalker(Vector2.ZERO, false), _stalker(Vector2(150, 0), false), _stalker(Vector2(0, 150), false)]
	_pack(stalkers)
	stalkers[0].heard_sound({"volume_type": "quiet", "position": Vector2(1500, 0)})
	check(stalkers.all(func(s): return s.state == Stalker.State.WANDER), "quiet sounds are ignored")
	stalkers[0].heard_sound({"volume_type": "loud", "position": Vector2(1500, 0)})
	check(stalkers.all(func(s): return s.state == Stalker.State.INVESTIGATE), "a loud one sends the whole pack")
	await wait_seconds(1.0)
	check(stalkers[0].global_position.x > 150.0, "they head for it")


func _test_death() -> void:
	var stalker := _stalker(Vector2.ZERO)
	var died := []
	stalker.died.connect(func(e): died.append(e))
	stalker.take_hit(100.0, 5, Vector2.ZERO, {"body": null, "name": "Player"})
	check(stalker.is_dead and died == [stalker], "it dies, and says so")
	check(not stalker.is_in_group("entity"), "projectiles and NPCs stop treating it as a target")
	check(stalker.body_visual.dead, "it shows as a corpse")
	stalker.take_hit(100.0, 5)
	check_eq(died.size(), 1, "it only dies once")
	var ref: WeakRef = weakref(stalker)  # a lambda capturing the Stalker itself errors once it's freed
	var gone := await wait_until(func(): return ref.get_ref() == null, Entity.CORPSE_TIME + Entity.CORPSE_FADE_TIME + 2.0)
	check(gone, "the corpse fades and frees itself")
