class_name Squad
extends RefCounted

## A squad of two or three NPCs that move and fight together (the player's
## companions are a squad with the player as leader, Phase 5). The scene
## owns them (CombatScene.squads); each member's knowledge points at its
## squad (NPCKnowledge.squad).
##
## Leader: the first member, then the next alive one when it dies. The
## leader's intent is the squad's: while it is calm (roaming, investigating,
## looting, leaving) the members follow it in a loose formation
## (travel_goal: beside or behind it, SPACING px apart, never in a line);
## in a fight each member runs its own tactics in its role.
## Roles (assign_roles): the anchor holds at range and keeps the target busy
## (the leader, or the first direct-fire build); the flanker moves to a
## position at least FLANK_ANGLE off the anchor's bearing to the target
## (the next direct-fire build); the support (a third member with indirect
## weapons or sensors) fights with its AoE and covers withdrawals with
## smoke. Roles are assigned again when a member dies.
## Callouts are barks: a member that calls out a contact (share_contact)
## puts it in its squadmates' stores after SHARE_DELAY s (deliver), as a
## "squad" contact, whether or not the bark got a line.
## Morale: a member's death raises its squadmates' panic; the leader's
## death is judged by loyalty (BaseBehaviour._on_mate_died). Shooting a
## member makes the whole squad hostile to the shooter (hostile_to). A
## member that opens a fallen member's wreck reads who killed it and bears
## a grudge for the rest of the expedition (fallen, BaseBehaviour.do_loot).
## Local shows a tag before each member's callsign ("[HLX] Viktor"), none
## for an Anonymous squad.
##
## The player's companions (Phase 5) are a squad whose leader is the player
## (is_player_led): the player is the leader but not in `members`. The player
## gives orders (give_order, from HudSquadOrders): "free" (none: members keep
## their travel slots and fight what they see), "follow" (stick to the player,
## firing on the move only), "hold" (stand round order_point), "attack" (the
## player's target, order_target, shared as a callout and hated), "regroup"
## (follow, sprinting). Members' callouts reach the player's contact store
## too (deliver), so they show on the HUD as pings.

## Seconds between a callout and the contact landing in squadmates' stores,
## and how long that contact stays live. Placeholders.
const SHARE_DELAY := 1.0
const SHARE_TTL := 2.5
## Formation spacing (px): 25 to 40 m. Placeholder.
const SPACING := 650.0
## Beyond this (px) from the leader a member is called to regroup; the
## leader says so at most every REGROUP_BARK_INTERVAL s. Placeholders.
const REGROUP_DISTANCE := 2000.0
const REGROUP_BARK_INTERVAL := 20.0
## The flanker's angle off the anchor's bearing to the target. Placeholder.
const FLANK_ANGLE := deg_to_rad(60.0)
## How much hostility every member gains toward whoever shoots one of them.
## Placeholder.
const MEMBER_SHOT_HOSTILITY := 0.25
const ROLE_ANCHOR := "anchor"
const ROLE_FLANKER := "flanker"
const ROLE_SUPPORT := "support"
## The orders a player can give, in menu order (HudSquadOrders).
const ORDERS := ["follow", "hold", "attack", "regroup"]
const ORDER_LABELS := {"follow": "FOLLOW ME", "hold": "HOLD HERE", "attack": "ATTACK MY TARGET", "regroup": "REGROUP"}

var tag := ""
var anonymous := false
var leader = null
## The player's standing order to the squad ("free" for none), where to hold
## and which way to face there, and the target to attack.
var order := "free"
var order_point := Vector2.INF
var order_facing := Vector2.UP
var order_target = null
## Members (Enemies), the leader among them when it is an NPC.
var members: Array = []
## Member instance id -> role.
var roles := {}
## Dead members: [{name, callsign, killer}] (the killer's callsign as others
## saw it, "" if unknown).
var fallen: Array[Dictionary] = []
var _shares: Array[Dictionary] = []
var _slots := {}
var _regroup_said_ms := -100000


func setup(squad_tag: String, is_anonymous := false) -> void:
	tag = squad_tag
	anonymous = is_anonymous


func add(member) -> void:
	if members.has(member):
		return
	members.append(member)
	if "knowledge" in member:
		member.knowledge.squad = self
	if leader == null:
		leader = member
	_assign_slots()
	assign_roles()


## Takes `member` out (it died, left, or was abandoned). The leader's place
## passes on.
func remove(member) -> void:
	if not members.has(member):
		return
	members.erase(member)
	if is_instance_valid(member):
		roles.erase(member.get_instance_id())
		_slots.erase(member.get_instance_id())
		if "knowledge" in member:
			member.knowledge.squad = null
	if is_same(leader, member):
		leader = null
		for m in alive_members():
			leader = m
			break
	_assign_slots()
	assign_roles()


func is_member(m) -> bool:
	return members.has(m)


## A member, or the leader (the player, who is never a member).
func is_in(m) -> bool:
	return members.has(m) or is_same(leader, m)


## Whether the player leads this squad (its companions).
func is_player_led() -> bool:
	return leader != null and is_instance_valid(leader) and leader.has_method("is_player") and leader.is_player()


func alive_members() -> Array:
	return members.filter(func(m): return is_instance_valid(m) and not m.is_dead)


## The living squadmates of `member`.
func mates_of(member) -> Array:
	return alive_members().filter(func(m): return not is_same(m, member))


func is_leader(member) -> bool:
	return is_same(leader, member)


func leader_alive() -> bool:
	return leader != null and is_instance_valid(leader) and not leader.is_dead


## The leader's intent, the squad's: an NPC leader's current intent; for the
## player, "engage" under an attack order, else "roam" ("roam" with no
## leader).
func intent() -> String:
	if not leader_alive():
		return "roam"
	if leader.get("logic") != null:
		return str(leader.logic.get_current_state())
	return "engage" if order == "attack" else "roam"


## `member` (or the player leading) died (killed by `killer`, or null) or
## left: its squadmates are told, and leadership passes on.
func on_member_died(member, killer, killed := true) -> void:
	var was_leader := is_leader(member)
	if killed and is_member(member):
		fallen.append({"name": str(member.mecha_name), "callsign": LocalPilots.name_of(member),
				"killer": LocalPilots.name_of(killer) if is_instance_valid(killer) else ""})
	if is_member(member):
		remove(member)
	elif was_leader:
		# The player: the first member leads what is left.
		leader = null
		order = "free"
		for m in alive_members():
			leader = m
			break
		_assign_slots()
		assign_roles()
	if not killed:
		return
	for mate in alive_members():
		if mate.has_method("on_squadmate_died"):
			mate.on_squadmate_died(member, killer, was_leader)


# ---- Orders ----

## The player's order to its companions: `kind` is one of ORDERS; "hold"
## keeps `point` (the player's spot) and the player's facing; "attack" calls
## `target` out to every member and makes it the squad's foe. Members
## acknowledge (Enemy.on_order).
func give_order(kind: String, point := Vector2.INF, target = null) -> void:
	order = kind
	order_point = point
	order_facing = leader.get_facing() if leader_alive() and leader.has_method("get_facing") else Vector2.UP
	order_target = target if kind == "attack" and is_instance_valid(target) else null
	if order_target != null:
		share_contact(leader, order_target, order_target.global_position)
		for m in alive_members():
			if m.has_method("add_hostility"):
				m.add_hostility(order_target, 1.0)
	for m in alive_members():
		if m.has_method("on_order"):
			m.on_order(kind)


## Housekeeping every member's think runs: an attack order ends with its
## target, a regroup once everyone is back.
func _tick_order() -> void:
	if order == "attack" and (not is_instance_valid(order_target) or order_target.is_dead):
		order = "free"
		order_target = null
	elif order == "regroup":
		var back := true
		for m in alive_members():
			if m.global_position.distance_to(travel_goal(m)) > SPACING:
				back = false
				break
		if back:
			order = "free"


## Whether a dead member of this squad had this name (the wreck's victim).
func is_fallen(callsign: String) -> bool:
	for entry in fallen:
		if entry.callsign == callsign or entry.name == callsign:
			return true
	return false


# ---- Roles ----

func assign_roles() -> void:
	roles.clear()
	var alive := alive_members()
	if alive.is_empty():
		return
	var direct: Array = alive.filter(func(m): return _is_direct_fire(m))
	var anchor_mecha = leader if leader_alive() and _is_direct_fire(leader) else (direct[0] if not direct.is_empty() else leader)
	if anchor_mecha == null:
		anchor_mecha = alive[0]
	roles[anchor_mecha.get_instance_id()] = ROLE_ANCHOR
	var flanker = null
	for m in direct:
		if not is_same(m, anchor_mecha):
			flanker = m
			break
	if flanker != null:
		roles[flanker.get_instance_id()] = ROLE_FLANKER
	for m in alive:
		if roles.has(m.get_instance_id()):
			continue
		roles[m.get_instance_id()] = ROLE_SUPPORT if _is_support(m) or flanker != null else ROLE_FLANKER
		if roles[m.get_instance_id()] == ROLE_FLANKER:
			flanker = m


func role_of(member) -> String:
	return str(roles.get(member.get_instance_id(), ROLE_FLANKER))


## The member holding the anchor role (the leader when none).
func anchor():
	for m in alive_members():
		if role_of(m) == ROLE_ANCHOR:
			return m
	return leader if leader_alive() else null


static func _is_direct_fire(member) -> bool:
	if member.get("combat_style") == "artillery":
		return false
	for slot in ["arm_weapon_left", "arm_weapon_right"]:
		if member.build.get(slot) != null:
			return true
	return false


static func _is_support(member) -> bool:
	if member.get("combat_style") == "artillery":
		return true
	var part = member.build.get("internal")
	return part != null and part.get("function") in ["ward", "drone", "seeker", "flare"]


# ---- Travel ----

func _assign_slots() -> void:
	_slots.clear()
	var i := 0
	for m in members:
		if is_same(m, leader):
			continue
		i += 1
		_slots[m.get_instance_id()] = i


## Where `member` should be while the squad travels: beside and behind the
## leader, SPACING px off, each member on its own side, the third further
## back; under a hold order, the same slots round the hold point, facing
## the way the player faced. Vector2.INF with no leader to follow.
func travel_goal(member) -> Vector2:
	if not leader_alive() or is_leader(member):
		return Vector2.INF
	var slot: int = int(_slots.get(member.get_instance_id(), 1))
	var holding: bool = order == "hold" and order_point != Vector2.INF
	var forward: Vector2 = order_facing if holding else (leader.get_facing() if leader.has_method("get_facing") else Vector2.UP)
	var right := forward.orthogonal()
	var offset := Vector2.ZERO
	if slot == 1:
		offset = -forward * SPACING * 0.5 + right * SPACING * 0.8
	elif slot == 2:
		offset = -forward * SPACING * 0.5 - right * SPACING * 0.8
	else:
		offset = -forward * SPACING * 1.2
	return (order_point if holding else leader.global_position) + offset


## Whether `member` has strayed REGROUP_DISTANCE from the leader.
func strayed(member) -> bool:
	return leader_alive() and not is_leader(member) \
			and member.global_position.distance_to(leader.global_position) > REGROUP_DISTANCE


## The leader calls a regroup, at most every REGROUP_BARK_INTERVAL s.
func call_regroup(by) -> void:
	var now := Time.get_ticks_msec()
	if now - _regroup_said_ms < int(REGROUP_BARK_INTERVAL * 1000.0):
		return
	_regroup_said_ms = now
	callout(by, "regroup")


# ---- Callouts ----

## `member` calls `event` out (a bark). Squadmates get the information
## through share_contact; the line itself is heard as any bark is.
func callout(member, event: String, target = null) -> void:
	if is_instance_valid(member) and member.has_method("bark"):
		member.bark(event, target)


## `from` tells its squadmates where `body` is: it lands in their stores
## after SHARE_DELAY s (deliver).
func share_contact(from, body, position: Vector2) -> void:
	if not is_instance_valid(body):
		return
	_shares.append({"from": from, "body": body, "position": position, "kind": ContactStore.kind_of(body),
			"at": Time.get_ticks_msec() + int(SHARE_DELAY * 1000.0)})


## Delivers the callouts that are due, to every other member's contact
## store and the player's when the player leads (the HUD shows them as
## pings). Any member may call it each think; the orders' housekeeping
## rides along.
func deliver() -> void:
	if order != "free":
		_tick_order()
	if _shares.is_empty():
		return
	var now := Time.get_ticks_msec()
	for i in range(_shares.size() - 1, -1, -1):
		var share: Dictionary = _shares[i]
		if now < int(share.at):
			continue
		_shares.remove_at(i)
		if not is_instance_valid(share.body):
			continue
		var listeners := mates_of(share.from)
		if is_player_led() and not is_same(leader, share.from):
			listeners.append(leader)
		for mate in listeners:
			var store = mate.get("contacts")
			if store is ContactStore:
				store.report(share.body, share.kind, share.position, "squad", SHARE_TTL)


# ---- Relationships ----

## Every member turns on whoever shot one of them (never on its leader: a
## player that shoots a companion loses it instead, Enemy.leave_squad).
func hostile_to(attacker, amount := MEMBER_SHOT_HOSTILITY) -> void:
	if is_same(leader, attacker):
		return
	for m in alive_members():
		if not is_same(m, attacker) and m.has_method("add_hostility"):
			m.add_hostility(attacker, amount)


## A fallen member's wreck was opened: every member reads who killed it
## (NPCKnowledge.learn_killer) and bears the grudge.
func learn_killer(record: Dictionary) -> void:
	for m in alive_members():
		if "knowledge" in m:
			m.knowledge.learn_killer(record)
