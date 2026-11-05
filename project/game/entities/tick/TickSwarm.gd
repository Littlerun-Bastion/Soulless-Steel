extends Entity
class_name TickSwarm

# Tick swarm: a patch of glowing ticks (motes) on the ground round its home,
# one Entity for all of them. The motes are data (Mote), drawn in one pass by
# the body (TickSwarmBody). Each has its own small collision circle that
# moves with it, so a shot only hits where a mote is.
#
# Its hp is the motes on the ground, and it has no armour. Each point of
# damage kills the mote nearest the impact, AOE_MOTES of them for a blast's
# (take_hit's is_aoe). With no motes left on the ground it dies, leaving no
# carcass and no loot.
#
# Motes mostly sit still. Now and then one makes a few tiny, quick hops,
# with pauses between, and now and then two drift apart. They never leave
# the patch. When a hot mecha's hull (its signature at or above
# heat_sense_min, the mote able to see it) comes within jump_range of a
# ground mote, the mote jumps straight onto it (Mecha.attach_tick). From then
# on it is the mecha's: attached ticks outlive their swarm. Only mechas.
#
# A brood (TickBrood.tscn, formed by synced ticks dropping off a mecha:
# spawn_brood) glows brighter, scuttles slower and doesn't jump. After
# brood_time each mote spawns another (up to MAX_MOTES) and it becomes a
# normal swarm. A normal swarm with disperse_at motes or fewer disperses: it
# fades out after disperse_time s. fade_out() is also how the director makes
# room for a brood (ExpeditionDirector.spawn_tick_brood).
#
# Mechas and other Entities walk through the patch: each one that comes near
# gets a collision exception with the swarm, so only shots meet the motes.

# Loaded when needed: the brood scene is this script's own scene.
const BROOD_PATH := "res://game/entities/tick/TickBrood.tscn"
const MAX_MOTES := 12
## A blast kills this many motes per point of damage.
const AOE_MOTES := 3
## Checks for nearby Entities to let through, this often (s).
const PASS_CHECK_INTERVAL := 0.5

@export_group("Swarm")
## Motes in a new swarm (min, max).
@export var mote_count := Vector2i(9, 12)
@export var patch_radius := 150.0
## A mote's collision circle.
@export var mote_radius := 7.0
## Spawned as a brood (TickBrood.tscn).
@export var brood := false
@export_group("Jumping")
## How close (px) a hot mecha's hull has to come to a mote for it to jump.
@export var jump_range := 100.0
## How long an attached tick stays on (min, max seconds).
@export var attach_time := Vector2(10.0, 15.0)
@export_group("Scuttling")
## Seconds a mote rests between its bursts of hops (min, max).
@export var hop_wait := Vector2(2.0, 7.0)
## Hops in a burst (min, max), how long each takes and how far it goes.
@export var hop_count := Vector2i(1, 3)
@export var hop_time := 0.07
@export var hop_distance := Vector2(3.0, 8.0)
## The pause between hops in a burst (min, max).
@export var hop_pause := Vector2(0.12, 0.35)
## Seconds between two motes drifting apart (min, max), and the drift.
@export var drift_wait := Vector2(4.0, 9.0)
@export var drift_speed := 12.0
@export var drift_time := 1.5
## A brood's scuttling (and flickering) is this much slower.
@export var brood_slow := 2.0
## How often, on average, a mote's glow flickers (per second).
@export var flicker_rate := 0.6
@export_group("Life")
## Seconds until a brood doubles and becomes a normal swarm.
@export var brood_time := 30.0
## A normal swarm with this many motes or fewer disperses...
@export var disperse_at := 3
## ...after this long.
@export var disperse_time := 60.0

class Mote:
	var pos := Vector2.ZERO       # in the swarm's space
	var shape: CollisionShape2D
	var wait := 0.0               # until its next burst of hops
	var hops_left := 0
	var pause := 0.0              # between hops in a burst
	var hop_t := -1.0             # 0..1 through a hop; < 0 resting
	var hop_from := Vector2.ZERO
	var hop_to := Vector2.ZERO
	var drift := Vector2.ZERO     # px/s
	var drift_left := 0.0
	var flicker := 0.0            # 0..1, a dip in its glow, easing back
	var phase := 0.0              # its own pulse phase

static var _born_count := 0

## The id attached ticks carry to tell which swarm they're from (Mecha's
## syncing). A brood gets its own.
var group_id := 0
## Spawn order: lower is older (the director fades the oldest first).
var born := 0
var jumps := 0  # motes that jumped on a mecha (tests, tuning)

var _motes: Array[Mote] = []
var _brood_t := 0.0
var _disperse_t := 0.0
var _drift_wait := 0.0
var _pass_check := 0.0
var _passing := {}   # bodies given a collision exception: body -> true
var _fading := false

@onready var swarm_body: TickSwarmBody = $Body as TickSwarmBody


func _ready() -> void:
	super._ready()
	_born_count += 1
	born = _born_count
	group_id = get_instance_id()
	rooted = true
	armor_rating = 0
	swarm_body.swarm = self
	_drift_wait = randf_range(drift_wait.x, drift_wait.y)


func setup(arena_ref) -> void:
	super.setup(arena_ref)
	if not brood and _motes.is_empty():
		var count := randi_range(mote_count.x, mote_count.y)
		for k in count:
			_add_mote(Vector2.from_angle(randf() * TAU) * patch_radius * sqrt(randf()))
		_update_hp()


## A brood formed by synced ticks dropping off a mecha, on the ground at
## `at`, with a mote where each tick dropped (`points`, world). Through the
## Expedition director when there is one (it keeps the population cap).
## Null if there's no arena to put it in.
static func spawn_brood(arena_ref, at: Vector2, points: Array) -> TickSwarm:
	if not is_instance_valid(arena_ref):
		return null
	var swarm = null
	var director = arena_ref.get("ExpeditionDirector")
	if director != null and is_instance_valid(director) and director.has_method("spawn_tick_brood"):
		swarm = director.spawn_tick_brood(at)
	elif arena_ref.has_method("add_entity"):
		swarm = arena_ref.add_entity(load(BROOD_PATH), at)
	if swarm is TickSwarm:
		swarm.add_motes(points)
		if swarm.get_mote_count() == 0:
			swarm.fade_out()
		return swarm
	return null


## Ticks joining the swarm on the ground, where they dropped (world),
## brought into the patch.
func add_motes(points: Array) -> void:
	if is_dead:
		return
	for point in points:
		if _motes.size() >= MAX_MOTES:
			break
		_add_mote(_in_patch(to_local(point)))
	_update_hp()


func get_mote_count() -> int:
	return _motes.size()


## The ground motes' positions (world), for tests and tuning.
func get_mote_positions() -> PackedVector2Array:
	var points := PackedVector2Array()
	for mote in _motes:
		points.append(to_global(mote.pos))
	return points


func get_motes() -> Array[Mote]:
	return _motes


# ---- Hooks ----

# It hunts nothing: its motes jump on what comes near.
func wants_prey() -> bool:
	return false


func get_thermal_signature() -> float:
	return 0.2


# ---- Every frame ----

func behave(dt: float) -> void:
	if _fading:
		return
	if brood:
		_brood_t += dt
		if _brood_t >= brood_time:
			_hatch()
	elif _motes.size() <= disperse_at:
		_disperse_t += dt
		if _disperse_t >= disperse_time:
			fade_out()
			return
	_scuttle(dt)
	_let_entities_through(dt)
	_check_jumps()


func _scuttle(dt: float) -> void:
	var slow := brood_slow if brood else 1.0
	for mote in _motes:
		mote.phase += dt
		mote.flicker = move_toward(mote.flicker, 0.0, dt * 3.0 / slow)
		if randf() < dt * flicker_rate / slow:
			mote.flicker = randf_range(0.3, 0.8)
		var moved := false
		if mote.hop_t >= 0.0:
			mote.hop_t = minf(mote.hop_t + dt / (hop_time * slow), 1.0)
			mote.pos = mote.hop_from.lerp(mote.hop_to, mote.hop_t)
			moved = true
			if mote.hop_t >= 1.0:
				mote.hop_t = -1.0
				mote.hops_left -= 1
				if mote.hops_left > 0:
					mote.pause = randf_range(hop_pause.x, hop_pause.y) * slow
				else:
					mote.wait = randf_range(hop_wait.x, hop_wait.y) * slow
		elif mote.hops_left > 0:
			mote.pause -= dt
			if mote.pause <= 0.0:
				_start_hop(mote)
		else:
			mote.wait -= dt
			if mote.wait <= 0.0:
				mote.hops_left = randi_range(hop_count.x, hop_count.y)
				_start_hop(mote)
		if mote.drift_left > 0.0:
			mote.drift_left -= dt
			mote.pos = _in_patch(mote.pos + mote.drift * dt / slow)
			moved = true
		if moved:
			mote.shape.position = mote.pos
	_drift_wait -= dt
	if _drift_wait <= 0.0:
		_drift_wait = randf_range(drift_wait.x, drift_wait.y) * slow
		_drift_apart()


func _start_hop(mote: Mote) -> void:
	mote.hop_from = mote.pos
	var step := Vector2.from_angle(randf() * TAU) * randf_range(hop_distance.x, hop_distance.y)
	mote.hop_to = _in_patch(mote.pos + step)
	mote.hop_t = 0.0


# A mote and its nearest neighbour drift a little way apart.
func _drift_apart() -> void:
	if _motes.size() < 2:
		return
	var a: Mote = _motes.pick_random()
	var b: Mote = null
	var best := INF
	for mote in _motes:
		if mote == a:
			continue
		var d := mote.pos.distance_squared_to(a.pos)
		if d < best:
			best = d
			b = mote
	var apart := (a.pos - b.pos).normalized() if best > 0.01 else Vector2.from_angle(randf() * TAU)
	a.drift = apart * drift_speed
	b.drift = -apart * drift_speed
	a.drift_left = drift_time
	b.drift_left = drift_time


# A hot mecha within reach: the nearest mote that can see it jumps on it,
# one jump a frame. A cheap distance check first; the sight ray only for a
# mote in range.
func _check_jumps() -> void:
	if arena == null or not is_instance_valid(arena) or not arena.has_method("get_mechas"):
		return
	var near := patch_radius + jump_range + EntityAttack.HULL_REACH
	for mecha in arena.get_mechas():
		if not is_valid_prey(mecha):
			continue
		var d := global_position.distance_to(mecha.global_position)
		if d > near + 400.0:
			continue
		_let_through(mecha)
		if brood or d > near or prey_heat(mecha) < heat_sense_min:
			continue
		var reach := jump_range + EntityAttack.HULL_REACH
		var best: Mote = null
		var best_d := reach
		for mote in _motes:
			var md := to_global(mote.pos).distance_to(mecha.global_position)
			if md <= best_d:
				best_d = md
				best = mote
		if best != null and _mote_sees(best, mecha):
			_jump(best, mecha)
			return


func _mote_sees(mote: Mote, mecha: Node2D) -> bool:
	var from := to_global(mote.pos)
	if MapSenses.smoke_between(from, mecha.global_position):
		return false
	var query := PhysicsRayQueryParameters2D.create(from, mecha.global_position, MapSenses.SIGHT_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == mecha or hit.collider is Entity


func _jump(mote: Mote, mecha: Node2D) -> void:
	var from := to_global(mote.pos)
	_remove_mote(mote)
	jumps += 1
	mecha.attach_tick(group_id, arena, from, randf_range(attach_time.x, attach_time.y))
	_update_hp()
	if _motes.is_empty():
		_vanish()


# Other Entities walking through the patch don't bump into the motes.
func _let_entities_through(dt: float) -> void:
	_pass_check -= dt
	if _pass_check > 0.0:
		return
	_pass_check = PASS_CHECK_INTERVAL
	if arena == null or not is_instance_valid(arena) or not arena.has_method("get_entities"):
		return
	var near := patch_radius + 600.0
	for entity in arena.get_entities():
		if entity != self and is_instance_valid(entity) and entity is PhysicsBody2D \
				and global_position.distance_to(entity.global_position) < near:
			_let_through(entity)


func _let_through(body: PhysicsBody2D) -> void:
	if _passing.has(body):
		return
	_passing[body] = true
	body.add_collision_exception_with(self)


# A brood's motes each spawn another, and it becomes a normal swarm.
func _hatch() -> void:
	brood = false
	_disperse_t = 0.0
	for mote in _motes.duplicate():
		if _motes.size() >= MAX_MOTES:
			break
		_add_mote(_in_patch(mote.pos + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 24.0)))
	_update_hp()


# ---- Motes ----

func _add_mote(pos: Vector2) -> void:
	var mote := Mote.new()
	mote.pos = pos
	mote.wait = randf_range(0.0, hop_wait.y)
	mote.phase = randf() * TAU
	mote.shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = mote_radius
	mote.shape.shape = circle
	mote.shape.position = pos
	add_child(mote.shape)
	_motes.append(mote)


func _remove_mote(mote: Mote) -> void:
	_motes.erase(mote)
	if is_instance_valid(mote.shape):
		mote.shape.queue_free()


func _in_patch(pos: Vector2) -> Vector2:
	return pos.limit_length(patch_radius)


func _update_hp() -> void:
	hp = float(_motes.size())
	max_hp = maxf(max_hp, hp)
	_update_components()


# ---- Damage ----

# Each point of damage kills the mote nearest the impact (AOE_MOTES for a
# blast's). No armour. Without an impact point, the first mote the hit
# would meet coming along dir.
func take_hit(damage: float, _pen: int, dir := Vector2.ZERO, source_info = null, _knockback := 0.0,
		is_aoe := false, impact := Vector2.INF) -> void:
	if is_dead or _fading or _motes.is_empty():
		return
	last_hit_aoe = is_aoe
	if typeof(source_info) == TYPE_DICTIONARY:
		last_damage_source = source_info
		var body = source_info.get("body")
		if body != self and is_valid_prey(body):
			last_attacker = body
	var at := impact if impact.is_finite() else _first_along(dir)
	var kills := maxi(roundi(damage), 1) * (AOE_MOTES if is_aoe else 1)
	for k in kills:
		if _motes.is_empty():
			break
		_remove_mote(_nearest_mote(at))
	_update_hp()
	_flash_timer = HIT_FLASH_TIME
	if _motes.is_empty():
		die()


func _nearest_mote(at: Vector2) -> Mote:
	var local := to_local(at)
	var best: Mote = _motes[0]
	var best_d := INF
	for mote in _motes:
		var d := mote.pos.distance_squared_to(local)
		if d < best_d:
			best_d = d
			best = mote
	return best


func _first_along(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return global_position
	var best: Mote = _motes[0]
	var best_t := INF
	for mote in _motes:
		var t := mote.pos.dot(dir)
		if t < best_t:
			best_t = t
			best = mote
	return to_global(best.pos)


## Fades out with no kill to anyone's name: dispersing, or making room.
func fade_out() -> void:
	if is_dead or _fading:
		return
	_fading = true
	_vanish()


func _vanish() -> void:
	last_damage_source = null
	last_attacker = null
	die()


func die() -> void:
	if is_dead:
		return
	for mote in _motes:
		if is_instance_valid(mote.shape):
			mote.shape.queue_free()
	super.die()
