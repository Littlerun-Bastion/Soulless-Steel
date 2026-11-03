extends TestSuite

# ContactsTest: the contact store every mecha keeps (ContactStore) and how
# the player is shown it. Reports are found by kind, source, liveness and
# distance; one body can have a contact per source; a contact not reported
# again becomes a ghost and is dropped later, keeping its last position; a
# freed body leaves its contact behind with no body; a paused mecha's
# contacts don't age; the player's sight and an NPC's sight write contacts;
# a vision contact keeps a mecha behind a wall shown (the Seeker's outlines
# it instead); and the HUD draws ping
# contacts as markers on screen and arrows on the screen's edge off it (with
# kind and distance), both fading as ghosts, plus everyone's contacts with
# the all_contacts debug setting.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const HUD_CONTACTS := preload("res://game/ui/hud/HudContacts.gd")

# A generated building spanning x 0..400, y 0..400.
const BUILDING := [Vector2(0, 0), Vector2(400, 0), Vector2(400, 400), Vector2(0, 400)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null
var _player = null


func run_tests() -> void:
	await case("reports are found by kind, source, liveness and distance", _test_query)
	await case("one body has one contact per source", _test_sources)
	await case("an unreported contact turns into a ghost, then goes", _test_ghosts)
	await case("a freed body leaves its contact, with no body", _test_freed)
	await case("a paused mecha's contacts don't age", _test_paused_clock)
	await case("the player's sight writes contacts", _test_player_sight)
	await case("an NPC's sight writes contacts", _test_npc_sight)
	await case("a vision contact shows a mecha behind a wall", _test_vision)
	await case("ping contacts are HUD markers (edge arrows off screen) that fade as ghosts", _test_hud_markers)
	await case("all_contacts draws every mecha's contacts", _test_debug_all)


func before_each() -> void:
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
	_player = _mecha(Vector2(-600, 200), PLAYER)
	_player.mecha_name = "Player"
	_player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mecha(pos: Vector2, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	_arena.mechas.append(mecha)
	return mecha


func _test_query() -> void:
	var store := ContactStore.new()
	var a := _mecha(Vector2(1000, 0))
	var b := _mecha(Vector2(3000, 0))
	var stalker: Entity = STALKER.instantiate()
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	check_eq(ContactStore.kind_of(a), "mech", "a mecha's kind")
	check_eq(ContactStore.kind_of(stalker), "Stalker", "an Entity's kind is its species")
	store.report(a, "mech", a.global_position, "ward", 2.5)
	store.report(b, "mech", b.global_position, "drone", 2.5)
	store.report(stalker, ContactStore.kind_of(stalker), Vector2(1200, 0), "drone", 2.5)
	check_eq(store.size(), 3, "three contacts")
	check_eq(store.query({"kind": "mech"}).size(), 2, "two mechs")
	check_eq(store.query({"source": "drone"}).size(), 2, "two from the drone")
	check_eq(store.query({"reveal": "ping"}).size(), 3, "wards and drones ping")
	check_eq(store.query({"near": Vector2(1100, 0), "radius": 300.0}).size(), 2, "two within 300 px of a point")
	check_eq(store.query({"body": b}).size(), 1, "one on b")
	check_eq(store.query({"live": false}).size(), 0, "no ghosts yet")
	check_eq(store.best_for(a).position, a.global_position, "the contact keeps the reported position")
	check(store.best_for(_player).is_empty(), "nothing on a body never reported")


func _test_sources() -> void:
	var store := ContactStore.new()
	var a := _mecha(Vector2(1000, 0))
	store.report(a, "mech", Vector2(1000, 0), "ward", 2.5)
	store.advance(1.0)
	store.report(a, "mech", Vector2(1010, 0), "seeker", 0.5)
	check_eq(store.query({"body": a}).size(), 2, "a ward and a Seeker contact on one body")
	check_eq(store.best_for(a).source, "seeker", "the latest live one is the best")
	check(store.has_live_vision(a), "the Seeker is a vision source")
	store.report(a, "mech", Vector2(1020, 0), "ward", 2.5)
	check_eq(store.query({"body": a}).size(), 2, "reporting again updates, it doesn't add")
	store.advance(1.0)
	check(not store.has_live_vision(a), "the Seeker's contact ran out")
	check_eq(store.best_for(a).source, "ward", "a live contact beats a ghost")
	store.forget(a)
	check_eq(store.size(), 0, "forget drops all of a body's contacts")


func _test_ghosts() -> void:
	var store := ContactStore.new()
	var a := _mecha(Vector2(1000, 0))
	store.report(a, "mech", Vector2(1000, 0), "drone", 2.5)
	a.global_position = Vector2(5000, 0)
	store.advance(2.0)
	check(store.best_for(a).live, "live within its ttl")
	check_eq(store.ghost_fade(store.best_for(a)), 0.0, "no fade while live")
	store.advance(1.0)
	var ghost := store.best_for(a)
	check(not ghost.live, "a ghost once its ttl is up")
	check_eq(ghost.position, Vector2(1000, 0), "the ghost stays where it was last put")
	store.advance(ContactStore.GHOST_TIME * 0.5)
	check(absf(store.ghost_fade(ghost) - 0.5) < 0.1, "half faded halfway through (%.2f)" % store.ghost_fade(ghost))
	var revision := store.revision
	store.advance(ContactStore.GHOST_TIME)
	check_eq(store.size(), 0, "dropped once the ghost time is up")
	check(store.revision > revision, "dropping it counts as a change")


func _test_freed() -> void:
	var store := ContactStore.new()
	var a := _mecha(Vector2(1000, 0))
	store.report(a, "mech", Vector2(1000, 0), "ward", 2.5)
	_arena.mechas.erase(a)
	a.free()
	store.advance(0.1)
	var all := store.get_all()
	check_eq(all.size(), 1, "the contact is still there")
	check(all[0].body == null, "with no body")
	check_eq(store.query({"kind": "mech", "live": true}).size(), 1, "and still found by kind")


func _test_paused_clock() -> void:
	var a := _mecha(Vector2(1000, 0))
	await get_tree().physics_frame
	var before: float = a.contacts.now
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(a.contacts.now > before, "the clock runs with the mecha")
	a.set_pause(true)
	before = a.contacts.now
	await get_tree().physics_frame
	await get_tree().physics_frame
	check_eq(a.contacts.now, before, "and stops while it is paused")


# Puts the player at `pos` facing `facing`, then runs its view long enough
# for a full fade.
func _look(pos: Vector2, facing: Vector2) -> void:
	_player.global_position = pos
	_player.global_rotation = Vector2.UP.angle_to(facing)
	await get_tree().physics_frame
	for i in 12:
		_player._update_view(0.1)


func _shown(body) -> bool:
	return not _player.is_hidden_from_view(body) and body.modulate.a > 0.95


func _hidden(body) -> bool:
	return _player.is_hidden_from_view(body) and body.modulate.a < 0.05


func _test_player_sight() -> void:
	var ahead := _mecha(Vector2(-600, -1000))
	var behind := _mecha(Vector2(800, 200))
	await _look(Vector2(-600, 200), Vector2.UP)
	var seen: Dictionary = _player.contacts.best_for(ahead)
	check(not seen.is_empty() and seen.source == "sight" and seen.live, "a mecha in view is a live sight contact")
	check(_player.contacts.best_for(behind).is_empty(), "one behind the building isn't")
	await _look(Vector2(-600, 200), Vector2.DOWN)
	_player.contacts.advance(1.0)
	check(not _player.contacts.best_for(ahead).live, "out of view it turns into a ghost")


func _test_npc_sight() -> void:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = Vector2(-600, -400)
	_arena.add_child(enemy)
	enemy.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Contacts test")
	enemy.set_scripted(false)
	enemy.paused = true
	_arena.mechas.append(enemy)
	# Within the NPC's sight range of a cold mecha (60% of 2000 px); one in
	# the open, one inside the building.
	var open := _mecha(Vector2(-500, -500))
	var walled := _mecha(Vector2(200, 200))
	enemy.global_position = Vector2(-500, 200)
	await get_tree().physics_frame
	enemy.update_senses(0.1)
	var seen: Dictionary = enemy.contacts.best_for(open)
	check(not seen.is_empty() and seen.source == "sight", "what the NPC sees is a sight contact")
	check(enemy.contacts.best_for(walled).is_empty(), "what is behind a wall isn't")


func _test_vision() -> void:
	var behind := _mecha(Vector2(800, 200))
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(behind), "behind the building it is hidden")
	_player.contacts.report(behind, "mech", behind.global_position, "flare", 0.5)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_shown(behind), "under a vision contact it is shown through the wall")
	_player.contacts.advance(1.0)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(behind), "hidden again once the contact runs out")
	_player.contacts.report(behind, "mech", behind.global_position, "seeker", 0.5)
	await _look(Vector2(-600, 200), Vector2.RIGHT)
	check(_hidden(behind) and _player.get_outlined_bodies().has(behind), "under the Seeker's it stays hidden and is outlined")
	check(_player.contacts.has_live_vision(behind) and not _player.contacts.has_live_vision(behind, "seeker"),
			"has_live_vision can leave one source out")


func _hud() -> HudContacts:
	var hud: HudContacts = HUD_CONTACTS.new()
	hud.size = Vector2(1920, 1080)
	_arena.add_child(hud)
	hud.setup(_player, _arena.mechas)
	return hud


# The world point at the middle of the screen, whatever the camera.
func _mid_screen() -> Vector2:
	var to_screen: Transform2D = _player.get_viewport().get_canvas_transform()
	return to_screen.affine_inverse() * (_player.get_viewport().get_visible_rect().size * 0.5)


func _test_hud_markers() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var near_player := _mid_screen()
	var other := _mecha(near_player)
	_player.contacts.report(other, "mech", near_player, "ward", 2.5)
	_player.contacts.report(_player, "mech", _player.global_position, "sight", 0.3)
	hud._process(0.0)
	var marks := hud.get_marks()
	check_eq(marks.size(), 1, "one marker: the ping, not the sight contact")
	if marks.size() == 1:
		check_eq(marks[0].text, "MECH", "labelled with its kind")
		check_eq(marks[0].alpha, 1.0, "fully drawn while live")
	_player.contacts.advance(2.5 + ContactStore.GHOST_TIME * 0.5)
	hud._process(0.0)
	marks = hud.get_marks()
	check(marks.size() == 1 and marks[0].alpha < 0.6 and marks[0].alpha > 0.4, "half faded halfway through its ghost")
	_player.contacts.advance(ContactStore.GHOST_TIME)
	hud._process(0.0)
	check_eq(hud.get_marks().size(), 0, "gone with the ghost")

	# Off screen: an arrow on the screen's edge pointing at it, with its kind
	# and distance from the player.
	var right_of: Vector2 = near_player + Vector2(50000, 0)
	_player.contacts.report(other, "mech", right_of, "ward", 2.5)
	var above := _mecha(near_player + Vector2(0, -400))
	_player.contacts.report(above, "mech", near_player + Vector2(0, -50000), "drone", 2.5)
	hud._process(0.0)
	marks = hud.get_marks()
	var screen: Vector2 = hud.get_viewport_rect().size
	check_eq(marks.size(), 2, "two pings off screen, two markers")
	var to_right := marks.filter(func(m): return m.arrow and m.dir.x > 0.99)
	var to_top := marks.filter(func(m): return m.arrow and m.dir.y < -0.99)
	check(to_right.size() == 1 and absf(to_right[0].at.x - (screen.x - HudContacts.ARROW_MARGIN.x)) < 1.5,
			"an arrow at the right edge for the one to the right")
	check(to_top.size() == 1 and absf(to_top[0].at.y - HudContacts.ARROW_MARGIN.y) < 1.5,
			"an arrow at the top edge for the one above")
	if to_right.size() == 1:
		var metres := roundi(_player.global_position.distance_to(right_of) / HudContacts.PX_PER_METRE)
		check_eq(to_right[0].text, "MECH %dM" % metres, "labelled with its kind and distance")
	_player.contacts.advance(2.5 + ContactStore.GHOST_TIME * 0.5)
	hud._process(0.0)
	check(hud.get_marks().all(func(m): return m.arrow and m.alpha < 0.6), "arrows fade as ghosts too")


func _test_debug_all() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var other := _mecha(_player.global_position + Vector2(200, 0))
	other.mecha_name = "Watcher"
	other.contacts.report(_player, "mech", _mid_screen(), "sight", 0.5)
	hud._process(0.0)
	check_eq(hud.get_marks().size(), 0, "another mecha's contacts are hidden normally")
	var was: bool = Debug.debug_settings["all_contacts"]
	Debug.debug_settings["all_contacts"] = true
	hud._process(0.0)
	var marks := hud.get_marks()
	check(marks.size() == 1 and marks[0].text == "MECH · Watcher" and marks[0].cross,
			"with all_contacts on, drawn as a cross with its owner")
	Debug.debug_settings["all_contacts"] = was
