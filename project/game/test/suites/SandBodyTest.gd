extends TestSuite

# SandBodyTest: the sand Entity looks (SandBody and the species bodies in
# game/entities/coyote and game/entities/fisher), driven the way an Entity
# drives them but without one: each body sits as the Body child of a plain
# Node2D. Every body builds, walks faster when it moves faster, and bursts
# into grains that outlive the Entity when it dies. The Coyote's whip and
# bite, the Spitter's charge and the Fisher's stages, harpoon and leap pose
# all play through and say when they land. The art bench
# (game/test/sand_bench) runs every species without errors.

const BODIES := {
	"Coyote": preload("res://game/entities/coyote/CoyoteBody.gd"),
	"Coyote Spitter": preload("res://game/entities/coyote/CoyoteSpitterBody.gd"),
	"Fisher": preload("res://game/entities/fisher/FisherBody.gd"),
}
const BENCH := preload("res://game/test/sand_bench/SandBench.tscn")

var _world: Node2D = null


func run_tests() -> void:
	await case("every body builds and animates", _test_builds)
	await case("the gait follows the speed", _test_gait)
	await case("a dead body bursts into grains that outlive the Entity", _test_death)
	await case("a Coyote whips, then bites", _test_coyote_attack)
	await case("a Coyote Spitter charges and fires at its aim", _test_spitter_fire)
	await case("a Fisher wakes, spiders out and curls back up", _test_fisher_stages)
	await case("a Fisher's harpoon, recoil and leap play through", _test_fisher_moves)
	await case("a dead Fisher leaves its shell behind", _test_fisher_shell)
	await case("the art bench runs every species", _test_bench)


func before_each() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)


# A body as the Body child of a stand-in Entity, in the world.
func _make(species: String) -> SandBody:
	var puppet := Node2D.new()
	var body: SandBody = BODIES[species].new()
	body.name = "Body"
	puppet.add_child(body)
	_world.add_child(puppet)
	return body


func _drive(body: SandBody, velocity: Vector2, frames: int) -> void:
	for _i in frames:
		var dt := get_process_delta_time()
		body.get_parent().position += velocity * dt
		body.update_motion(velocity, dt)
		await get_tree().process_frame


func _test_builds() -> void:
	for species in BODIES:
		var body := _make(species)
		if body is FisherBody:
			(body as FisherBody).stage = FisherBody.Stage.ACTIVE
		await _drive(body, Vector2(200.0, 0.0), 20)
		check(not body.dead, "%s is alive" % species)
		check(body.gait_phase > 0.0, "%s walks" % species)


func _test_gait() -> void:
	var slow := _make("Coyote")
	var fast := _make("Coyote")
	fast.get_parent().position.y = 600.0
	for _i in 30:
		var dt := get_process_delta_time()
		slow.update_motion(Vector2(120.0, 0.0), dt)
		fast.update_motion(Vector2(650.0, 0.0), dt)
		await get_tree().process_frame
	check(fast.gait_phase > slow.gait_phase, "a faster Coyote takes more strides")
	check(fast.gait_blend > slow.gait_blend, "and runs rather than walks")
	slow.alarm = true
	await wait_seconds(1.0)
	check(slow.intensity > 0.9, "hunting, its sand flows faster")


func _test_death() -> void:
	var body := _make("Coyote")
	await _drive(body, Vector2(300.0, 0.0), 10)
	var before := _world.get_child_count()
	body.die()
	check(body.dead, "dead")
	check(_world.get_child_count() == before + 1, "the burst of grains moves out into the world")
	body.die()  # twice is harmless
	body.get_parent().queue_free()
	await wait_frames(2)
	var grains: Array = _world.get_children().filter(func(n): return n is GPUParticles2D)
	check(grains.size() == 1, "and keeps scattering after the Entity is gone")
	check(await wait_until(func(): return _world.get_child_count() == 0, 4.0), "then clears itself up")


func _test_coyote_attack() -> void:
	var body: CoyoteBody = _make("Coyote")
	var events: Array[String] = []
	body.whip_struck.connect(func(): events.append("whip"); body.bite())
	body.bite_closed.connect(func(): events.append("bite"))
	await _drive(body, Vector2.ZERO, 2)
	body.whip()
	check(body.is_attacking(), "attacking")
	check(await wait_until(func(): return not body.is_attacking(), 3.0), "the attack ends")
	check_eq(events, ["whip", "bite"] as Array[String], "the whip lands, then the bite")
	check(body.thrash > 0.0, "its tendrils thrashed")


func _test_spitter_fire() -> void:
	var body: CoyoteSpitterBody = _make("Coyote Spitter")
	var shots: Array = []
	body.fired.connect(func(muzzle, direction): shots.append([muzzle, direction]))
	await _drive(body, Vector2.ZERO, 2)
	var aim := Vector2(0.0, 800.0)
	body.charge(aim)
	body.charge(aim)  # already charging: ignored
	check(await wait_until(func(): return not body.is_attacking(), 3.0), "the charge plays through")
	check_eq(shots.size(), 1, "one shot")
	if shots.size() == 1:
		var to_aim: Vector2 = (aim - shots[0][0]).normalized()
		check((shots[0][1] as Vector2).dot(to_aim) > 0.99, "fired at the aim point")


func _test_fisher_stages() -> void:
	var body: FisherBody = _make("Fisher")
	await _drive(body, Vector2.ZERO, 5)
	check(body.legs_out() == 0.0, "dormant: legs drawn in")
	body.stage = FisherBody.Stage.ALERT
	await wait_seconds(1.0)
	check(body.legs_out() == 0.0, "alert: still only the antennae")
	body.stage = FisherBody.Stage.ACTIVE
	check(await wait_until(func(): return body.legs_out() >= 1.0, 3.0), "active: the legs spider out")
	body.stage = FisherBody.Stage.DORMANT
	check(await wait_until(func(): return body.legs_out() <= 0.0, 3.0), "and draw back in")
	# Set straight after instancing, before the legs exist.
	var early: FisherBody = BODIES["Fisher"].new()
	early.stage = FisherBody.Stage.ACTIVE
	var puppet := Node2D.new()
	puppet.add_child(early)
	_world.add_child(puppet)
	check(await wait_until(func(): return early.legs_out() >= 1.0, 3.0), "a Fisher made active before it's ready still stands up")


func _test_fisher_moves() -> void:
	var body: FisherBody = _make("Fisher")
	body.stage = FisherBody.Stage.ACTIVE
	await wait_until(func(): return body.legs_out() >= 1.0, 3.0)
	var root := body.harpoon_root()
	check(root.distance_to(body.global_position) < body.shell_radius * 1.5, "the harpoon leaves from under the shell")
	body.recoil(Vector2.RIGHT)
	for mode in [FisherBody.HarpoonMode.FLYING, FisherBody.HarpoonMode.LATCHED, FisherBody.HarpoonMode.REELING]:
		body.harpoon_mode = mode
		body.harpoon_tip = root + Vector2(500.0, 0.0)
		body.drain_phase += 0.5
		await _drive(body, Vector2.ZERO, 5)
	body.harpoon_mode = FisherBody.HarpoonMode.NONE
	for phase in [FisherBody.LeapPhase.CROUCH, FisherBody.LeapPhase.AIR, FisherBody.LeapPhase.LAND]:
		for k in 5:
			body.set_leap(phase, k / 4.0, Vector2.RIGHT)
			if phase == FisherBody.LeapPhase.AIR and k == 2:
				check(body.air_height > 0.0 and body.airborne, "in the air at the top of the leap")
			await _drive(body, Vector2.ZERO, 1)
	body.set_leap(FisherBody.LeapPhase.NONE, 0.0, Vector2.RIGHT)
	check(body.air_height == 0.0 and not body.airborne, "back on the ground")
	await _drive(body, Vector2(150.0, 0.0), 10)
	check(not body.dead, "it walks on afterwards")


func _test_fisher_shell() -> void:
	var body: FisherBody = _make("Fisher")
	await _drive(body, Vector2.ZERO, 3)
	body.die()
	body.get_parent().queue_free()
	await wait_frames(2)
	var shells: Array = _world.get_children().filter(func(n): return n is Sprite2D)
	check(shells.size() == 1, "the shell is left in the world")


func _test_bench() -> void:
	var bench: Node2D = BENCH.instantiate()
	bench.autopilot = true
	_world.add_child(bench)
	for species in ["Coyote", "Coyote Spitter", "Fisher"]:
		bench.species = species
		bench.spawn()
		bench.noise()
		bench.hunt()
		await wait_seconds(1.5)
		bench.attack()
		bench.leap(Vector2.RIGHT)
		bench.hit()
		await wait_seconds(2.0)
		bench.calm()
		bench.kill()
		await wait_seconds(0.5)
		check(bench.body.dead, "%s runs on the bench" % species)
	bench.queue_free()
