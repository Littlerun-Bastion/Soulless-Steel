extends TestSuite

# CompanionTest: the player's companions (Phase 5 of the AI brief). A
# companion squad is one the player leads: members follow the player into
# their slots, fight what they see with no order, keep to a follow or hold
# order over a fight while firing on the move, take the player's target on
# an attack order once its callout has landed, and their own callouts land
# in the player's contact store as pings. Standing decides whether an NPC
# offers to buddy up (its hostility toward the player, the player's
# reputation, being spared); an NPC whose help call the player answered
# offers after the fight by its personality's chance; the offer is a bark,
# a Local line and the scene's prompt, taken or declined with a key, lapsing
# in time. The orders menu opens on its key and sends an order on a number.
# A companion the player shoots leaves, one left far behind leaves after a
# while, and a Rat companion turns on a weak, lonely player. A Guardian that
# sees a pilot it has nothing against attacked joins it. Last, a real Test
# Arena: the starting companion, an offer accepted on the keys, an order
# given and acknowledged, the Local lines.

const ENEMY := preload("res://game/mecha/Enemy.tscn")
const MECHA := preload("res://game/mecha/Mecha.tscn")
const TEST_ARENA := preload("res://game/arena/TestArena.tscn")


class FakeArena extends Node2D:
	var mechas: Array = []
	var player = null
	var local_pilots := LocalPilots.new()
	var offers: Array = []
	var joined: Array = []
	var squads: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return []
	func get_lock_areas() -> Array:
		return []
	func get_safe_position() -> Vector2:
		return Vector2(-5000, -5000)
	func get_random_position() -> Vector2:
		return Vector2(randf_range(-3000, 3000), randf_range(-3000, 3000))
	func offer_buddy(npc) -> bool:
		offers.append(npc)
		return true
	func buddy_up(npc, other) -> bool:
		joined.append([npc, other])
		var squad := Squad.new()
		squad.setup("", false)
		squad.add(other)
		squad.add(npc)
		squads.append(squad)
		return true
	func player_squad(_create := false):
		for squad in squads:
			if squad.is_player_led():
				return squad
		return null


# A round's area as the NPC's proximity sensor sees it.
class FakeRound extends RefCounted:
	var original_mecha_info = null


# Just enough of a player for the orders menu.
class FakeOrderer extends Node2D:
	var controls_locked := false
	var paused := false
	var is_dead := false
	var orders: Array = []
	func give_order(kind: String) -> bool:
		orders.append(kind)
		return true


var _arena: FakeArena = null
var _scene = null
var _spoken: Array = []


func run_tests() -> void:
	await case("a companion follows the player into its slot and fights what it sees", _test_follow)
	await case("follow and hold orders keep it from fighting; it fires on the move", _test_orders_hold)
	await case("an attack order: the player's target, once the callout lands; regroup ends on arrival", _test_attack)
	await case("a companion's callout pings the player's HUD store", _test_sharing)
	await case("standing: hostility, reputation and being spared; the offer by rate and after a help call", _test_standing)
	await case("the orders menu opens on its key and sends an order on a number", _test_menu)
	await case("a companion shot by the player leaves; one left far behind leaves in time", _test_leaving)
	await case("a Rat companion turns on a weak, lonely player", _test_rat)
	await case("a Guardian joins a pilot it sees attacked", _test_guardian)
	await case("in a real match: the starting companion, an offer on the keys, an order", _test_match)
	await before_each()


func _init() -> void:
	slow = true


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	if is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	_spoken.clear()
	Barks.reset_cooldown()
	PlayerProgress.reset()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	LocalPilots.current = _arena.local_pilots
	var region := NavigationRegion2D.new()
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = nav
	_arena.add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


# An NPC that thinks for itself, held still (paused) unless `run`, facing +x.
func _enemy(pos: Vector2, type := Personality.Type.PROFESSIONAL, run := false) -> Mecha:
	var enemy = ENEMY.instantiate()
	enemy.mech_inventory = Inventory.new()
	enemy.position = pos
	_arena.add_child(enemy)
	var design: Dictionary = PlayerProgress.DEFAULT_MECHA.duplicate()
	design["personality"] = NPCManager._personality_from_string(str(Personality.Type.keys()[type]).to_lower())
	enemy.setup(_arena, design, "Companion test %s %d" % [Personality.Type.keys()[type], _arena.mechas.size()])
	enemy.is_anonymous = false
	enemy.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	enemy.set_scripted(false)
	enemy.wait_for_map_sync = 0.0
	enemy.paused = not run
	enemy.spoke.connect(func(_m, text, _s, _a): _spoken.append(text))
	_arena.mechas.append(enemy)
	_arena.local_pilots.join(enemy)
	return enemy


# A plain mecha at `pos`, hot (seen at full range), held still; the player
# as the game tells it (is_player) when `player_name`.
func _mecha(pos: Vector2, player_name := false, callsign := "") -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_illuminator(false)
	mecha.external_temp = 250.0
	mecha.arena = _arena
	mecha.global_rotation = Vector2.UP.angle_to(Vector2.RIGHT)
	if player_name:
		mecha.mecha_name = "Player"
		mecha.callsign = "Drifter"
		_arena.player = mecha
	elif callsign != "":
		mecha.callsign = callsign
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	_arena.local_pilots.join(mecha)
	return mecha


# The player's squad with `members` as its companions.
func _companions(player: Mecha, members: Array) -> Squad:
	var squad := Squad.new()
	squad.setup("", false)
	squad.leader = player
	for m in members:
		squad.add(m)
	_arena.squads.append(squad)
	return squad


func _test_follow() -> void:
	var player := _mecha(Vector2.ZERO, true)
	var buddy := _enemy(Vector2(0, 2500), Personality.Type.PROFESSIONAL, true)
	var squad := _companions(player, [buddy])
	check(squad.is_player_led() and squad.is_in(player) and not squad.is_member(player), "the player leads but isn't a member")
	check_eq(squad.intent(), "roam", "with no order the squad is calm")
	var scored := await wait_until(func(): return str(buddy.logic.get_current_state()) == "follow", 4.0)
	check(scored, "the companion follows (%s)" % str(buddy.logic.get_current_state()))
	var arrived := await wait_until(func(): return buddy.global_position.distance_to(squad.travel_goal(buddy)) < 400.0, 30.0)
	check(arrived, "and gets to its slot by the player (%.0f px off)" % buddy.global_position.distance_to(squad.travel_goal(buddy)))
	check(not buddy.should_attack(player), "the player is never its target")
	# With no order it fights what it sees (within its engage range from
	# its slot behind the player).
	var foe := _mecha(Vector2(1000, 0), false, "Foe")
	buddy.mark_traitor(foe)
	buddy.knowledge.see(foe, foe.global_position)
	var fights := await wait_until(func(): return str(buddy.logic.get_current_state()) == "engage", 4.0)
	check(fights, "with no order it fights a foe it sees (%s)" % str(buddy.logic.get_current_state()))


func _test_orders_hold() -> void:
	var player := _mecha(Vector2.ZERO, true)
	var buddy := _enemy(Vector2(0, 600), Personality.Type.PROFESSIONAL, true)
	var squad := _companions(player, [buddy])
	var foe := _mecha(Vector2(1000, 0), false, "Foe")
	foe.flag_grace = 1.0e9
	buddy.mark_traitor(foe)
	buddy.knowledge.see(foe, foe.global_position)
	await wait_until(func(): return str(buddy.logic.get_current_state()) == "engage", 4.0)
	var acks := _spoken.size()
	squad.give_order("follow", player.global_position)
	check(_spoken.size() > acks or Time.get_ticks_msec() < buddy._bark_ready_ms, "it acknowledges the order (unless its barks are on cooldown)")
	var follows := await wait_until(func(): return str(buddy.logic.get_current_state()) == "follow", 3.0)
	check(follows, "a follow order pulls it out of the fight (%s)" % str(buddy.logic.get_current_state()))
	check(buddy.logic.scores.get("follow", 0.0) > buddy.logic.scores.get("engage", 0.0), "the order outscores engage")
	# It still fires on the move at what it sees.
	foe.flag_grace = 0.0
	var shots := [0]
	buddy.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	var fired := await wait_until(func(): return shots[0] > 0, 6.0)
	check(fired, "and fires on the move at the foe in sight")
	# Hold: its slot sits round the hold point, facing as the player did.
	player.global_position = Vector2(-2000, -2000)
	squad.give_order("hold", Vector2(0, 0))
	var goal: Vector2 = squad.travel_goal(buddy)
	check(goal.distance_to(Vector2.ZERO) < Squad.SPACING and goal.distance_to(player.global_position) > 2000.0,
			"a hold order keeps its slot round the hold point, not the player")
	check(str(buddy.logic.get_current_state()) == "follow", "holding is the follow intent at the hold point")
	# Flee still wins over an order.
	buddy.is_exposed = true
	buddy.logic.evaluate_now(buddy)
	check(buddy.logic.scores.get("flee", 0.0) > buddy.logic.scores.get("follow", 0.0), "fleeing for its life beats the order")


func _test_attack() -> void:
	var player := _mecha(Vector2.ZERO, true)
	var a := _enemy(Vector2(0, 600))
	var b := _enemy(Vector2(0, -600))
	var squad := _companions(player, [a, b])
	var foe := _mecha(Vector2(1200, 0), false, "Foe")
	check(not a.knowledge.knows(foe), "the companion knows nothing of the target")
	squad.give_order("attack", player.global_position, foe)
	check_eq(squad.order, "attack", "the order stands")
	check_eq(squad.intent(), "engage", "the squad's intent is a fight")
	check_eq(a.get_relationship(foe).hostility, 1.0, "the target is the squad's foe")
	a.logic.behaviour._check_targets(a)
	check(not a.valid_target, "not a target until the callout lands")
	var landed := await wait_until(func():
		squad.deliver()
		return a.knowledge.knows(foe) and b.knowledge.knows(foe), 5.0)
	check(landed, "the player's callout lands with both companions")
	a.logic.behaviour._check_targets(a)
	check(a.valid_target == foe, "then it is the companion's target")
	a.logic.evaluate_now(a)
	check(a.logic.scores.get("follow", 0.0) == 0.0 and a.logic.scores.get("engage", 0.0) > 0.0, "and it goes to fight it")
	foe.is_dead = true
	squad.deliver()
	check_eq(squad.order, "free", "the order ends with its target")
	# Regroup ends once everyone is back.
	a.global_position = Vector2(5000, 5000)
	squad.give_order("regroup", player.global_position)
	squad.deliver()
	check_eq(squad.order, "regroup", "a regroup stands while a member is away")
	a.global_position = squad.travel_goal(a)
	b.global_position = squad.travel_goal(b)
	squad.deliver()
	check_eq(squad.order, "free", "and ends once everyone is back in its slot")


func _test_sharing() -> void:
	var player := _mecha(Vector2.ZERO, true)
	var buddy := _enemy(Vector2(0, 600))
	var squad := _companions(player, [buddy])
	var foe := _mecha(Vector2(1400, 0), false, "Foe")
	buddy.mark_traitor(foe)
	buddy.knowledge.see(foe, foe.global_position)
	buddy.logic.behaviour._check_targets(buddy)
	check(buddy.valid_target == foe, "the companion takes the foe as its target and calls it out")
	var landed := await wait_until(func():
		squad.deliver()
		return not player.contacts.best_for(foe).is_empty(), 5.0)
	check(landed, "the callout lands in the player's contact store")
	var contact: Dictionary = player.contacts.best_for(foe)
	check(contact.get("source") == "squad" and contact.get("reveal") == "ping", "as a squad contact, a ping on the HUD")


func _test_standing() -> void:
	var player := _mecha(Vector2(800, 0), true)
	var npc := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	check(npc.standing_with_player(), "a Guardian with nothing against the player and a clean reputation stands well")
	npc.add_hostility(player, 0.5)
	check(not npc.standing_with_player(), "not once it holds a grudge")
	npc.add_hostility(player, -0.5)
	PlayerProgress.add_reputation(-10)
	check(not npc.standing_with_player(), "nor with the player's reputation below zero")
	npc.knowledge.spared_by[player.get_instance_id()] = true
	check(npc.standing_with_player(), "a pilot the player spared stands well whatever the reputation")
	npc.knowledge.spared_by.clear()
	PlayerProgress.add_reputation(10)
	# The offer: a bark, a Local line, the scene's prompt, once.
	var lines := []
	_arena.local_pilots.message.connect(func(entry): lines.append(entry))
	npc.knowledge.see(player, player.global_position)
	npc.paused = false
	_arena.player = player
	npc.offer_buddy()
	check(_arena.offers == [npc], "the offer reaches the scene")
	check(lines.any(func(e): return e.kind == "buddy_offer" and e.sender == npc), "and Local")
	check(_spoken.any(func(t): return t.contains("team") or t.contains("cover") or t.contains("wingman")), "with a line out loud")
	npc._consider_offer(100.0)
	check_eq(_arena.offers.size(), 1, "an NPC offers once")
	# After a help call the player answered: a chance by personality.
	check_eq(npc.help_offer_chance(), 0.8, "a Guardian's chance after an answered help call")
	check_eq(_enemy(Vector2(0, 600), Personality.Type.HUNTER).help_offer_chance(), 0.3, "a Hunter's")
	check_eq(_enemy(Vector2(0, 1200), Personality.Type.SCAVENGER).help_offer_chance(), 0.6, "anyone else's")
	var foe := _mecha(Vector2(0, -1500), false, "Foe")
	var caller := _enemy(Vector2(0, -600), Personality.Type.SCAVENGER)
	caller._help_called_at = caller.knowledge.now()
	caller._help_foe = foe
	caller._on_attack_witnessed(player, foe)
	check(caller._help_answered, "the player shooting the foe it called about answers the call")
	var other := _enemy(Vector2(0, -1200), Personality.Type.SCAVENGER)
	other._on_attack_witnessed(player, foe)
	check(not other._help_answered, "not for an NPC that didn't call")
	# The rate: an unseen or far player never gets an offer.
	var far := _enemy(Vector2(-4000, 0), Personality.Type.GUARDIAN)
	far._consider_offer(1000.0)
	check(not _arena.offers.has(far), "an NPC that doesn't see the player never offers")


func _test_menu() -> void:
	var orderer := FakeOrderer.new()
	add_child(orderer)
	var menu := HudSquadOrders.new()
	add_child(menu)
	menu.setup(orderer)
	check(not menu.handle_input(_key(KEY_2)), "number keys do nothing while it is closed")
	check(menu.handle_input(_action("squad_orders")) and menu.visible, "the squad orders key opens it")
	check(menu.handle_input(_key(KEY_2)) and not menu.visible, "a number key is taken and closes it")
	check_eq(orderer.orders, ["hold"], "order 2 is hold here")
	menu.handle_input(_action("squad_orders"))
	check(menu.handle_input(_action("escape")) and not menu.visible, "Esc closes it")
	orderer.controls_locked = true
	menu.handle_input(_action("squad_orders"))
	check(not menu.visible, "it doesn't open in a cutscene")
	check_eq(Squad.ORDERS, ["follow", "hold", "attack", "regroup"], "the four orders, in menu order")
	menu.queue_free()
	orderer.queue_free()


func _test_leaving() -> void:
	var player := _mecha(Vector2.ZERO, true)
	var buddy := _enemy(Vector2(0, 600))
	var squad := _companions(player, [buddy])
	var lines := []
	_arena.local_pilots.message.connect(func(entry): lines.append(entry))
	var shot := FakeRound.new()
	shot.original_mecha_info = {"name": player.mecha_name, "body": player}
	buddy._on_nearby_projectile_area_entered(shot)
	check(not squad.is_member(buddy) and buddy.knowledge.squad == null, "a companion the player shoots leaves")
	check(lines.any(func(e): return e.kind == "buddy_left"), "and says so in Local")
	check_eq(buddy.get_relationship(player).hostility, 0.25, "and takes the shot as anyone would")
	# Far behind for too long.
	var other := _enemy(Vector2(0, -600))
	squad = _companions(player, [other])
	other.paused = false
	other.global_position = Vector2(8000, 0)
	other._far_time = other.LEAVE_TIME - 0.5
	other._tick_companion(0.4)
	check(squad.is_member(other), "far behind but not yet for long enough, it stays")
	other._tick_companion(0.2)
	check(not squad.is_member(other), "left far behind for LEAVE_TIME it goes its own way")
	other.paused = true


func _test_rat() -> void:
	var player := _mecha(Vector2(300, 0), true)
	var rat := _enemy(Vector2.ZERO, Personality.Type.RAT)
	var mate := _enemy(Vector2(0, 600), Personality.Type.PROFESSIONAL)
	var squad := _companions(player, [rat, mate])
	rat.knowledge.see(player, player.global_position)
	check(not rat.would_betray_player(), "a whole player with another companion about is safe")
	squad.remove(mate)
	check(not rat.would_betray_player(), "alone, but whole: still safe")
	player.hp = player.max_hp * 0.3
	# The health it sees refreshes every half second of its own time.
	rat.knowledge.contacts.advance(1.0)
	rat.knowledge.see(player, player.global_position)
	check(rat.would_betray_player(), "weak and alone: the Rat would turn")
	rat.betray_player()
	check(not squad.is_member(rat) and rat.get_relationship(player).hostility == 1.0, "and does: it leaves and hates the player")
	check(rat.knowledge.knows(player), "knowing where the player is")
	check(_spoken.any(func(t): return t.contains("personal") or t.contains("ride") or t.contains("tired") or t.contains("back")), "with a line")


func _test_guardian() -> void:
	var guardian := _enemy(Vector2.ZERO, Personality.Type.GUARDIAN)
	var victim := _enemy(Vector2(500, 0), Personality.Type.PROFESSIONAL)
	var attacker := _mecha(Vector2(1200, 0), false, "Bully")
	guardian.knowledge.see(victim, victim.global_position)
	guardian.add_hostility(attacker, 0.5)
	for i in 20:
		guardian._joined = false
		guardian._on_attack_witnessed(attacker, victim)
		if not _arena.joined.is_empty():
			break
	check(not _arena.joined.is_empty(), "a Guardian that sees a pilot it has nothing against attacked joins it")
	if not _arena.joined.is_empty():
		check(guardian.knowledge.squad != null and guardian.knowledge.squad.is_member(victim), "they are a squad now")
	var hostile := _enemy(Vector2(0, 700), Personality.Type.GUARDIAN)
	hostile.knowledge.see(victim, victim.global_position)
	hostile.add_hostility(victim, 0.5)
	hostile.add_hostility(attacker, 0.5)
	var before := _arena.joined.size()
	for i in 20:
		hostile._joined = false
		hostile._on_attack_witnessed(attacker, victim)
	check_eq(_arena.joined.size(), before, "not a pilot it holds a grudge against")


func _test_match() -> void:
	TransitionManager.captured.clear()
	var saved_skip = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true
	_scene = TEST_ARENA.instantiate()
	add_child(_scene)
	var ready := await wait_until(func(): return _scene.player_squad(false) != null and _scene.local_pilots.live \
			and is_instance_valid(_scene.player) and not _scene.player.paused, 20.0)
	Debug.debug_settings["skip_intro"] = saved_skip
	check(ready, "the Test Arena started with the player's squad")
	var squad: Squad = _scene.player_squad(false)
	check(squad != null and squad.alive_members().size() == _scene.STARTING_COMPANIONS, "the arena starts the player with a companion")
	if squad == null:
		return
	var player = _scene.player
	var companion = squad.alive_members()[0]
	check(companion.knowledge.squad == squad and companion.global_position.distance_to(player.global_position) < 1500.0, "beside the player")
	# An offer, taken on the key.
	var npc = _scene.all_mechas.filter(func(m): return m != player and "knowledge" in m and m.knowledge.squad == null)[0]
	var lines := []
	_scene.local_pilots.message.connect(func(entry): lines.append(entry))
	check(_scene.offer_buddy(npc), "an offer goes up")
	await wait_frames(2)
	check(_scene.PlayerHUD.hud_alerts.get_current().contains("OFFERS TO BUDDY UP"), "the HUD says who offers and the keys (%s)" % _scene.PlayerHUD.hud_alerts.get_current())
	check(not _scene.offer_buddy(companion), "one offer at a time")
	player._input(_action("accept_offer"))
	check(squad.is_member(npc) and npc.knowledge.squad == squad, "the accept key takes it: the NPC is a companion")
	check(lines.any(func(e): return e.kind == "buddy_accept" and e.sender == npc), "Local says so")
	check(_scene.pending_offer.is_empty(), "the offer is spent")
	# An order, acknowledged.
	var said := []
	npc.spoke.connect(func(_m, text, _s, _a): said.append(text))
	player.global_position = npc.global_position + Vector2(400, 0)
	check(_scene.give_order("hold"), "a hold order is taken")
	check_eq(squad.order, "hold", "the squad holds")
	await wait_frames(2)
	check(_scene.PlayerHUD.hud_alerts.get_current().contains("HOLD"), "the HUD confirms it (%s)" % _scene.PlayerHUD.hud_alerts.get_current())
	check(not said.is_empty() or Time.get_ticks_msec() < npc._bark_ready_ms, "the companion acknowledges (unless its barks are on cooldown)")
	# Declining.
	var third = _scene.all_mechas.filter(func(m): return m != player and "knowledge" in m and m.knowledge.squad == null)[0]
	_scene.offer_buddy(third)
	player._input(_action("decline_offer"))
	check(_scene.pending_offer.is_empty() and third.knowledge.squad == null, "the decline key turns an offer down")
	# The keys and the menu are in place.
	check(InputMap.has_action("squad_orders") and InputMap.has_action("accept_offer") and InputMap.has_action("decline_offer"), "the keys exist")
	check(_scene.PlayerHUD.hud_squad_orders != null, "the orders menu is on the HUD")


func _key(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
