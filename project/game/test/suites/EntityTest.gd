extends TestSuite

# EntityTest: the Entities (creatures, game/entities/) on a small stand-in
# arena with real mechas: real bullets and grenade blasts hurt them, armour
# halves weak weapons, their bites go through a mecha's armour from behind but
# not from the front, a Stalker pack hunts and bites, a hurt Stalker flees, a
# broken pack scatters and regroups, gunfire draws a pack in, a dead Entity
# cleans up after itself, and Stalkers drop bio salvage into a Carcass.
# Spitters keep their distance and lob acid that splashes where it lands;
# Brutes wind up, charge, ram, stomp, get stunned by walls, shrug off light
# guns and never flee; both drop their own loot.
# (In the real Expedition: ExpeditionRunTest.)

const STALKER := preload("res://game/entities/Stalker.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const SPITTER := preload("res://game/entities/Spitter.tscn")
const BRUTE := preload("res://game/entities/Brute.tscn")
const CARCASS := preload("res://game/entities/Carcass.tscn")
const STALKER_LOOT := preload("res://database/loot-tables/entity_stalker.tres")
const SPITTER_LOOT := preload("res://database/loot-tables/entity_spitter.tres")
const BRUTE_LOOT := preload("res://database/loot-tables/entity_brute.tres")
const HEART := preload("res://database/items/bio/nt_engine_heart.tres")
const LOOT_ROLLS := 300


# Stands in for the player at a carcass: LootContainer only asks is_player().
class FakePlayer extends Node:
	func is_player() -> bool:
		return true


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
	await case("a Stalker drops bio salvage", _test_stalker_loot)
	await case("a carcass holds the loot and shows the corpse", _test_carcass)
	await case("a Spitter keeps its distance", _test_spitter_range)
	await case("a Spitter's acid hits its prey", _test_spitter_acid)
	await case("an acid glob splashes only where it lands", _test_acid_glob)
	await case("a Brute winds up, charges and rams", _test_brute_charge)
	await case("a Brute stomps what's close", _test_brute_stomp)
	await case("a Brute charging into a wall is stunned", _test_brute_stun)
	await case("a Brute shrugs off light guns and gets angry, never scared", _test_brute_tough)
	await case("Spitters and Brutes drop their loot", _test_spitter_brute_loot)
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


func _spawn(scene: PackedScene, pos: Vector2, paused: bool) -> Entity:
	var entity: Entity = scene.instantiate()
	entity.position = pos
	_arena.add_child(entity)
	entity.setup(_arena)
	entity.set_pause(paused)
	_arena.entities.append(entity)
	return entity


func _stalker(pos: Vector2, paused := true) -> Stalker:
	return _spawn(STALKER, pos, paused)


func _spitter(pos: Vector2, paused := true) -> Spitter:
	return _spawn(SPITTER, pos, paused)


func _brute(pos: Vector2, paused := true) -> Brute:
	return _spawn(BRUTE, pos, paused)


func _damage_counter(mecha: Mecha) -> Array:
	var damaged := [0]
	mecha.component_damaged.connect(func(_p, _c, _hp, _max): damaged[0] += 1)
	return damaged


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
	args["pos"] = Vector2(100, 0)
	var grenade = ProjectileManager.create(shooter, args, shots[0][1]).node
	# Only the blast: no flying, no contact hit, no proximity fuse going off.
	grenade.monitoring = false
	grenade.get_node("Fuse").monitoring = false
	_arena.add_child(grenade)
	grenade.set_physics_process(false)
	await _physics_frames(3)
	if not check(is_instance_valid(grenade), "the grenade is still waiting to go off"):
		return
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
	var stalker := _stalker(Vector2(0, 1000))
	# Bites trace a ray to the hull (EntityAttack.find_impact): let the
	# physics world catch up with the new mecha's shapes and rotation first.
	await _physics_frames(2)
	var forward := Vector2(0, -1).rotated(mecha.global_rotation)
	stalker.global_position = mecha.global_position + forward * 150.0
	check_eq(EntityAttack.facing_toward(mecha, stalker.global_position), "front", "a Stalker ahead of the mecha is in front of it")
	# A worn-through face counts as penetrated (armor_check), and glancing bites
	# chip it; so the front plating is refitted before each bite here.
	var front_through := 0
	for _i in 6:
		for part_name in mecha.armor:
			mecha.armor[part_name]["front"].pips = 3
		if EntityAttack.hit_mecha(stalker, mecha, 1, 2):
			front_through += 1
	check_eq(front_through, 0, "no front bite gets through intact plating")
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

	# Glancing bites chip the plating; enough of them wear a face through.
	# (Its own mecha: once worn through, bites can finish one off.)
	var worn := _mecha(Vector2(2000, 0))
	for part_name in worn.armor:
		worn.armor[part_name]["front"].level = 3
	await _physics_frames(2)
	var worn_forward := Vector2(0, -1).rotated(worn.global_rotation)
	stalker.global_position = worn.global_position + worn_forward * 150.0
	var front_pips := func():
		var total := 0
		for part_name in worn.armor:
			total += worn.armor[part_name]["front"].pips
		return total
	var pips_before: int = front_pips.call()
	for _i in 30:
		EntityAttack.hit_mecha(stalker, worn, 1, 2)
	check(front_pips.call() < pips_before, "repeated front bites wear the plating down")


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


func _sorted_ids(stacks: Array) -> Array:
	var ids := stacks.map(func(s): return s.item.id)
	ids.sort()
	return ids


func _seeded_rng(seed_value := 777) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# 1-2 items from the Stalker table, low tech mostly.
func _test_stalker_loot() -> void:
	var stalker := _stalker(Vector2.ZERO)
	check(stalker.loot_table == STALKER_LOOT, "Stalkers use the entity_stalker table")
	var table_items := STALKER_LOOT.entries.map(func(e): return e.item)
	var rng := _seeded_rng()
	var counts := {}
	var tiers := {}
	var foreign := 0
	for _i in LOOT_ROLLS:
		var stacks := stalker.roll_loot(rng)
		counts[stacks.size()] = counts.get(stacks.size(), 0) + 1
		for stack in stacks:
			if not stack.item in table_items:
				foreign += 1
			tiers[stack.get_tech_tier()] = tiers.get(stack.get_tech_tier(), 0) + 1
	check(counts.keys().all(func(n): return n >= 1 and n <= 2), "always 1 or 2 items (%s)" % str(counts))
	check(counts.has(1) and counts.has(2), "both happen")
	check_eq(foreign, 0, "items from outside the table")
	var low: int = tiers.get(item_data.TechTier.LOW, 0)
	var high: int = tiers.get(item_data.TechTier.HIGH, 0)
	check(low > high and high > 0, "mostly low tech, high tech rare but possible (%s)" % str(tiers))
	print("    Stalker carcass: %s items per carcass, tiers %s" % [str(counts), str(tiers)])


func _test_carcass() -> void:
	var stalker := _stalker(Vector2(300, 200))
	stalker.rotation = 1.0
	var expected := _sorted_ids(stalker.roll_loot(_seeded_rng(99)))
	var carcass: Carcass = CARCASS.instantiate()
	carcass.position = stalker.global_position
	carcass.setup_from(stalker, _seeded_rng(99))
	_arena.add_child(carcass)
	check_eq(carcass.display_name, "CARCASS - STALKER", "named after the Entity")
	check(carcass.is_in_group("loot_container") and carcass.is_in_group("interactable"), "lootable like a wreck")
	check_eq(_sorted_ids(carcass.inventory.get_stacks()), expected, "holds the Stalker's rolled loot")
	var corpse := carcass.get_corpse()
	check(corpse != null and corpse.dead, "drawn as the dead Stalker")
	check(is_equal_approx(carcass.get_node("Hull").rotation, 1.0), "lying the way it fell")
	check(carcass.state == Wreck.State.UNSEARCHED and carcass.get_node("Marker").visible, "marked until searched")
	var player := FakePlayer.new()
	add_child(player)
	carcass.interact(player)
	check_eq(carcass.state, Wreck.State.SEARCHED, "searched once opened")
	for stack in carcass.inventory.get_stacks().duplicate():
		carcass.inventory.remove_item_stack(stack)
	carcass.close()
	check_eq(carcass.state, Wreck.State.EMPTY, "empty once taken")
	check(carcass.get_node("Hull").modulate == Carcass.CORPSE_EMPTY_TINT, "an empty carcass goes darker")
	player.queue_free()


# ---- Spitter ----

func _test_spitter_range() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var spitter := _spitter(Vector2(500, 0), false)
	var hunting := await wait_until(func(): return spitter.target == mecha, 2.0)
	check(hunting, "it spots the mecha")
	var backed_off := await wait_until(func(): return spitter.distance_to(mecha) >= spitter.keep_range.x - 50.0, 8.0)
	check(backed_off, "too close: it backs off to spitting range (%d)" % int(spitter.distance_to(mecha)))


func _test_spitter_acid() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var damaged := _damage_counter(mecha)
	var spitter := _spitter(Vector2(1000, 0), false)
	var spat := await wait_until(func(): return spitter.volleys > 0, 8.0)
	check(spat, "it rears up and spits")
	var hurt := await wait_until(func(): return damaged[0] > 0, 15.0)
	check(hurt, "the acid ate through to the mecha's components")
	var source = mecha.last_damage_source
	check(typeof(source) == TYPE_DICTIONARY and source.get("name") == "Spitter", "the Spitter is credited")
	check(spitter.distance_to(mecha) > spitter.retreat_range, "it stayed out of reach while doing it")


# A glob lobbed at one mecha: that one takes the splash, a mecha 600 away
# doesn't, and nor does an Entity in the splash. (Whether one splash gets
# through the armour varies; the case above covers the damage.)
func _test_acid_glob() -> void:
	var near := _mecha(Vector2.ZERO)
	var far := _mecha(Vector2(600, 0))
	var far_damage := _damage_counter(far)
	var stalker := _stalker(Vector2(0, 120))
	var glob: AcidGlob = AcidGlob.new()
	_arena.add_child(glob)
	var splashes := []
	glob.splashed.connect(func(_g, mechas_hit): splashes.append(mechas_hit))
	glob.launch(null, _arena, Vector2(-800, 0), Vector2.ZERO, 0.3)
	var landed := await wait_until(func(): return not splashes.is_empty(), 3.0)
	if not check(landed, "the glob lands"):
		return
	check_eq(splashes[0], [near], "the mecha it landed on is splashed, not the one 600 away")
	check_eq(far_damage[0], 0, "the far mecha is untouched")
	check_eq(stalker.hp, stalker.max_hp, "Entities aren't hurt by acid")
	var ref: WeakRef = weakref(glob)
	var gone := await wait_until(func(): return ref.get_ref() == null, 2.0)
	check(gone, "the splash fades and frees itself")


# ---- Brute ----

func _test_brute_charge() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var damaged := _damage_counter(mecha)
	var brute := _brute(Vector2(800, 0), false)
	var winding := await wait_until(func(): return brute.state == Brute.State.WINDUP, 6.0)
	check(winding, "it winds up first (the tell)")
	var charging := await wait_until(func(): return brute.state == Brute.State.CHARGE, 3.0)
	check(charging, "then charges")
	var rammed := await wait_until(func(): return brute.rams > 0, 4.0)
	check(rammed, "and rams the mecha")
	check(damaged[0] > 0, "the ram got through to the components")


func _test_brute_stomp() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var damaged := _damage_counter(mecha)
	var brute := _brute(Vector2(230, 0), false)
	var stomped := await wait_until(func(): return brute.stomps > 0, 4.0)
	check(stomped, "it stomps")
	check(damaged[0] > 0, "the stomp hurt the mecha")


func _test_brute_stun() -> void:
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(60, 800)
	wall.add_child(shape)
	wall.position = Vector2(450, 0)
	_arena.add_child(wall)
	var brute := _brute(Vector2.ZERO, false)
	await _physics_frames(2)
	brute.start_charge(Vector2.RIGHT)
	var stunned := await wait_until(func(): return brute.state == Brute.State.STUNNED, 3.0)
	check(stunned and brute.stuns == 1, "it hits the wall and is stunned")
	var recovered := await wait_until(func(): return brute.state != Brute.State.STUNNED, brute.stun_time + 1.0)
	check(recovered, "for a moment")


func _test_brute_tough() -> void:
	var brute := _brute(Vector2.ZERO)
	brute.take_hit(2.0, 1)
	check_eq(brute.hp, brute.max_hp - 1.0, "pen 1 does half against its armour 2")
	brute.take_hit(2.0, 3)
	check_eq(brute.hp, brute.max_hp - 3.0, "pen 3 does full damage")
	check(brute.is_enraged(), "hurting it enrages it")
	brute.take_hit(brute.hp - 1.0, 5)
	check(brute.wants_prey(), "nearly dead, it still wants a fight")
	check(not Brute.State.has("FLEE"), "it has no way to flee")


func _test_spitter_brute_loot() -> void:
	var spitter := _spitter(Vector2.ZERO)
	var brute := _brute(Vector2(600, 0))
	check(spitter.loot_table == SPITTER_LOOT and brute.loot_table == BRUTE_LOOT, "each has its own table")
	var spitter_items := SPITTER_LOOT.entries.map(func(e): return e.item)
	var brute_items := BRUTE_LOOT.entries.map(func(e): return e.item)
	var rng := _seeded_rng(31)
	var spitter_ok := true
	var brute_ok := true
	var hearts := 0
	for _i in LOOT_ROLLS:
		var stacks := spitter.roll_loot(rng)
		spitter_ok = spitter_ok and stacks.size() >= 1 and stacks.size() <= 2 \
				and stacks.all(func(s): return s.item in spitter_items)
		stacks = brute.roll_loot(rng)
		var heart_count := stacks.filter(func(s): return s.item == HEART).size()
		hearts += heart_count
		var rolled := stacks.size() - heart_count
		brute_ok = brute_ok and rolled >= 3 and rolled <= 4 and heart_count <= 1 \
				and stacks.all(func(s): return s.item == HEART or s.item in brute_items)
	check(spitter_ok, "a Spitter leaves 1-2 items from its table")
	check(brute_ok, "a Brute leaves 3-4 items from its table, plus at most one heart")
	var heart_rate := float(hearts) / LOOT_ROLLS
	check(heart_rate > 0.15 and heart_rate < 0.35, "about a quarter of Brutes carry an NT Engine Heart (%.2f)" % heart_rate)
	var carcass: Carcass = CARCASS.instantiate()
	carcass.setup_from(brute, _seeded_rng(5))
	_arena.add_child(carcass)
	check(carcass.inventory.grid_width == 5 and carcass.inventory.grid_height == 5, "a Brute carcass has room for it all")
	check(not carcass.inventory.is_empty(), "and holds it")
