extends TestSuite

# MapLandmarksTest: the named places of a generated map (MapLandmarks,
# Landmarks in game/map/) and how the HUD names them. landmarks.json's data
# becomes a MapLandmarks (build_meshes.gd uses the same from_json); at()
# finds the place an outline (or a radius, with no outline) holds, the
# smaller of two that overlap; nearest() and describe() give the place and a
# hint ("near ...", "... m north of ..."); entering a place emits
# player_entered once, not again until the player has been out of it for
# reentry_time, and not for the place the player starts in; and the HUD shows
# the name as a notice below every other notice (dropped if the player has
# left the place before it could show), and in the top strip while the
# player is there (after the site, without a leading site name). A Landmarks
# node loads its landmarks_path on ready, and a missing file gives no places.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const GARDEN := [[2000, -1000], [6000, -1000], [6000, 2000], [2000, 2000]]


class FakePlayer extends Node2D:
	func _init() -> void:
		add_to_group("mecha")

	func is_player() -> bool:
		return true


var _root: Node2D = null


func run_tests() -> void:
	await case("landmarks.json becomes a MapLandmarks", _test_from_json)
	await case("at, nearest and describe", _test_lookups)
	await case("entering a place tells once per visit", _test_entering)
	await case("the HUD names the place, below other notices", _test_hud_notice)
	await case("the top strip shows the place the player is in", _test_top_strip)


func before_each() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
		await wait_frames(2)
	_root = Node2D.new()
	add_child(_root)


func _data() -> Dictionary:
	return {"items": [
		{"name": "Japanese Garden", "kind": "garden", "x": 4000.0, "y": 500.0, "radius": 3600.0, "outline": GARDEN},
		{"name": "the Old Pavilion", "kind": "pavilion", "x": 3000.0, "y": 0.0, "radius": 500.0, "outline": []},
		{"name": "Helwan Observatory", "kind": "observatory", "x": -20000.0, "y": -30000.0, "radius": 1500.0,
			"outline": []},
	]}


func _field() -> Landmarks:
	var field := Landmarks.new()
	field.landmarks = MapLandmarks.from_json(_data())
	_root.add_child(field)
	return field


func _test_from_json() -> void:
	var lm := MapLandmarks.from_json(_data())
	check_eq(lm.count(), 3, "three places")
	check_eq(lm.names[0], "Japanese Garden", "named as the generator named them")
	check_eq(lm.kinds[2], "observatory", "with their kinds")
	check_eq(lm.outline(0).size(), 4, "the garden keeps its outline")
	check(lm.outline(0)[2].is_equal_approx(Vector2(6000, 2000)), "in world px")
	check(lm.outline(1).is_empty(), "the pavilion has none")
	check(lm.centres[2].is_equal_approx(Vector2(-20000, -30000)) and lm.radii[2] == 1500.0, "centres and radii")
	check_eq(MapLandmarks.from_json(null).count(), 0, "no data: no places")
	check_eq(MapLandmarks.from_json({"items": [{"name": "Bare"}]}).count(), 1, "missing fields are filled in")
	var path := "user://test/landmarks_test.res"
	DirAccess.make_dir_recursive_absolute("user://test/")
	check_eq(ResourceSaver.save(lm, path), OK, "it saves as build_meshes saves it")
	var back := load(path) as MapLandmarks
	check(back != null and back.count() == 3 and back.outline(0) == lm.outline(0), "and loads back")
	var by_path := Landmarks.new()
	by_path.landmarks_path = path
	_root.add_child(by_path)
	check_eq(by_path.count(), 3, "a Landmarks node loads its landmarks_path when ready (the generated scene's way)")
	check_eq(by_path.name_of(by_path.at(Vector2(5000, 0))), "Japanese Garden", "and answers from it")
	var missing := Landmarks.new()
	missing.landmarks_path = "user://test/no_such_landmarks.res"
	_root.add_child(missing)
	check(missing.count() == 0 and missing.at(Vector2(5000, 0)) < 0 and missing.describe(Vector2.ZERO) == "",
			"a missing file (build_meshes not run yet) means no places")


func _test_lookups() -> void:
	var field := _field()
	await wait_frames(1)
	check(Landmarks.find(self) == field, "found from any node")
	check_eq(field.at(Vector2(5000, 1500)), 0, "inside the garden's outline")
	check_eq(field.at(Vector2(3000, 100)), 1, "the pavilion (radius only) inside the garden wins: it is smaller")
	check_eq(field.at(Vector2(7000, 500)), -1, "outside the outline, though within the garden's radius")
	check_eq(field.at(Vector2(-20000, -28800)), 2, "within a radius")
	check_eq(field.nearest(Vector2(8000, 500), 3000.0), 0, "the nearest place, by its edge")
	check_eq(field.nearest(Vector2(8000, 500), 1000.0), -1, "none within a shorter reach")
	check(is_equal_approx(field.distance_to(0, Vector2(8000, 500)), 2000.0), "2000 px from the garden's east edge")
	check_eq(field.describe(Vector2(5000, 1500)), "near Japanese Garden", "inside: near it")
	check_eq(field.describe(Vector2(8000, 500)), "near Japanese Garden", "100 m out: near it")
	check_eq(field.describe(Vector2(4000, -9000)), "400 m north of Japanese Garden", "further: how far and which way")
	check_eq(field.describe(Vector2(-14000, -24000)), "300 m south-east of Helwan Observatory", "a bearing between")
	check_eq(field.describe(Vector2(40000, 40000)), "", "too far from everything: nothing to say")
	check_eq(field.name_of(9), "", "a bad index has no name")


func _test_entering() -> void:
	var field := _field()
	field.reentry_time = 10.0
	var entered: Array[int] = []
	var changes: Array[int] = []
	field.player_entered.connect(func(i: int): entered.append(i))
	field.place_changed.connect(func(i: int): changes.append(i))
	var player := FakePlayer.new()
	player.position = Vector2(5000, 1500)
	_root.add_child(player)
	field._process(0.3)
	check(entered.is_empty(), "the place the player starts in is not announced")
	check(changes == [0] and field.current() == 0, "but it is the current place")
	player.position = Vector2(0, 0)
	field._process(0.3)
	check(changes.back() == -1 and field.current() == -1, "out of every place")
	player.position = Vector2(5000, 1500)
	field._process(0.3)
	check(entered.is_empty() and field.current() == 0, "the start place counts as visited: back soon, no notice")
	player.position = Vector2(-20000, -30000)
	field._process(0.3)
	check(entered == [2], "walking into another place announces it")
	field._process(0.3)
	field._process(0.3)
	check(entered == [2], "once")
	player.position = Vector2(0, 0)
	field._process(0.3)
	player.position = Vector2(-20000, -30000)
	field._process(0.3)
	check(entered == [2], "back within reentry_time: not again")
	player.position = Vector2(0, 0)
	for _i in 40:
		field._process(0.3)
	player.position = Vector2(-20000, -30000)
	field._process(0.3)
	check(entered == [2, 2], "after reentry_time out of it, again")
	player.position = Vector2(5000, 1500)
	field._process(0.3)
	check(entered == [2, 2, 0], "and the start place too, long after leaving it")
	field._process(0.1)
	field._process(0.1)
	check(entered == [2, 2, 0] and field.current() == 0, "checked every CHECK_INTERVAL, nothing more")


func _hud() -> HudAlerts:
	var canvas := Control.new()
	canvas.theme = THEME
	canvas.size = Vector2(1920, 1080)
	_root.add_child(canvas)
	var alerts := HudAlerts.new()
	canvas.add_child(alerts)
	# Driven by hand below, in steps of a frame or so.
	alerts.set_process(false)
	return alerts


func _run(alerts: HudAlerts, seconds: float) -> void:
	var steps := ceili(seconds / 0.05)
	for _i in steps:
		alerts._process(seconds / steps)


func _test_hud_notice() -> void:
	var alerts := _hud()
	await wait_frames(1)
	alerts.show_place("JAPANESE GARDEN")
	_run(alerts, 0.1)
	check_eq(alerts.get_current(), "JAPANESE GARDEN", "the name shows")
	_run(alerts, HudAlerts.NOTICE_TIME)
	check_eq(alerts.get_current(), "", "and goes after its time")
	alerts.show_notice("WARD DESTROYED")
	alerts.show_place("HELWAN OBSERVATORY")
	_run(alerts, 0.1)
	check_eq(alerts.get_current(), "WARD DESTROYED", "a notice comes first")
	_run(alerts, HudAlerts.NOTICE_TIME)
	check_eq(alerts.get_current(), "HELWAN OBSERVATORY", "the name waits for it, then shows")
	_run(alerts, HudAlerts.NOTICE_TIME * 0.8)
	check_eq(alerts.get_current(), "HELWAN OBSERVATORY", "for its whole time")
	_run(alerts, HudAlerts.NOTICE_TIME * 0.4)
	check_eq(alerts.get_current(), "", "then goes")
	alerts.show_notice("ORDER: HOLD HERE", HudAlerts.PLACE_WAIT + 5.0)
	alerts.show_place("THE NORTH CEMETERY")
	_run(alerts, HudAlerts.PLACE_WAIT + 6.0)
	check_eq(alerts.get_current(), "", "a name that waited past PLACE_WAIT is dropped")
	alerts.extracting = true
	alerts.show_place("HELWAN METRO STATION")
	_run(alerts, 0.5)
	check(alerts.get_current().begins_with("EXTRACTING"), "the extraction countdown stays over a place name (%s)" % alerts.get_current())
	alerts.extracting = false
	_run(alerts, 0.1)
	check_eq(alerts.get_current(), "HELWAN METRO STATION", "which shows once the extraction is off")
	_run(alerts, HudAlerts.NOTICE_TIME)
	alerts.show_notice("WARD DESTROYED")
	alerts.show_place("THE NORTH CEMETERY")
	alerts.set_current_place("THE NORTH CEMETERY")
	_run(alerts, 1.0)
	alerts.set_current_place("")
	_run(alerts, HudAlerts.NOTICE_TIME)
	check_eq(alerts.get_current(), "", "a name still waiting when the player leaves the place is dropped")
	alerts.show_notice("WARD DESTROYED")
	alerts.show_place("JAPANESE GARDEN")
	_run(alerts, 1.0)
	alerts.set_current_place("JAPANESE GARDEN")
	_run(alerts, HudAlerts.NOTICE_TIME)
	check_eq(alerts.get_current(), "JAPANESE GARDEN", "one whose place the player is still in shows")
	_run(alerts, 1.0)
	alerts.set_current_place("")
	_run(alerts, 0.1)
	check_eq(alerts.get_current(), "JAPANESE GARDEN", "and once on show it ends its time even if the player leaves")


func _test_top_strip() -> void:
	var strip := HudTopStrip.new()
	_root.add_child(strip)
	await wait_frames(1)
	strip.set_site("Helwan", Rect2(-50000, -50000, 100000, 100000))
	var label: Label = strip.get("_site_label")
	check_eq(label.text, "HELWAN", "the site alone")
	strip.set_place("Japanese Garden")
	check_eq(label.text, "HELWAN · JAPANESE GARDEN", "then the place after it")
	strip.set_place("")
	check_eq(label.text, "HELWAN", "and the site alone again outside")
	strip.set_place("Helwan University")
	check_eq(label.text, "HELWAN · UNIVERSITY", "a place named after the site drops the site's name")
	strip.set_place("Ain Helwan Metro Station")
	check_eq(label.text, "HELWAN · AIN HELWAN METRO STATION", "but only a leading one")
	strip.set_place("the East Cemetery")
	check_eq(label.text, "HELWAN · THE EAST CEMETERY", "other names show as given")
	strip.queue_free()
	var early := HudTopStrip.new()
	_root.add_child(early)
	await wait_frames(1)
	early.set_place("Helwan Rail Yard")
	early.set_site("Helwan", Rect2(-50000, -50000, 100000, 100000))
	var early_label: Label = early.get("_site_label")
	check_eq(early_label.text, "HELWAN · RAIL YARD", "a place set before the site is shortened once the site is known")
	early.queue_free()
