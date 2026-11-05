class_name KillRecord
extends RefCounted

## What a mecha's death leaves behind for whoever finds it. Mecha.die builds
## one (kill_record), Expedition copies it onto the wreck (Wreck.kill_record),
## and opening the wreck shows it beside the loot (KillRecordWindow). A
## Dictionary:
##   "victim"           the dead mecha's name as others see it
##                      (LocalPilots.name_of: "Unknown" if Anonymous)
##   "position"         where it died
##   "time"             match time of the death (LocalPilots.current.now), or 0
##   "killer"           the killer's callsign; "Unknown" if Anonymous, gone,
##                      or nobody; a creature's species
##   "killer_position"  where the killer was at that moment, or null
##   "weapon"           the weapon's part name, or "" if not known
##   "contacts"         the dead mecha's contacts at that moment, live ones
##                      first, then ghosts, newest first: {"kind", "source",
##                      "position", "live", "age" (s since last reported)}

const UNKNOWN := "Unknown"
const WEAPON_TYPES := ["arm_weapon", "shoulder_weapon"]
const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]


static func build(victim: Node2D, source_info, weapon_name) -> Dictionary:
	var killer_body = null
	if typeof(source_info) == TYPE_DICTIONARY:
		killer_body = source_info.get("body")
	elif source_info is Node:
		killer_body = source_info
	var killer := UNKNOWN
	var killer_position = null
	if is_instance_valid(killer_body) and killer_body != victim:
		killer = LocalPilots.name_of(killer_body)
		if killer_body is Node2D:
			killer_position = (killer_body as Node2D).global_position
	var local := LocalPilots.current
	var record := {
		"victim": LocalPilots.name_of(victim),
		"position": victim.global_position,
		"time": local.now if local != null else 0.0,
		"killer": killer,
		"killer_position": killer_position,
		"weapon": weapon_label(weapon_name),
		"contacts": [],
	}
	var store = victim.get("contacts")
	if store is ContactStore:
		var known: Array = []
		for contact in (store as ContactStore).get_all():
			known.append({"kind": contact.kind, "source": contact.source, "position": contact.position,
					"live": contact.live, "age": (store as ContactStore).age(contact)})
		known.sort_custom(func(a, b): return a.live and not b.live or a.live == b.live and a.age < b.age)
		record.contacts = known
	return record


## A weapon's part name from its part id, or "" when there is none.
static func weapon_label(weapon_name) -> String:
	if weapon_name == null or str(weapon_name) == "" or str(weapon_name) == "Test":
		return ""
	var id := str(weapon_name)
	for type in WEAPON_TYPES:
		var parts: Dictionary = PartManager.get_parts(type)
		if parts.has(id):
			var part_name = parts[id].get("part_name")
			return str(part_name) if part_name else id
	return id


## "84 M NE": how far and which way `to` is from `from`.
static func bearing(from: Vector2, to: Vector2) -> String:
	var offset := to - from
	var metres := roundi(offset.length() / MapSenses.PX_PER_METRE)
	if metres == 0:
		return "0 M"
	var octant := posmod(roundi(offset.angle() / (PI / 4.0)), 8)
	return "%d M %s" % [metres, COMPASS[octant]]
