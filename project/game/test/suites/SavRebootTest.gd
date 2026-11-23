extends TestSuite

const REBOOT := preload("res://game/onboarding/SavReboot.tscn")

var _reboot = null


func run_tests() -> void:
	await case("the reboot cuts the screen to black and types its boot log", _test_black_and_log)
	await case("then the picture comes back and the reboot ends", _test_picture_back)


func before_each() -> void:
	if is_instance_valid(_reboot):
		_reboot.queue_free()
		await wait_frames(2)
	_reboot = REBOOT.instantiate()
	add_child(_reboot)
	await wait_frames(1)


func _test_black_and_log() -> void:
	check(not _reboot.is_covering(), "nothing covers the screen before it plays")

	_reboot.play()
	var black := await wait_until(func(): return _reboot.is_covering(), 2.0)
	var typed := await wait_until(func(): return "COLD BOOT" in _reboot.get_log_text(), 6.0)

	check(black, "the screen goes black")
	check(_reboot.get_cover_rect().size == get_viewport().get_visible_rect().size, "all of it")
	check(typed, "and the boot log types out over it")
	var bars := StageBars.new()
	var bar_height: float = get_viewport().get_visible_rect().size.y * bars.height_ratio
	bars.free()
	check(_reboot.get_log_rect().position.y > bar_height, "below the scene's top bar, where all of it shows")
	check(_reboot.layer < ShaderEffects.layer, "under the CRT effect, which bends it with the rest")


func _test_picture_back() -> void:
	var finished := [0]
	_reboot.finished.connect(func(): finished[0] += 1)

	_reboot.play()
	var done := await wait_until(func(): return finished[0] > 0, 12.0)

	check(done, "the reboot ends")
	check_eq(finished[0], 1, "once")
	check(not _reboot.is_covering(), "with the picture back")
	for line in ["SENSORS", "MOBILITY", "SAFETY FLAG"]:
		check(line in _reboot.get_log_text(), "the log reported %s" % line)
