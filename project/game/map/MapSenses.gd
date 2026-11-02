class_name MapSenses
extends RefCounted

# Shared rules for how a map's buildings, vehicles and foliage affect shots
# and sight.
#
# Walls: BuildingField gives every generated building its outline as a
# collision shape on WALL_LAYER. Nothing moves against that layer (mechas
# walk through walls), but rays see it: each outline crossed is one wall.
#   - A shot loses 1 AP per wall it crosses and stops at the wall where its
#     AP reaches 0 (trace_shot).
#   - Walls block sight (walls_between, and SIGHT_MASK rays). Two points in
#     the same building have no wall between them, so mechas inside one
#     building see each other.
#
# Vehicles: VehicleField puts cars (vehicles a tank can trample) on
# VEHICLE_LAYER and heavier vans and trucks on HEAVY_VEHICLE_LAYER.
# VEHICLE_MASK covers both. Mechas collide with both and push vehicles; a
# sprinting mecha drops VEHICLE_LAYER and passes over cars (Mecha.move).
#   - A shot passing through a vehicle stops in it with that vehicle's
#     shot_block chance; otherwise it goes on with its AP unchanged
#     (trace_shot). With `damage` on (real projectiles), every vehicle the
#     shot meets takes 1 point of damage (VehicleField.damage).
#   - Vehicles don't block sight: they are lower than a mecha.
#
# Ray masks:
#   SHOT_MASK      the main hit ray of a projectile; walls and vehicles are
#                  handled by trace_shot first.
#   SIGHT_MASK     line of sight; sees walls, not vehicles.
#   NON_WALL_MASK  movement steering; sees vehicles, not walls.
#
# Foliage: a target under foliage is detected at a shorter range
# (detection_mult), and an observer under a tree sees less far (sight_mult).
# Bushes are too small to hide a mecha, so they only hide Entities.

const WALL_LAYER := 10
const WALL_MASK := 1 << (WALL_LAYER - 1)
const VEHICLE_LAYER := 11
const HEAVY_VEHICLE_LAYER := 12
const CAR_MASK := 1 << (VEHICLE_LAYER - 1)
const HEAVY_VEHICLE_MASK := 1 << (HEAVY_VEHICLE_LAYER - 1)
const VEHICLE_MASK := CAR_MASK | HEAVY_VEHICLE_MASK
## Damage a shot does to each vehicle it meets.
const SHOT_VEHICLE_DAMAGE := 1.0
const NON_WALL_MASK := 0xFFFFFFFF & ~WALL_MASK
const SHOT_MASK := 0xFFFFFFFF & ~(WALL_MASK | VEHICLE_MASK)
const SIGHT_MASK := 0xFFFFFFFF & ~VEHICLE_MASK
const MAX_WALLS := 16
const MAX_SHOT_HITS := 24

## Detection range multiplier for a target under a tree.
const TREE_CONCEALMENT := 0.6
## Detection range multiplier for an Entity in a bush.
const BUSH_CONCEALMENT := 0.5
## Sight range multiplier for an observer under a tree.
const TREE_SIGHT := 0.85


# Points where the segment from `from` to `to` crosses a wall, in order.
static func wall_hits(world: World2D, from: Vector2, to: Vector2) -> PackedVector2Array:
	var hits := PackedVector2Array()
	if from.is_equal_approx(to):
		return hits
	var space := world.direct_space_state
	var dir := (to - from).normalized()
	var start := from
	for _i in MAX_WALLS:
		var query := PhysicsRayQueryParameters2D.create(start, to, WALL_MASK)
		query.collide_with_areas = false
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		hits.append(result.position)
		start = result.position + dir * 0.5
		if start.distance_squared_to(from) >= to.distance_squared_to(from):
			break
	return hits


static func walls_between(world: World2D, a: Vector2, b: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(a, b, WALL_MASK)
	query.collide_with_areas = false
	return not world.direct_space_state.intersect_ray(query).is_empty()


# Moves a shot with `ap` armour pen from `from` to `to` through the walls and
# vehicles on the way, in order. Each wall costs 1 AP and the shot stops at
# the wall where its AP reaches 0, or at the first wall if stop_at_wall (an
# impact fuse). Each vehicle stops it with the vehicle's shot_block chance,
# and with `damage` takes SHOT_VEHICLE_DAMAGE.
# Returns {"ap": AP left, "stop": where it stopped or null, "by": "wall",
# "vehicle" or ""}.
static func trace_shot(world: World2D, from: Vector2, to: Vector2, ap: int, stop_at_wall := false, damage := false) -> Dictionary:
	var length_sq := from.distance_squared_to(to)
	if length_sq < 0.0001:
		return {"ap": ap, "stop": null, "by": ""}
	var space := world.direct_space_state
	var dir := (to - from).normalized()
	var start := from
	for _i in MAX_SHOT_HITS:
		var query := PhysicsRayQueryParameters2D.create(start, to, WALL_MASK | VEHICLE_MASK)
		query.collide_with_areas = false
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result.collider
		var field: VehicleField = null
		if collider is VehicleField:
			field = collider
		elif collider != null and collider.get_parent() is VehicleField:
			field = collider.get_parent()
		if field != null:
			var index := field.index_of(collider, result.rid)
			var stopped := randf() < field.shot_block_for(collider, result.rid)
			if damage and index >= 0:
				field.damage(index, SHOT_VEHICLE_DAMAGE)
			if stopped:
				return {"ap": ap, "stop": result.position, "by": "vehicle"}
		else:
			ap -= 1
			if ap <= 0 or stop_at_wall:
				return {"ap": maxi(ap, 0), "stop": result.position, "by": "wall"}
		start = result.position + dir * 0.5
		if from.distance_squared_to(start) >= length_sq:
			break
	return {"ap": ap, "stop": null, "by": ""}


# Detection range multiplier for `target`, from the foliage covering it.
static func detection_mult(target: Node2D) -> float:
	var cover := _foliage_at(target)
	if cover == "tree":
		return TREE_CONCEALMENT
	if cover == "bush" and not target.is_in_group("mecha"):
		return BUSH_CONCEALMENT
	return 1.0


# Sight range multiplier for `observer`, from a tree above it.
static func sight_mult(observer: Node2D) -> float:
	return TREE_SIGHT if _foliage_at(observer) == "tree" else 1.0


# Foliage over a node, looked up once per physics frame per node: many
# observers ask about the same targets each frame.
static var _foliage_cache := {}
static var _foliage_cache_frame := -1


static func _foliage_at(node: Node2D) -> String:
	if not node.is_inside_tree():
		return ""
	var frame := Engine.get_physics_frames()
	if frame != _foliage_cache_frame:
		_foliage_cache.clear()
		_foliage_cache_frame = frame
	var id := node.get_instance_id()
	if _foliage_cache.has(id):
		return _foliage_cache[id]
	var kind := _foliage_lookup(node)
	_foliage_cache[id] = kind
	return kind


static func _foliage_lookup(node: Node2D) -> String:
	var best := ""
	for layer in node.get_tree().get_nodes_in_group("foliage_layer"):
		var kind: String = layer.concealment_at(layer.to_local(node.global_position))
		if kind == "tree":
			return kind
		if kind != "":
			best = kind
	return best
