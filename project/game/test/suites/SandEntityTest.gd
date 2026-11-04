extends TestSuite

# SandEntityTest: the sand Entities (Coyote, Coyote Spitter, Fisher) on a
# small stand-in arena with real mechas. They find prey by its heat and let
# it go once it cools. A Coyote pack hunts together; a Coyote's whip only
# tears at external components and its bite drains heat and stacks a slow
# that wears off; a Coyote Spitter keeps its range and fires medium-AP globs
# from the side. A Fisher sleeps through heat but wakes on noise, keeps its
# distance, harpoons through the armour and latches on (a hit that always
# gets through every two seconds, heat drained, hp regained), lets go after
# six seconds or when the tether is stretched too far, leaps when rushed, and
# can't hurt a mecha in the Flag's grace window. Their carcasses show what's
# left of them, and the Expedition director spawns Coyote packs that always
# have a Spitter. Coyotes scavenge parts from wrecks and off the ground (a
# wreck's shed parts, which then leave its unsalvageable list, and parts a
# live mecha lost). A Spitter's glob flies as a drop of fluid and splashes
# into droplets.
# (The first species are covered by EntityTest.)

const COYOTE := preload("res://game/entities/coyote/Coyote.tscn")
const COYOTE_SPITTER := preload("res://game/entities/coyote/CoyoteSpitter.tscn")
const FISHER := preload("res://game/entities/fisher/Fisher.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const CARCASS := preload("res://game/entities/Carcass.tscn")
const DIRECTOR := preload("res://game/expedition/ExpeditionDirector.gd")
const TICKS := preload("res://game/entities/tick/TickSwarm.tscn")
const WRECK := preload("res://game/mecha/Wreck.tscn")

## A mecha this hot (°C above ambient) reads as a strong heat signature.
const HOT := 110.0


# The parts of a combat scene Entities use.
class FakeArena extends Node2D:
	var mechas: Array = []
	var entities: Array = []
	var player = null
	var ExpeditionDirector = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return entities
	func add_entity(scene: PackedScene, pos: Vector2) -> Entity:
		var entity: Entity = scene.instantiate()
		entity.position = pos
		add_child(entity)
		entity.setup(self)
		entities.append(entity)
		entity.died.connect(func(e): entities.erase(e))
		return entity


var _arena: FakeArena = null


func run_tests() -> void:
	await case("Coyotes find prey by its heat", _test_heat_finds)
	await case("prey that cools down is let go", _test_cooling_releases)
	await case("a Coyote's bite drains heat and stacks a slow that wears off", _test_bite)
	await case("a Coyote's whip only tears at external components", _test_whip_externals)
	await case("a Coyote pack hunts: whips land, bites slow, one at a time", _test_pack_hunt)
	await case("a Coyote Spitter fires medium-AP globs from range", _test_spitter)
	await case("a badly hurt Coyote flees", _test_flee)
	await case("a Fisher sleeps through heat but wakes on noise", _test_fisher_wakes)
	await case("a shot wakes a Fisher and it goes for the shooter", _test_fisher_shot)
	await case("a Fisher's harpoon latches on and draws on its prey", _test_fisher_latch)
	await case("a stretched tether snaps", _test_tether_snaps)
	await case("a rushed Fisher leaps away", _test_fisher_leaps)
	await case("a Fisher's drain can't hurt a mecha in the Flag's grace window", _test_fisher_grace)
	await case("carcasses show what's left", _test_carcasses)
	await case("the director's Coyote packs always have a Spitter", _test_director_packs)
	await case("a blast's hit on an Entity is marked AoE, a direct hit isn't", _test_aoe_mark)
	await case("a tick swarm's hp is its motes on the ground", _test_swarm_hp)
	await case("a point of damage kills the nearest mote, a blast's point three", _test_swarm_damage)
	await case("a shot between the motes misses", _test_swarm_gap)
	await case("a mote jumps on a hot mecha close by, not a cold one", _test_tick_jump)
	await case("ticks drain external heat, glow and bite", _test_tick_effects)
	await case("damage shakes ticks off, a blast's three a point", _test_tick_shake)
	await case("three ticks from a swarm sync and drop off as a brood, which doubles", _test_tick_brood)
	await case("a swarm down to three motes disperses after a minute", _test_swarm_disperse)
	await case("over the cap, the oldest unseen swarm fades out for a brood", _test_swarm_cap)
	await case("an Entity hunting a mecha with ticks on it is in frenzy", _test_frenzy)
	await case("a wandering pack takes a part from a wreck, and the wreck loses it", _test_scavenge_wreck)
	await case("a Coyote takes a part a wreck shed, and it leaves the unsalvageable list", _test_scavenge_shed)
	await case("a Coyote takes a part a live mecha lost, off the ground", _test_scavenge_lost_part)
	await case("a glob flies as a drop of fluid and splashes into droplets", _test_glob_look)
	await case("a Coyote rips a part off a Flagged mecha instead of biting", _test_rip_flagged)
	await case("a shield covers only the front and breaks when its pips run out", _test_shield)
	await case("a gun fires the weapon's own rounds at the target, credited to the Coyote", _test_gun)
	await case("a Coyote's carcass holds the parts it scavenged", _test_scavenged_loot)
	await case("sweeps and the Biosensor report Coyotes, Fishers and ticks; what they leave fades with them", _test_sensed_and_seen)
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


func _spawn(scene: PackedScene, pos: Vector2, paused := false) -> Entity:
	var entity := _arena.add_entity(scene, pos)
	entity.set_pause(paused)
	return entity


# A mecha facing -Y (Mecha._ready turns each one a random way): an attacker
# at +Y of it is behind it.
func _mecha(pos: Vector2, heat := HOT, design := PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.global_rotation = 0.0
	_arena.mechas.append(mecha)
	mecha.external_temp = heat
	return mecha


# Keeps a mecha hot while a case runs (it sheds heat on its own).
func _keep_hot(mecha: Mecha) -> Callable:
	var heat := func(): if is_instance_valid(mecha): mecha.external_temp = maxf(mecha.external_temp, HOT)
	get_tree().physics_frame.connect(heat)
	return func(): get_tree().physics_frame.disconnect(heat)


func _pack(members: Array) -> EntityPack:
	var pack := EntityPack.new()
	for member in members:
		pack.add(member)
	return pack


func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# component_damaged events: [part, component].
func _damage_log(mecha: Mecha) -> Array:
	var log := []
	mecha.component_damaged.connect(func(part, comp, _hp, _max): log.append([part, comp]))
	return log


# ---- Heat ----

func _test_heat_finds() -> void:
	var mecha := _mecha(Vector2.ZERO, 0.0)
	var coyotes := [_spawn(COYOTE, Vector2(700, 0)), _spawn(COYOTE, Vector2(750, 120)),
			_spawn(COYOTE_SPITTER, Vector2(760, -120))]
	_pack(coyotes)
	await wait_seconds(1.0)
	check(coyotes.all(func(c): return c.target == null), "a cold mecha goes unnoticed close by")
	check(coyotes[0].sense_range(mecha) == 0.0, "it can't be sensed at all")
	mecha.external_temp = HOT
	var stop := _keep_hot(mecha)
	var found := await wait_until(func(): return coyotes.all(func(c): return c.target == mecha), 3.0)
	stop.call()
	check(found, "heated up, the whole pack goes after it")
	var warm := _mecha(Vector2(5000, 0), 30.0)
	check(coyotes[0].sense_range(warm) < coyotes[0].sense_range(mecha), "a cooler mecha is sensed from closer")
	check(coyotes[0].sense_range(mecha) > coyotes[0].sight_range, "a hot one from further than it sees")


func _test_cooling_releases() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var coyote: Coyote = _spawn(COYOTE, Vector2(600, 0))
	coyote.acquire_target(mecha)
	mecha.external_temp = 0.0
	var let_go := await wait_until(func(): return coyote.target == null, 2.0)
	check(let_go, "cooled to ambient, it's let go")
	await wait_seconds(0.5)
	check(coyote.target == null, "and not picked back up")


# ---- Coyote ----

func _test_bite() -> void:
	var mecha := _mecha(Vector2.ZERO, 100.0)
	var coyote: Coyote = _spawn(COYOTE, Vector2(0, 150), true)
	var log := _damage_log(mecha)
	var before := mecha.external_temp
	coyote.bite(mecha)
	check(mecha.external_temp < before - 5.0, "the bite drains heat (%.0f -> %.0f)" % [before, mecha.external_temp])
	check(is_equal_approx(mecha.get_entity_slow(), 1.0 - Mecha.ENTITY_SLOW_PER_STACK), "and slows the mecha")
	check(log.is_empty(), "without damaging a component")
	for _i in 6:
		coyote.bite(mecha)
	check_eq(mecha.entity_slow_stacks.size(), Mecha.ENTITY_SLOW_MAX_STACKS, "slow stacks, up to a limit")
	check(mecha.drain_heat(1.0e9) >= 0.0 and mecha.external_temp == 0.0 and mecha.internal_temp == 0.0,
			"heat can't be drained below ambient")
	var worn := await wait_until(func(): return mecha.get_entity_slow() == 1.0, coyote.bite_slow_time + 2.0)
	check(worn, "the slow wears off")


func _test_whip_externals() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var coyote: Coyote = _spawn(COYOTE, Vector2(0, 160), true)
	var log := _damage_log(mecha)
	var armor_before: Dictionary = mecha.armor.duplicate(true)
	for _i in 8:
		EntityAttack.hit_external(coyote, mecha, 1)
	check(not log.is_empty(), "whips damage components")
	check(log.all(func(e): return "external" in mecha.components[e[0]][e[1]].tags), "only external ones")
	check(mecha.armor == armor_before, "without touching the armour")
	check(not mecha.is_dead, "and can't kill the mecha")


func _test_pack_hunt() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var stop := _keep_hot(mecha)
	var coyotes := [_spawn(COYOTE, Vector2(800, 0)), _spawn(COYOTE, Vector2(850, 120)),
			_spawn(COYOTE, Vector2(850, -120)), _spawn(COYOTE_SPITTER, Vector2(900, 0))]
	_pack(coyotes)
	var melee := coyotes.slice(0, 3)
	var attacking := func(): return melee.filter(func(c): return c.state in [Coyote.State.WINDUP, Coyote.State.LUNGE, Coyote.State.STRIKE]).size()
	var most := [0]
	var watch := func(): most[0] = maxi(most[0], attacking.call())
	get_tree().physics_frame.connect(watch)
	var whipped := await wait_until(func(): return melee.any(func(c): return c.whips > 0), 20.0)
	check(whipped, "a Coyote lunged and whipped")
	var bit := await wait_until(func(): return melee.any(func(c): return c.bites > 0), 20.0)
	check(bit, "and bit")
	check(mecha.get_entity_slow() < 1.0 or melee.all(func(c): return c.bites == 0), "the bites slow the mecha")
	get_tree().physics_frame.disconnect(watch)
	check(most[0] <= 1, "one attacks at a time (at most %d at once)" % most[0])
	check(coyotes[3].whips == 0 and coyotes[3].bites == 0, "the Spitter never closes in")
	stop.call()


func _test_spitter() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var stop := _keep_hot(mecha)
	var spitter: CoyoteSpitter = _spawn(COYOTE_SPITTER, Vector2(700, 300))
	check_eq(spitter.glob_pen, 3, "medium AP")
	var globs := []
	_arena.child_entered_tree.connect(func(n): if n is AcidGlob: globs.append(n))
	var fired := await wait_until(func(): return spitter.shots > 0, 15.0)
	check(fired, "it charges and fires")
	if not globs.is_empty():
		var glob: AcidGlob = globs[0]
		check(glob.pen == spitter.glob_pen and glob.source == spitter, "a medium-AP glob, credited to it")
	check(spitter.distance_to(mecha) > spitter.fire_range.x * 0.6, "from range")
	check(spitter.state != Coyote.State.LUNGE and spitter.whips == 0, "it never lunges")
	stop.call()


func _test_flee() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var coyote: Coyote = _spawn(COYOTE, Vector2(500, 0))
	coyote.acquire_target(mecha)
	coyote.take_hit(6.0, 5, Vector2.ZERO, {"body": mecha, "name": "Shooter"})
	check_eq(coyote.state, Coyote.State.FLEE, "badly hurt, it flees")
	await wait_seconds(1.0)
	check(coyote.distance_to(mecha) > 600.0, "away from its attacker")


# ---- Fisher ----

func _test_fisher_wakes() -> void:
	var mecha := _mecha(Vector2(0, 450))
	var stop := _keep_hot(mecha)
	var fisher: Fisher = _spawn(FISHER, Vector2.ZERO)
	await wait_seconds(1.0)
	check(fisher.state == Fisher.State.DORMANT and fisher.target == null, "dormant, it ignores a hot mecha")
	check(fisher.fisher_body.legs_out() == 0.0, "curled up in its shell")
	fisher.heard_sound({"volume_type": "loud", "position": Vector2(200, 200)})
	check_eq(fisher.state, Fisher.State.ALERT, "a loud noise wakes it")
	var hunting := await wait_until(func(): return fisher.target == mecha and fisher.state == Fisher.State.HUNT, 2.0)
	check(hunting, "awake, it finds the heat and hunts")
	var standing := await wait_until(func(): return fisher.fisher_body.legs_out() >= 1.0, 3.0)
	check(standing, "its legs come out")
	stop.call()


func _test_fisher_shot() -> void:
	var mecha := _mecha(Vector2(0, 600), 0.0)
	var fisher: Fisher = _spawn(FISHER, Vector2.ZERO)
	fisher.take_hit(1.0, 5, Vector2.UP, {"body": mecha, "name": "Shooter"})
	check(fisher.state == Fisher.State.HUNT and fisher.target == mecha, "it hunts its shooter, hot or not")


func _test_fisher_latch() -> void:
	# Behind the mecha (it faces -Y), where a pen 2 harpoon gets through.
	var mecha := _mecha(Vector2(0, -450))
	var stop := _keep_hot(mecha)
	var log := _damage_log(mecha)
	var fisher: Fisher = _spawn(FISHER, Vector2.ZERO)
	fisher.hp = 10.0
	fisher.acquire_target(mecha)
	var latched := await wait_until(func(): return fisher.harpoon == Fisher.Harpoon.LATCHED, 6.0)
	if not check(latched, "the harpoon gets through and latches on"):
		stop.call()
		return
	check(fisher.hp > 10.0, "a hit that gets through heals it")
	var hp_latched := fisher.hp
	var damage_latched := log.size()
	var drained := await wait_until(func(): return fisher.drain_hits >= 2, fisher.drain_period * 2.0 + 1.0)
	check(drained, "it draws on the prey every %.0f s" % fisher.drain_period)
	check(log.size() >= damage_latched + 2, "each draw damages a component")
	check(fisher.hp >= minf(hp_latched + 2.0, fisher.max_hp), "and heals it")
	var released := await wait_until(func(): return fisher.harpoon != Fisher.Harpoon.LATCHED, fisher.latch_time)
	check(released, "it lets go after %.0f s" % fisher.latch_time)
	check(fisher.drain_hits <= int(fisher.latch_time / fisher.drain_period), "having drawn on it %d times" % fisher.drain_hits)
	stop.call()


func _test_tether_snaps() -> void:
	var mecha := _mecha(Vector2(0, -450))
	var stop := _keep_hot(mecha)
	var fisher: Fisher = _spawn(FISHER, Vector2.ZERO)
	fisher.acquire_target(mecha)
	var latched := await wait_until(func(): return fisher.harpoon == Fisher.Harpoon.LATCHED, 6.0)
	if not check(latched, "latched on"):
		stop.call()
		return
	mecha.global_position = Vector2(0, -fisher.tether_break - 300.0)
	await _physics_frames(3)
	check(fisher.harpoon == Fisher.Harpoon.REELING or fisher.harpoon == Fisher.Harpoon.NONE,
			"pulled more than %.0f px away, the tether snaps" % fisher.tether_break)
	stop.call()


func _test_fisher_leaps() -> void:
	var mecha := _mecha(Vector2(0, -500))
	var stop := _keep_hot(mecha)
	var fisher: Fisher = _spawn(FISHER, Vector2.ZERO)
	fisher.harpoon_cooldown = Vector2(100.0, 100.0)  # no harpoon: just the leap
	fisher._harpoon_cool = 100.0
	fisher.acquire_target(mecha)
	await wait_until(func(): return fisher.fisher_body.legs_out() >= 1.0, 3.0)
	var start := fisher.global_position
	# Charge it, at 700 px/s.
	var rush := func(): if is_instance_valid(mecha): mecha.global_position = mecha.global_position.move_toward(
			fisher.global_position, 700.0 * get_physics_process_delta_time() * Engine.time_scale)
	get_tree().physics_frame.connect(rush)
	var leapt := await wait_until(func(): return fisher.leaps > 0, 3.0)
	get_tree().physics_frame.disconnect(rush)
	check(leapt, "rushed, it leaps")
	await wait_seconds(fisher.crouch_time + fisher.air_time + fisher.land_time + 0.2)
	check(fisher.global_position.distance_to(start) > fisher.leap_distance * 0.5, "a good way")
	check(fisher.global_position.distance_to(mecha.global_position) > 350.0, "away from the rush")
	stop.call()


# In the emergency Flag's grace window nothing hurts the mecha, the Fisher's
# draw (a hit that always gets through) included.
func _test_fisher_grace() -> void:
	var mecha := _mecha(Vector2(0, -450))
	var fisher: Fisher = _spawn(FISHER, Vector2.ZERO, true)
	mecha.damage_component("core", "core_shell", 3)
	check(mecha.is_exposed and mecha.is_in_flag_grace(), "the mecha is Exposed, in the grace window")
	var log := _damage_log(mecha)
	var through := false
	for _i in 20:
		through = EntityAttack.hit_through(fisher, mecha, 5) or through
	check(not through and log.is_empty(), "the draws do nothing")
	check(not mecha.is_dead, "and can't kill it")


# ---- Carcasses, spawning ----

func _test_carcasses() -> void:
	for scene in [COYOTE, FISHER]:
		var entity: Entity = _spawn(scene, Vector2(300, 300), true)
		entity.die()
		var carcass: Carcass = CARCASS.instantiate()
		carcass.setup_from(entity)
		_arena.add_child(carcass)
		var corpse := carcass.get_corpse()
		check(corpse != null and corpse.dead, "a %s carcass shows its remains" % entity.species)
		if entity is Fisher:
			check(corpse.get_children().any(func(n): return n is Sprite2D), "a Fisher's is its empty shell")
		entity.queue_free()
		await wait_frames(2)
		check(is_instance_valid(corpse), "and keeps them when the Entity is gone")


func _test_director_packs() -> void:
	var director: Node = DIRECTOR.new()
	director.arena = _arena
	add_child(director)
	for _i in 6:
		var pack: EntityPack = director.spawn_coyote_pack(Vector2(randf_range(-3000, 3000), 3000))
		var size := pack.members.size()
		check(size >= director.min_pack_size and size <= director.max_pack_size, "a pack of %d" % size)
		var spitters := pack.members.filter(func(m): return m is CoyoteSpitter).size()
		check(spitters >= director.min_pack_spitters and spitters <= director.max_pack_spitters, "with %d Spitter(s)" % spitters)
		check(not pack.leader() is CoyoteSpitter, "led by a Coyote")
		for member in pack.members:
			member.set_pause(true)
	check(director.spawn_fisher(Vector2(0, -3000)) is Fisher, "Fishers spawn alone")
	director.queue_free()


# ---- AoE ----

# A shooter's first round from `slot`, made but not fired: [args, weapon].
func _first_round(shooter: Mecha, slot: String) -> Array:
	shooter.battery = 1000000.0
	var shots := []
	var keep := func(_m, args, weapon): shots.append([args, weapon])
	shooter.create_projectile.connect(keep)
	await wait_until(func():
		shooter.shoot(slot)
		return not shots.is_empty(), 3.0)
	shooter.create_projectile.disconnect(keep)
	return shots[0] if not shots.is_empty() else []


func _grenadier(pos: Vector2) -> Mecha:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = "MA-GL44"
	for core_id in PartManager.get_parts("core"):
		if PartManager.get_part("core", core_id).has_left_shoulder:
			design["core"] = core_id
			break
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	_arena.mechas.append(mecha)
	return mecha


# A round made from the shooter's shot, put at `pos` going along `dir`, not
# yet in the tree.
func _round_at(shooter: Mecha, shot: Array, pos: Vector2, dir: Vector2) -> Node:
	var args: Dictionary = shot[0].duplicate()
	args["pos"] = pos
	args["dir"] = dir
	args["align_dir"] = dir
	return ProjectileManager.create(shooter, args, shot[1]).node


func _test_aoe_mark() -> void:
	var shooter := _grenadier(Vector2(-2000, 0))
	var shot := await _first_round(shooter, "shoulder_weapon_left")
	if not check(not shot.is_empty(), "the grenade launcher fires"):
		return
	var coyote: Coyote = _spawn(COYOTE, Vector2.ZERO, true)
	coyote.max_hp = 1000.0
	coyote.hp = 1000.0
	var grenade = _round_at(shooter, shot, Vector2(100, 0), Vector2.LEFT)
	grenade.monitoring = false
	grenade.get_node("Fuse").monitoring = false
	_arena.add_child(grenade)
	grenade.set_physics_process(false)
	await _physics_frames(3)
	grenade.hit_entity(coyote)
	check(coyote.hp < coyote.max_hp and not coyote.last_hit_aoe, "the direct hit isn't AoE")
	var hp := coyote.hp
	grenade.explosion()
	check(coyote.hp < hp and coyote.last_hit_aoe, "the same round's blast is")


# ---- Tick swarms ----

func _swarm(pos: Vector2, paused := false) -> TickSwarm:
	return _spawn(TICKS, pos, paused)


# Puts a swarm's motes where given (its own space) and drops the rest.
func _place_motes(swarm: TickSwarm, points: Array) -> void:
	var motes := swarm.get_motes()
	while motes.size() > points.size():
		swarm._remove_mote(motes[-1])
	for k in points.size():
		motes[k].pos = points[k]
		motes[k].shape.position = points[k]
	swarm._update_hp()


func _test_swarm_hp() -> void:
	var swarm := _swarm(Vector2.ZERO, true)
	var count := swarm.get_mote_count()
	check(count >= 9 and count <= 12, "9 to 12 motes (%d)" % count)
	check_eq(swarm.hp, float(count), "hp is the motes on the ground")
	check_eq(swarm.armor_rating, 0, "no armour")
	var points := swarm.get_mote_positions()
	check(Array(points).all(func(p): return p.distance_to(swarm.global_position) <= swarm.patch_radius + 0.5),
			"within the patch")
	var shapes := swarm.get_motes().filter(func(m): return m.shape.get_parent() == swarm and not m.shape.disabled)
	check_eq(shapes.size(), count, "each with its own collision circle")
	swarm.set_pause(false)
	await wait_seconds(3.0)
	check(Array(swarm.get_mote_positions()).all(func(p): return p.distance_to(swarm.global_position) <= swarm.patch_radius + 0.5),
			"scuttling, they stay in the patch")
	check(swarm.get_motes().all(func(m): return m.shape.position == m.pos), "their circles move with them")


func _test_swarm_damage() -> void:
	var swarm := _swarm(Vector2.ZERO, true)
	_place_motes(swarm, [Vector2(-100, 0), Vector2(-60, 0), Vector2(0, 0), Vector2(60, 0), Vector2(100, 0),
			Vector2(0, 100), Vector2(0, -100)])
	var source := {"body": null, "name": "Shooter"}
	swarm.take_hit(1.0, 1, Vector2.RIGHT, source, 0.0, false, Vector2(95, 5))
	check_eq(swarm.get_mote_count(), 6, "one point kills one mote")
	check(not Array(swarm.get_mote_positions()).has(Vector2(100, 0)), "the one nearest the impact")
	swarm.take_hit(1.0, 1, Vector2.RIGHT, source, 0.0, true, Vector2(-100, 0))
	check_eq(swarm.get_mote_count(), 3, "a blast's point kills three")
	check_eq(swarm.hp, 3.0, "hp follows")
	swarm.take_hit(5.0, 1, Vector2.RIGHT, {"body": null, "name": "Player"}, 0.0, false, Vector2.ZERO)
	check(swarm.is_dead, "with none left on the ground it dies")
	check(not swarm.leaves_carcass, "leaving no carcass")
	check(swarm.roll_loot().is_empty(), "and no loot")


# A real round from an arm weapon, through the gap between two motes and then
# through a mote.
func _test_swarm_gap() -> void:
	var shooter: Mecha = _mecha(Vector2(-3000, 0), 0.0)
	var shot := await _first_round(shooter, "arm_weapon_left")
	if not check(not shot.is_empty(), "the shooter fires"):
		return
	var swarm := _swarm(Vector2.ZERO, true)
	_place_motes(swarm, [Vector2(-50, 0), Vector2(50, 0)])
	await _physics_frames(2)
	var through_gap = _round_at(shooter, shot, Vector2(0, -400), Vector2.DOWN)
	_arena.add_child(through_gap)
	await wait_seconds(1.0)
	check_eq(swarm.get_mote_count(), 2, "a round between the motes misses")
	var at_mote = _round_at(shooter, shot, Vector2(50, -400), Vector2.DOWN)
	_arena.add_child(at_mote)
	var hit := await wait_until(func(): return swarm.get_mote_count() < 2, 2.0)
	check(hit, "one at a mote hits it")
	if hit:
		var left := swarm.get_mote_positions()


func _test_tick_jump() -> void:
	var swarm := _swarm(Vector2.ZERO)
	_place_motes(swarm, [Vector2(0, 90), Vector2(10, 100), Vector2(-10, 100)])
	swarm.hop_wait = Vector2(100.0, 100.0)
	var mecha := _mecha(Vector2(0, 260), 0.0)
	await wait_seconds(1.0)
	check_eq(mecha.get_tick_count(), 0, "a cold mecha close by is left alone")
	var far := _mecha(Vector2(0, 800))
	var stop := _keep_hot(far)
	await wait_seconds(1.0)
	check_eq(far.get_tick_count(), 0, "a hot one further than %d px is too" % int(swarm.jump_range))
	stop.call()
	mecha.external_temp = HOT
	stop = _keep_hot(mecha)
	var jumped := await wait_until(func(): return mecha.get_tick_count() > 0, 2.0)
	stop.call()
	check(jumped, "a hot one within %d px of its hull gets jumped" % int(swarm.jump_range))
	check(swarm.get_mote_count() < 3 and swarm.hp == float(swarm.get_mote_count()), "an attached tick doesn't count in the swarm's hp")
	await _physics_frames(10)
	var tick: Mecha.Tick = mecha.ticks[0]
	check(tick.jump >= 1.0 and mecha.tick_position(tick).distance_to(mecha.get_part_global_position(tick.part)) < 40.0,
			"it lands on a part in about %.1f s" % Mecha.TICK_JUMP_TIME)
	mecha.global_position += Vector2(300, 0)
	check(mecha.tick_position(tick).distance_to(mecha.get_part_global_position(tick.part)) < 40.0, "and moves with the mecha")


func _test_tick_effects() -> void:
	var mecha := _mecha(Vector2.ZERO, 100.0)
	var control := _mecha(Vector2(3000, 0), 100.0)
	var before := mecha.get_thermal_signature()
	mecha.attach_tick(1, _arena, Vector2(0, 200), 30.0)
	check(is_equal_approx(mecha.get_thermal_signature(), before + Mecha.TICK_GLOW), "a tick adds %.1f to the signature" % Mecha.TICK_GLOW)
	mecha.internal_temp = 40.0
	control.internal_temp = 40.0
	await wait_seconds(2.0)
	var drained := control.external_temp - mecha.external_temp
	var expected := Mecha.TICK_DRAIN * 2.0 / mecha.external_capacity
	check(drained > expected * 0.5, "it drains the external layer (%.1f °C more than without, about %.1f expected)" % [drained, expected])
	check(absf(control.internal_temp - mecha.internal_temp) < 1.0, "not the internal one")
	var tick: Mecha.Tick = mecha.ticks[0]
	var armor_before: Dictionary = mecha.armor.duplicate(true)
	var log := _damage_log(mecha)
	for _i in 12:
		mecha._tick_bite(tick)
	var plates := 0
	for facing in mecha.armor[tick.part]:
		plates += armor_before[tick.part][facing].pips - mecha.armor[tick.part][facing].pips
	check(plates > 0 or not log.is_empty(), "its bites strip armour or damage components")
	check(log.all(func(e): return e[0] == tick.part and "external" in mecha.components[e[0]][e[1]].tags),
			"only external components of the part it's on")
	for part in mecha.armor:
		if part != tick.part:
			check(mecha.armor[part] == armor_before[part], "and only that part's armour (%s untouched)" % part)
	check_eq(mecha.get_tick_count(), 1, "its own bites don't shake it off")


func _test_tick_shake() -> void:
	var mecha := _mecha(Vector2.ZERO)
	for k in 6:
		mecha.attach_tick(k + 1, _arena, Vector2(0, 200), 30.0)
	mecha.damage_component("core", "radiator", 1, Vector2.DOWN)
	check_eq(mecha.get_tick_count(), 5, "one point of damage shakes one off")
	var pen := mecha.armor_check("core", mecha.global_position + Vector2(0, 80), Vector2.UP, 10, 1, true)
	if pen.penetrated and pen.component_name != "":
		mecha.damage_component(pen.part_name, pen.component_name, 1, Vector2.UP)
	check_eq(mecha.get_tick_count(), 2, "a blast's point shakes off three")
	mecha.external_temp = 0.0
	await wait_seconds(0.5)
	check_eq(mecha.get_tick_count(), 2, "cooling down doesn't")


func _test_tick_brood() -> void:
	var mecha := _mecha(Vector2.ZERO)
	for duration in [0.6, 1.4, 5.0]:
		mecha.attach_tick(7, _arena, Vector2(0, 200), duration)
	var times := mecha.ticks.map(func(t): return t.time_left)
	var middle: float = times[1]
	check(times.all(func(t): return absf(t - middle) <= Mecha.TICK_SYNC_SPREAD + 0.001), "three from one swarm sync within ±1 s (%s)" % str(times))
	check(mecha.ticks.all(func(t): return t.synced), "they're synced")
	var broods := func(): return _arena.entities.filter(func(e): return e is TickSwarm and is_instance_valid(e) and not e.is_dead)
	var formed := await wait_until(func(): return not broods.call().is_empty(), 4.0)
	if not check(formed, "when the middle one drops off, a brood forms"):
		return
	var brood: TickSwarm = broods.call()[0]
	check(brood.brood and brood.global_position.distance_to(mecha.global_position) < brood.patch_radius, "on the ground where the mecha is")
	var joined := await wait_until(func(): return mecha.get_tick_count() == 0 and brood.get_mote_count() == 3, 4.0)
	check(joined, "the group's last one joins it as it drops off (%d motes)" % brood.get_mote_count())
	check(brood.brood_time == 30.0, "it hatches after 30 s")
	# Out of the way, so the hatched swarm has nothing to jump on.
	mecha.global_position = Vector2(-6000, 0)
	mecha.external_temp = 0.0
	brood._brood_t = brood.brood_time - 0.05
	await _physics_frames(4)
	check(not brood.brood and brood.get_mote_count() == 6, "then each mote spawns one and it's a normal swarm (%d)" % brood.get_mote_count())
	# Shaken below three before the middle one goes: no brood.
	var other := _mecha(Vector2(3000, 0))
	for duration in [0.6, 1.0, 1.2]:
		other.attach_tick(8, _arena, Vector2(3000, 200), duration)
	other.damage_component("core", "radiator", 1, Vector2.DOWN)
	var near_other := func(): return broods.call().filter(func(s): return s.global_position.distance_to(other.global_position) < 1000.0)
	await wait_seconds(2.5)
	check(other.get_tick_count() == 0 and near_other.call().is_empty(), "a group shaken below three forms none")


func _test_swarm_disperse() -> void:
	var swarm := _swarm(Vector2.ZERO)
	check_eq(swarm.disperse_time, 60.0, "a minute")
	_place_motes(swarm, [Vector2(-20, 0), Vector2(0, 0), Vector2(20, 0)])
	swarm.disperse_time = 2.0
	await wait_seconds(1.0)
	check(not swarm.is_dead, "it waits")
	var gone := await wait_until(func(): return swarm.is_dead, 3.0)
	check(gone, "then disperses")
	var brood: TickSwarm = TickSwarm.spawn_brood(_arena, Vector2(2000, 0), [Vector2(2000, 0)])
	brood.disperse_time = 0.5
	await wait_seconds(1.5)
	check(not brood.is_dead, "a brood doesn't")


func _test_swarm_cap() -> void:
	var director: Node = DIRECTOR.new()
	director.arena = _arena
	add_child(director)
	_arena.ExpeditionDirector = director
	var old := _swarm(Vector2(-3000, 0), true)
	var young := _swarm(Vector2(3000, 0), true)
	director.entity_population_cap = _arena.entities.size()
	var brood: TickSwarm = TickSwarm.spawn_brood(_arena, Vector2(0, 3000), [Vector2(0, 3000), Vector2(10, 3000)])
	check(brood != null and brood.brood and brood.get_mote_count() == 2, "the brood forms")
	check(old.is_dead and not young.is_dead, "the oldest swarm nobody sees fades out for it")
	_arena.ExpeditionDirector = null
	director.queue_free()


func _test_frenzy() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var stop := _keep_hot(mecha)
	var coyote: Coyote = _spawn(COYOTE, Vector2(600, 0))
	coyote.acquire_target(mecha)
	await _physics_frames(2)
	check(not coyote.frenzied, "no ticks, no frenzy")
	mecha.attach_tick(1, _arena, Vector2(0, 200), 30.0)
	await _physics_frames(2)
	check(coyote.frenzied, "ticks on its prey: frenzy")
	check(is_equal_approx(coyote.speed_mult(), 1.25) and is_equal_approx(coyote.attack_gap_mult(), 0.5),
			"25% faster, half the time between attacks")
	check(coyote.coyote_body.frenzy, "its sand shows it")
	coyote.take_hit(6.0, 5, Vector2.ZERO, {"body": mecha, "name": "Shooter"})
	check(coyote.state != Coyote.State.FLEE, "badly hurt, it doesn't flee")
	stop.call()


# ---- Scavenging ----

func _wreck_of(mecha: Mecha) -> Wreck:
	var wreck: Wreck = WRECK.instantiate()
	wreck.position = mecha.global_position
	wreck.setup(mecha.mecha_name, [])
	wreck.copy_mecha_visuals(mecha)
	_arena.add_child(wreck)
	_arena.mechas.erase(mecha)
	mecha.queue_free()
	return wreck


func _test_scavenge_wreck() -> void:
	var wreck := _wreck_of(_mecha(Vector2.ZERO, 0.0))
	await wait_frames(2)
	var before := wreck.body.takeable_slots()
	check(before.has("left_shoulder") and before.has("arm_weapon_left"), "the wreck has shoulders and arm weapons to take")
	var pack := [_spawn(COYOTE, Vector2(900, 0)), _spawn(COYOTE, Vector2(950, 100)), _spawn(COYOTE_SPITTER, Vector2(950, -100))]
	_pack(pack)
	var took := await wait_until(func(): return pack.any(func(c): return not c.gun.is_empty() or not c.shield.is_empty()), 15.0)
	if not check(took, "a wandering Coyote goes and takes a part"):
		return
	await wait_frames(2)
	check(not wreck.body.taken_slots.is_empty(), "the wreck loses it (%s)" % str(wreck.body.taken_slots))
	check(wreck.body.taken_slots.all(func(s): return not s in wreck.body.takeable_slots() and not s in wreck.body.get_part_slots()),
			"it's gone from the body")
	check(not wreck.body.taken_slots.any(func(s): return s.begins_with("shoulder_weapon")), "never a shoulder weapon")
	var carrier: Coyote = pack.filter(func(c): return not c.gun.is_empty() or not c.shield.is_empty())[0]
	check(carrier.coyote_body._gun_sprite != null or carrier.coyote_body._shield_sprite != null, "it carries the part's own sprite")


# A Coyote with a shield wants only a gun: both arm weapons lie shed on the
# ground, and it takes one of them.
func _test_scavenge_shed() -> void:
	var wreck := _wreck_of(_mecha(Vector2.ZERO, 0.0))
	await wait_frames(2)
	wreck.body.shed("arm_weapon_left", false)
	wreck.body.shed("arm_weapon_right", false)
	var listed := wreck.unsalvageable.map(func(e): return e.slot)
	check_eq(listed, ["arm_weapon_left", "arm_weapon_right"], "the shed arm weapons are listed unsalvageable")
	var coyote: Coyote = _spawn(COYOTE, Vector2(700, 0))
	coyote.shield = {"part_id": PlayerProgress.DEFAULT_MECHA.shoulders, "texture": null, "level": 1, "pips": 3}
	var took := await wait_until(func(): return not coyote.gun.is_empty(), 15.0)
	if not check(took, "it goes and picks a shed arm weapon up"):
		return
	var taken: Array = wreck.body.taken_slots.filter(func(s): return s.begins_with("arm_weapon"))
	check(taken.size() == 1 and taken[0] in wreck.body.shed_slots, "one that was lying on the ground (%s)" % str(taken))
	check_eq(wreck.unsalvageable.map(func(e): return e.slot), listed.filter(func(s): return not s in taken),
			"it's gone from the unsalvageable list; the other stays")
	check(not wreck.body.taken_slots.has("left_shoulder") and not wreck.body.taken_slots.has("right_shoulder"),
			"with its shield already held, it leaves the shoulders")


func _test_scavenge_lost_part() -> void:
	var mecha := _mecha(Vector2.ZERO, 0.0)
	var added := []
	_arena.child_entered_tree.connect(func(n): if n is MechaBody: added.append(n))
	check(mecha.lose_part("left_shoulder"), "a live mecha loses its left shoulder")
	await wait_frames(2)
	if not check(added.size() == 1, "it lies on the ground beside the mecha"):
		return
	var debris: MechaBody = added[0]
	check(debris.is_in_group(MechaBody.SCAVENGE_GROUP), "where scavengers can find it")
	check(debris.takeable_slots().has("left_shoulder") and debris.takeable_slots().has("arm_weapon_left"),
			"the shoulder and its arm weapon can be taken (%s)" % str(debris.takeable_slots()))
	mecha.global_position = Vector2(-6000, 0)
	var coyote: Coyote = _spawn(COYOTE, debris.global_position + Vector2(700, 0))
	var took := await wait_until(func(): return not coyote.gun.is_empty() or not coyote.shield.is_empty(), 15.0)
	check(took, "a wandering Coyote picks it up")
	check(not debris.taken_slots.is_empty(), "off the ground (%s)" % str(debris.taken_slots))


func _test_glob_look() -> void:
	var mecha := _mecha(Vector2.ZERO)
	var glob: AcidGlob = AcidGlob.new()
	glob.color = Color(0.12, 0.12, 0.12)
	_arena.add_child(glob)
	var splashes := []
	glob.splashed.connect(func(g, _hit): splashes.append(g.get_splash()))
	glob.launch(null, _arena, Vector2(-600, 0), mecha.global_position, 1.2)
	await _physics_frames(2)
	check(glob.get_splash() == null, "in flight, no splash yet")
	check(glob._heading > -PI * 0.5 and glob._heading < 0.0, "rising, the drop heads up and along (%.2f rad)" % glob._heading)
	var landed := await wait_until(func(): return not splashes.is_empty(), 3.0)
	if not check(landed, "it lands"):
		return
	var splash: CPUParticles2D = splashes[0]
	check(splash != null and splash.emitting and splash.one_shot, "and bursts into a spray of droplets")
	if splash == null:
		return
	check(splash.texture != null and splash.texture.get_size() == AcidGlob.DROPLET.get_size(), "each one the blood droplet sprite")
	check(splash.particle_flag_align_y and splash.spread >= 180.0, "pointing the way it flies, all round")
	check(splash.color.is_equal_approx(glob.color), "in the glob's colour")


func _test_rip_flagged() -> void:
	var mecha := _mecha(Vector2.ZERO)
	mecha.raise_flag()
	var coyote: Coyote = _spawn(COYOTE, Vector2(-150, 0), true)
	coyote.target = mecha
	coyote._set_state(Coyote.State.STRIKE)
	coyote._on_bite_closed()
	var held := coyote.gun if not coyote.gun.is_empty() else coyote.shield
	check(not held.is_empty() and coyote.bites == 0, "it tears a part off instead of biting")
	var taken := "arm_weapon_left" if not coyote.gun.is_empty() else "left_shoulder"
	check(mecha.is_part_lost(taken), "the mecha loses it (%s)" % taken)
	if taken == "left_shoulder":
		check(mecha.is_part_lost("arm_weapon_left"), "a shoulder takes its arm weapon with it")
	var other: Coyote = _spawn(COYOTE, Vector2(-150, 0), true)
	other.gun = {"part_id": "x", "weapon": null, "texture": null}
	other.shield = {"part_id": "x", "texture": null, "level": 1, "pips": 1}
	check_eq(other.rip_part(mecha), "", "with no hand free it takes nothing")
	mecha.lower_flag()
	var biter: Coyote = _spawn(COYOTE, Vector2(-150, 0), true)
	await wait_seconds(Mecha.FLAG_LOWER_TIME + 0.2)
	biter.target = mecha
	biter._set_state(Coyote.State.STRIKE)
	biter._on_bite_closed()
	check(biter.bites == 1 and biter.gun.is_empty() and biter.shield.is_empty(), "a mecha that isn't Flagged just gets bitten")


func _test_shield() -> void:
	var coyote: Coyote = _spawn(COYOTE, Vector2.ZERO, true)
	coyote.max_hp = 100.0
	coyote.hp = 100.0
	coyote._carry({"slot": "left_shoulder", "part_id": PlayerProgress.DEFAULT_MECHA.shoulders, "texture": null,
			"armor": {"level": 2, "pips": 2}})
	check_eq(coyote.shield.pips, 2, "a shield with the shoulder's front pips")
	# It faces +X: a hit travelling -X comes at its front.
	coyote.take_hit(2.0, 1, Vector2.LEFT)
	check_eq(coyote.hp, 99.0, "from the front, a hit below the shoulder's armour does half")
	check_eq(coyote.shield.pips, 1, "and strips a pip")
	coyote.take_hit(2.0, 1, Vector2.RIGHT)
	check_eq(coyote.hp, 97.0, "from behind, its own armour counts")
	check_eq(coyote.shield.pips, 1, "and the shield isn't touched")
	coyote.take_hit(2.0, 1, Vector2.UP)
	check_eq(coyote.shield.pips, 1, "nor from the side")
	coyote.take_hit(2.0, 2, Vector2.LEFT)
	check_eq(coyote.hp, 93.0, "with enough pen, full damage")
	check(coyote.shield.is_empty(), "at 0 pips it breaks and drops")


func _test_gun() -> void:
	var mecha := _mecha(Vector2(0, -700))
	var stop := _keep_hot(mecha)
	var coyote: Coyote = _spawn(COYOTE, Vector2.ZERO)
	var weapon_id: String = PlayerProgress.DEFAULT_MECHA.arm_weapon_left
	coyote._carry({"slot": "arm_weapon_left", "part_id": weapon_id, "texture": null})
	if not check(not coyote.gun.is_empty(), "it holds the gun"):
		stop.call()
		return
	var rounds := []
	_arena.child_entered_tree.connect(func(n): if n.get("original_mecha_info") != null: rounds.append(n))
	coyote.acquire_target(mecha)
	var fired := await wait_until(func(): return not rounds.is_empty(), 6.0)
	stop.call()
	if not check(fired, "it fires while it circles"):
		return
	var round = rounds[0]
	check(round.original_mecha_info.body == coyote and round.part_id == weapon_id, "the weapon's own round, credited to the Coyote")
	var weapon = coyote.gun.weapon
	var fresh = weapon.projectile.instantiate()
	check(round.base_damage == fresh.base_damage, "at the weapon's damage")
	fresh.free()
	var start: Vector2 = coyote.global_position
	var hp_before := coyote.hp
	var impact := _impact_of(round)
	var landed := await wait_until(func(): return impact[0] != null, 3.0)
	check(landed, "the round goes somewhere")
	var reached: float = (impact[0] as Vector2).distance_to(start) if landed else 0.0
	check(reached > 200.0, "it flies out past the Coyote, to %.0f px" % reached)
	check(is_equal_approx(coyote.hp, hp_before), "the Coyote doesn't shoot itself")
	coyote.set_pause(true)
	coyote._gun_left = weapon.clip_size
	for _i in weapon.clip_size:
		coyote.fire_gun()
	check(is_equal_approx(coyote._gun_cool, weapon.reload_speed), "a magazine's worth, then it waits the reload time")
	# A packmate right in the line of fire: the rounds go through it.
	await wait_seconds(0.5)
	var to_prey: Vector2 = mecha.global_position - coyote.global_position
	var mate: Coyote = _spawn(COYOTE, coyote.global_position + to_prey * 0.4, true)
	var mate_hp := mate.hp
	rounds.clear()
	coyote.gun_spread = 0.0
	coyote.fire_gun()
	await _physics_frames(1)
	var shot_impact := _impact_of(rounds.back()) if not rounds.is_empty() else [null]
	await wait_until(func(): return shot_impact[0] != null, 2.0)
	check(is_equal_approx(mate.hp, mate_hp), "a packmate in the line of fire isn't hit")
	check(shot_impact[0] != null and (shot_impact[0] - coyote.global_position).length() > to_prey.length() * 0.6,
			"the round flies on past it")


# Where a round ends (its bullet_impact as it dies); [null] until then.
func _impact_of(round) -> Array:
	var at := [null]
	round.bullet_impact.connect(func(projectile, _effect, clear, _body):
		if clear:
			at[0] = projectile.global_position)
	return at


func _test_scavenged_loot() -> void:
	var coyote: Coyote = _spawn(COYOTE, Vector2.ZERO, true)
	coyote._carry({"slot": "arm_weapon_right", "part_id": PlayerProgress.DEFAULT_MECHA.arm_weapon_right, "texture": null})
	coyote._carry({"slot": "right_shoulder", "part_id": PlayerProgress.DEFAULT_MECHA.shoulders, "texture": null,
			"armor": {"level": 2, "pips": 3}})
	coyote.die()
	var carcass: Carcass = CARCASS.instantiate()
	carcass.setup_from(coyote)
	_arena.add_child(carcass)
	var parts := carcass.inventory.get_stacks().filter(func(s): return s.kind == item_stack.ItemKind.PART)
	check(parts.any(func(s): return s.item_type == "arm_weapon" and s.item_id == PlayerProgress.DEFAULT_MECHA.arm_weapon_right),
			"its gun is in the carcass")
	check(parts.any(func(s): return s.item_type == "shoulders" and s.item_id == PlayerProgress.DEFAULT_MECHA.shoulders),
			"and its shield")


# ---- Senses and the player's view ----

# Sweeps and the Biosensor go by species. The player's view fades a body out
# (its modulate); what the sand species and ticks leave or carry fades with it: ticks
# on a mecha and parts a Coyote carries are drawn under them, and a death
# burst or a Fisher's shell dropped while hidden stays hidden.
func _test_sensed_and_seen() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["internal"] = "BS-1"
	var mecha := _mecha(Vector2.ZERO, 0.0, design)
	mecha.internal_on = true
	var coyote: Coyote = _spawn(COYOTE, Vector2(0, -500), true)
	var fisher: Fisher = _spawn(FISHER, Vector2(300, -500), true)
	var swarm: TickSwarm = _swarm(Vector2(-400, -500), true)
	mecha._update_biosensor(mecha.build.internal.update_interval + 1.0)
	for entity in [coyote, fisher, swarm]:
		var seen: Dictionary = mecha.contacts.best_for(entity)
		check(not seen.is_empty() and seen.kind == entity.species, "the Biosensor reports a %s" % entity.species)
	var result := mecha.sweep(Vector2.UP, 360.0)
	check(result.ok and result.counts.get("Coyote") == 1 and result.counts.get("Fisher") == 1 and result.counts.get("Tick Swarm") == 1,
			"a sweep counts each species (%s)" % Mecha.describe_sweep(result.counts))
	check("TICK SWARM" in Mecha.describe_sweep(result.counts), "by name")
	mecha.attach_tick(swarm.group_id, _arena, Vector2(0, 200), 30.0)
	check(mecha._tick_layer != null and mecha._tick_layer.get_parent() == mecha, "ticks on a mecha are drawn under it")
	coyote._carry({"slot": "arm_weapon_left", "part_id": design.arm_weapon_left, "texture": mecha.LeftArmWeaponMain.texture})
	var gun_sprite: Sprite2D = coyote.coyote_body._gun_sprite
	check(gun_sprite != null and coyote.is_ancestor_of(gun_sprite), "a carried part is drawn under its Coyote")
	coyote.modulate.a = 0.0
	coyote.die()
	check(coyote.coyote_body._death.modulate.a == 0.0, "a death burst out of sight stays hidden")
	fisher.modulate.a = 0.0
	fisher.die()
	check(fisher.fisher_body._shell.modulate.a == 0.0, "and so does a Fisher's dropped shell")