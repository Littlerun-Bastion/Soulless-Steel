class_name Positioning
extends RefCounted

## The position picker: where an NPC should stand. Every intent that moves
## in relation to a foe (engage, search, ambush, disengage) asks it for a
## point, with its own weights. One per NPC (Enemy.positioning), holding
## that NPC's cover cache and its last candidates for the debug overlay.
##
## A pick samples up to MAX_CANDIDATES points: a ring round the foe at the
## wanted range, a few round the NPC itself, a couple toward the goal, where
## it stands and its last pick. Each is scored on:
##   cover      building walls between it and the foe (walls_between): 0 in
##              the open, 0.5 with a wall the NPC's own rounds still get
##              through, 1 with enough walls to stop any round
##   fire_line  1 while the NPC's rounds get through to the foe (fewer walls
##              than its best armour pen), else 0
##   range      how close the distance to the foe is to the wanted range
##   far        distance from the foe, as a share of `far_scale` (disengage)
##   travel     1 close by, 0 at `travel_scale` px away
##   way        1 when the way there is covered from the foe (its midpoint)
##   open       1 on open ground, 0 inside a building (the route grid's cost)
##   mines      1 when a known mine lies within MINE_CLEARANCE px
##   smoke      1 inside smoke
##   view       1 when the point has a clear line to `watch` (ambush)
##   behind     1 when the point lies behind the foe (against `foe_facing`:
##              a stalker's approach), 0 in front of it
##   flank      how far off the anchor's bearing to the foe the point lies,
##              1 at Squad.FLANK_ANGLE or more (a squad's flanker)
##   spacing    1 when a squadmate stands within SQUAD_SPACING px of the point
## The weights Dictionary gives each term's weight; a negative weight makes a
## term a cost. The best point is confirmed with one ray (walls and smoke
## between it and the foe) before it is handed out; if the ray disagrees
## with the estimate, the next best is taken.
##
## Cover is worked out from building footprints (BuildingField.walls_crossed),
## cached per pair of route grid cells for COVER_CACHE_TIME s; on a map with
## no building field the top candidates get a wall ray each instead. A pick
## is made on events (new contact, lost target, took fire, the foe moved
## MOVE_REPICK px) and otherwise every REPICK_TIME s, jittered; a far NPC
## (Enemy.is_near_player false) only on events.

const MAX_CANDIDATES := 16
const RING_COUNT := 8
const SELF_RING_COUNT := 4
## Radius (px) of the ring round the NPC itself. Placeholder.
const SELF_RING_RADIUS := 450.0
## Steps (px) toward the goal. Placeholder.
const GOAL_STEPS := [500.0, 1000.0]
const REPICK_TIME := 1.5
const REPICK_JITTER := 0.5
const MOVE_REPICK := 400.0
const COVER_CACHE_TIME := 3.0
const COVER_CACHE_MAX := 256
const MINE_CLEARANCE := 300.0
const SQUAD_SPACING := 500.0
## The flank term reaches 1 at this multiple of Squad.FLANK_ANGLE.
const FLANK_MARGIN := 1.25
## Armour pen assumed for a foe whose weapons the NPC can't judge.
const DEFAULT_FOE_AP := 2
## Rays spent per pick on a map with no building field.
const RAY_CANDIDATES := 3
## Scores below this are not worth moving for: the NPC stays where it is.
const MIN_GAIN := 0.05

## The last pick ({} for none): position, score, time (store time).
var pick := {}
## The last candidates, [{position, score}], newest pick first (overlay).
var candidates: Array[Dictionary] = []
var _timer := 0.0
var _dirty := true
var _picked_for := Vector2.INF
var _cover_cache := {}
var _cover_hits := 0
var _cover_misses := 0


func reset() -> void:
	pick = {}
	candidates.clear()
	_dirty = true
	_picked_for = Vector2.INF


## Something happened: pick again at the next chance.
func request() -> void:
	_dirty = true


func tick(dt: float) -> void:
	_timer -= dt


## Whether it is time to pick again: an event, the foe having moved, or the
## timer, which far NPCs skip.
func due(enemy, foe_position: Vector2) -> bool:
	if _dirty or pick.is_empty():
		return true
	if _picked_for != Vector2.INF and _picked_for.distance_to(foe_position) > MOVE_REPICK:
		return true
	return _timer <= 0.0 and enemy.is_near_player()


## Picks where to stand against a foe believed at `foe_position`, for a
## wanted range, with `weights` (see above). `goal` is where the intent
## would otherwise go (the foe's position when it has no other goal);
## `watch` a point the NPC wants a view of (ambush), or Vector2.INF.
## Returns the point (the NPC's own position when nothing beats it).
func choose(enemy, foe_position: Vector2, wanted_range: float, weights: Dictionary,
		goal := Vector2.INF, watch := Vector2.INF, foe_facing := Vector2.ZERO, anchor := Vector2.INF) -> Vector2:
	var profile_start := FrameProfiler.start()
	var picked := _choose(enemy, foe_position, wanted_range, weights, goal, watch, foe_facing, anchor)
	FrameProfiler.add("  pick (in behaviour)", profile_start)
	return picked


func _choose(enemy, foe_position: Vector2, wanted_range: float, weights: Dictionary,
		goal: Vector2, watch: Vector2, foe_facing: Vector2, anchor: Vector2) -> Vector2:
	_timer = REPICK_TIME + randf_range(-REPICK_JITTER, REPICK_JITTER)
	_dirty = false
	_picked_for = foe_position
	var pos: Vector2 = enemy.global_position
	var field: BuildingField = enemy.get_building_field()
	var my_ap: int = enemy.best_armor_pen()
	var foe_ap := DEFAULT_FOE_AP
	var travel_scale: float = maxf(float(weights.get("travel_scale", 1500.0)), 1.0)
	var far_scale: float = maxf(float(weights.get("far_scale", 3000.0)), 1.0)
	var points := _sample(enemy, pos, foe_position, wanted_range, goal)
	var scored: Array[Dictionary] = []
	for p in points:
		var terms := _terms(enemy, field, p, pos, foe_position, wanted_range, my_ap, foe_ap, travel_scale, far_scale, watch, field != null)
		if foe_facing != Vector2.ZERO and p.distance_squared_to(foe_position) > 1.0:
			terms.behind = 1.0 if foe_facing.dot(foe_position.direction_to(p)) < -0.3 else 0.0
		if anchor != Vector2.INF and p.distance_squared_to(foe_position) > 1.0 and anchor.distance_squared_to(foe_position) > 1.0:
			# Full marks a little past the angle, so the pick clears it with
			# room for the anchor to drift.
			var off := absf(foe_position.direction_to(anchor).angle_to(foe_position.direction_to(p)))
			terms.flank = clampf(off / (Squad.FLANK_ANGLE * FLANK_MARGIN), 0.0, 1.0)
		terms.spacing = _spacing(enemy, p)
		scored.append({"position": p, "score": _weigh(terms, weights), "terms": terms})
	# No building field: rays for the best few, then score them again.
	if field == null:
		scored.sort_custom(func(a, b): return a.score > b.score)
		var world: World2D = enemy.get_world_2d()
		for i in mini(RAY_CANDIDATES, scored.size()):
			var entry: Dictionary = scored[i]
			var walls := MapSenses.wall_hits(world, entry.position, foe_position).size()
			_cover_terms(entry.terms, walls, my_ap, foe_ap)
			entry.score = _weigh(entry.terms, weights)
	scored.sort_custom(func(a, b): return a.score > b.score)
	candidates = scored
	# The NPC's own spot is the measure: a point must gain on it.
	var here_score := -INF
	for entry in scored:
		if entry.position == pos:
			here_score = entry.score
			break
	var world2: World2D = enemy.get_world_2d()
	for entry in scored:
		if entry.score < here_score + MIN_GAIN and entry.position != pos:
			break
		# One ray confirms the winner: a fire line the footprints promised
		# but a wall or smoke denies sends it to the next candidate.
		if entry.position != pos and float(entry.terms.fire_line) > 0.5 and float(weights.get("fire_line", 0.0)) > 0.0 \
				and MapSenses.sight_blocked(world2, entry.position, foe_position):
			continue
		pick = {"position": entry.position, "score": entry.score, "time": enemy.knowledge.now()}
		return entry.position
	pick = {"position": pos, "score": here_score, "time": enemy.knowledge.now()}
	return pos


func has_pick() -> bool:
	return not pick.is_empty()


func pick_position() -> Vector2:
	return pick.position if has_pick() else Vector2.INF


## Cache statistics (tests): how many cover look-ups were answered from the
## cache and how many were worked out.
func cover_stats() -> Dictionary:
	return {"hits": _cover_hits, "misses": _cover_misses, "size": _cover_cache.size()}


func _sample(enemy, pos: Vector2, foe: Vector2, wanted_range: float, goal: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(pos)
	if has_pick() and pick.position != pos:
		points.append(pick.position)
	var to_foe := foe - pos
	var bearing := to_foe.angle() if to_foe.length_squared() > 1.0 else 0.0
	# Round the foe at the wanted range, starting from the NPC's own side.
	for i in RING_COUNT:
		var angle := bearing + PI + TAU * i / RING_COUNT
		points.append(foe + Vector2.from_angle(angle) * wanted_range)
	# Round the NPC: its sides and back relative to the foe.
	for i in SELF_RING_COUNT:
		var angle := bearing + PI * 0.5 + PI * 0.5 * i
		points.append(pos + Vector2.from_angle(angle) * SELF_RING_RADIUS)
	# Toward the goal.
	if goal != Vector2.INF and goal.distance_to(pos) > 1.0:
		var dir := pos.direction_to(goal)
		for step in GOAL_STEPS:
			if pos.distance_to(goal) > step:
				points.append(pos + dir * step)
	if points.size() > MAX_CANDIDATES:
		points.resize(MAX_CANDIDATES)
	var arena = enemy.arena
	if arena and arena.has_method("is_position_on_map"):
		var kept := PackedVector2Array()
		for p in points:
			if arena.is_position_on_map(p):
				kept.append(p)
		return kept
	return points


func _terms(enemy, field: BuildingField, p: Vector2, pos: Vector2, foe: Vector2, wanted_range: float,
		my_ap: int, foe_ap: int, travel_scale: float, far_scale: float, watch: Vector2, with_cover: bool) -> Dictionary:
	var dist_foe := p.distance_to(foe)
	var terms := {
		"cover": 0.0,
		"fire_line": 1.0,
		"range": 1.0 - clampf(absf(dist_foe - wanted_range) / maxf(wanted_range, 1.0), 0.0, 1.0),
		"far": clampf(dist_foe / far_scale, 0.0, 1.0),
		"travel": 1.0 - clampf(p.distance_to(pos) / travel_scale, 0.0, 1.0),
		"way": 0.0,
		"open": 1.0,
		"mines": 0.0,
		"smoke": 1.0 if MapSenses.in_smoke(p) else 0.0,
		"view": 0.0,
		"behind": 0.0,
		"flank": 0.0,
		"spacing": 0.0,
	}
	if with_cover:
		_cover_terms(terms, _walls_between(field, p, foe), my_ap, foe_ap)
		var mid := (p + pos) * 0.5
		terms.way = 1.0 if _walls_between(field, mid, foe) >= foe_ap else 0.0
		if watch != Vector2.INF:
			terms.view = 1.0 if _walls_between(field, p, watch) == 0 else 0.0
	elif watch != Vector2.INF:
		terms.view = 1.0
	if field != null:
		var cost := field.route_cost_at(p)
		terms.open = 1.0 - clampf((cost - 1.0) / BuildingField.ROUTE_BUILDING_WEIGHT, 0.0, 1.0)
	# Only mines the NPC knows of (NPCKnowledge.spot_mines): the fairness rule.
	if enemy.knowledge.known_mine_near(p, MINE_CLEARANCE):
		terms.mines = 1.0
	return terms


# 1 when a living squadmate stands within SQUAD_SPACING px of the point.
func _spacing(enemy, p: Vector2) -> float:
	var squad = enemy.knowledge.squad
	if squad == null:
		return 0.0
	for mate in squad.mates_of(enemy):
		if mate.global_position.distance_to(p) < SQUAD_SPACING:
			return 1.0
	return 0.0


func _cover_terms(terms: Dictionary, walls: int, my_ap: int, foe_ap: int) -> void:
	if walls >= foe_ap:
		terms.cover = 1.0
	elif walls > 0:
		terms.cover = 0.5
	else:
		terms.cover = 0.0
	terms.fire_line = 1.0 if walls < my_ap else 0.0


func _weigh(terms: Dictionary, weights: Dictionary) -> float:
	var score := 0.0
	for key in weights:
		if terms.has(key):
			score += float(weights[key]) * float(terms[key])
	return score


# Walls between two points from the footprints, cached per pair of route
# cells for COVER_CACHE_TIME s (the store's clock is not to hand here, so the
# cache uses real time).
func _walls_between(field: BuildingField, a: Vector2, b: Vector2) -> int:
	var ca := field.route_cell(a)
	var cb := field.route_cell(b)
	var key := Vector4i(ca.x, ca.y, cb.x, cb.y)
	var now := Time.get_ticks_msec()
	if _cover_cache.has(key):
		var entry: Array = _cover_cache[key]
		if now - int(entry[1]) < int(COVER_CACHE_TIME * 1000.0):
			_cover_hits += 1
			return int(entry[0])
	if _cover_cache.size() >= COVER_CACHE_MAX:
		_cover_cache.clear()
	var walls := field.walls_crossed(a, b)
	_cover_cache[key] = [walls, now]
	_cover_misses += 1
	return walls
