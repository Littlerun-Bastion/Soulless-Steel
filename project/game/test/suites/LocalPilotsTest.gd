extends TestSuite

# LocalPilotsTest: Local, the match's chat channel (LocalPilots) and its UI.
# Pilots who join before the intro ends join quietly, later ones are
# announced; dying and extracting leave the same line; Anonymous pilots are
# off the roster, get no lines and speak as "Unknown"; callsigns never
# repeat and named NPCs keep theirs; broadcasts carry where the sender was;
# the player's callsign and Anonymous choice come from the Hangar and are
# saved; reputation drops for an unprovoked kill (less while Anonymous,
# never in the Arena); the HUD feed keeps the last lines and fades when idle;
# quick chat sends presets; the LOC app shows the roster, log and reputation;
# Local lines reach the LOG app. Last, a real Test Arena: NPCs on the
# roster, an NPC killed and one extracting leave the same way, the player's
# kill costs reputation, and speech within earshot shows over a hidden NPC.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const TEST_ARENA := preload("res://game/arena/TestArena.tscn")


# Just enough of a mecha for Local: a callsign, Anonymous, a position.
class FakePilot extends Node2D:
	var callsign := ""
	var is_anonymous := false
	var mecha_name := "Fake"
	var controls_locked := false
	var paused := false
	var is_dead := false
	func _init() -> void:
		add_to_group("mecha")


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []


var _scene = null
var _nodes: Array = []


func run_tests() -> void:
	await case("joins before the intro ends are quiet, later ones announced", _test_join)
	await case("dying and extracting leave Local with the same line", _test_leave)
	await case("Anonymous pilots: off the roster, no lines, 'Unknown'", _test_anonymous)
	await case("callsigns never repeat; named NPCs keep theirs", _test_callsigns)
	await case("a broadcast carries the sender and where it was", _test_broadcast)
	await case("the player's callsign and Anonymous come from the Hangar and save", _test_player_profile)
	await case("reputation: unprovoked kills cost it, less while Anonymous", _test_reputation)
	await case("the HUD feed keeps the last lines and fades when idle", _test_feed)
	await case("quick chat sends a preset as the player", _test_quick_chat)
	await case("the LOC app shows the roster, log and reputation", _test_loc_app)
	await case("Local lines reach the LOG app's LOCAL tab", _test_mech_log)
	await case("in a real match: roster, leaving, reputation, speech", _test_match)
	await before_each()


func before_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	MechOS.close_all()
	PlayerProgress.reset()
	await wait_frames(2)


func _pilot(callsign := "", anonymous := false, pos := Vector2.ZERO) -> FakePilot:
	var pilot := FakePilot.new()
	pilot.callsign = callsign
	pilot.is_anonymous = anonymous
	pilot.position = pos
	add_child(pilot)
	_nodes.append(pilot)
	return pilot


# Every message `local` sends while `body` runs.
func _messages(local: LocalPilots) -> Array:
	var got := []
	local.message.connect(func(entry): got.append(entry))
	return got


func _test_join() -> void:
	var local := LocalPilots.new()
	var got := _messages(local)
	var a := _pilot("Ash")
	local.join(a)
	check(got.is_empty(), "no line for a pilot there from the start")
	check_eq(", ".join(local.get_roster()), "Ash", "but it is on the roster")
	local.go_live()
	var b := _pilot("Wren")
	local.join(b)
	check(got.size() == 1 and got[0].text == "Wren has joined Local", "a later pilot is announced")
	local.join(b)
	check_eq(got.size(), 1, "joining twice changes nothing")


func _test_leave() -> void:
	var local := LocalPilots.new()
	var got := _messages(local)
	var dead := _pilot("Ash")
	var extracted := _pilot("Wren")
	local.join(dead)
	local.join(extracted)
	local.leave(dead)
	local.leave(extracted)
	check_eq(got.size(), 2, "two lines")
	if got.size() == 2:
		check_eq(got[0].text, "Ash has left Local", "the line")
		check_eq(got[1].text, "Wren has left Local", "the same line, whatever the reason")
		check_eq(got[0].kind, got[1].kind, "and the same kind")
	check(local.get_roster().is_empty(), "both are off the roster")


func _test_anonymous() -> void:
	var local := LocalPilots.new()
	local.go_live()
	var got := _messages(local)
	var hidden := _pilot("Shrike", true)
	local.join(hidden)
	check(local.get_roster().is_empty(), "not on the roster")
	check(local.is_in_local(hidden), "but registered")
	check(got.is_empty(), "no join line")
	var entry := local.broadcast(hidden, "back_off")
	check_eq(entry.callsign, "Unknown", "it speaks as Unknown")
	check_eq(LocalPilots.format(entry), "Unknown: Back off.", "shown so")
	local.leave(hidden)
	check_eq(got.size(), 1, "no leave line (only the broadcast)")


func _test_callsigns() -> void:
	var local := LocalPilots.new()
	var names := {}
	var count: int = LocalPilots.callsign_pool().size() + 5
	check(LocalPilots.callsign_pool().size() >= 30, "the callsign list has names (%d)" % LocalPilots.callsign_pool().size())
	for i in count:
		var pilot := _pilot()
		local.join(pilot)
		check(pilot.callsign != "", "a pilot without a callsign gets one")
		names[pilot.callsign] = true
	check_eq(names.size(), count, "none repeats, even past the end of the list")
	var named := _pilot("Lady Volk")
	local.join(named)
	check_eq(named.callsign, "Lady Volk", "a callsign it already has is kept")
	var volk = NPCManager.get_special_npc("Lady Volk")
	var design: Dictionary = NPCManager.get_design_data(volk)
	check_eq(design.get("callsign"), "Lady Volk", "a named NPC's design carries its name as callsign")
	var arena := FakeArena.new()
	add_child(arena)
	_nodes.append(arena)
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	arena.add_child(enemy)
	enemy.setup(arena, design, "Lady Volk")
	enemy.paused = true
	check(enemy.callsign == "Lady Volk" and not enemy.is_anonymous, "the NPC keeps it and is never Anonymous")


func _test_broadcast() -> void:
	var local := LocalPilots.new()
	var got := _messages(local)
	var sender := _pilot("Tern", false, Vector2(1234, -50))
	local.join(sender)
	var entry := local.broadcast(sender, "hostile_spotted")
	check_eq(got.size(), 1, "every listener gets it (signal message)")
	check(entry.sender == sender and entry.kind == "hostile_spotted", "with the sender and kind")
	check_eq(entry.position, Vector2(1234, -50), "and where the sender was")
	check_eq(entry.text, "Hostile spotted.", "a quick chat kind uses its preset text")
	check_eq(local.broadcast(sender, "found_loot", "Crates!").text, "Crates!", "or the text given")
	check_eq(local.get_log().size(), 2, "both are in the log")
	check_eq(LocalPilots.QUICK_CHAT.size(), 5, "five quick chat presets")


func _test_player_profile() -> void:
	check_eq(PlayerProgress.get_callsign(), PlayerProgress.DEFAULT_CALLSIGN, "a new profile has the default callsign")
	PlayerProgress.set_callsign("  Vesper Nine Long Name Here  ")
	check_eq(PlayerProgress.get_callsign(), "Vesper Nine Long", "trimmed and cut to %d" % PlayerProgress.MAX_CALLSIGN_LENGTH)
	PlayerProgress.set_callsign("   ")
	check_eq(PlayerProgress.get_callsign(), "Vesper Nine Long", "an empty one keeps the old")
	PlayerProgress.set_deploy_anonymous(true)
	var arena := FakeArena.new()
	add_child(arena)
	_nodes.append(arena)
	var player = PLAYER.instantiate()
	player.mech_inventory = Inventory.new()
	arena.add_child(player)
	player.setup(arena)
	player.set_physics_process(false)
	check(player.callsign == "Vesper Nine Long" and player.is_anonymous, "the player deploys with them")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.reset()
	PlayerProgress.set_save_data(saved)
	check(PlayerProgress.get_callsign() == "Vesper Nine Long" and PlayerProgress.deploy_anonymous, "both are saved")
	var dep := MechOS.open_app("deployments") as DeploymentsWindow
	dep.anonymous_button.button_pressed = false
	check(not PlayerProgress.deploy_anonymous, "the DEP window's ANONYMOUS toggle sets it")


func _test_reputation() -> void:
	var local := LocalPilots.new()
	var player := _pilot("Me")
	var victim := _pilot("Them")
	var attacker := _pilot("Rude")
	local.note_attack(player, victim)
	local.note_attack(victim, player)
	check(local.struck_first(player, victim) and not local.struck_first(victim, player), "the first hit decides who struck first")
	check_eq(local.score_player_kill(player, victim), LocalPilots.UNPROVOKED_KILL_REPUTATION, "killing someone who didn't strike first costs reputation")
	check_eq(PlayerProgress.get_reputation(), -10, "taken from the player's")
	local.note_attack(attacker, player)
	local.note_attack(player, attacker)
	check_eq(local.score_player_kill(player, attacker), 0, "killing someone who struck first costs nothing")
	var other := _pilot("Other")
	player.is_anonymous = true
	local.note_attack(player, other)
	check_eq(local.score_player_kill(player, other), -5, "half while Anonymous")
	check_eq(PlayerProgress.get_reputation(), -15, "both counted")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PlayerProgress.get_save_data()))
	PlayerProgress.reset()
	check_eq(PlayerProgress.get_reputation(), 0, "a new profile starts at 0")
	PlayerProgress.set_save_data(saved)
	check_eq(PlayerProgress.get_reputation(), -15, "reputation is saved")
	var arena_local := LocalPilots.new()
	arena_local.applies_reputation = false
	arena_local.note_attack(player, victim)
	check_eq(arena_local.score_player_kill(player, victim), 0, "nothing where reputation doesn't apply (the Arena)")


func _test_feed() -> void:
	var local := LocalPilots.new()
	var feed := HudLocalFeed.new()
	add_child(feed)
	_nodes.append(feed)
	feed.setup(local)
	var pilot := _pilot("Ash")
	for i in 6:
		local.broadcast(pilot, "need_help", "line %d" % i)
	var lines := feed.get_lines()
	check_eq(lines.size(), HudLocalFeed.LINES, "only the last %d lines" % HudLocalFeed.LINES)
	check_eq(lines[lines.size() - 1], "Ash: line 5", "newest at the bottom")
	check_eq(feed.modulate.a, 1.0, "shown at full")
	feed._process(HudLocalFeed.IDLE_TIME + HudLocalFeed.FADE_TIME + 0.1)
	check_eq(feed.modulate.a, 0.0, "faded out once idle")
	local.post_bark(pilot, "Contact.")
	check_eq(feed.modulate.a, 1.0, "back with the next line")
	var last: Label = feed._labels[HudLocalFeed.LINES - 1]
	check_eq(last.theme_type_variation, &"LabelMeta", "a bark is the dimmer style")


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _test_quick_chat() -> void:
	var local := LocalPilots.new()
	var got := _messages(local)
	var player := _pilot("Me", false, Vector2(10, 20))
	var menu := HudQuickChat.new()
	add_child(menu)
	_nodes.append(menu)
	menu.setup(player)
	menu.local = local
	check(not menu.handle_input(_key(KEY_3)), "number keys do nothing while it is closed")
	check(menu.handle_input(_action("quick_chat")) and menu.visible, "the quick chat key opens it")
	check(menu.handle_input(_key(KEY_3)), "a number key is taken")
	check(not menu.visible, "and closes it")
	check(got.size() == 1 and got[0].kind == "found_loot" and got[0].sender == player, "preset 3 is sent as the player")
	menu.handle_input(_action("quick_chat"))
	check(menu.handle_input(_action("escape")) and not menu.visible, "Esc closes it")
	player.controls_locked = true
	menu.handle_input(_action("quick_chat"))
	check(not menu.visible, "it doesn't open in a cutscene")


func _test_loc_app() -> void:
	var local := LocalPilots.new()
	LocalPilots.current = local
	local.join(_pilot("Ash"))
	local.join(_pilot("Shrike", true))
	local.broadcast(_pilot("Wren"), "friendly")
	PlayerProgress.add_reputation(-10)
	var window := MechOS.open_app("local") as LocalWindow
	check(window != null, "LOC opens")
	if window == null:
		return
	check_eq(", ".join(window.get_roster()), "Ash", "the roster, without the Anonymous pilot")
	check_eq(" | ".join(window.get_log_lines()), "Wren: Friendly.", "the log")
	check_eq(window.get_reputation_text(), "-10", "the reputation")
	check(not window.is_callsign_editable(), "the callsign is read-only in the field")
	local.broadcast(_pilot("Tern"), "back_off")
	check_eq(window.get_log_lines().size(), 2, "new lines come in")
	MechOS.close_app("local")
	local.active = false
	window = MechOS.open_app("local") as LocalWindow
	check(window.is_callsign_editable(), "out of the field it can be changed")
	check_eq(window.get_log_lines().size(), 2, "and the last match's log is still there")
	window._callsign.text = "Heron"
	window._on_callsign_submitted("Heron")
	check_eq(PlayerProgress.get_callsign(), "Heron", "submitting saves it")
	LocalPilots.current = null


func _test_mech_log() -> void:
	var local := LocalPilots.new()
	local.broadcast(_pilot("Ash"), "need_help")
	var last: Dictionary = MechLog.lines[MechLog.lines.size() - 1]
	check(last.source == "LOC" and last.kind == MechLog.Kind.LOCAL and last.text == "Ash: Need help!", "a Local line is a LOC line of kind LOCAL")
	var window := MechOS.open_app("log") as LogWindow
	window.set_filter(MechLog.Kind.LOCAL)
	var shown := window.get_visible_lines()
	check(not shown.is_empty() and str(shown[shown.size() - 1]).ends_with("Ash: Need help!"), "the LOCAL tab shows it")


func _test_match() -> void:
	var saved_skip: bool = Debug.debug_settings["skip_intro"]
	Debug.debug_settings["skip_intro"] = true
	_scene = TEST_ARENA.instantiate()
	add_child(_scene)
	var ready := await wait_until(func(): return _scene.all_mechas.size() > 2 and _scene.local_pilots.live, 20.0)
	Debug.debug_settings["skip_intro"] = saved_skip
	check(ready, "the Test Arena started and Local went live")
	if not ready:
		return
	var local: LocalPilots = _scene.local_pilots
	check(LocalPilots.current == local, "it is the current channel")
	var player = _scene.player
	check(local.is_in_local(player), "the player is in Local")
	var enemies: Array = _scene.all_mechas.filter(func(m): return m != player)
	var listed := 0
	for e in enemies:
		check(e.callsign != "", "every NPC has a callsign")
		if not e.is_anonymous:
			listed += 1
	check_eq(local.get_roster().size(), listed + (0 if player.is_anonymous else 1), "the roster lists everyone not Anonymous")
	for e in enemies:
		e.is_anonymous = false
		e.set_pause(true)
	var got := _messages(local)

	# Killed by the player, unprovoked: leaves Local and costs reputation.
	var killed = enemies[0]
	local.note_attack(player, killed)
	killed.last_damage_source = {"body": player, "name": "Player"}
	killed.die({"body": player, "name": "Player"}, "Test")
	await wait_until(func(): return got.any(func(e): return e.kind == "left"), 5.0)
	var leave_lines := got.filter(func(e): return e.kind == "left")
	check_eq(leave_lines.size(), 1, "the killed NPC left Local")
	check_eq(PlayerProgress.get_reputation(), LocalPilots.UNPROVOKED_KILL_REPUTATION, "and the unprovoked kill cost reputation")

	# Extracting: the same kind of line, no reputation change.
	var extracting = enemies[1]
	var callsign: String = extracting.callsign
	extracting.last_damage_source = {"body": player, "name": "Player"}
	extracting._on_ExtractTimer_timeout()
	leave_lines = got.filter(func(e): return e.kind == "left")
	check(leave_lines.size() == 2 and leave_lines[1].text == "%s has left Local" % callsign, "an extracting NPC leaves the same way")
	check_eq(PlayerProgress.get_reputation(), LocalPilots.UNPROVOKED_KILL_REPUTATION, "extracting isn't a kill")

	# Speech within earshot shows over the speaker, even hidden from view.
	var speaker = enemies[2]
	# Every NPC dark: a lit speaker, or one in another's cone, would be seen
	# from anywhere.
	for npc in enemies:
		if is_instance_valid(npc):
			npc.auto_illuminator = false
			npc.set_illuminator(false)
	player.set_physics_process(false)
	player.global_rotation = 0.0
	speaker.global_position = player.global_position + Vector2(0, 1200)
	await wait_frames(3)
	for i in 12:
		player._update_view(0.1)
	check(player.is_hidden_from_view(speaker), "the speaker is out of sight behind the player")
	speaker.say("Testing.", 2.0)
	var hud = _scene.PlayerHUD
	check_eq(hud.hud_world_labels.get_speech(speaker), "Testing.", "its speech box is up anyway")
	check(got.any(func(e): return e.kind == "bark" and e.text == "Testing."), "and the line is in Local")
	var far = enemies[3] if enemies.size() > 3 else null
	if far != null:
		far.global_position = player.global_position + Vector2(Barks.EARSHOT + 500.0, 0)
		far.say("Too far.", 2.0)
		check_eq(hud.hud_world_labels.get_speech(far), "", "speech out of earshot isn't shown")
