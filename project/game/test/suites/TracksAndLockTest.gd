extends TestSuite

# TracksAndLockTest: wedge tracks, locks and the radar.
#   - Wedges (ContactStore): shot, sound and lock wedges, their bearing,
#     width, range band and estimate point (drawn round the truth, the source
#     always inside), ageing into ghosts, no body; none for a source in sight.
#   - An NPC goes by a wedge's estimate point, not the shooter's position.
#   - The player's lock: nothing before the settle, the reveal at it, a reset
#     when the reticle leaves, no start in smoke or past the sight circle,
#     each break, and a lock that isn't sight.
#   - The lock warning: the target's wedge narrowing to a line, LOCKING and
#     LOCKED, the beep quickening.
#   - An NPC's lock: refused with no reason or with the target outside it,
#     the search time by skill, the slip only with no live track, no search
#     with one; direct lock-on rounds held behind walls.
#   - RCS (RadarCrossSection): facing widths, the largest-plus-fraction sum, a
#     part shot off, the reference, the signature multiplier.
#   - Sweeps: kinds by relative RCS, aspect, ticks one by one, a decoy.
#   - The radar: each mark, stacking, nothing without a track; the chipset's
#     radar stats gone.
#
# Mechas are held still (no physics) and stepped by hand.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const CLOUD := preload("res://game/weapons/SmokeCloud.tscn")
const TICKS := preload("res://game/entities/tick/TickSwarm.tscn")
const RADAR := preload("res://game/ui/player_radar/PlayerRadar.tscn")
const HUD := preload("res://game/ui/PlayerHUD.gd")
const VLS := "TORI-V4"
const CLUSTER := "TORI-ML"
# A generated building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]
const TRIALS := 25


class FakeArena extends Node2D:
	var mechas: Array = []
	var entities: Array = []
	var player = null
	var ExpeditionDirector = null
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return entities
	func get_lock_areas() -> Array:
		return mechas.filter(func(m): return is_instance_valid(m)).map(func(m): return m.get_lock_area())
	func get_safe_position() -> Vector2:
		return Vector2(-9000, -9000)
	func get_random_position() -> Vector2:
		return Vector2.ZERO
	func add_entity(scene: PackedScene, pos: Vector2) -> Entity:
		var entity: Entity = scene.instantiate()
		entity.position = pos
		add_child(entity)
		entity.setup(self)
		entities.append(entity)
		return entity


var _arena: FakeArena = null
var _player = null
var _saved_factors := {}
var _saved_chipset := {}


func run_tests() -> void:
	await case("shot, sound and lock wedges: bearing, width, band, estimate, ageing", _test_wedges)
	await case("an NPC goes by the estimate point, not the shooter", _test_npc_estimate)
	await case("the player's lock: the settle, the reveal, a reset, smoke, the circle", _test_player_lock)
	await case("a made lock breaks, and isn't sight", _test_lock_breaks)
	await case("the lock warning narrows; LOCKING, LOCKED and the beep", _test_warning)
	await case("an NPC's lock: reasons, the search, the slip", _test_npc_lock)
	await case("direct lock-on rounds count as AP 0 against walls", _test_lock_walls)
	await case("RCS: facing widths, the sum, a part shot off, the reference", _test_rcs)
	await case("the signature multiplier takes the larger of heat and RCS", _test_signature)
	await case("sweeps report kinds by RCS, ticks one by one, decoys as mechs", _test_sweeps)
	await case("the radar draws tracks only, each mark, stacked", _test_radar)
	await case("the chipset's radar stats are gone", _test_chipset)
	await before_each()


func before_each() -> void:
	_restore()
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	_player = _mecha(Vector2(-4000, 4000), PLAYER)
	_player.mecha_name = "Player"
	_player.arena = _arena
	_arena.player = _player
	_arena.mechas.erase(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mecha(pos: Vector2, scene: PackedScene = MECHA, design: Dictionary = PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_physics_process(false)
	mecha.set_parts_from_design(design)
	mecha.global_rotation = 0.0
	mecha.set_illuminator(false)
	mecha.external_temp = 0.0
	_arena.mechas.append(mecha)
	return mecha


func _enemy(pos: Vector2, design: Dictionary = PlayerProgress.DEFAULT_MECHA) -> Mecha:
	var enemy: Mecha = ENEMY.instantiate()
	enemy.position = pos
	_arena.add_child(enemy)
	enemy.setup(_arena, design, "Lock test")
	enemy.set_scripted(false)
	enemy.paused = true
	enemy.auto_illuminator = false
	enemy.set_illuminator(false)
	enemy.global_rotation = 0.0
	_arena.mechas.append(enemy)
	return enemy


# Sets every outlined part's rcs_factor on `mecha` (parts are shared), put
# back by before_each.
func _set_factor(mecha, factor: float) -> void:
	for slot in ["core", "head", "shoulders", "chassis"]:
		var part = mecha.build.get(slot)
		if part == null:
			continue
		if not _saved_factors.has(part):
			_saved_factors[part] = part.rcs_factor
		part.rcs_factor = factor
	mecha._stats_changed()


func _set_lock_speed(mecha, speed: float) -> void:
	var chipset = mecha.build.chipset
	if not _saved_chipset.has(chipset):
		_saved_chipset[chipset] = chipset.lock_on_speed
	chipset.lock_on_speed = speed


func _restore() -> void:
	for part in _saved_factors:
		part.rcs_factor = _saved_factors[part]
	_saved_factors.clear()
	for chipset in _saved_chipset:
		chipset.lock_on_speed = _saved_chipset[chipset]
	_saved_chipset.clear()


func _angle_off(wedge: Dictionary, point: Vector2) -> float:
	return absf(rad_to_deg(angle_difference(float(wedge.bearing), (point - Vector2(wedge.origin)).angle())))


func _test_wedges() -> void:
	var me := _mecha(Vector2(3000, 3000))
	var shooter := _mecha(me.global_position + Vector2(2000, -1000))
	var from: Vector2 = shooter.global_position
	var distance := me.global_position.distance_to(from)
	var inside := true
	var off := 0
	var estimates := {}
	for i in TRIALS:
		var guess: Vector2 = me.note_round_from(shooter, from)
		var wedge: Dictionary = me.contacts.wedges({"source": "shot"})[0]
		inside = inside and ContactStore.wedge_contains(wedge, from)
		off += int(guess.distance_to(from) > 1.0)
		estimates[guess.round()] = true
		if i == 0:
			check_eq(guess, ContactStore.estimate_point(wedge), "what it makes out is the wedge's estimate point")
	var wedge: Dictionary = me.contacts.wedges({"source": "shot"})[0]
	check_eq(me.contacts.wedges({"source": "shot"}).size(), 1, "one shooter keeps one shot wedge")
	check_eq(wedge.width, ContactStore.WEDGES.shot.width, "a shot wedge is %.0f degrees wide" % ContactStore.WEDGES.shot.width)
	check(inside, "the shooter is inside it every time")
	check(off == TRIALS and estimates.size() > TRIALS / 2, "its estimate point is a guess, never the shooter, and it changes shot to shot")
	check(_angle_off(wedge, from) <= wedge.width * 0.5, "its bearing within half its width of the truth")
	var centre := (float(wedge.min_range) + float(wedge.max_range)) * 0.5
	check(absf(centre - distance) <= distance * ContactStore.WEDGE_BAND_JITTER + 1.0, "its band centred within 25% of the distance")
	check(is_equal_approx(float(wedge.max_range) / float(wedge.min_range), 1.4 / 0.6), "the band ±40% of its centre")
	check(not wedge.has("body"), "a wedge has no body")
	check(me.contacts.query({"source": "shot"}).is_empty() and me.contacts.best_for(shooter).is_empty(),
			"and no query or best_for hands it out")
	check(wedge.live, "live")
	me.contacts.advance(ContactStore.WEDGES.shot.ttl + 0.1)
	check(not me.contacts.wedges({"source": "shot"})[0].live, "a ghost after %.0f s" % ContactStore.WEDGES.shot.ttl)
	me.contacts.advance(me.contacts.ghost_time)
	check(me.contacts.wedges().is_empty(), "and gone after its ghost time")

	var loud := _mecha(me.global_position + Vector2(-1500, 0))
	var heard: Vector2 = me.note_sound_from(loud, loud.global_position)
	var sound: Dictionary = me.contacts.wedges({"source": "sound"})[0]
	check_eq(sound.width, ContactStore.WEDGES.sound.width, "a sound wedge is %.0f degrees wide" % ContactStore.WEDGES.sound.width)
	check(ContactStore.wedge_contains(sound, loud.global_position) and heard == ContactStore.estimate_point(sound), "round the sound, the guess its middle")

	me.contacts.report(shooter, "mech", from, "sight", 1.0)
	check_eq(me.note_round_from(shooter, from), from, "a shooter in sight is where it is")
	check(me.contacts.wedges({"source": "shot"}).is_empty(), "and makes no wedge")

	var locker := _mecha(me.global_position + Vector2(0, -2500))
	locker._warn_target(me, 0.0)
	var lock: Dictionary = me.contacts.wedges({"source": "lock"})[0]
	check(is_equal_approx(lock.width, ContactStore.WEDGES.lock.width), "a lock wedge starts %.0f degrees wide" % ContactStore.WEDGES.lock.width)
	check(lock.min_range == 0.0 and is_inf(lock.max_range), "with no range")
	check(ContactStore.wedge_contains(lock, locker.global_position), "toward the locker")
	var first_bearing: float = lock.bearing
	locker._warn_target(me, 0.5)
	check(is_equal_approx(lock.width, ContactStore.WEDGES.lock.width * 0.5), "half as wide at half the lock")
	locker._warn_target(me, 1.0)
	check(lock.width == 0.0 and _angle_off(lock, locker.global_position) < 0.01, "a line onto the locker once locked")
	check(absf(angle_difference(first_bearing, lock.bearing)) <= deg_to_rad(ContactStore.WEDGES.lock.width * 0.5),
			"narrowing onto it, not jumping about")
	check(ContactStore.estimate_point(lock).distance_to(me.global_position + Vector2.from_angle(lock.bearing) * ContactStore.UNKNOWN_RANGE_ESTIMATE) < 1.0,
			"with no range, its estimate point is UNKNOWN_RANGE_ESTIMATE out")
	me.contacts.advance(ContactStore.WEDGES.lock.ttl + 0.1)
	check(not lock.live, "a lock wedge lingers %.0f s once it stops" % ContactStore.WEDGES.lock.ttl)


func _test_npc_estimate() -> void:
	var npc := _enemy(Vector2(3000, -3000))
	var shooter := _mecha(npc.global_position + Vector2(0, -2400))
	npc.mark_traitor(shooter)
	var fired_from: Vector2 = shooter.global_position
	npc._took_round(shooter, fired_from)
	var wedges: Array = npc.contacts.wedges({"source": "shot"})
	check_eq(wedges.size(), 1, "a round from an unseen shooter is a shot wedge")
	if wedges.is_empty():
		return
	var guess := ContactStore.estimate_point(wedges[0])
	check(guess.distance_to(fired_from) > 1.0, "whose estimate point isn't the shooter's position")
	check_eq(npc.last_attack_position, guess, "the NPC goes to where it makes out the shot came from")
	check(npc.knowledge.recent_fire_positions().has(guess), "fire taken is kept at the estimate point")
	var contact: Dictionary = npc.contacts.query({"body": shooter, "source": "shot"})[0] if not npc.contacts.query({"body": shooter, "source": "shot"}).is_empty() else {}
	check(not contact.is_empty() and contact.position == guess, "and so is its shot contact")
	check(is_same(npc.most_recent_attacker, shooter), "who fired still counts (its threat score, hostility)")
	check(not npc.round_comes_close(npc.global_position + Vector2(Mecha.SHOT_WEDGE_RADIUS * 2.0, -2000), Vector2.DOWN),
			"a round passing wide isn't fire taken")
	check(npc.round_comes_close(npc.global_position + Vector2(Mecha.SHOT_WEDGE_RADIUS * 0.5, -2000), Vector2.DOWN),
			"one passing within %.0f px is" % Mecha.SHOT_WEDGE_RADIUS)
	check(not npc.round_comes_close(npc.global_position + Vector2(0, -2000), Vector2.UP), "one flying away isn't")


func _test_player_lock() -> void:
	var target := _mecha(_player.global_position + Vector2(0, -1500))
	_player.cur_mode = _player.MODES.LOCK
	var at: Vector2 = target.get_lock_area().global_position
	_player.update_locking(Mecha.LOCK_SETTLE_TIME * 0.5, at)
	check(not _player.get_locking_to(), "nothing before the settle")
	check(target.contacts.wedges({"source": "lock"}).is_empty() and target.lock_warning().is_empty(), "no warning either")
	_player.update_locking(Mecha.LOCK_SETTLE_TIME * 0.6, at)
	check(_player.get_locking_to() and is_same(_player.get_locking_to().mecha, target), "the reveal: locking starts once the reticle has settled")
	_player.update_locking(0.05, at)
	check(_player.get_locking_to().progress > 0.0, "and runs while the reticle stays")
	check(not target.lock_warning().is_empty(), "the target is warned from the start")
	_player.update_locking(0.05, at + Vector2(3000, 0))
	check(not _player.get_locking_to(), "the reticle off it: the progress is lost")
	_player.update_locking(Mecha.LOCK_SETTLE_TIME * 0.5, at)
	check(not _player.get_locking_to(), "and the settle starts again")
	_player.update_locking(Mecha.LOCK_SETTLE_TIME * 0.6, at)
	for i in 60:
		_player.update_locking(0.1, at)
	check(is_same(_player.get_locked_to(), target), "held long enough, it locks")
	_player.break_lock()

	var cloud: Node2D = CLOUD.instantiate()
	cloud.position = target.global_position
	cloud.lifetime = 15.0
	_arena.add_child(cloud)
	var thick := await wait_until(func(): return cloud.is_thick(), 3.0)
	check(thick, "(a thick cloud on the target)")
	check(not _player.can_start_lock(target), "no lock starts on a mech in smoke")
	cloud.global_position = _player.global_position.lerp(target.global_position, 0.5)
	await get_tree().physics_frame
	check(not _player.can_start_lock(target), "or behind it")
	cloud.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(_player.can_start_lock(target), "with the smoke gone, it can")
	target.global_position = _player.global_position + Vector2(0, -(_player.sight_radius() + 200.0))
	check(not _player.can_start_lock(target), "but not past the sight circle")


func _test_lock_breaks() -> void:
	var target := _mecha(Vector2(800, 200))
	_player.global_position = Vector2(-1200, 200)
	_player.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	_player.set_illuminator(false)
	var made := func():
		_player.break_lock()
		_player.locking_to = {"progress": 1.0, "mecha": target}
		_player._advance_lock(0.01)
		_player.lock_on_duration = 1000.0
		return is_same(_player.get_locked_to(), target)
	check(made.call(), "(locked on a mech behind the building)")
	_player._check_lock_breaks()
	check(not _player.contacts.query({"body": target, "source": "lock"}).is_empty(), "a made lock is a live lock contact")
	check(not _player.can_see_body(target), "but not sight: the mech behind the building stays hidden")
	check(_player.contacts.query({"body": target, "source": "lock"})[0].reveal == "ping", "a marker shows where it is")

	target.global_position = _player.global_position + Vector2(_player.sight_radius() + 300.0, 0)
	_player._check_lock_breaks()
	check(not _player.get_locked_to(), "it breaks when the target leaves the sight circle")
	target.global_position = Vector2(800, 200)
	made.call()
	target.is_dead = true
	_player._check_lock_breaks()
	check(not _player.get_locked_to(), "when the target dies")
	target.is_dead = false
	made.call()
	_player._on_enter_lock_mode()
	check(not _player.get_locked_to(), "when lock mode is entered again")
	made.call()
	_player.lock_on_duration = 0.5
	_player.lock_timer = 0.6
	_player.set_physics_process(true)
	await get_tree().physics_frame
	_player.set_physics_process(false)
	check(not _player.get_locked_to(), "when the chipset's lock_on_duration runs out")
	made.call()
	target.ecm = 1000.0
	target.ecm_frequency = 1.0
	var broke := false
	for i in 20:
		_player.ecm_attempt_cooldown = 0.0
		_player._check_lock_breaks()
		if not _player.get_locked_to():
			broke = true
			break
	check(broke, "when an ECM roll succeeds")
	target.ecm = 0.0
	made.call()
	var cloud: Node2D = CLOUD.instantiate()
	cloud.position = target.global_position
	_arena.add_child(cloud)
	await wait_until(func(): return cloud.is_thick(), 3.0)
	_player._check_lock_breaks()
	check(is_same(_player.get_locked_to(), target), "smoke doesn't break a lock already made")
	cloud.queue_free()


func _test_warning() -> void:
	var locker := _mecha(_player.global_position + Vector2(1500, 0))
	check(_player.lock_warning().is_empty(), "no warning with nobody locking")
	locker._warn_target(_player, 0.3)
	var warning: Dictionary = _player.lock_warning()
	check(not warning.is_empty() and warning.state == "locking" and is_equal_approx(warning.progress, 0.3), "LOCKING at 30%")
	check(is_equal_approx(warning.wedge.width, ContactStore.WEDGES.lock.width * 0.7), "its wedge 70% of its full width")
	var alerts := HudAlerts.new()
	add_child(alerts)
	alerts.setup(_player)
	alerts._process(0.0)
	check(alerts.get_current() == "! LOCKING", "the HUD says LOCKING (%s)" % alerts.get_current())
	locker._warn_target(_player, 1.0)
	alerts._process(0.0)
	check(_player.lock_warning().state == "locked" and alerts.get_current() == "! LOCKED", "and LOCKED once it is a line (%s)" % alerts.get_current())
	check(HUD.lock_beep_interval(0.0) > HUD.lock_beep_interval(0.5) and HUD.lock_beep_interval(0.5) > HUD.lock_beep_interval(1.0),
			"the beep comes faster as the lock grows")
	_player.contacts.advance(Mecha.LOCK_WARNING_FRESH + 0.05)
	alerts._process(0.0)
	check(_player.lock_warning().is_empty() and alerts.get_current() == "", "a lock no longer refreshed is no longer a warning")
	alerts.queue_free()


func _test_npc_lock() -> void:
	var npc := _enemy(Vector2(3000, -3000))
	var target := _mecha(npc.global_position + Vector2(0, -1500))
	npc.update_enemy_locking(0.1, target)
	check(not npc.get_locking_to() and npc._lock_search < 0.0, "no reason, no lock and no search")
	npc.contacts.report(null, "mech", target.global_position + Vector2(npc.LOCK_SEARCH_RADIUS * 2.0, 0), "alarm", 5.0)
	npc.update_enemy_locking(0.1, target)
	check(npc._lock_search < 0.0, "an alarm too far from the target is no reason")
	npc.contacts.clear()
	npc.knowledge.place(target, target.global_position + Vector2(npc.LOCK_SEARCH_RADIUS * 0.5, 0))
	check(npc.lock_reason_for(target), "a ghost near it is a reason")
	npc.contacts.clear()
	npc.contacts.report_wedge(target, "shot", npc.global_position, target.global_position)
	check(npc.lock_reason_for(target), "so is a wedge it is inside")
	var elsewhere := _mecha(npc.global_position + Vector2(1500, 0))
	check(not npc.lock_reason_for(elsewhere), "but not for a mech outside the wedge")

	npc.personality.skill = 0.0
	var slow := []
	var fast := []
	for i in 40:
		slow.append(npc.lock_search_time())
	npc.personality.skill = 1.0
	for i in 40:
		fast.append(npc.lock_search_time())
	check(slow.all(func(t): return t >= 4.5 - 0.001 and t <= 5.0), "skill 0 searches 4.5 to 5 s (%.2f to %.2f)" % [slow.min(), slow.max()])
	check(fast.all(func(t): return t >= 2.0 and t <= 2.5 + 0.001), "skill 1, 2 to 2.5 s (%.2f to %.2f)" % [fast.min(), fast.max()])
	check(is_equal_approx(npc.lock_slip_chance(), 0.02), "slips 2% a second at skill 1")
	npc.personality.skill = 0.0
	check(is_equal_approx(npc.lock_slip_chance(), 0.10), "and 10% at skill 0")

	npc.update_enemy_locking(0.1, target)
	check(not npc.get_locking_to() and npc._lock_search > 0.0, "with a reason and no live track, it searches first")
	var search: float = npc._lock_search
	npc.update_enemy_locking(search + 0.01, target)
	check(npc.get_locking_to() and is_same(npc.get_locking_to().mecha, target), "then locks, nothing having shown before")

	_set_lock_speed(npc, 0.001)
	npc.locking_to.progress = 0.5
	npc.update_enemy_locking(15.0, target)
	check(npc.get_locking_to().progress < 0.5, "with no live track its reticle slips off: back to 0")
	npc.knowledge.see(target, target.global_position)
	npc.locking_to.progress = 0.5
	npc.update_enemy_locking(15.0, target)
	check(npc.get_locking_to().progress >= 0.5, "with a live track, no slip")
	npc.break_lock()
	npc.update_enemy_locking(0.01, target)
	check(npc.get_locking_to() and npc._lock_search < 0.0, "and no search")
	target.global_position = npc.global_position + Vector2(0, -(npc.sight_radius() + 300.0))
	npc.update_enemy_locking(0.1, target)
	check(not npc.get_locking_to(), "nor any lock past its sight circle")


func _test_lock_walls() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["shoulder_weapon_left"] = CLUSTER
	design["shoulder_weapon_right"] = VLS
	var npc := _enemy(Vector2(-600, 200), design)
	var behind := _mecha(Vector2(900, 200))
	npc.locked_to = behind
	npc.lock_on_duration = 1000.0
	check(not npc.lock_shot_clear("shoulder_weapon_left"), "a direct lock-on round is held with a wall on the way")
	check(npc.lock_shot_clear("shoulder_weapon_right"), "an indirect one (VLS) isn't: it comes down from above")
	behind.global_position = Vector2(-600, -1500)
	check(npc.lock_shot_clear("shoulder_weapon_left"), "in the open the direct one fires")


func _test_rcs() -> void:
	var rect := PackedVector2Array([Vector2(-20, -50), Vector2(20, -50), Vector2(20, 50), Vector2(-20, 50)])
	check(is_equal_approx(RadarCrossSection.facing_width(rect, Transform2D.IDENTITY, Vector2.DOWN), 40.0), "a 40 x 100 rectangle is 40 wide from the front")
	check(is_equal_approx(RadarCrossSection.facing_width(rect, Transform2D.IDENTITY, Vector2.RIGHT), 100.0), "and 100 from the side")
	check(is_equal_approx(RadarCrossSection.facing_width(rect, Transform2D(PI * 0.5, Vector2.ZERO), Vector2.DOWN), 100.0), "and 100 turned side-on")
	check(is_equal_approx(RadarCrossSection.combine([10.0, 4.0, 2.0]), 10.0 + RadarCrossSection.RCS_OTHERS * 6.0), "the largest plus a quarter of the rest")
	var plain := _mecha(Vector2(3000, 3000))
	var ahead := plain.global_position + Vector2(0, -2000)
	check(absf(RadarCrossSection.relative(plain, ahead) - 1.0) < 0.02, "the default mech from the front reads 1.0 (%.3f)" % RadarCrossSection.relative(plain, ahead))
	var reference := RadarCrossSection.of_build(plain.build) / RadarCrossSection.reference_rcs()
	check(is_equal_approx(reference, 1.0), "RCS_REFERENCE is its build's RCS from the front")
	var before := RadarCrossSection.of_mecha(plain, ahead)
	plain.lose_part("left_shoulder")
	check(RadarCrossSection.of_mecha(plain, ahead) < before, "a shoulder shot off adds nothing (%.0f < %.0f)" % [RadarCrossSection.of_mecha(plain, ahead), before])
	var parts_now := plain.rcs_outlines().filter(func(e): return not plain.is_part_lost(e.lost)).size()
	check_eq(parts_now, plain.rcs_outlines().size() - 1, "one outline fewer")
	_set_factor(plain, 0.5)
	check(is_equal_approx(RadarCrossSection.of_mecha(plain, ahead), RadarCrossSection.of_mecha(plain, ahead)), "(stable)")
	var half := RadarCrossSection.of_mecha(plain, ahead)
	_set_factor(plain, 1.0)
	check(is_equal_approx(half * 2.0, RadarCrossSection.of_mecha(plain, ahead)), "rcs_factor scales it")
	check(PartManager.get_part("core", PlayerProgress.DEFAULT_MECHA.core).rcs_factor == 1.0, "every part keeps 1.0 for now")


func _test_signature() -> void:
	var locker := _mecha(Vector2(-3000, -3000))
	var mech := _mecha(locker.global_position + Vector2(0, -1500))
	mech.global_rotation = PI
	_set_factor(mech, 0.1)
	mech.external_temp = 0.0
	var cold_small := locker.signature_lock_mult(mech)
	check(is_equal_approx(cold_small, maxf(locker.get_target_thermal_lock_mult(mech), RadarCrossSection.MULT_MIN)),
			"cold and small: the larger of its heat and RCS multipliers (%.2f)" % cold_small)
	mech.external_temp = 1000.0
	var hot_small := locker.signature_lock_mult(mech)
	_set_factor(mech, 3.0)
	mech.external_temp = 0.0
	var cold_big := locker.signature_lock_mult(mech)
	check(cold_small < 1.0, "a cold, small mech locks slowly (×%.2f)" % cold_small)
	check(hot_small > cold_small and cold_big > cold_small, "a hot small one (×%.2f) and a cold big one (×%.2f) lock fast" % [hot_small, cold_big])
	check(is_equal_approx(cold_big, RadarCrossSection.MULT_MAX), "the RCS multiplier is clamped at %.1f" % RadarCrossSection.MULT_MAX)


func _test_sweeps() -> void:
	var sweeper := _mecha(Vector2(-3000, 3000))
	sweeper.external_temp = 0.0
	var mech := _mecha(sweeper.global_position + Vector2(0, -1500))
	mech.global_rotation = PI
	var front := RadarCrossSection.relative(mech, sweeper.global_position)
	for row in [[1.0, "mech"], [0.6, "Coyote"], [0.2, "Raven"], [0.05, "Tick"]]:
		_set_factor(mech, float(row[0]) / front)
		var found: Dictionary = sweeper.sweep(Vector2.UP, 30.0).counts
		sweeper.sweep_cooldown = 0.0
		check(found.get(row[1]) == 1 and found.size() == 1, "relative RCS %.2f reads as %s (%s)" % [row[0], row[1], Mecha.describe_sweep(found)])
	_set_factor(mech, 1.0)
	mech.global_rotation = PI * 0.5
	var side := RadarCrossSection.relative(mech, sweeper.global_position)
	mech.global_rotation = PI
	check(not is_equal_approx(side, front), "(side-on %.2f, nose-on %.2f)" % [side, front])
	_set_factor(mech, 0.8 * 2.0 / (front + side))
	var nose: String = ContactStore.sweep_kind_of(mech, sweeper)
	mech.global_rotation = PI * 0.5
	var broadside: String = ContactStore.sweep_kind_of(mech, sweeper)
	check(nose != broadside, "a mech straddling a threshold reads %s nose-on and %s side-on" % [nose, broadside])
	_set_factor(mech, 1.0)
	mech.global_rotation = PI

	var swarm: TickSwarm = _arena.add_entity(TICKS, sweeper.global_position + Vector2(1500, 0))
	swarm.set_pause(true)
	var motes := swarm.get_mote_count()
	var found: Dictionary = sweeper.sweep(Vector2.RIGHT, 30.0).counts
	sweeper.sweep_cooldown = 0.0
	check_eq(found.get(Mecha.TICK_KIND), motes, "a swarm reads one tick a mote (%s)" % Mecha.describe_sweep(found))
	check("%d TICK" % motes in Mecha.describe_sweep(found), "as %d TICK" % motes)
	for i in 3:
		mech.attach_tick(swarm.group_id, _arena, mech.global_position + Vector2(0, 100), 30.0)
	found = sweeper.sweep(Vector2.UP, 30.0).counts
	sweeper.sweep_cooldown = 0.0
	check(found.get("mech") == 1 and found.get(Mecha.TICK_KIND) == mech.ticks.size() and mech.ticks.size() == 3,
			"a mech with three ticks on it adds three (%s)" % Mecha.describe_sweep(found))
	var decoy := Node2D.new()
	decoy.add_to_group("decoy")
	_arena.add_child(decoy)
	check_eq(ContactStore.sweep_kind_of(decoy, sweeper), "mech", "a decoy reads as a mech")
	decoy.queue_free()


func _test_radar() -> void:
	var radar = RADAR.instantiate()
	add_child(radar)
	radar.setup(_player)
	var o: Vector2 = _player.global_position
	var sight: float = _player.sight_radius()
	var mech := _mecha(o + Vector2(sight * 0.2, 0))
	var unknown := _mecha(o + Vector2(0, sight * 0.5))
	var far_one := _mecha(o + Vector2(-sight * 0.9, 0))
	var gone := _mecha(o + Vector2(0, -sight * 2.0))
	var untracked := _mecha(o + Vector2(sight * 0.5, sight * 0.5))
	_player.contacts.report(mech, "mech", mech.global_position, "sight", 1.0)
	_player.contacts.report(unknown, IRSensing.KIND, unknown.global_position, IRSensing.SOURCE, 1.0)
	_player.contacts.report(far_one, "Stalker", far_one.global_position, "ward", 1.0)
	_player.contacts.report(gone, "mech", gone.global_position, "drone", 0.0)
	_player.contacts.report(null, "car", o + Vector2(sight * 0.4, -10.0), "alarm", 1.0)
	_player.contacts.report_wedge(far_one, "shot", o, far_one.global_position)
	_player.contacts.report_wedge(unknown, "sound", o, unknown.global_position)
	_player.locked_to = mech
	_player.lock_on_duration = 1000.0
	var locker := _mecha(o + Vector2(0, 2000))
	locker._warn_target(_player, 0.5)
	_player.contacts.advance(0.01)
	radar.refresh()
	var shapes: Array = radar.marks.map(func(m): return m.shape)
	check_eq(radar.marks.size(), 5, "one mark per track, none for the mech it has no track on")
	check("triangle" in shapes and "square" in shapes and "diamond" in shapes and "round" in shapes,
			"a mech, an UNKNOWN, an Entity and an alarm each have their mark (%s)" % str(shapes))
	var by_source := {}
	for m in radar.marks:
		by_source[m.source] = m
	check(by_source.sight.chevrons == 3 and by_source.ir.chevrons == 2 and by_source.ward.chevrons == 1,
			"chevrons: 3 near, 2 mid, 1 far")
	check(by_source.drone.hollow and by_source.drone.chevrons == 0, "a ghost is hollow, and one past the circle has no chevrons")
	check(by_source.sight.locked and not by_source.ir.locked, "the locked target's mark has the bracket")
	check(by_source.alarm.level > 0 or by_source.sight.level > 0, "two marks at nearly one bearing stack outward")
	var arc_sources: Array = radar.arcs.map(func(a): return a.source)
	check("shot" in arc_sources and "sound" in arc_sources and "lock" in arc_sources, "shot, sound and lock arcs (%s)" % str(arc_sources))
	var lock_arc: Dictionary = radar.arcs.filter(func(a): return a.source == "lock")[0]
	check(lock_arc.pulse and is_equal_approx(lock_arc.width, ContactStore.WEDGES.lock.width * 0.5), "the lock arc pulses, as wide as the lock leaves it")
	check_eq(radar.chevrons_for(sight * 2.0, sight), 0, "past the circle, no chevrons")
	radar.queue_free()


func _test_chipset() -> void:
	var chipset = PartManager.get_part("chipset", PlayerProgress.DEFAULT_MECHA.chipset)
	check(not "radar_range" in chipset and not "radar_refresh_rate" in chipset and not "lock_on_distance" in chipset,
			"radar_range, radar_refresh_rate and lock_on_distance are gone")
	check("has_radar" in chipset and "lock_on_duration" in chipset, "has_radar and lock_on_duration stay")
	var ids: Array = []
	for group in StatsPanel.GROUPS:
		for stat in group.stats:
			ids.append(stat.id)
	check(not "radar_range" in ids and StatsPanel.RCS_FRONT in ids, "the stats panel shows RCS (front), not the radar range")
	var build := {}
	for slot in ["core", "head", "shoulders", "chassis"]:
		build[slot] = PartManager.get_part(slot, PlayerProgress.DEFAULT_MECHA[slot])
	check_eq(StatsPanel.stat_value(build, StatsPanel.RCS_FRONT), 1.0, "1.0 for the default mech")
