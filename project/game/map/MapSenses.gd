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
# Smoke (smoke_cloud.gd) blocks sight too: in_smoke, smoke_between, and
# sight_blocked (walls or smoke) for NPCs and the player's view.
#
# Darkness and the vision cone are drawn with 2D lights (Mecha.tscn): the
# player's MechaShadowGen dims everything on SIGHT_LIGHT_MASK, and every
# mecha's MechaLight (its IR illuminator) lights a cone on it, shadowed by
# LightOccluder2Ds (BuildingField streams them for its buildings, Building.tscn
# has its own). Smoke casts no shadow; it hides things through the queries
# above. join_sight_light puts a map on that light layer.
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

const SMOKE := preload("res://game/weapons/smoke_cloud.gd")
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
const MAX_SOLID_SKIPS := 4
## Light layer the darkness and the vision cones act on (light_mask bit 2).
const SIGHT_LIGHT_MASK := 2

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


# Line of sight from `a` to `b`: blocked by a building wall or by smoke. The
# shared sight check for NPCs (Enemy.update_senses) and the player's view.
static func sight_blocked(world: World2D, a: Vector2, b: Vector2) -> bool:
	return smoke_between(a, b) or walls_between(world, a, b)


# Smoke (smoke_cloud.gd): whether `point` is in thick smoke, and whether
# thick smoke lies between two points. Plain maths over the few live clouds.
static func in_smoke(point: Vector2) -> bool:
	return SMOKE.point_in_smoke(point)


static func smoke_between(a: Vector2, b: Vector2) -> bool:
	return SMOKE.blocks(a, b)


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


# Puts `node` and everything under it (internal children too) on the sight
# light layer, keeping the layers it already has. Once per map and per
# streamed-in scene; nodes built later by map code copy their parent's mask.
static func join_sight_light(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).light_mask |= SIGHT_LIGHT_MASK
	for child in node.get_children(true):
		join_sight_light(child)


# Where the line from `from` to `to` first meets a wall or another solid body,
# or null if it is clear. Vehicles (lower than a shoulder mount), mechas,
# Entities and devices (wards, drones) don't count. Used where something is
# stopped by walls only: a direct-fire designator and the laser beam.
static func solid_hit(world: World2D, from: Vector2, to: Vector2, exclude: Array[RID] = []):
	var space := world.direct_space_state
	var skip: Array[RID] = exclude.duplicate()
	for _i in MAX_SOLID_SKIPS:
		var query := PhysicsRayQueryParameters2D.create(from, to, SIGHT_MASK, skip)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return null
		var collider := hit.collider as Node
		if collider and (collider.is_in_group("mecha") or collider.is_in_group("entity") or collider.is_in_group("device")):
			skip.append(hit.rid)
			continue
		return hit.position
	return null


# Which building `pos` is in, as a key two points can be compared by: ""
# outside, "field:<id>" in a generated building (BuildingField), "node:<id>"
# in a hand-made one (the BuildingArea polygon of Building.tscn). Blasts only
# reach targets with the same key as the blast, and an indirect shell that
# comes down where the key isn't "" hits the roof (complex_projectile).
# Called per blast and per landing, not per frame.
static func building_key_at(node: Node, pos: Vector2) -> String:
	if node == null or not node.is_inside_tree():
		return ""
	var field := BuildingField.find(node)
	if field:
		var i := field.building_at(pos)
		if i >= 0:
			return "field:%d" % i
	for area in node.get_tree().get_nodes_in_group("building_area"):
		if not (area is Area2D):
			continue
		for child in area.get_children():
			var poly := child as CollisionPolygon2D
			if poly and Geometry2D.is_point_in_polygon(poly.global_transform.affine_inverse() * pos, poly.polygon):
				return "node:%d" % area.get_parent().get_instance_id()
	return ""


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
