extends TestSuite

# WalkCycleTest: every mecha's walk cycle (the Walking animation, whose slow
# beats Mecha.update_speed sets from the chassis) is its own: the animation
# and its library are local to scene in Mecha.tscn, so one mecha's chassis
# never changes how another walks. Plain mechas, NPCs and the player alike.

const SCENES := {
	"Mecha": preload("res://game/mecha/Mecha.tscn"),
	"Enemy": preload("res://game/mecha/Enemy.tscn"),
	"Player": preload("res://game/mecha/player/Player.tscn"),
}

var _made: Array = []


func run_tests() -> void:
	await case("each mecha walks to its own chassis", _test_own_cycle)


func _mecha(scene: PackedScene, chassis: String) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	add_child(mecha)
	mecha.set_physics_process(false)  # held: only its set-up runs
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["chassis"] = chassis
	mecha.set_parts_from_design(design)
	_made.append(mecha)
	return mecha


func _slow_beat(mecha: Mecha) -> float:
	return mecha.MovementAnimation.get_animation("Walking").track_get_key_value(0, 2)


func _test_own_cycle() -> void:
	var legs := ""
	var other := ""
	for id in PartManager.get_parts("chassis"):
		var chassis = PartManager.get_part("chassis", id)
		if chassis.is_legs and legs == "":
			legs = id
		elif not chassis.is_legs and other == "":
			other = id
	if not check(legs != "" and other != "", "a legged chassis and another to compare"):
		return
	for label in SCENES:
		var walker := _mecha(SCENES[label], legs)
		var beat := _slow_beat(walker)
		check(absf(beat - walker.move_acc / 100.0) < 0.0001, "%s: its slow beats follow its chassis" % label)
		# Another mecha set up after it, on a different chassis.
		var later := _mecha(SCENES[label], other)
		check(walker.MovementAnimation.get_animation("Walking") != later.MovementAnimation.get_animation("Walking"),
				"%s: each has its own walk cycle" % label)
		check(absf(_slow_beat(walker) - beat) < 0.0001, "%s: and a later mecha's chassis leaves it as it was" % label)
	for mecha in _made:
		mecha.queue_free()
	_made.clear()
	await wait_frames(2)
