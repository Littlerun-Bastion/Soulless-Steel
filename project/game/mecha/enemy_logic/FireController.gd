class_name FireController
extends RefCounted

## One place that decides when and how an NPC fires, for every intent. One
## per NPC (Enemy.fire). The intents say what they want (engage a target,
## fire at a last-known spot, screen with smoke, lay a mine, send a drone)
## and the controller applies the rules:
##   - guns (the plain firing path) fire at a target in sight with a clear
##     line (try_to_shoot), and blind at where it was last seen or heard
##     while the memory is fresh and their rounds can get through the walls
##     (blind_fire), or at a track's point (blind_fire_at); a Guardian never
##     fires blind
##   - skillshots (the cannon's line, the laser's rectangle) and direct AoE
##     designators fire at the lead point, through Mecha.fire_at_point, which
##     holds them to the weapon's facing and range
##   - lock-on weapons fire at their lock from anywhere a round can reach it
##     (a direct one is held behind a wall: Enemy.lock_shot_clear), else at a
##     target in sight within range
##   - indirect weapons (mortar, MLRS, howitzer) fire at where the target is
##     believed to be, in sight or not for INDIRECT_MEMORY s after it was last
##     seen, never into a building (roofs would take the round) and never
##     from inside one, within their minimum and maximum range
##   - the smoke launcher and mine layers fire only when an intent asks
##     (screen_self, lay_mine)
##   - a disciplined pilot (the Professional) holds fire on a poor shot: the
##     target near the edge of range, or well off the mecha's facing
##   - running hot (near the behaviour's weapon heat threshold), guns fire
##     in bursts: BURST_ON s on, BURST_OFF s off
##   - internal parts: a flare at a point, a drone toward a point, a ward or
##     a decoy at the mecha's feet, and the sensor sweep, each through the
##     player's calls with their cooldowns and charges
##   - with no target and nobody shooting at it, the NPC shoots enemy wards,
##     drones, Seekers and decoys it can see within DEVICE_RANGE
## Every shot an NPC fires goes through here, so AICombatLog sees them all.
## Weapon roles come from Enemy._weapon_roles (see Enemy._weapon_role).

## Guns burst once heat passes this share of the weapon heat threshold.
## Placeholders.
const BURST_HEAT_START := 0.8
const BURST_ON := 0.4
const BURST_OFF := 0.6
## A poor shot for a disciplined pilot: beyond this share of the shooting
## range, or this far off the mecha's facing. Placeholders.
const POOR_SHOT_RANGE := 0.85
const POOR_SHOT_ANGLE := deg_to_rad(25.0)
## Indirect weapons fire at a last-known position this old at most (s).
## Placeholder.
const INDIRECT_MEMORY := 8.0
## Blind fire: for this long (s) after the target was last seen or heard, and
## only once the mecha faces within this cone of the spot. Placeholders.
const BLIND_FIRE_TIME := 4.0
const BLIND_FIRE_CONE := deg_to_rad(12.0)
## Enemy devices are looked for this often (s) within this range (px) and
## shot once the mecha faces within this cone of them. Placeholders.
const DEVICE_SCAN_INTERVAL := 1.0
const DEVICE_RANGE := 1500.0
const DEVICE_AIM_CONE := deg_to_rad(10.0)
## The sweep an NPC makes (degrees). Placeholder.
const SWEEP_WIDTH := 60.0

var npc = null
## Knowledge time (NPCKnowledge.now) of the last shot it fired: a burst is
## over once it has stopped (Enemy's flashing light).
var last_shot_time := -INF
## The last sweep it made: {"direction", "counts" (the kinds it reported),
## "time"}; {} for none.
var last_sweep := {}
var _burst_time := 0.0
var _device_scan := 0.0
var _device_target = null
## Slot -> how many salvos it fired through fire_at_point (tests).
var salvos_fired := {}


func setup(enemy) -> void:
	npc = enemy


func role(slot: String) -> String:
	return str(npc._weapon_roles.get(slot, ""))


# ---- Fighting ----

## Fires at `target` for the engage and search intents. `seen`: in sight at
## the last senses update; `eff`: the behaviour's effective distances;
## `state`: the NPC's own state; `disciplined`: hold fire on a poor shot.
## Returns whether anything fired.
func engage(dt: float, target, seen: bool, eff: Dictionary, state: Dictionary, disciplined: bool) -> bool:
	var profile_start := FrameProfiler.start()
	var fired := _engage(dt, target, seen, eff, state, disciplined)
	FrameProfiler.add("  fire (in behaviour)", profile_start)
	return fired


func _engage(dt: float, target, seen: bool, eff: Dictionary, state: Dictionary, disciplined: bool) -> bool:
	if not is_instance_valid(target) or npc.holds_fire_at(target):
		cease()
		return false
	var target_pos: Vector2 = npc.get_target_position(target)
	var distance: float = npc.global_position.distance_to(target_pos)
	_burst_time += dt
	if _bursting(state) and fmod(_burst_time, BURST_ON + BURST_OFF) > BURST_ON:
		cease()
		return false
	if disciplined and seen and _poor_shot(target_pos, distance, eff):
		cease()
		return false
	var clear: bool = seen and npc.can_see_target(target)
	var aim: Vector2 = npc.ai_aim_point if npc.ai_aim_point != null else target_pos
	var fired := false
	for slot in npc.WEAPON_SLOTS:
		var what := role(slot)
		if what == "" or what == "smoke" or what == "mine":
			continue
		if what == "gun" or what == "melee":
			if seen:
				fired = _try_to_shoot(slot, target) or fired
		elif what == "lock":
			if npc.fires_at_lock(slot):
				if npc.lock_shot_clear(slot):
					fired = _fire_at(slot, target_pos) or fired
			elif clear:
				fired = _fire_at(slot, target_pos) or fired
		elif what == "skillshot" or what == "aoe":
			if clear:
				fired = _fire_at(slot, aim) or fired
		elif what == "indirect":
			if seen or npc.time_unseen(target) <= INDIRECT_MEMORY:
				fired = fire_indirect_at(slot, target_pos) or fired
	if fired:
		last_shot_time = npc.knowledge.now()
		AICombatLog.record_shot(npc, distance, not seen)
	return fired


## Blind fire: guns fire at where `target` was last seen or heard, through
## walls, for BLIND_FIRE_TIME s (blind_fire_at). A Guardian never fires
## blind: it could hit a friend. Returns whether any fired.
func blind_fire(target) -> bool:
	if not is_instance_valid(target) or npc.holds_fire_at(target):
		return false
	var knowledge = npc.knowledge
	if not knowledge.knows(target) or knowledge.is_seen(target) or knowledge.age_of(target) > BLIND_FIRE_TIME:
		return false
	return blind_fire_at(knowledge.position_of(target))


## Guns fire at `point`, unseen, each only if its round can get through the
## walls on the way (a round loses 1 AP per wall, see MapSenses.trace_shot),
## and only once the mecha faces that point; never for a Guardian (it could
## hit a friend). Search fires at a lost target's spot through here, and
## identify at a track's. Returns whether any fired.
func blind_fire_at(point: Vector2) -> bool:
	if npc.personality != null and npc.personality.type == Personality.Type.GUARDIAN:
		return false
	var to_point: Vector2 = point - npc.global_position
	if absf(Vector2.UP.rotated(npc.global_rotation).angle_to(to_point)) > BLIND_FIRE_CONE:
		return false
	var walls: int = MapSenses.wall_hits(npc.get_world_2d(), npc.global_position, point).size()
	var fired := false
	for slot in npc.WEAPON_SLOTS:
		if role(slot) != "gun" or int(npc._weapon_ap.get(slot, 0)) <= walls:
			continue
		var node = npc.get_weapon_part(slot)
		if not node:
			continue
		if node.can_reload() == "yes" and node.is_clip_empty() and not node.is_reloading():
			node.reload()
		elif node.can_shoot():
			npc.shoot(slot)
			fired = true
	if fired:
		last_shot_time = npc.knowledge.now()
		AICombatLog.record_shot(npc, to_point.length(), true)
	return fired


## An indirect weapon in `slot` fires at `point`, unless the point is inside
## a building (the roof would take the round) or the weapon can't fire there
## now (range, facing, heat, reload, indoors).
func fire_indirect_at(slot: String, point: Vector2) -> bool:
	if MapSenses.building_key_at(npc, point) != "":
		return false
	return _fire_at(slot, point)


## Stops every weapon (continuous fire).
func cease() -> void:
	for slot in npc.WEAPON_SLOTS:
		npc.stop_shooting(slot)


# ---- Tools ----

## Whether it has a smoke launcher.
func has_smoke() -> bool:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) == "smoke":
			return true
	return false


## The smoke launcher fires round the mecha itself.
func screen_self() -> bool:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) == "smoke" and _fire_at(slot, npc.global_position):
			return true
	return false


## The smoke launcher fires at `point` (a squadmate to cover), held to its
## facing and range by fire_at_point.
func screen_at(point: Vector2) -> bool:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) == "smoke" and _fire_at(slot, point):
			return true
	return false


## `point`, or the nearest point to it the smoke launcher reaches (its max
## range along the way there).
func reach_toward(point: Vector2) -> Vector2:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) != "smoke":
			continue
		var reach: float = float(npc.build[slot].max_range)
		var offset: Vector2 = point - npc.global_position
		if offset.length() > reach:
			return npc.global_position + offset.normalized() * reach
	return point


## Whether only the mecha's facing keeps the smoke launcher from `point`
## (the caller may turn toward it).
func cover_blocked_by_facing(point: Vector2) -> bool:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) == "smoke" and npc.can_fire_at_point(slot, point) == "not_facing":
			return true
	return false


## A mine layer fires at `point` (held to its facing and range by
## fire_at_point).
func lay_mine(point: Vector2) -> bool:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) == "mine" and _fire_at(slot, point):
			return true
	return false


## Whether the NPC carries a weapon of this role.
func has_role(what: String) -> bool:
	for slot in npc.WEAPON_SLOTS:
		if role(slot) == what:
			return true
	return false


## Whether the internal bay holds a part with this function, with a use left.
func has_internal(function: String) -> bool:
	var part = npc.build.get("internal")
	return part != null and part.get("function") == function and npc.can_use_internal() == ""


func fire_flare(point: Vector2) -> bool:
	return has_internal("flare") and npc.use_internal(point) == ""


func launch_drone(toward: Vector2) -> bool:
	return has_internal("drone") and npc.use_internal(toward) == ""


func place_ward() -> bool:
	return has_internal("ward") and npc.use_internal() == ""


func throw_decoy() -> bool:
	return has_internal("decoy") and npc.use_internal() == ""


## A sensor sweep `width` degrees wide (SWEEP_WIDTH) along `direction`.
func sweep(direction: Vector2, width := SWEEP_WIDTH) -> bool:
	if npc.can_sweep() != "":
		return false
	var result: Dictionary = npc.sweep(direction, width)
	if bool(result.get("ok", false)):
		last_sweep = {"direction": direction, "counts": result.get("counts", {}), "time": npc.knowledge.now()}
		return true
	return false


## Whether a sweep is ready.
func can_sweep() -> bool:
	return npc.can_sweep() == ""


# ---- Enemy devices ----

## With no target and nobody shooting at it, the NPC aims at and shoots an
## enemy device it can see. Returns whether it is busy with one (its aim
## point is then set).
func shoot_devices(dt: float) -> bool:
	if npc.valid_target or npc.under_fire_timer > 0.0:
		_device_target = null
		return false
	_device_scan -= dt
	if not _device_usable(_device_target):
		_device_target = null
		if _device_scan > 0.0:
			return false
		_device_scan = DEVICE_SCAN_INTERVAL
		var best = null
		var best_dist := INF
		for device in Device.find_near(npc, npc.global_position, DEVICE_RANGE):
			if not _device_usable(device):
				continue
			var d: float = npc.global_position.distance_to(device.global_position)
			if d < best_dist and npc.can_see_target(device):
				best = device
				best_dist = d
		_device_target = best
		if best == null:
			return false
	var at: Vector2 = _device_target.global_position
	npc.ai_aim_point = at
	var facing: Vector2 = Vector2.UP.rotated(npc.global_rotation)
	if absf(facing.angle_to(at - npc.global_position)) <= DEVICE_AIM_CONE:
		for slot in npc.WEAPON_SLOTS:
			if role(slot) == "gun":
				_try_to_shoot(slot, _device_target)
	return true


func _device_usable(device) -> bool:
	if device == null or not is_instance_valid(device) or device.is_gone() or not device.destructible:
		return false
	if device.owner_mecha == npc:
		return false
	return npc.global_position.distance_to(device.global_position) <= DEVICE_RANGE


# ---- Helpers ----

func _bursting(state: Dictionary) -> bool:
	var threshold = npc.logic.behaviour.get("weapon_heat_threshold") if npc.logic and npc.logic.behaviour else null
	if threshold == null:
		threshold = 0.75
	return float(state.get("heat_ratio", 0.0)) >= float(threshold) * BURST_HEAT_START


func _poor_shot(target_pos: Vector2, distance: float, eff: Dictionary) -> bool:
	if distance > float(eff.max_shoot) * POOR_SHOT_RANGE:
		return true
	var facing: Vector2 = Vector2.UP.rotated(npc.global_rotation)
	return absf(facing.angle_to(target_pos - npc.global_position)) > POOR_SHOT_ANGLE


func _fire_at(slot: String, point: Vector2) -> bool:
	if npc.fire_at_point(slot, point) != "":
		return false
	salvos_fired[slot] = int(salvos_fired.get(slot, 0)) + 1
	return true


# A gun fires at `target` (a body) when it has a clear line to it.
func _try_to_shoot(slot: String, target) -> bool:
	var node = npc.get_weapon_part(slot)
	if not node:
		return false
	if node.can_reload() == "yes" and node.is_clip_empty() and not node.is_reloading():
		node.reload()
		return false
	if node.can_shoot() and npc.can_see_target(target):
		npc.shoot(slot)
		return true
	return false
