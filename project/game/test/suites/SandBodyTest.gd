extends TestSuite

# SandBodyTest: the sand Entity looks (SandBody and the species bodies in
# game/entities/coyote and game/entities/fisher), driven the way an Entity
# drives them but without one: each body sits as the Body child of a plain
# Node2D. Every body builds, walks faster when it moves faster, and bursts
# into grains that outlive the Entity when it dies. The Coyote's whip and
# bite, the Spitter's charge and the Fisher's stages, harpoon and leap pose
# all play through and say when they land. Out of the player's sight
# (SandBody.may_be_seen) a body moves on but isn't redrawn, and a braid's
# strands sit where the old per-strand maths put them. Nothing a body
# draws (legs, tails, grains, shadows, carried parts, its corpse or a
# Fisher's dead shell) sits below z 0, where the map's ground would cover
# it, and the body draws over its legs and trailing tails. The art bench
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
	await case("nothing is drawn under the ground, and the body is over its legs", _test_layers)
	await case("the Fisher is half again its first size", _test_fisher_size)
	await case("faded out of the player's view, its legs and tails fade with it", _test_fades_whole)
	await case("out of the player's sight it moves on but isn't redrawn", _test_drawn_in_sight)
	await case("a braid's strands are where they always were", _test_braid_points)
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
	var slow_coyote := _make("Coyote")
	var fast_coyote := _make("Coyote")
	fast_coyote.get_parent().position.y = 600.0
	for _i in 30:
		var dt := get_process_delta_time()
		slow_coyote.update_motion(Vector2(120.0, 0.0), dt)
		fast_coyote.update_motion(Vector2(650.0, 0.0), dt)
		await get_tree().process_frame
	check(fast_coyote.gait_phase > slow_coyote.gait_phase, "a faster Coyote takes more strides")
	check(fast_coyote.gait_blend > slow_coyote.gait_blend, "and runs rather than walks")
	slow_coyote.alarm = true
	await wait_seconds(1.0)
	check(slow_coyote.intensity > 0.9, "hunting, its sand flows faster")


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


func _test_layers() -> void:
	for species in BODIES:
		var body := _make(species)
		if body is FisherBody:
			(body as FisherBody).stage = FisherBody.Stage.ACTIVE
		if body is CoyoteBody:
			var tex := ImageTexture.create_from_image(Image.create(40, 20, false, Image.FORMAT_RGBA8))
			(body as CoyoteBody).carry_shield(tex)
			(body as CoyoteBody).carry_gun(tex)
		await _drive(body, Vector2(200.0, 0.0), 10)
		check_eq(_lowest_z(body.get_parent()), 0, "%s: nothing alive is drawn below z 0" % species)
		# The legs and tails are top_level, drawn over anything at their z that
		# isn't, so the body needs a higher z; the grains go by child order.
		var tail_z: int = body._tail_layer.z_index
		check(body._limb_layer.top_level and body._body_layer.z_index > body._limb_layer.z_index
				and (tail_z < body._body_layer.z_index or tail_z == SandBody.RAISED_TAIL_Z),
				"%s: the body is a z over its legs and trailing tails, a raised tail over the body" % species)
		check(body._body_layer.get_index() > body._grains.get_index(), "%s: and drawn after its grains" % species)
		if body is FisherBody:
			var shell: Sprite2D = (body as FisherBody)._shell
			check(shell.get_parent() == body._body_layer, "the Fisher's shell is on its body, over its legs")
		body.die()
		await wait_frames(2)
		check_eq(_lowest_z(_world), 0, "%s: nor what it leaves when it dies" % species)
		var corpse := body.make_corpse()
		_world.add_child(corpse)
		await wait_frames(1)
		check_eq(_lowest_z(corpse), 0, "%s: nor its corpse" % species)
		corpse.queue_free()
		body.get_parent().queue_free()
		await wait_frames(2)


func _test_fisher_size() -> void:
	var body: FisherBody = _make("Fisher")
	await _drive(body, Vector2.ZERO, 2)
	check(FisherBody.SIZE >= 1.5, "at least half again as big (x%.2f)" % FisherBody.SIZE)
	check(is_equal_approx(body.shell_radius, 60.0 * FisherBody.SIZE) and is_equal_approx(body.limb_length, 160.0 * FisherBody.SIZE),
			"shell and legs both (%.0f, %.0f px)" % [body.shell_radius, body.limb_length])
	var fisher: Fisher = load("res://game/entities/fisher/Fisher.tscn").instantiate()
	var shape := fisher.get_node("CollisionShape2D").shape as CircleShape2D
	check(fisher.radius >= body.shell_radius * 0.95 and shape.radius >= body.shell_radius * 0.9,
			"and so is its body in the world (radius %.0f, collision %.0f)" % [fisher.radius, shape.radius])
	fisher.free()


# The legs and tails are top_level, which doesn't take the Entity's modulate:
# the player's view hides an Entity through its alpha (Player._update_view).
func _test_fades_whole() -> void:
	for species in BODIES:
		var body := _make(species)
		await _drive(body, Vector2(100.0, 0.0), 3)
		var entity := body.get_parent() as Node2D
		entity.modulate.a = 0.0
		await _drive(body, Vector2.ZERO, 2)
		check(body._limb_layer.top_level and body._limb_layer.modulate.a == 0.0 and body._tail_layer.modulate.a == 0.0,
				"%s: hidden, its legs and tails are too" % species)
		entity.modulate.a = 1.0
		await _drive(body, Vector2.ZERO, 2)
		check(body._limb_layer.modulate.a == 1.0 and body._tail_layer.modulate.a == 1.0, "%s: and back with it" % species)
		entity.queue_free()
		await wait_frames(1)


# Stand-ins for an Entity, its arena and the player whose view shows it
# (SandBody.may_be_seen asks the Entity's arena for its player).
class FakeViewer extends Node2D:
	var sight := 3000.0
	func sight_radius() -> float:
		return sight


class FakeArena extends Node2D:
	var player = null


class FakeEntity extends Node2D:
	var arena = null


const FAR := Vector2(60000, 60000)


# A body as the Body child of a stand-in Entity at `pos`, with a player in
# its arena at `viewer_pos`.
func _make_seen(species: String, pos: Vector2, viewer_pos: Vector2) -> SandBody:
	var arena := FakeArena.new()
	var viewer := FakeViewer.new()
	viewer.position = viewer_pos
	arena.add_child(viewer)
	arena.player = viewer
	_world.add_child(arena)
	var entity := FakeEntity.new()
	entity.arena = arena
	entity.position = pos
	var body: SandBody = BODIES[species].new()
	body.name = "Body"
	entity.add_child(body)
	arena.add_child(entity)
	return body


func _leg_points(body: SandBody) -> PackedVector2Array:
	return body._limbs[0].line.points


func _test_drawn_in_sight() -> void:
	var body := _make_seen("Coyote", FAR, FAR + Vector2(20000, 0))
	await _drive(body, Vector2(300.0, 0.0), 2)
	var drawn := _leg_points(body)
	var gait := body.gait_phase
	await _drive(body, Vector2(300.0, 0.0), 30)
	check(not body.may_be_seen(), "off screen and past the player's sight circle: can't be seen")
	check(body.gait_phase > gait, "it walks on")
	check(_leg_points(body) == drawn, "its legs aren't redrawn")
	# The player comes near: the body is in its sight circle, still off screen.
	var viewer: FakeViewer = body.get_parent().arena.player
	viewer.global_position = body.global_position + Vector2(2500, 0)
	check(body.may_be_seen(), "within the sight circle: may be seen")
	await _drive(body, Vector2(300.0, 0.0), SandBody.OFF_SCREEN_INTERVAL + 1)
	check(_leg_points(body) != drawn, "its legs are redrawn by its next step")
	# Past the circle but within OFF_SCREEN_MARGIN of it: drawn too.
	viewer.global_position = body.global_position + Vector2(viewer.sight + SandBody.OFF_SCREEN_MARGIN - 50.0, 0)
	check(body.may_be_seen(), "just past the circle, within the margin: may be seen")
	viewer.global_position = body.global_position + Vector2(viewer.sight + SandBody.OFF_SCREEN_MARGIN + 50.0, 0)
	check(not body.may_be_seen(), "past the margin: can't")
	# Near the screen it is always drawn, with or without a player.
	var plain := _make("Coyote")
	await _drive(plain, Vector2(300.0, 0.0), 2)
	var before := _leg_points(plain)
	await _drive(plain, Vector2(300.0, 0.0), 1)
	check(plain.may_be_seen(), "on screen: may be seen")
	check(_leg_points(plain) != before, "and redrawn every frame")


# The strands as _update_braid placed them before it shared the per-point
# work between strands: the same points, to the bit.
func _old_strands(body: SandBody, points: PackedVector2Array, strand_count: int, width: float, taper: Curve,
		joints: PackedFloat32Array, seed: float) -> Array:
	var core := body._smooth(points)
	var count := core.size()
	var along := PackedFloat32Array()
	along.resize(count)
	for i in range(1, count):
		along[i] = along[i - 1] + core[i].distance_to(core[i - 1])
	var total := maxf(along[count - 1], 1.0)
	var out := []
	for j in strand_count:
		var pts := PackedVector2Array()
		pts.resize(count)
		for i in count:
			var s := along[i] / total
			var tangent := (core[mini(i + 1, count - 1)] - core[maxi(i - 1, 0)]).normalized()
			var pinch := 1.0
			for j_at in joints:
				pinch = minf(pinch, lerpf(0.2, 1.0, smoothstep(0.0, 0.12, absf(s - j_at))))
			var amp := width * 0.42 * taper.sample(s) * pinch
			var wind := sin(along[i] / SandBody.STRAND_TURN_PX * TAU + j * PI + seed - body.flow_phase * 2.0)
			pts[i] = core[i] + tangent.orthogonal() * wind * amp
		out.append(pts)
	return out


func _test_braid_points() -> void:
	for species in BODIES:
		var body := _make(species)
		if body is FisherBody:
			(body as FisherBody).stage = FisherBody.Stage.ACTIVE
		await _drive(body, Vector2(250.0, 0.0), 20)
		var braided := 0
		for limb in body._limbs:
			if limb.strands.is_empty() or limb.points.size() < 2:
				continue
			var joints := PackedFloat32Array([0.35, 0.7])
			var expected := _old_strands(body, limb.points, limb.strands.size(), limb.width, body._taper, joints, limb.seed)
			body._update_braid(limb.points, limb.line, limb.strands, limb.width, body._taper, joints, limb.seed)
			var same := true
			for j in limb.strands.size():
				same = same and limb.strands[j].points == expected[j]
			check(same, "%s: a leg's strands are where they were" % species)
			braided += 1
			break
		for tail in body._tails:
			if tail.strands.is_empty():
				continue
			var expected := _old_strands(body, tail.points, tail.strands.size(), tail.width, body._tail_taper, PackedFloat32Array(), tail.seed)
			body._update_braid(tail.points, tail.line, tail.strands, tail.width, body._tail_taper, PackedFloat32Array(), tail.seed)
			var same := true
			for j in tail.strands.size():
				same = same and tail.strands[j].points == expected[j]
			check(same, "%s: a tail's strands are where they were" % species)
			braided += 1
			break
		check(braided > 0, "%s has a braid to compare" % species)
		body.get_parent().queue_free()
		await wait_frames(1)


# The lowest z any CanvasItem under `root` is drawn at, counting relative z
# up to `root`.
func _lowest_z(root: Node) -> int:
	var lowest := 0
	for node in root.find_children("*", "CanvasItem", true, false):
		var z := 0
		var at: Node = node
		while at is CanvasItem and at != root.get_parent():
			z += (at as CanvasItem).z_index
			if not (at as CanvasItem).z_as_relative:
				break
			at = at.get_parent()
		lowest = mini(lowest, z)
	if root is CanvasItem:
		lowest = mini(lowest, (root as CanvasItem).z_index)
	return lowest


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
