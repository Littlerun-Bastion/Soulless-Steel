extends TestSuite

const HUD := preload("res://game/ui/PlayerHUD.tscn")

var _hud = null


func run_tests() -> void:
	await case("a dark HUD draws nothing", _test_dark)
	await case("a dark HUD stays dark when a scene hands control back", _test_dark_through_scenes)
	await case("booting brings the panels back one system after another", _test_boot_order)
	await case("each panel flickers before it holds", _test_flicker)
	await case("the boot types a line per system and then clears it", _test_boot_log)
	await case("booting ends with the HUD as it was", _test_boot_restores)


func before_each() -> void:
	if is_instance_valid(_hud):
		_hud.queue_free()
		await wait_frames(2)
	_hud = HUD.instantiate()
	add_child(_hud)
	await wait_frames(1)


func _panels() -> Array:
	return _hud.hud_viewport.get_children().filter(func(n): return n is CanvasItem)


func _drawn(item: CanvasItem) -> bool:
	var mask: int = _hud.hud_viewport.canvas_cull_mask
	var node: Node = item
	while node is CanvasItem:
		if node.visibility_layer & mask == 0:
			return false
		node = node.get_parent()
	return true


func _test_dark() -> void:
	_hud.go_dark()

	check(_hud.is_dark(), "the HUD says it is dark")
	var lit := _panels().filter(_drawn)
	check(lit.is_empty(), "no panel is drawn (%s)" % ", ".join(lit.map(func(n): return n.name)))
	check(not _hud.top_strip.visible, "the top strip is off")


func _test_dark_through_scenes() -> void:
	_hud.go_dark()

	_hud.set_cinematic(true)
	_hud.set_cinematic(false)

	check(_panels().filter(_drawn).is_empty(), "still nothing is drawn")
	check(not _hud.top_strip.visible, "nor the top strip")


func _test_boot_order() -> void:
	_hud.go_dark()
	var first_lit := {}
	var order := [_hud.hud_status, _hud.hud_weapons, _hud.PlayerRadar]

	_hud.boot()
	check(_hud.is_booting(), "the HUD is booting")
	var done := await wait_until(func():
		for panel in order:
			if not first_lit.has(panel) and _drawn(panel):
				first_lit[panel] = first_lit.size()
		return not _hud.is_booting(), 10.0)

	check(done, "the boot ends")
	check_eq(order.map(func(p): return first_lit.get(p, -1)), [0, 1, 2], "the frame readout, then the weapons, then the radar")
	check(not _hud.is_dark(), "the HUD is no longer dark")


func _test_flicker() -> void:
	_hud.go_dark()
	var changes := [0]
	var was := [false]
	# Looked at on every change, as it happens: at the suite's speed a flicker
	# is shorter than a frame, so looking once a frame could miss one.
	var note := func():
		var now := _drawn(_hud.hud_status)
		if now != was[0]:
			changes[0] += 1
			was[0] = now
	_hud._boot.lit_changed.connect(note)

	_hud.boot()
	await wait_until(func(): return not _hud.is_booting(), 10.0)
	_hud._boot.lit_changed.disconnect(note)

	check(changes[0] >= 3, "the frame readout came on, went off and came on again (%d changes)" % changes[0])
	check(was[0], "and held on")


func _test_boot_log() -> void:
	_hud.go_dark()
	var booted := [0]
	_hud.booted.connect(func(): booted[0] += 1)

	_hud.boot()
	await wait_until(func(): return not _hud.is_booting(), 10.0)
	var log_text: String = _hud.get_boot_log_text()

	for system in ["FRAME", "WEAPONS", "TARGETING", "RADAR", "NAV"]:
		check(system in log_text, "the log names %s" % system)
	check_eq(booted[0], 1, "the boot was announced once")
	var cleared := await wait_until(func(): return _hud.get_boot_log_text() == "", 5.0)
	check(cleared, "and the log goes away")


func _test_boot_restores() -> void:
	var before := {}
	for panel in _panels():
		before[panel] = panel.visibility_layer
	_hud.go_dark()

	_hud.boot()
	await wait_until(func(): return not _hud.is_booting(), 10.0)

	var changed := _panels().filter(func(p): return before.has(p) and p.visibility_layer != before[p])
	check(changed.is_empty(), "every panel is drawn as before (%s)" % ", ".join(changed.map(func(n): return n.name)))
