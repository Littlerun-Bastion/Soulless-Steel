class_name ContactStore
extends RefCounted

## What one mecha knows about where other bodies are: its contacts. Every
## mecha has one (Mecha.contacts). Each information source writes into its
## owner's store: the mecha's own sight, and later its devices (wards,
## drones, the Seeker...). The player's HUD draws the player's contacts
## (HudContacts, Player._update_view); NPC code reads its own.
## Unrelated to Messenger's ContactData (the people the player talks to).
##
## A contact is a Dictionary. Callers read it and never change it:
##   body         the mecha or Entity, or null (it was freed, or there never
##                was a body)
##   kind         "mech", or the Entity's species ("Stalker", "Brute"...)
##   position     where the source last put it; frozen once it is a ghost
##   time         store time (s) of that report
##   source       what found it: "sight", "ward", "drone", "seeker", "flare",
##                "biosensor", "alarm", "ir" (the head's IR sensor,
##                IRSensing: a live track on a body it can't make out, kind
##                "unknown", reported every view check) or "light" (a mecha
##                whose illuminator is on, within a screen of an NPC:
##                Illumination.in_light_range)
##   reveal       how the player is shown it, from the source (REVEALS):
##                "ping" a HUD marker at its position, "vision" the body
##                drawn through walls and darkness, "sight" seen anyway
##   live         whether the source still covers it; false = a ghost
##   live_until   store time it turns into a ghost unless reported again
##   ghost_until  store time it is dropped
##
## There is one contact per body and source. A source calls report() on each
## of its updates, with a ttl a little longer than its update interval. A
## contact not reported again within its ttl becomes a ghost, and a ghost is
## dropped GHOST_TIME s later. So no source has to say it lost a body: a body
## that leaves range, or a device that is destroyed, simply stops being
## reported.
##
## The store keeps its own clock (now), advanced by its mecha's
## _physics_process, so a paused or frozen mecha's contacts don't age.
## Expiry is worked out when the store is read and every PRUNE_INTERVAL s,
## never per contact per frame.

## Seconds a ghost stays (the ping marker's fade), unless the store sets its
## own ghost_time. Placeholder.
const GHOST_TIME := 8.0
const PRUNE_INTERVAL := 1.0
## Source -> how the player is shown its contacts. The last four are what
## NPC knowledge writes (NPCKnowledge): a round that gave its shooter away,
## a body heard, a squadmate's callout, a Local message's blurred position.
const REVEALS := {
	"sight": "sight",
	"ward": "ping",
	"drone": "ping",
	"alarm": "ping",
	"seeker": "vision",
	"flare": "vision",
	"biosensor": "vision",
	"ir": "ping",
	"light": "ping",
	"shot": "ping",
	"sound": "ping",
	"squad": "ping",
	"local": "ping",
}
## Details a report may carry on the contact, with their defaults when a
## report leaves them out: the body's velocity as seen, and how whole it
## looked (structural health and hp fraction, for NPC aggression).
const DETAIL_DEFAULTS := {
	"velocity": Vector2.ZERO,
	"health": 1.0,
	"hp_fraction": 1.0,
}

## Seconds a ghost stays in this store. An NPC's store keeps its memories
## longer than the player's HUD fade (Enemy.BODY_LIFETIME).
var ghost_time := GHOST_TIME
## Store time, in game seconds.
var now := 0.0
## Goes up whenever a contact is reported, turns into a ghost or is dropped.
var revision := 0

var _contacts: Array[Dictionary] = []
# Body instance id -> its contacts (one per source).
var _by_body := {}
var _prune_timer := PRUNE_INTERVAL
# The store time expiry was last worked out at.
var _updated_at := -1.0


## The kind a contact records for `body`: an Entity's species, else "mech".
static func kind_of(body: Object) -> String:
	if body is Node and (body as Node).is_in_group("entity"):
		return str(body.get("species"))
	return "mech"


func advance(dt: float) -> void:
	now += dt
	_prune_timer -= dt
	if _prune_timer <= 0.0:
		_prune_timer = PRUNE_INTERVAL
		_update()


## Records that `source` puts `body` (null for none) at `position` now, live
## for `ttl` s. `details` may carry DETAIL_DEFAULTS keys (a report without
## them keeps the contact's last values). Returns the contact.
func report(body: Object, kind: String, position: Vector2, source: String, ttl: float, details := {}) -> Dictionary:
	if not REVEALS.has(source):
		push_error("ContactStore: unknown source '%s'" % source)
		return {}
	_update()
	var contact := _find(body, source)
	if contact.is_empty():
		contact = {"body": body, "body_id": 0, "source": source, "reveal": REVEALS[source]}
		contact.merge(DETAIL_DEFAULTS)
		if body != null:
			contact.body_id = body.get_instance_id()
			if not _by_body.has(contact.body_id):
				_by_body[contact.body_id] = []
			_by_body[contact.body_id].append(contact)
		_contacts.append(contact)
	contact.kind = kind
	contact.position = position
	contact.time = now
	contact.live = true
	contact.live_until = now + ttl
	contact.ghost_until = now + ttl + ghost_time
	for key in details:
		if DETAIL_DEFAULTS.has(key):
			contact[key] = details[key]
	revision += 1
	return contact


## Every contact, live and ghost, oldest report first.
func get_all() -> Array[Dictionary]:
	_update()
	return _contacts.duplicate()


## The contacts matching every key given in `filter`:
##   kind, source, reveal  equal to the contact's
##   live                  true for live only, false for ghosts only
##   body                  that body's contacts
##   near + radius         within radius px of the point near
func query(filter := {}) -> Array[Dictionary]:
	_update()
	var result: Array[Dictionary] = []
	var near: Variant = filter.get("near")
	var radius_sq := 0.0
	if near is Vector2:
		var radius := float(filter.get("radius", 0.0))
		radius_sq = radius * radius
	var pool: Array = _contacts
	if filter.has("body"):
		var body: Object = filter.body
		pool = _by_body.get(body.get_instance_id(), []) if body != null else []
	for contact in pool:
		if filter.has("kind") and contact.kind != filter.kind:
			continue
		if filter.has("source") and contact.source != filter.source:
			continue
		if filter.has("reveal") and contact.reveal != filter.reveal:
			continue
		if filter.has("live") and contact.live != filter.live:
			continue
		if near is Vector2 and contact.position.distance_squared_to(near) > radius_sq:
			continue
		result.append(contact)
	return result


## The live contacts from `source` (one Array, no filter Dictionary).
func live_from(source: String) -> Array[Dictionary]:
	_update()
	var result: Array[Dictionary] = []
	for contact in _contacts:
		if contact.live and contact.source == source:
			result.append(contact)
	return result


## The best contact on `body`: a live one before a ghost, then the latest.
## {} if there is none.
func best_for(body: Object) -> Dictionary:
	_update()
	var best := {}
	if body == null:
		return best
	for contact in _by_body.get(body.get_instance_id(), []):
		if best.is_empty() or (contact.live and not best.live) \
				or (contact.live == best.live and contact.time > best.time):
			best = contact
	return best


## Whether a vision source covers `body` right now (Player._update_view
## shows it through walls and darkness), leaving out `ignore_source` if given.
func has_live_vision(body: Object, ignore_source := "") -> bool:
	_update()
	if body == null:
		return false
	for contact in _by_body.get(body.get_instance_id(), []):
		if contact.live and contact.reveal == "vision" and contact.source != ignore_source:
			return true
	return false


## Seconds since `contact` was last reported.
func age(contact: Dictionary) -> float:
	return now - float(contact.time)


## 0 while `contact` is live, rising to 1 as its ghost runs out.
func ghost_fade(contact: Dictionary) -> float:
	if contact.live:
		return 0.0
	return clampf((now - float(contact.live_until)) / ghost_time, 0.0, 1.0)


## Turns every live contact from `source` that wasn't reported at the
## current store time into a ghost now (an NPC's sight at the end of a
## senses update). No allocation: it walks the contacts in place.
func expire_unrefreshed(source: String) -> void:
	for contact in _contacts:
		if contact.live and contact.source == source and float(contact.time) < now:
			contact.live = false
			contact.live_until = now
			revision += 1


## Drops `body`'s contact from `source`, if it has one (no ghost left).
func drop(body: Object, source: String) -> void:
	var contact := _find(body, source)
	if contact.is_empty():
		return
	_unindex(contact)
	_contacts.erase(contact)
	revision += 1


## Drops every contact on `body`.
func forget(body: Object) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	if not _by_body.has(id):
		return
	for contact in _by_body[id]:
		_contacts.erase(contact)
	_by_body.erase(id)
	revision += 1


func clear() -> void:
	if _contacts.is_empty():
		return
	_contacts.clear()
	_by_body.clear()
	revision += 1


func size() -> int:
	_update()
	return _contacts.size()


func _find(body: Object, source: String) -> Dictionary:
	if body == null:
		return {}
	for contact in _by_body.get(body.get_instance_id(), []):
		if contact.source == source:
			return contact
	return {}


# Turns contacts past their ttl into ghosts, drops ghosts past their time,
# and lets go of bodies that were freed (their contacts stay, body null).
# Does nothing more than once per store time.
func _update() -> void:
	if _updated_at == now:
		return
	_updated_at = now
	for i in range(_contacts.size() - 1, -1, -1):
		var contact: Dictionary = _contacts[i]
		if contact.body_id != 0 and not is_instance_valid(contact.body):
			_unindex(contact)
			contact.body = null
			contact.body_id = 0
			revision += 1
		if now >= contact.ghost_until:
			_unindex(contact)
			_contacts.remove_at(i)
			revision += 1
		elif contact.live and now >= contact.live_until:
			contact.live = false
			revision += 1


func _unindex(contact: Dictionary) -> void:
	var id: int = contact.body_id
	if id == 0 or not _by_body.has(id):
		return
	var list: Array = _by_body[id]
	list.erase(contact)
	if list.is_empty():
		_by_body.erase(id)
