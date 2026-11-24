class_name Camp
extends RefCounted

# A group of Entities that is only on the map while someone could notice it
# (CampField decides when it wakes and sleeps), and, for an encounter, the
# NPCs fighting them or each other there.
#
# Dormant, a camp is a roster: one entry per member, with its hp and where
# it stands from the camp's site. Nothing of it is in the scene. Awake, its
# members are ordinary Entities on the map (an encounter's NPCs ordinary
# NPCs). Put back to sleep, the survivors go back in the roster with their
# hp, and the site moves to where they ended up, so a camp keeps its losses
# and a cleared one never comes back.
#
# Members killed while it was dormant (CampField's paper fights, an
# encounter's fight before anyone arrived) are kept as remains: they are
# put on the map dead when it wakes, and leave their carcasses there.
#
# Kinds:
#   coyote_pack  a Coyote pack, Spitters included
#   fisher       a Fisher, dormant in its shell
#   tick_swarm   a tick swarm (an entry's "motes" is its size)
#   hunt         an encounter: an NPC fighting a Coyote pack
#   duel         an encounter: two NPCs fighting each other
# An encounter is armed at a time (armed_at) and its fight runs for
# `duration` s from then whether anyone is there or not (progress()). Once
# it wakes, its NPCs are released to the world and what is left of the pack
# goes on as a coyote_pack camp.

enum State { DORMANT, AWAKE, CLEARED }

const PACK := "coyote_pack"
const FISHER := "fisher"
const TICK_SWARM := "tick_swarm"
const HUNT := "hunt"
const DUEL := "duel"
const ENCOUNTERS := [HUNT, DUEL]

## What a sweep counts one tick as (Mecha.TICK_KIND).
const TICK_KIND := "Tick"

var kind := PACK
var site := Vector2.ZERO
var state := State.DORMANT
## {"scene": PackedScene, "species": String, "hp": 0..1, "offset": Vector2,
## "motes": int (tick swarms; 0 for a fresh one)}.
var roster: Array[Dictionary] = []
## {"scene": PackedScene, "offset": Vector2}.
var remains: Array[Dictionary] = []
## An encounter's NPCs before it wakes: {"design": Dictionary, "name":
## String, "offset": Vector2}.
var mechas: Array[Dictionary] = []
## The Entities on the map while it is awake.
var members: Array = []
## Never held back by the awake budget, and never dropped (a quest target).
var pinned := false
## Encounters: when the fight began (CampField's clock), how long it lasts.
var armed_at := -1.0
var duration := 0.0
## A sweep heard while dormant: where it came from and when (CampField's
## clock). The members wake up listening for it.
var heard_at := Vector2.INF
var heard_time := -INF
## Seconds awake with nobody near (CampField puts it to sleep).
var quiet := 0.0
## Seconds since its encounter's fight ended with nobody having woken it.
var unvisited := 0.0


func _init(kind_ := PACK, site_ := Vector2.ZERO) -> void:
	kind = kind_
	site = site_


func is_encounter() -> bool:
	return kind in ENCOUNTERS


## How far its encounter's fight has got, 0 to 1, at `clock`.
func progress(clock: float) -> float:
	if armed_at < 0.0 or duration <= 0.0:
		return 0.0
	return clampf((clock - armed_at) / duration, 0.0, 1.0)


## A dormant member: `scene` at `offset` from the site.
func add_member(scene: PackedScene, species: String, offset := Vector2.ZERO, hp := 1.0, motes := 0) -> void:
	roster.append({"scene": scene, "species": species, "hp": hp, "offset": offset, "motes": motes})


## Members it has, dormant or awake.
func size() -> int:
	return roster.size() + living().size()


func living() -> Array:
	return members.filter(func(m): return is_instance_valid(m) and not m.is_dead)


## Whether there is anything left to put on the map.
func is_empty() -> bool:
	return roster.is_empty() and remains.is_empty() and mechas.is_empty() and living().is_empty()


## What a sweep finds of it while dormant: {kind: count}, as the bodies
## would read (ContactStore.sweep_kind_of: an Entity's species, a tick
## swarm one TICK_KIND per mote). Its NPCs read as mechs.
func sweep_counts() -> Dictionary:
	var counts := {}
	for entry in roster:
		var motes := int(entry.get("motes", 0))
		if motes > 0:
			counts[TICK_KIND] = counts.get(TICK_KIND, 0) + motes
		else:
			var species := str(entry.species)
			counts[species] = counts.get(species, 0) + 1
	if not mechas.is_empty():
		counts["mech"] = counts.get("mech", 0) + mechas.size()
	return counts
