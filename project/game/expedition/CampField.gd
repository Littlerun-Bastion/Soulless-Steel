class_name CampField
extends Node

# Every Camp on an Expedition map, and when each is on the map. The
# ExpeditionDirector makes one (start) and puts its Entities in camps
# instead of on the map.
#
# Waking: a dormant camp wakes when something that could notice it comes
# near its site:
#   - the player and every NPC in full simulation (not Enemy.is_distant),
#     out to its head's sight circle (Mecha.sight_radius, undamaged) plus
#     WAKE_MARGIN; the player also when the site is within WAKE_MARGIN of
#     its screen
#   - every device out (wards, drones, flares, Seekers: Device), out to its
#     sensor_range plus WAKE_MARGIN
# Sweeps reach much further but give only counts, so they wake nothing: a
# dormant camp in the cone adds its roster to the counts (sweep_counts), and
# one within Mecha.SWEEP_SOUND_RANGE remembers where the sweep came from, so
# its members wake up listening for it (Entity.hears_sweeps).
# A camp wakes with at most awake_budget Entities on the map in all (the
# rest of its roster waits, and joins it when it next sleeps); a pinned
# camp always wakes whole.
#
# Sleeping: an awake camp goes back to sleep once nothing that would wake it
# has been within its wake reach plus SLEEP_SLACK of its members for
# SLEEP_DELAY s, while none of them is hunting, frenzied or on the player's
# screen. Entities on the map that belong to no camp (a brood, a test's)
# are taken into a new camp the same way, all of a pack together; scripted
# ones never are.
#
# Paper fights: a distant NPC (Enemy.is_distant) within PAPER_REACH of a
# dormant pack or Fisher fights it by rough rules, once a PAPER_TICK: each
# member may land a hit on it (PAPER_STATS: chance, pips, and how it lands as
# the member's real attack does: a Coyote's whip on an external component, a
# Spitter's glob through the shield and armour checks at its pen, a Fisher's
# harpoon straight through; paper_hit), and it may kill one member
# (PAPER_KILL_CHANCE times the member's PAPER_STATS frailty), which joins the
# camp's remains. Tick swarms don't fight on paper.
#
# Encounters (Camp.HUNT, Camp.DUEL) are armed by the director's tension at
# one of the sites laid out at the start (lay_out_sites; arm_encounter).
# Their fight runs on its own clock: while it lasts, gunfire sounds at the
# site every GUNFIRE_INTERVAL s (NPCs and creatures hear it as they hear any
# shot, and the player gets its sound wedge). When it wakes, the NPCs and
# the pack are put on the map as far through the fight as it has got
# (Camp.progress): hurt, some of the pack dead, and once it is over, the
# loser dead (a wreck or carcasses). The NPCs are then ordinary NPCs. A fight
# that ended unvisited is given up after ABANDON_TIME s: the pack's
# survivors stay on as a pack camp, the NPCs are gone.

signal camp_woken(camp, was_encounter: bool)
signal camp_slept(camp)

const TICK := 0.5
const WAKE_MARGIN := 1500.0
const SLEEP_SLACK := 1500.0
const SLEEP_DELAY := 8.0
## Where a dormant camp's members stand from its site, at most (px).
const SPREAD := 250.0
const PAPER_TICK := 1.0
const PAPER_REACH := 2000.0
## Placeholders: species -> [hit chance per PAPER_TICK, damage pips, how it
## lands (paper_hit: armour pen, or EXTERNAL or THROUGH), frailty (how easily
## a mecha kills one)].
const PAPER_STATS := {
	"Coyote": [0.25, 1, EXTERNAL, 1.0],
	"Coyote Spitter": [0.2, 1, 2, 1.0],
	"Fisher": [0.3, 2, THROUGH, 0.25],
}
## paper_hit's `pen` for a hit that skips the armour: on an external
## component, or on any component.
const EXTERNAL := -1
const THROUGH := -2
const PAPER_KILL_CHANCE := 0.3
## Encounters (placeholders).
const ENCOUNTER_DURATION := 90.0
const ABANDON_TIME := 240.0
const GUNFIRE_INTERVAL := Vector2(3.0, 7.0)
const GUNFIRE_RANGE := 10000.0
## Pips of damage an NPC has taken by the end of a hunt or a duel it lives
## through; a hunt kills up to HUNT_PACK_LOSS of the pack before it ends.
const HUNT_DAMAGE := 8
const DUEL_DAMAGE := 10
const HUNT_PACK_LOSS := 0.6
## The chance the NPC wins a hunt that ended before anyone came.
const HUNT_NPC_WIN := 0.6
## An encounter's NPCs stand this far apart (px), its pack round them.
const ENCOUNTER_GAP := 700.0

const COYOTE = preload("res://game/entities/coyote/Coyote.tscn")
const COYOTE_SPITTER = preload("res://game/entities/coyote/CoyoteSpitter.tscn")
const FISHER = preload("res://game/entities/fisher/Fisher.tscn")
const TICK_SWARM = preload("res://game/entities/tick/TickSwarm.tscn")
const ENEMY_SCRIPT = preload("res://game/mecha/Enemy.gd")

var arena = null
var camps: Array[Camp] = []
## Encounter sites: {"position": Vector2, "district": String, "used": bool}.
var sites: Array[Dictionary] = []
## Entities on the map at most before a camp holds members back.
var awake_budget := 24
var clock := 0.0

var _tick_timer := 0.0
var _paper_timer := 0.0
# Loose Entity -> seconds it has been unwatched.
var _loose_quiet := {}
# Camp -> seconds to its encounter's next gunfire.
var _gunfire := {}
var _encounter_count := 0
var _scene_cache := {}


func setup(arena_ref, budget: int) -> void:
	arena = arena_ref
	awake_budget = budget


func _process(dt: float) -> void:
	if not is_instance_valid(arena) or get_tree().paused:
		return
	advance(dt)


## Runs the field for `dt` s (tests drive it directly).
func advance(dt: float) -> void:
	clock += dt
	_tick_timer -= dt
	if _tick_timer <= 0.0:
		_tick_timer = TICK
		update()
	_paper_timer -= dt
	if _paper_timer <= 0.0:
		_paper_timer = PAPER_TICK
		_paper_fights()
	_encounter_clocks(dt)


## Wakes and puts to sleep what should be (see the top).
func update() -> void:
	var wakers := _wakers()
	for camp in camps.duplicate():
		match camp.state:
			Camp.State.DORMANT:
				if _watched(camp.site, wakers, 0.0):
					wake(camp)
			Camp.State.AWAKE:
				_tend_awake(camp, wakers)
	_adopt_loose(wakers)
	for k in range(camps.size() - 1, -1, -1):
		if camps[k].state == Camp.State.CLEARED:
			camps.remove_at(k)


# ---- Making camps ----

## A dormant camp of `kind` at `site`, filled with its usual members (a pack
## of `size` Coyotes, -1 for the director's, `spitters` of them Spitters).
func add_camp(kind: String, site: Vector2, size := 4, spitters := 1) -> Camp:
	var camp := Camp.new(kind, site)
	match kind:
		Camp.PACK, Camp.HUNT:
			fill_pack(camp, size, spitters)
		Camp.FISHER:
			camp.add_member(FISHER, "Fisher")
		Camp.TICK_SWARM:
			camp.add_member(TICK_SWARM, "Tick Swarm")
	camps.append(camp)
	return camp


## A camp the director keeps whatever happens (a quest target): awake, it
## is never held back by the budget.
func add_pinned_camp(kind: String, site: Vector2) -> Camp:
	var camp := add_camp(kind, site)
	camp.pinned = true
	return camp


## `size` Coyotes in `camp`'s roster, `spitters` of them Spitters (at least
## one, and at least one Coyote to lead), Coyotes first.
static func fill_pack(camp: Camp, size: int, spitters: int) -> void:
	size = maxi(size, 2)
	spitters = clampi(spitters, 1, size - 1)
	for i in size:
		var spitter := i >= size - spitters
		camp.add_member(COYOTE_SPITTER if spitter else COYOTE, "Coyote Spitter" if spitter else "Coyote",
				Vector2(randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD)))


## A circle the camp is somewhere in: `radius` px round a point within
## `radius` * 0.6 of the site, so the circle doesn't give the spot away.
func hint_circle(camp: Camp, radius: float) -> Dictionary:
	var off := Vector2.from_angle(randf() * TAU) * radius * 0.6 * sqrt(randf())
	return {"centre": camp.site + off, "radius": radius}


# ---- Who notices ----

# [[position, reach], ...] of everything that wakes camps.
func _wakers() -> Array:
	var found := []
	var player = arena.get("player")
	if is_instance_valid(player) and not player.is_dead:
		found.append([player.global_position, full_sight(player) + WAKE_MARGIN])
	if arena.has_method("get_mechas"):
		for m in arena.get_mechas():
			if m == player or not is_instance_valid(m) or m.is_dead:
				continue
			if m.has_method("is_distant") and m.is_distant():
				continue
			found.append([m.global_position, full_sight(m) + WAKE_MARGIN])
	for device in get_tree().get_nodes_in_group("device"):
		if device is Device and not device.is_gone() and device.sensor_range > 0.0:
			found.append([device.global_position, device.sensor_range + WAKE_MARGIN])
	return found


## How far `mecha` sees with its head whole: its head's visual_range.
static func full_sight(mecha) -> float:
	var head = mecha.build.get("head") if mecha.get("build") is Dictionary else null
	if head != null and not mecha.is_part_lost("head"):
		return float(head.visual_range) * MapSenses.PX_PER_METRE
	return mecha.sight_radius()


# Whether anything in `wakers` reaches `point`, with `slack` px more reach;
# also the player's screen, grown by WAKE_MARGIN + slack.
func _watched(point: Vector2, wakers: Array, slack: float) -> bool:
	for w in wakers:
		var r: float = w[1] + slack
		if point.distance_squared_to(w[0]) < r * r:
			return true
	var player = arena.get("player")
	if is_instance_valid(player) and not player.is_dead:
		return MapSenses.screen_rect(player, WAKE_MARGIN + slack).has_point(point)
	return false


# ---- Waking ----

## Puts `camp` on the map (see the top).
func wake(camp: Camp) -> void:
	if camp.state != Camp.State.DORMANT:
		return
	camp.state = Camp.State.AWAKE
	camp.quiet = 0.0
	var encounter := camp.is_encounter()
	if encounter:
		_wake_encounter(camp)
	else:
		_put_remains(camp)
		_put_members(camp)
	_listen(camp)
	camp_woken.emit(camp, encounter)


# The roster on the map, within the budget, as one pack when it is Coyotes.
func _put_members(camp: Camp) -> Array:
	var room := INF if camp.pinned else float(maxi(awake_budget - _awake_count(), 0))
	var placed := []
	var held: Array[Dictionary] = []
	for entry in camp.roster:
		if placed.size() >= room:
			held.append(entry)
			continue
		var entity := _place(entry, camp.site + entry.offset)
		if entity != null:
			placed.append(entity)
	camp.roster = held
	var pack: EntityPack = null
	for entity in placed:
		if entity is Coyote:
			if pack == null:
				pack = EntityPack.new()
			pack.add(entity)
		camp.members.append(entity)
		entity.set_meta(&"camp", camp)
	return placed


func _place(entry: Dictionary, at: Vector2) -> Entity:
	var motes := int(entry.get("motes", 0))
	var entity: Entity = arena.add_entity(entry.scene, at, func(e):
		if motes > 0 and "mote_count" in e:
			e.mote_count = Vector2i(motes, motes))
	if entity == null:
		return null
	if entity is TickSwarm:
		var missing: int = motes - entity.get_mote_count()
		if missing > 0:
			var points := []
			for k in missing:
				points.append(entity.global_position + Vector2.from_angle(randf() * TAU) * 40.0 * sqrt(randf()))
			entity.add_motes(points)
	else:
		entity.hp = entity.max_hp * clampf(float(entry.get("hp", 1.0)), 0.05, 1.0)
	return entity


# The members killed while it slept, put on the map dead: each leaves its
# carcass (Expedition._before_entity_removed).
func _put_remains(camp: Camp) -> void:
	for entry in camp.remains:
		var body: Entity = arena.add_entity(entry.scene, camp.site + entry.offset)
		if body != null:
			body.die()
	camp.remains.clear()


# A sweep heard in its sleep in the last minute: the members heard it.
func _listen(camp: Camp) -> void:
	if camp.heard_at == Vector2.INF or clock - camp.heard_time > 60.0:
		return
	for entity in camp.living():
		if entity.get("hears_sweeps") != false:
			entity.heard_sound({"volume_type": "loud", "type": "sweep", "position": camp.heard_at,
					"source": null, "max_distance": INF})
	camp.heard_at = Vector2.INF


func _awake_count() -> int:
	var count := 0
	for entity in arena.get_entities():
		if is_instance_valid(entity) and not entity.is_dead:
			count += 1
	return count


# ---- Sleeping ----

func _tend_awake(camp: Camp, wakers: Array) -> void:
	var living := camp.living()
	camp.members = living
	if living.is_empty():
		camp.state = Camp.State.DORMANT if not camp.roster.is_empty() else Camp.State.CLEARED
		return
	var busy := false
	var watched := false
	for entity in living:
		if is_instance_valid(entity.target) or entity.get("frenzied") == true:
			busy = true
		if _watched(entity.global_position, wakers, SLEEP_SLACK):
			watched = true
		if busy and watched:
			break
	if busy or watched:
		camp.quiet = 0.0
		return
	camp.quiet += TICK
	if camp.quiet >= SLEEP_DELAY:
		sleep(camp)


## Takes `camp`'s members off the map (see the top).
func sleep(camp: Camp) -> void:
	var living := camp.living()
	if not living.is_empty():
		var centre := Vector2.ZERO
		for entity in living:
			centre += entity.global_position
		centre /= living.size()
		for entity in living:
			camp.roster.append(_entry_of(entity, centre))
			_take_off(entity)
		camp.site = centre
	camp.members.clear()
	camp.quiet = 0.0
	camp.state = Camp.State.DORMANT if not camp.roster.is_empty() else Camp.State.CLEARED
	camp_slept.emit(camp)


func _entry_of(entity: Entity, centre: Vector2) -> Dictionary:
	var motes := int(entity.get_mote_count()) if entity.has_method("get_mote_count") else 0
	return {
		"scene": _scene_of(entity),
		"species": entity.species,
		"hp": entity.get_hp_fraction(),
		"offset": (entity.global_position - centre).limit_length(SPREAD * 2.0),
		"motes": motes,
	}


func _scene_of(entity: Entity) -> PackedScene:
	var path := entity.scene_file_path
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path]


func _take_off(entity: Entity) -> void:
	_loose_quiet.erase(entity)
	if arena.has_method("unregister_entity"):
		arena.unregister_entity(entity)
	if entity.pack != null:
		entity.pack.members.erase(entity)
	entity.queue_free()


# Entities that belong to no camp, unwatched for SLEEP_DELAY s, become one
# (a pack's members together).
func _adopt_loose(wakers: Array) -> void:
	var seen := {}
	for entity in arena.get_entities():
		if not is_instance_valid(entity) or entity.is_dead or entity.scripted or entity.has_meta(&"camp"):
			continue
		seen[entity] = true
		if is_instance_valid(entity.target) or entity.get("frenzied") == true \
				or _watched(entity.global_position, wakers, SLEEP_SLACK):
			_loose_quiet[entity] = 0.0
			continue
		_loose_quiet[entity] = float(_loose_quiet.get(entity, 0.0)) + TICK
	for entity in _loose_quiet.keys():
		if not seen.has(entity):
			_loose_quiet.erase(entity)
	for entity in _loose_quiet.keys():
		if not _loose_quiet.has(entity) or float(_loose_quiet[entity]) < SLEEP_DELAY:
			continue
		var group: Array = [entity]
		if entity.pack != null:
			group = entity.pack.alive()
		if not group.all(func(e): return float(_loose_quiet.get(e, 0.0)) >= SLEEP_DELAY and not e.has_meta(&"camp")):
			continue
		var kind := Camp.PACK if entity is Coyote else (Camp.FISHER if entity is Fisher else Camp.TICK_SWARM)
		var camp := Camp.new(kind, entity.global_position)
		camp.state = Camp.State.AWAKE
		for e in group:
			camp.members.append(e)
			e.set_meta(&"camp", camp)
		camps.append(camp)
		sleep(camp)


## The camp an awake Entity belongs to, or null.
static func camp_of(entity: Node) -> Camp:
	return entity.get_meta(&"camp") if is_instance_valid(entity) and entity.has_meta(&"camp") else null


# ---- Sweeps ----

## What dormant camps add to `sweeper`'s sweep along `direction`, `width`
## degrees wide ({kind: count}); every dormant camp within earshot hears it.
func sweep_counts(sweeper: Node2D, direction: Vector2, width: float) -> Dictionary:
	var counts := {}
	var from := sweeper.global_position
	var forward := direction.normalized() if direction != Vector2.ZERO else Vector2.UP.rotated(sweeper.global_rotation)
	var half := deg_to_rad(width) * 0.5
	for camp in camps:
		if camp.state != Camp.State.DORMANT:
			continue
		var offset := camp.site - from
		var d := offset.length()
		if d <= Mecha.SWEEP_SOUND_RANGE:
			camp.heard_at = from
			camp.heard_time = clock
		if d > Mecha.SWEEP_RANGE:
			continue
		if width < Mecha.SWEEP_MAX_WIDTH and absf(forward.angle_to(offset)) > half:
			continue
		var found := camp.sweep_counts()
		for kind in found:
			counts[kind] = counts.get(kind, 0) + found[kind]
	return counts


# ---- Paper fights ----

func _paper_fights() -> void:
	if not arena.has_method("get_mechas"):
		return
	for npc in arena.get_mechas():
		if not is_instance_valid(npc) or npc.is_dead or not npc.has_method("is_distant") or not npc.is_distant():
			continue
		for camp in camps:
			if camp.state != Camp.State.DORMANT or camp.is_encounter() or camp.roster.is_empty():
				continue
			if npc.global_position.distance_to(camp.site) <= PAPER_REACH:
				paper_round(camp, npc)


## One PAPER_TICK of `npc` fighting dormant `camp` (see the top).
func paper_round(camp: Camp, npc) -> void:
	var fighters := camp.roster.filter(func(e): return PAPER_STATS.has(str(e.species)))
	if fighters.is_empty():
		return
	for entry in fighters:
		var stats: Array = PAPER_STATS[str(entry.species)]
		if randf() < float(stats[0]):
			paper_hit(npc, camp.site + entry.offset, int(stats[1]), int(stats[2]), str(entry.species))
	var victim: Dictionary = fighters.pick_random()
	if randf() < PAPER_KILL_CHANCE * float(PAPER_STATS[str(victim.species)][3]):
		camp.roster.erase(victim)
		camp.remains.append({"scene": victim.scene, "offset": victim.offset})


## A hit of `pips` on `mecha` from `from`, by `attacker_name`, on a random
## part (weighted as a rough round's, Enemy._rough_part). At armour pen
## `pen` >= 0 it goes through the shield and armour checks as a rough round
## does (Enemy._rough_hits); EXTERNAL damages a living external component of
## that part or the next part that has one, past the shield check only (a
## Coyote's whip, EntityAttack.hit_external); THROUGH a living component of
## any kind, nothing checked (a Fisher's harpoon, EntityAttack.hit_through).
## Nothing lands in the Flag's grace window. Returns whether it did damage.
static func paper_hit(mecha, from: Vector2, pips: int, pen: int, attacker_name: String) -> bool:
	if not is_instance_valid(mecha) or mecha.is_dead or not mecha.has_method("armor_check"):
		return false
	if mecha.is_in_flag_grace():
		return false
	var dir: Vector2 = (mecha.global_position - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	if pen != THROUGH and mecha.shield_check(from, maxi(pen, 0), pips) != "":
		return false
	var part: String = ENEMY_SCRIPT._rough_part()
	if pen < 0:
		var parts: Array = [part]
		for other in mecha.armor:
			if other not in parts:
				parts.append(other)
		for part_name in parts:
			var options: Array = mecha.get_eligible_components(part_name, "", pen == THROUGH)
			if options.is_empty():
				continue
			mecha.last_damage_source = {"body": null, "name": attacker_name}
			mecha.damage_component(part_name, mecha.select_component_by_weight(part_name, options), pips, dir)
			return true
		return false
	var result: Dictionary = mecha.armor_check(part, mecha.global_position - dir * 60.0, dir, pen, pips)
	if not bool(result.get("penetrated", false)) or str(result.get("component_name", "")) == "":
		return false
	mecha.last_damage_source = {"body": null, "name": attacker_name}
	mecha.damage_component(str(result.part_name), str(result.component_name), pips, dir)
	return true


# ---- Encounters ----

## Spots on open ground over the map for encounters, `count` of them, each
## tagged with its district (MapDistricts) where the map has them.
func lay_out_sites(points: Array) -> void:
	sites.clear()
	var field := BuildingField.find(arena)
	var districts: MapDistricts = field.districts if field != null else null
	for p in points:
		sites.append({"position": p, "district": districts.name_at(p) if districts != null else "residential", "used": false})


## An unused site `min_distance`..`max_distance` px from `from`, or null.
func pick_site(from: Vector2, min_distance: float, max_distance: float):
	var options := sites.filter(func(s): return not s.used \
			and s.position.distance_to(from) >= min_distance and s.position.distance_to(from) <= max_distance)
	return options.pick_random() if not options.is_empty() else null


## Arms an encounter of `kind` at `site` (a sites entry): its fight starts
## now. `intensity` (0 to 1) makes the pack bigger. `designs` are the NPCs'
## design data (NPCManager.random_design_data when empty).
func arm_encounter(kind: String, site: Dictionary, intensity: float, designs: Array = []) -> Camp:
	site.used = true
	var camp := Camp.new(kind, site.position)
	var count := 1 if kind == Camp.HUNT else 2
	for k in count:
		var design: Dictionary = designs[k] if k < designs.size() else NPCManager.random_design_data()
		var side := Vector2.from_angle(randf() * TAU) * ENCOUNTER_GAP * 0.5 if count > 1 else Vector2.ZERO
		_encounter_count += 1
		camp.mechas.append({"design": design, "name": "Camp_%d" % _encounter_count, "offset": side * (1 if k == 0 else -1)})
	if kind == Camp.HUNT:
		var size := 3 + roundi(clampf(intensity, 0.0, 1.0) * 3.0)
		fill_pack(camp, size, 1 if size < 5 else 2)
		for entry in camp.roster:
			entry.offset = Vector2.from_angle(randf() * TAU) * randf_range(ENCOUNTER_GAP * 0.6, ENCOUNTER_GAP)
	camp.armed_at = clock
	camp.duration = ENCOUNTER_DURATION
	camp.set_meta(&"site", site)
	camps.append(camp)
	_gunfire[camp] = randf_range(0.5, GUNFIRE_INTERVAL.x)
	return camp


## Encounters armed and not yet woken.
func armed_encounters() -> Array:
	return camps.filter(func(c): return c.is_encounter() and c.state == Camp.State.DORMANT)


func _encounter_clocks(dt: float) -> void:
	for camp in armed_encounters():
		if camp.progress(clock) >= 1.0:
			_gunfire.erase(camp)
			camp.unvisited += dt
			if camp.unvisited >= ABANDON_TIME:
				_abandon(camp)
			continue
		_gunfire[camp] = float(_gunfire.get(camp, 0.0)) - dt
		if _gunfire[camp] <= 0.0:
			_gunfire[camp] = randf_range(GUNFIRE_INTERVAL.x, GUNFIRE_INTERVAL.y)
			if arena.has_method("_on_mecha_made_sound"):
				arena._on_mecha_made_sound({"volume_type": "loud", "type": "gunshot", "source": null,
						"position": camp.site, "max_distance": GUNFIRE_RANGE})


# A fight over with nobody having come: the pack's survivors stay, the
# NPCs are gone.
func _abandon(camp: Camp) -> void:
	_free_site(camp)
	camp.mechas.clear()
	camp.remains.clear()
	if camp.kind == Camp.HUNT:
		_settle_hunt_offstage(camp)
	camp.kind = Camp.PACK
	camp.armed_at = -1.0
	if camp.roster.is_empty():
		camp.state = Camp.State.CLEARED


func _free_site(camp: Camp) -> void:
	if camp.has_meta(&"site"):
		camp.get_meta(&"site").used = false
		camp.remove_meta(&"site")


# What a hunt nobody saw end leaves of the pack: the NPC won (HUNT_NPC_WIN)
# and only one Coyote may have got away, or it lost and the pack lost
# HUNT_PACK_LOSS * 0.5 of its members.
func _settle_hunt_offstage(camp: Camp) -> bool:
	var npc_won := randf() < HUNT_NPC_WIN
	var keep := mini(randi_range(0, 1), camp.roster.size()) if npc_won \
			else camp.roster.size() - floori(camp.roster.size() * HUNT_PACK_LOSS * 0.5)
	while camp.roster.size() > keep:
		var entry: Dictionary = camp.roster.pop_back()
		camp.remains.append({"scene": entry.scene, "offset": entry.offset})
	return npc_won


# An encounter on the map as far through its fight as it has got (see the
# top), its NPCs then released to the world.
func _wake_encounter(camp: Camp) -> void:
	var p := camp.progress(clock)
	var npcs := []
	for m in camp.mechas:
		var npc = arena.add_enemy(m.design, m.name, camp.site + m.offset)
		if npc != null:
			npcs.append(npc)
	camp.mechas.clear()
	var npc_won := true
	var loser = null
	if camp.kind == Camp.HUNT:
		if p >= 1.0:
			npc_won = _settle_hunt_offstage(camp)
		else:
			var dead := floori(p * HUNT_PACK_LOSS * camp.roster.size())
			for k in dead:
				var entry: Dictionary = camp.roster.pop_back()
				camp.remains.append({"scene": entry.scene, "offset": entry.offset})
	elif camp.kind == Camp.DUEL and p >= 1.0 and npcs.size() >= 2:
		loser = npcs.pick_random()
	_put_remains(camp)
	var pack := _put_members(camp)
	for npc in npcs:
		var pips := roundi(p * float(HUNT_DAMAGE if camp.kind == Camp.HUNT else DUEL_DAMAGE))
		var from: Vector2 = npc.global_position + Vector2.from_angle(randf() * TAU) * 400.0
		for k in pips:
			paper_hit(npc, from, 1, 3, "unknown")
	if camp.kind == Camp.HUNT and not npc_won and not npcs.is_empty():
		loser = npcs[0]
	for npc in npcs:
		if npc == loser:
			continue
		for other in npcs:
			if other != npc and other != loser:
				npc.mark_traitor(other)
				npc.knowledge.see(other, other.global_position)
		for entity in pack:
			npc.knowledge.see(entity, entity.global_position)
	for entity in pack:
		var prey = npcs.filter(func(n): return n != loser)
		if not prey.is_empty() and entity.has_method("acquire_target"):
			entity.acquire_target(prey.pick_random())
	if loser != null:
		var killer: String = "Coyote" if camp.kind == Camp.HUNT else str(npcs[0 if npcs[1] == loser else 1].mecha_name)
		loser.die({"body": null, "name": killer}, "")
	_free_site(camp)
	_gunfire.erase(camp)
	camp.kind = Camp.PACK
	camp.armed_at = -1.0
	if camp.living().is_empty() and camp.roster.is_empty():
		camp.state = Camp.State.CLEARED
