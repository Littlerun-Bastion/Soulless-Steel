class_name NPCKnowledge
extends RefCounted

## Everything one NPC knows, in one place. Enemy holds one (Enemy.knowledge)
## and its behaviour reads it; nothing an NPC decides on comes from anywhere
## else, so an NPC never acts on a body it has no contact on (the fairness
## rule).
##
## Bodies: the mecha's own ContactStore (Mecha.contacts, the same object).
##   - Its own sight writes "sight" contacts (see), live until the next
##     senses update that doesn't see the body (end_sight_update), with the
##     body's velocity, how whole it looked and its Flag.
##   - A round that gave its shooter away writes a "shot" contact
##     (heard_shot); a body heard, a "sound" contact (heard_body).
##   - A body its head's IR sensor picks up but it doesn't see writes an "ir"
##     contact (sensed_heat, kind "unknown": it can't tell what it is): its
##     true position, live like a sight contact until the next senses update
##     that doesn't sense it, but not seen. Like a body heard, the NPC knows
##     where it is and can take it on; unlike one heard, it keeps tracking it
##     exactly behind cover.
##   - A mecha with its illuminator on within a screen of it writes a "light"
##     contact (noticed_light, Illumination.in_light_range): the player sees
##     an illuminator's cone anywhere on screen, so the NPC knows where that
##     mecha is, live, and that it's a mecha (it can take it on, and keeps it
##     while the light stays on), but doesn't see it.
##   - A contact no source refreshes becomes a ghost, frozen where it was,
##     and is dropped after the store's ghost_time: Enemy.BODY_LIFETIME for
##     an NPC. So "forgotten" means the store dropped it.
##   - position_of(body) is where the NPC believes a body is: the best
##     contact's position, or the NPC's own position when it has none
##     (never the body's true position).
## The Flag: a mech the NPC saw raise its Flag by choice is remembered
## (flag_memory), with when it lowered it; one that then attacks is a
## traitor (Enemy). A pilot the NPC saw spare it is remembered (spared_by).
## Sounds: what it heard (Enemy.heard_sound), with lifetimes; the behaviour
## consumes them as it investigates.
## Local (Phase 6): help calls and loot shouts it read (heard_local), each
## with the sender's position blurred once to a random point within
## LEAD_BLUR (the fairness rule: a pilot could place a caller about that
## well from map knowledge), kept LEAD_MEMORY s; the intents help, vulture
## and investigate read them (help_leads, loot_leads). Being swept is
## remembered by time only (swept_at): a sweep gives no bearing. A spot to
## keep away from (avoid_point: a car alarm, where it was swept) for
## AVOID_TIME s, which wandering steers clear of.
## Danger: where it took fire from, with the time; the mines it has seen
## (spot_mines: a mine within MINE_SIGHT_RANGE is seen unless the one roll
## made for it, by panic, misses it for good).
## Panic (0 to 1): rises with hits, fire, being outnumbered, overheating,
## being swept and losing a device, falls while nothing threatens, both
## scaled by courage (tick_panic). The intents, the aim and the barks read it.
## Its own state: self_state() is a frame-cached snapshot of heat, weapons,
## ammo and damaged systems that the intents read.

## The contact source for a mecha given away by its illuminator.
const LIGHT_SOURCE := "light"
## A body heard or a shot's origin stays live this long (s). Placeholder.
const SHOT_TTL := 1.0
const SOUND_TTL := 1.0
## Fire positions are kept this long (s). Placeholder.
const FIRE_MEMORY := 20.0
## How whole a seen body looks is read again at most this often (s): it
## walks the body's armour and components.
const HEALTH_REFRESH := 0.5
## Panic: what each event adds, and how it falls (per second) with nothing
## threatening. Rises are scaled by (1.5 - courage), falls by (0.5 +
## courage). Placeholders.
const PANIC_HIT := 0.05
const PANIC_COMPONENT_LOST := 0.15
const PANIC_UNDER_FIRE_RATE := 0.05
const PANIC_SQUADMATE_LOST := 0.3
const PANIC_OUTNUMBERED_RATE := 0.05
const PANIC_OVERHEAT := 0.1
const PANIC_SWEPT := 0.05
const PANIC_DEVICE_LOST := 0.05
const PANIC_FALL_RATE := 0.05
## Mines: seen within this range (px, 25 m), half of it in smoke; the one
## roll to miss a mine is MINE_MISS_BASE + panic * MINE_MISS_PANIC, plus
## MINE_MISS_HURRY while sprinting or fleeing. Placeholders.
const MINE_SIGHT_RANGE := 500.0
const MINE_SMOKE_MULT := 0.5
const MINE_MISS_BASE := 0.1
const MINE_MISS_PANIC := 0.6
const MINE_MISS_HURRY := 0.2
## Local leads: the blur radius (px, 150 m) and how long a lead is kept (s).
## Placeholders.
const LEAD_BLUR := 3000.0
const LEAD_MEMORY := 60.0
## How long (s) a spot is kept away from. Placeholder.
const AVOID_TIME := 60.0
## The Flag as a contact records it: none, the emergency state, by choice.
const FLAG_NONE := 0
const FLAG_EMERGENCY := 1
const FLAG_VOLUNTARY := 2

var npc = null
var contacts: ContactStore = null
## Sounds heard, each {volume_type, type, position, lifetime, source}. The
## same Array as Enemy.senses.sounds.
var sounds: Array = []
## Positions this NPC took fire from, newest last: {position, time}.
var fire_taken: Array[Dictionary] = []
## Panic, 0 to 1.
var panic := 0.0
## Mechs seen raising their Flag by choice: body instance id -> {body,
## raised_at, lowered_at (-INF while up)}.
var flag_memory := {}
## Pilots that spared this NPC after it raised its Flag: instance id -> true.
var spared_by := {}
## Whether this NPC ignores the player's Flag (rolled once per expedition by
## the player's reputation; Rats always).
var ignores_player_flag := false
## Mines seen: mine node instance id -> {node, position}; mines rolled and
## missed: id -> true.
var known_mines := {}
var missed_mines := {}
## The squad this NPC is in (Squad), or null.
var squad = null
## Pilots this NPC read off wrecks' kill records as killers: callsign -> the
## victim's callsign.
var killers := {}
## Local leads, oldest first: {kind ("need_help", "found_loot"), sender,
## callsign, position (blurred), time, answer (null until the intent has
## rolled whether to act on it)}.
var local_leads: Array[Dictionary] = []
## Store time of the last sweep that found this NPC (-INF for none), and how
## many have.
var swept_at := -INF
var swept_count := 0
## A spot to keep away from, until store time avoid_until.
var avoid_point := Vector2.INF
var avoid_until := -INF
## Tests: a fixed roll (0 to 1) for the mine miss, instead of a random one.
var mine_luck := -1.0

var _self_state_cache = null
var _self_state_frame := -1
var _overheating := false


func setup(enemy) -> void:
	npc = enemy
	contacts = enemy.contacts


## The store's clock (game seconds).
func now() -> float:
	return contacts.now


## Ages what has a lifetime of its own (sounds, fire positions); the contact
## store is advanced by the NPC itself.
func age(dt: float) -> void:
	var to_remove := []
	for sound in sounds:
		sound.lifetime -= dt
		if sound.lifetime <= 0:
			to_remove.append(sound)
	for sound in to_remove:
		sounds.erase(sound)
	while not fire_taken.is_empty() and now() - float(fire_taken[0].time) > FIRE_MEMORY:
		fire_taken.pop_front()
	while not local_leads.is_empty() and now() - float(local_leads[0].time) > LEAD_MEMORY:
		local_leads.pop_front()


# ---- Local ----

## A Local message read (Enemy._on_local_message): a help call or a loot
## shout becomes a lead at a point blurred once within LEAD_BLUR of the
## sender. Returns the lead ({} for a message that is no lead).
func heard_local(entry: Dictionary) -> Dictionary:
	var kind := str(entry.get("kind", ""))
	if kind != "need_help" and kind != "found_loot":
		return {}
	var true_position: Vector2 = entry.get("position", Vector2.ZERO)
	var lead := {
		"kind": kind,
		"sender": entry.get("sender"),
		"callsign": str(entry.get("callsign", "")),
		"position": true_position + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * LEAD_BLUR,
		"time": now(),
		"answer": null,
	}
	local_leads.append(lead)
	return lead


## The leads of one kind, newest first.
func leads_of(kind: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for i in range(local_leads.size() - 1, -1, -1):
		if local_leads[i].kind == kind:
			found.append(local_leads[i])
	return found


func help_leads() -> Array[Dictionary]:
	return leads_of("need_help")


func loot_leads() -> Array[Dictionary]:
	return leads_of("found_loot")


func drop_lead(lead: Dictionary) -> void:
	local_leads.erase(lead)


# ---- Danger ----

## A sweep found this NPC: it knows when, not from where.
func noted_sweep() -> void:
	swept_at = now()
	swept_count += 1


## Keeps away from `point` for AVOID_TIME s (a car alarm, the spot it was
## swept on).
func set_avoid(point: Vector2) -> void:
	avoid_point = point
	avoid_until = now() + AVOID_TIME


## Whether `point` lies within `radius` of the spot it keeps away from.
func avoids(point: Vector2, radius: float) -> bool:
	return avoid_point != Vector2.INF and now() < avoid_until and point.distance_to(avoid_point) < radius


# ---- Bodies ----

## The NPC sees `body` at `position` now.
func see(body, position: Vector2, velocity := Vector2.ZERO) -> Dictionary:
	var contact := contacts.report(body, ContactStore.kind_of(body), position, "sight", npc.SIGHT_CONTACT_TTL)
	contact.velocity = velocity
	if body is Mecha:
		if contacts.now - float(contact.get("health_time", -INF)) >= HEALTH_REFRESH:
			contact.health_time = contacts.now
			contact.health = _structural_health(body)
			contact.hp_fraction = clampf(float(body.hp) / float(body.max_hp), 0.0, 1.0) if body.max_hp > 0 else 1.0
		var flag := flag_state_of(body)
		var before: int = int(contact.get("flag", FLAG_NONE))
		if flag != before:
			contact.flag = flag
			_note_flag_change(body, before, flag)
	_met(body)
	return contact


## A round from `body` arrived; it fired from about `position`.
func heard_shot(body, position: Vector2) -> Dictionary:
	var contact := contacts.report(body, ContactStore.kind_of(body), position, "shot", SHOT_TTL)
	_met(body)
	return contact


## `body` is sensed by its heat at `position` now (see above).
func sensed_heat(body, position: Vector2, velocity := Vector2.ZERO) -> Dictionary:
	var contact := contacts.report(body, IRSensing.KIND, position, IRSensing.SOURCE, npc.SIGHT_CONTACT_TTL)
	contact.velocity = velocity
	return contact


## `body`'s illuminator gives it away at `position` now (see above).
func noticed_light(body, position: Vector2, velocity := Vector2.ZERO) -> Dictionary:
	var contact := contacts.report(body, ContactStore.kind_of(body), position, LIGHT_SOURCE, npc.SIGHT_CONTACT_TTL)
	contact.velocity = velocity
	_met(body)
	return contact


## `body` was heard at `position`.
func heard_body(body, position: Vector2) -> Dictionary:
	var contact := contacts.report(body, ContactStore.kind_of(body), position, "sound", SOUND_TTL)
	_met(body)
	return contact


## Gives the NPC a memory of `body` at `position` that is already stale (a
## ghost): tests and scripted set-ups.
func place(body, position: Vector2) -> Dictionary:
	var contact := contacts.report(body, ContactStore.kind_of(body), position, "sound", 0.0)
	contact.live = false
	contact.live_until = contacts.now
	contacts.revision += 1
	_met(body)
	return contact


## Ends a senses update: every sight, heat or light contact the update
## didn't refresh goes stale now, so "seen" means in sight at the last
## update, and a heat or light track is live only while it holds, whatever
## the ttl.
func end_sight_update() -> void:
	contacts.expire_unrefreshed("sight")
	contacts.expire_unrefreshed(IRSensing.SOURCE)
	contacts.expire_unrefreshed(LIGHT_SOURCE)


## Whether the NPC has any contact on `body`.
func knows(body) -> bool:
	return not best(body).is_empty()


## Whether all the NPC has on `body` is its heat (sensed_heat): it can't tell
## what it is, so it doesn't start a fight with it (Enemy.check_for_targets).
func known_only_by_heat(body) -> bool:
	if best(body).is_empty():
		return false
	for contact in contacts.query({"body": body}):
		if contact.source != IRSensing.SOURCE:
			return false
	return true


## The best contact on `body` ({} for none): live before ghost, then latest.
## A body that is gone or dead is forgotten.
func best(body) -> Dictionary:
	if not is_instance_valid(body) or _is_dead(body):
		return {}
	return contacts.best_for(body)


## Whether `body` was in sight at the last senses update.
func is_seen(body) -> bool:
	var contact := best(body)
	return not contact.is_empty() and contact.live and contact.source == "sight"


## Where the NPC believes `body` is (see above).
func position_of(body) -> Vector2:
	var contact := best(body)
	if contact.is_empty():
		return npc.global_position
	return contact.position


## Seconds since the NPC last saw or heard `body`; INF if it doesn't know it.
func age_of(body) -> float:
	var contact := best(body)
	if contact.is_empty():
		return INF
	return contacts.age(contact)


## The velocity `body` had when last seen (zero when only heard).
func velocity_of(body) -> Vector2:
	var contact := best(body)
	if contact.is_empty():
		return Vector2.ZERO
	return contact.velocity


## How whole `body` looked when last seen: its structural health (0 to 1).
func health_of(body) -> float:
	var contact := best(body)
	if contact.is_empty():
		return 1.0
	return float(contact.health)


## The hp fraction `body` had when last seen.
func hp_fraction_of(body) -> float:
	var contact := best(body)
	if contact.is_empty():
		return 1.0
	return float(contact.hp_fraction)


## The living bodies in sight right now.
func seen_bodies() -> Array:
	var found := []
	for contact in contacts.live_from("sight"):
		var body = contact.body
		if is_instance_valid(body) and not _is_dead(body) and not found.has(body):
			found.append(body)
	return found


## Every living mecha the NPC has a contact on, with where it believes it is:
## [{body, position, live}].
func known_mechas() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen := {}
	for contact in contacts.query({"kind": "mech"}):
		var body = contact.body
		if not is_instance_valid(body) or _is_dead(body) or seen.has(body):
			continue
		seen[body] = true
		var b := contacts.best_for(body)
		found.append({"body": body, "position": b.position, "live": b.live})
	return found


func forget(body) -> void:
	contacts.forget(body)


## The living mechas giving themselves away by their light right now (live
## "light" contacts, noticed_light).
func light_bodies() -> Array:
	var found := []
	for contact in contacts.live_from(LIGHT_SOURCE):
		var body = contact.body
		if is_instance_valid(body) and not _is_dead(body) and not found.has(body):
			found.append(body)
	return found


## The living bodies squadmates called out lately (live "squad" contacts).
func squad_bodies() -> Array:
	var found := []
	for contact in contacts.live_from("squad"):
		var body = contact.body
		if is_instance_valid(body) and not _is_dead(body) and not found.has(body):
			found.append(body)
	return found


# ---- The squad ----

## This NPC's role in its squad ("" with none).
func role() -> String:
	return squad.role_of(npc) if squad != null else ""


## Whether this NPC leads its squad.
func leads() -> bool:
	return squad != null and squad.is_leader(npc)


## A wreck's kill record, read: the killer is remembered by callsign (any
## wreck), and with `grudge` (a fallen squadmate's), if it is still on
## Local's roster, hated outright (hostility 1) for the rest of the
## expedition. An Anonymous killer can't be known.
func learn_killer(record: Dictionary, grudge := true) -> void:
	var killer: String = str(record.get("killer", ""))
	if killer == "" or killer == LocalPilots.UNKNOWN:
		return
	killers[killer] = str(record.get("victim", ""))
	var local: LocalPilots = LocalPilots.current
	if local == null or not grudge:
		return
	var body = local.pilot_named(killer)
	if body != null and not is_same(body, npc):
		npc.add_hostility(body, 1.0)
		AICombatLog.record_squad("grudge")


# ---- The Flag ----

## A body's Flag as the NPC reads it off it: FLAG_NONE, FLAG_EMERGENCY or
## FLAG_VOLUNTARY.
static func flag_state_of(body) -> int:
	if body.get("flag_up") != true:
		return FLAG_NONE
	return FLAG_VOLUNTARY if body.get("flag_voluntary") == true else FLAG_EMERGENCY


## Whether the NPC saw `body` raise its Flag by choice.
func saw_flag_raised(body) -> bool:
	return is_instance_valid(body) and flag_memory.has(body.get_instance_id())


## Whether `body` lowered a Flag it had raised by choice within `window` s,
## as far as the NPC saw.
func flag_lowered_recently(body, window: float) -> bool:
	if not is_instance_valid(body):
		return false
	var entry: Dictionary = flag_memory.get(body.get_instance_id(), {})
	if entry.is_empty():
		return false
	return now() - float(entry.lowered_at) <= window


func _note_flag_change(body, before: int, after: int) -> void:
	var id: int = body.get_instance_id()
	if after == FLAG_VOLUNTARY:
		flag_memory[id] = {"body": body, "raised_at": now(), "lowered_at": -INF}
	elif before == FLAG_VOLUNTARY and after == FLAG_NONE and flag_memory.has(id):
		flag_memory[id].lowered_at = now()


# ---- Danger ----

## The NPC took fire from about `position` just now.
func took_fire_from(position: Vector2) -> void:
	fire_taken.append({"position": position, "time": now()})


## Where it took fire from within the last `max_age` s.
func recent_fire_positions(max_age := FIRE_MEMORY) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for entry in fire_taken:
		if now() - float(entry.time) <= max_age:
			found.append(entry.position)
	return found


## Looks for mines within sight range of the NPC (less in smoke). A mine
## that comes within range for the first time gets one roll to be missed,
## by panic (and by hurry: sprinting or fleeing); a missed mine stays
## unseen. Mines that are gone are forgotten. Returns the mines seen this
## time.
func spot_mines(hurrying: bool) -> Array:
	var seen_now := []
	for id in known_mines.keys():
		if not is_instance_valid(known_mines[id].node):
			known_mines.erase(id)
	var range := MINE_SIGHT_RANGE
	if MapSenses.in_smoke(npc.global_position):
		range *= MINE_SMOKE_MULT
	for mine in npc.mines_near(npc.global_position, range):
		var node = mine.node
		if not is_instance_valid(node):
			continue
		var id: int = node.get_instance_id()
		if known_mines.has(id):
			known_mines[id].position = mine.position
			continue
		if missed_mines.has(id):
			continue
		if MapSenses.in_smoke(mine.position) and range > MINE_SIGHT_RANGE * MINE_SMOKE_MULT \
				and npc.global_position.distance_to(mine.position) > MINE_SIGHT_RANGE * MINE_SMOKE_MULT:
			continue
		var miss := MINE_MISS_BASE + panic * MINE_MISS_PANIC + (MINE_MISS_HURRY if hurrying else 0.0)
		var roll: float = mine_luck if mine_luck >= 0.0 else randf()
		if roll < miss:
			missed_mines[id] = true
			AICombatLog.record_flag("mine_missed")
			continue
		known_mines[id] = {"node": node, "position": mine.position, "trigger_radius": mine.trigger_radius}
		seen_now.append(known_mines[id])
		AICombatLog.record_flag("mine_seen")
	return seen_now


## Whether a mine the NPC knows of lies within `radius` of `point`.
func known_mine_near(point: Vector2, radius: float) -> bool:
	for entry in known_mines.values():
		if entry.position.distance_to(point) <= radius:
			return true
	return false


# ---- Panic ----

## Something frightening happened: panic rises by `amount`, scaled by
## courage.
func raise_panic(amount: float) -> void:
	var courage: float = npc.personality.courage if npc.personality else 0.5
	panic = clampf(panic + amount * (1.5 - courage), 0.0, 1.0)


## A thinking frame's panic: under fire and outnumbered it rises; the
## overheating status coming on adds once; with nothing threatening it falls.
func tick_panic(dt: float, under_fire: bool, enemies_seen: int, overheating: bool) -> void:
	var courage: float = npc.personality.courage if npc.personality else 0.5
	var rise := 0.0
	if under_fire:
		rise += PANIC_UNDER_FIRE_RATE * dt
	if enemies_seen > 1:
		rise += PANIC_OUTNUMBERED_RATE * dt * (enemies_seen - 1)
	if overheating and not _overheating:
		rise += PANIC_OVERHEAT
	_overheating = overheating
	if rise > 0.0:
		panic = clampf(panic + rise * (1.5 - courage), 0.0, 1.0)
	elif not under_fire and enemies_seen == 0:
		panic = clampf(panic - PANIC_FALL_RATE * dt * (0.5 + courage), 0.0, 1.0)


# ---- Own state ----

## Drops the frame's cached own state, so the next read works it out again
## (tests that change the NPC within one frame).
func refresh_state() -> void:
	_self_state_frame = -1


# Frame-memoized: the intents and the flee rule all need this snapshot, and
# computing it walks the weapon slots and the components. Callers only read
# the Dictionary, so sharing one per physics frame is safe.
func self_state(weapon_heat_threshold: float, general_heat_threshold: float) -> Dictionary:
	var frame = Engine.get_physics_frames()
	if _self_state_frame == frame and _self_state_cache != null:
		return _self_state_cache
	_self_state_frame = frame
	_self_state_cache = _compute_self_state(weapon_heat_threshold, general_heat_threshold)
	return _self_state_cache


func _compute_self_state(weapon_heat_threshold: float, general_heat_threshold: float) -> Dictionary:
	var enemy = npc
	var state = {
		"heat_ratio": 0.0,
		"is_overheating": false,
		"is_hot": false,
		"weapons_working": 0,
		"weapons_total": 0,
		"low_ammo": false,
		"no_ammo": false,
		"mobility_damaged": false,
		"sensors_damaged": false,
	}

	# Heat
	if enemy.overheat_temp > 0:
		var worst_heat = maxf(enemy.internal_temp, enemy.external_temp)
		state.heat_ratio = worst_heat / enemy.overheat_temp
		state.is_overheating = state.heat_ratio >= general_heat_threshold
		state.is_hot = state.heat_ratio >= weapon_heat_threshold

	# Weapons and ammo
	var weapon_slots = ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]
	var disabled_keys = ["left_arm_weapon", "right_arm_weapon", "left_shoulder_weapon", "right_shoulder_weapon"]
	var any_has_ammo = false
	var any_low_ammo = false
	for i in weapon_slots.size():
		var node = enemy.get_weapon_part(weapon_slots[i])
		if node and not enemy.disabled_systems[disabled_keys[i]]:
			state.weapons_total += 1
			state.weapons_working += 1
			var max_ammo = enemy.get_max_ammo(weapon_slots[i])
			var total_ammo = enemy.get_total_ammo(weapon_slots[i])
			if typeof(max_ammo) != TYPE_BOOL and typeof(total_ammo) != TYPE_BOOL:
				if total_ammo > 0:
					any_has_ammo = true
				if max_ammo > 0 and float(total_ammo) / float(max_ammo) < 0.25:
					any_low_ammo = true
			else:
				any_has_ammo = true  # battery/melee = unlimited
		elif node:
			state.weapons_total += 1

	state.low_ammo = any_low_ammo
	state.no_ammo = state.weapons_working > 0 and not any_has_ammo

	# Systems
	state.mobility_damaged = enemy.disabled_systems.mobility < 0.8
	state.sensors_damaged = enemy.disabled_systems.sensors < 0.8

	return state


## Armour and component health of a mecha, 0 to 1 (no heat, status or
## weapons, to avoid double-counting in aggression).
static func _structural_health(mecha) -> float:
	var score := 0.0
	var total_pips := 0
	var max_pips := 0
	for part_name in mecha.armor:
		for facing in mecha.armor[part_name]:
			var face = mecha.armor[part_name][facing]
			if face.level > 0:
				total_pips += face.pips
				max_pips += 3
	if max_pips > 0:
		score += (float(total_pips) / float(max_pips)) * 0.55
	else:
		score += 0.55
	var comp_total := 0.0
	var comp_count := 0
	for part_name in mecha.components:
		for comp_name in mecha.components[part_name]:
			var comp = mecha.components[part_name][comp_name]
			if comp.max_hp > 0:
				comp_total += float(comp.hp) / float(comp.max_hp)
			comp_count += 1
	if comp_count > 0:
		score += (comp_total / float(comp_count)) * 0.45
	else:
		score += 0.45
	return clampf(score, 0.0, 1.0)


# A first-time mecha gets its personality-based hostility seeded, so
# factions clash without waiting to be provoked.
func _met(body) -> void:
	if is_instance_valid(body) and body is Node and not (body as Node).is_in_group("entity"):
		npc._seed_relationship(body)


static func _is_dead(body) -> bool:
	return "is_dead" in body and body.is_dead
