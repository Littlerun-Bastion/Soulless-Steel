extends "res://database/parts/complex_projectile.gd"

# A mine, fired by a mine layer ("point" or "circle" designator). It is a
# complex projectile until it settles, then a mine that waits until a mecha
# sets it off; there is no limit on how many are out.
#
# Flight: an indirect mine flies over everything onto its landing point (a
# roof landing bursts on the roof, as for any indirect round). A direct mine
# flies flat towards its landing point and bounces off walls, solid bodies
# and vehicles on the way, up to MAX_BOUNCES times, until it has covered the
# distance to the point; it passes over mechas and Entities.
#
# Settled, after arm_time it reacts to mechas (any mecha, its layer's own
# included):
#   contact   goes off when a mecha's centre comes within trigger_radius
#             (driven over)
#   sensor    goes off when a mecha comes within trigger_radius
#   magnetic  when a mecha comes within attract_radius, crawls towards it at
#             crawl_speed and goes off within trigger_radius; it gives up
#             and settles again if the mecha gets 1.5x attract_radius away
# Going off takes TRIGGER_FRAMES physics frames (the blast area finds what is
# in reach), then the usual blast (complex_projectile.explosion).
#
# Cheap at large numbers: a settled mine runs no process and no physics (its
# areas stop monitoring). Mines sit in a static grid of CELL_SIZE squares;
# each mecha calls check_mecha() once per physics frame (Mecha), which looks
# only at the mines in the 3x3 cells round it. mines_near() reads the same
# grid for NPC code.

const CELL_SIZE := 500.0
const MAX_BOUNCES := 4
const TRIGGER_FRAMES := 2
const SETTLED := 0
const FLYING := 1
const ARMING := 2
const ARMED := 3
const CHASING := 4
const TRIGGERED := 5

@export_enum("contact", "sensor", "magnetic") var mine_type: String = "contact"
@export var trigger_radius := 70.0
@export var attract_radius := 450.0
@export var crawl_speed := 350.0
@export var arm_time := 1.0

# Grid cell -> mines in it.
static var _cells := {}
static var _count := 0

var mine_state := FLYING
var _cell := Vector2i.ZERO
var _registered := false
var _indirect := false
var _travel_left := 0.0
var _bounces := 0
var _arm_left := 0.0
var _trigger_left := 0
var _chasing = null


func setup(mecha, _args, _weapon):
	super.setup(mecha, _args, _weapon)
	_indirect = is_airborne
	if target_pos == null:
		target_pos = position
	_travel_left = position.distance_to(target_pos)


func _physics_process(dt):
	if dying:
		return
	if mine_state == FLYING:
		if is_airborne:
			_fly_indirect(dt)
		else:
			_fly_direct(dt)
	elif mine_state == ARMING:
		_arm_left -= dt
		if _arm_left <= 0.0:
			mine_state = ARMED
			set_physics_process(false)
	elif mine_state == CHASING:
		_crawl(dt)
	elif mine_state == TRIGGERED:
		_trigger_left -= 1
		if _trigger_left <= 0:
			payload()


func _exit_tree() -> void:
	_unregister()


# ---- flight -------------------------------------------------------------

func _fly_direct(dt: float) -> void:
	var step := minf(float(muzzle_speed) * dt, _travel_left)
	var hit := _blocker(position, position + dir * step)
	if hit.is_empty():
		position += dir * step
		_travel_left -= step
	else:
		var hit_pos: Vector2 = hit.position
		var normal: Vector2 = hit.normal
		_travel_left -= position.distance_to(hit_pos)
		position = hit_pos + normal * 2.0
		_bounces += 1
		if _bounces > MAX_BOUNCES:
			_travel_left = 0.0
		else:
			dir = dir.bounce(normal).normalized()
			rotation_degrees = rad_to_deg(dir.angle()) + 90
	if _travel_left <= 0.0:
		_land()


# The first wall, solid body or vehicle on the way: {"position", "normal"},
# or empty. Mechas and Entities don't stop a mine (it flies into them).
func _blocker(from: Vector2, to: Vector2) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var space := get_world_2d().direct_space_state
	var skip: Array[RID] = []
	for _i in MapSenses.MAX_SOLID_SKIPS:
		var query := PhysicsRayQueryParameters2D.create(from, to, MapSenses.SIGHT_MASK | MapSenses.VEHICLE_MASK, skip)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.collider as Node
		if collider and (collider.is_in_group("mecha") or collider.is_in_group("entity")):
			skip.append(hit.rid)
			continue
		return {"position": hit.position, "normal": hit.normal}
	return {}


func _land() -> void:
	is_airborne = false
	change_scaling(projectile_size)
	if _indirect:
		position = target_pos
		if MapSenses.building_key_at(self, global_position) != "":
			roof_burst = true
			payload()
			return
	_settle()


func _settle() -> void:
	mine_state = ARMING
	_arm_left = arm_time
	speed = 0
	velocity = Vector2.ZERO
	self.monitoring = false
	self.monitorable = false
	$Fuse.monitoring = false
	$Explosion.monitoring = false
	_register()


# ---- triggering ---------------------------------------------------------

# Called by check_mecha for each mecha near this mine.
func _sense(mecha) -> void:
	if mine_state != ARMED or mecha.is_dead:
		return
	var d := global_position.distance_to(mecha.global_position)
	if mine_type == "magnetic":
		if d <= attract_radius:
			_chasing = mecha
			mine_state = CHASING
			set_physics_process(true)
	elif d <= trigger_radius:
		trigger()


func _crawl(dt: float) -> void:
	if not is_instance_valid(_chasing) or _chasing.is_dead:
		_stop_chasing()
		return
	var to: Vector2 = _chasing.global_position - global_position
	if to.length() <= trigger_radius:
		trigger()
		return
	if to.length() > attract_radius * 1.5:
		_stop_chasing()
		return
	position += to.normalized() * minf(crawl_speed * dt, to.length())
	_move_cell()


func _stop_chasing() -> void:
	_chasing = null
	mine_state = ARMED
	set_physics_process(false)


# Sets the mine off: it leaves the grid and blows TRIGGER_FRAMES frames later.
func trigger() -> void:
	if mine_state == TRIGGERED or dying:
		return
	mine_state = TRIGGERED
	_unregister()
	$Explosion.monitoring = true
	_trigger_left = TRIGGER_FRAMES
	set_physics_process(true)


func is_armed() -> bool:
	return mine_state == ARMED or mine_state == CHASING


# ---- grid ---------------------------------------------------------------

static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL_SIZE).floor())


func _register() -> void:
	if _registered:
		return
	_registered = true
	_cell = _cell_of(global_position)
	if not _cells.has(_cell):
		_cells[_cell] = []
	_cells[_cell].append(self)
	_count += 1


func _unregister() -> void:
	if not _registered:
		return
	_registered = false
	var list: Array = _cells.get(_cell, [])
	list.erase(self)
	if list.is_empty():
		_cells.erase(_cell)
	_count -= 1


func _move_cell() -> void:
	var cell := _cell_of(global_position)
	if cell != _cell and _registered:
		_unregister()
		_register()


# Lets the mines round `mecha` react to it. Once per mecha per physics frame.
static func check_mecha(mecha: Node2D) -> void:
	if _count == 0:
		return
	var c := _cell_of(mecha.global_position)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var list = _cells.get(c + Vector2i(dx, dy))
			if list == null:
				continue
			for i in range(list.size() - 1, -1, -1):
				if i < list.size():
					list[i]._sense(mecha)


# The mines within `radius` of `pos`, settled or arming: {"type", "owner"
# (the mecha that laid it, or null), "position", "trigger_radius",
# "attract_radius" (magnetic only, else 0), "armed", "node"}.
static func mines_near(pos: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _count == 0:
		return out
	var c0 := _cell_of(pos - Vector2(radius, radius))
	var c1 := _cell_of(pos + Vector2(radius, radius))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for mine in _cells.get(Vector2i(cx, cy), []):
				if mine.global_position.distance_to(pos) > radius:
					continue
				var owner_body = mine.original_mecha_info.get("body") if mine.original_mecha_info else null
				out.append({
					"type": mine.mine_type,
					"owner": owner_body if is_instance_valid(owner_body) else null,
					"position": mine.global_position,
					"trigger_radius": mine.trigger_radius,
					"attract_radius": mine.attract_radius if mine.mine_type == "magnetic" else 0.0,
					"armed": mine.is_armed(),
					"node": mine,
				})
	return out


static func count() -> int:
	return _count
