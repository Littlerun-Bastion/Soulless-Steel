extends TestSuite

# SprintGaitProbe: what the walk and the sprint really do (Mecha.
# apply_movement), for the two legged chassis that set no max_speed or
# move_acc of their own (MSV-L3J-L, the default legs, and SAMURAI-03L) and a
# legged chassis that does (GTk-1Cr). A plain mecha with the default build
# is driven straight ahead at full throttle, as an NPC or the player drives
# it, for WALK_SECONDS walking and SPRINT_SECONDS sprinting; it prints the
# chassis' numbers, the mean walk speed (px/s and as a share of max_speed,
# the gait's slow beats included) and the sprint speed beside walk times
# thrust_speed_multiplier and the "thrust_max_speed" stat (Mecha.get_stat:
# the thruster's thrust_max_speed plus max_speed), the cap the sprint line
# seems meant to apply. It changes nothing and never fails on a number. A
# probe, not a test: it runs only when named (--suite=SprintGaitProbe), so
# the full run stays within TestSession.MAX_RUN_SECONDS.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const WALK_SECONDS := 6.4
const SPRINT_SECONDS := 2.0
const CHASSIS := ["MSV-L3J-L", "SAMURAI_Chassis", "GTk-1Cr_Chassis"]


func _init() -> void:
	slow = true
	time_scale = 1.0


func run_tests() -> void:
	if not asked_for():
		return
	await case("walk and sprint speeds of legged chassis", _test_speeds)

# Whether this probe should run: opened on its own (F6), or named in
# --suite=... on the command line.
func asked_for() -> bool:
	if get_tree().current_scene == self:
		return true
	for filter in TestSession.get_options()["suites"]:
		if str(filter).to_lower() in get_suite_name().to_lower():
			return true
	print("  (a probe: run it with --suite=%s)" % get_suite_name())
	return false


func _test_speeds() -> void:
	var lines := PackedStringArray(["[SprintGaitProbe] ms = m/s; 20 px = 1 m"])
	for chassis in CHASSIS:
		if PartManager.get_part("chassis", chassis) == null:
			lines.append("  %s: no such chassis" % chassis)
			continue
		var mecha: Mecha = MECHA.instantiate()
		mecha.mech_inventory = Inventory.new()
		add_child(mecha)
		var design := PlayerProgress.DEFAULT_MECHA.duplicate()
		design["chassis"] = chassis
		mecha.set_parts_from_design(design)
		mecha.global_rotation = 0.0
		mecha.throttle = 1.0
		await get_tree().physics_frame
		var part = mecha.build.chassis
		# Settle into the walk, then measure.
		await _drive(mecha, false, 1.0)
		var walk := await _drive(mecha, false, WALK_SECONDS)
		var sprint_start := await _drive(mecha, true, 1.0)
		var sprint := await _drive(mecha, true, SPRINT_SECONDS)
		var thruster = mecha.build.thruster
		var mult: float = float(thruster.thrust_speed_multiplier) if thruster else 0.0
		var cap: float = float(mecha.get_stat("thrust_max_speed")) if thruster else 0.0
		lines.append("  %s (%s): chassis max_speed %s, move_acc %s; walk %.0f px/s (%.1f m/s, %.0f%% of max_speed); sprint %.0f px/s (%.1f m/s; first second %.0f px/s); max_speed x %.1f = %.0f px/s; thrust_max_speed stat %.0f px/s (%.1f m/s); overweight %s" % [
				chassis, part.part_name, str(part.max_speed), str(part.move_acc), walk, walk / 20.0,
				100.0 * walk / maxf(float(mecha.max_speed), 1.0), sprint, sprint / 20.0, sprint_start,
				mult, float(mecha.max_speed) * mult, cap, cap / 20.0, str(mecha.is_overweight())])
		mecha.queue_free()
		await wait_frames(2)
	print("\n".join(lines))
	check(lines.size() > 1, "speeds were measured")


# Drives `mecha` straight ahead (its body's forward) for `seconds`, walking
# or sprinting, and returns its mean speed (px/s) over them.
func _drive(mecha: Mecha, sprint: bool, seconds: float) -> float:
	mecha.is_sprinting = sprint
	var start := mecha.global_position
	var frames := int(seconds * 60.0)
	for _i in frames:
		await get_tree().physics_frame
		mecha.apply_movement(1.0 / 60.0, Vector2(0, -1))
	return mecha.global_position.distance_to(start) / seconds
