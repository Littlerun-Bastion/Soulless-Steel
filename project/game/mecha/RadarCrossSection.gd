class_name RadarCrossSection
extends RefCounted

## A mecha's radar cross-section (RCS): how big it looks to a chipset from a
## direction. Each part with a collision outline (the core, the head, each
## shoulder, and the chassis: one shape, or one per leg) adds its facing
## width times its part's rcs_factor. Weapons and internal parts have no
## outline and add nothing; a part shot off adds nothing.
##
## The facing width is how wide an outline is across the line from the
## observer to the mecha: its points, in the mecha's pose now, projected onto
## the axis perpendicular to that line, the largest minus the smallest. A
## projection's width doesn't depend on where the outline sits, only on how
## it is turned, so a part at rest is measured the same on a live mecha and
## from its part resource.
##
## A mecha's RCS is its largest part RCS plus RCS_OTHERS times the sum of the
## rest, so a stealthy build needs every part stealthy.
##
## RCS_REFERENCE (reference_rcs) is PlayerProgress.DEFAULT_MECHA's RCS from
## straight ahead, worked out once from its part resources. A lock reads the
## RCS multiplier (mult: clamped); a sweep reads the relative RCS (relative:
## not clamped) and the kind it looks like (sweep_kind).
##
## A live mecha keeps its outlines (Mecha.rcs_outlines) in each collision
## node's own space, rebuilt only when its build changes.

## Placeholders.
const RCS_OTHERS := 0.25
const MULT_MIN := 0.3
const MULT_MAX := 1.5
## What a sweep reports a mecha as, by its relative RCS: the first row whose
## min it reaches. Placeholders.
const SWEEP_KINDS := [
	{"min": 0.8, "kind": "mech"},
	{"min": 0.4, "kind": "Coyote"},
	{"min": 0.1, "kind": "Raven"},
	{"min": 0.0, "kind": "Tick"},
]
## The head's outline: Mecha.tscn's HeadCollision, the same for every head.
const HEAD_OUTLINE := [Vector2(-16.6674, -23), Vector2(16.3326, -23), Vector2(16.3326, 37), Vector2(-16.6674, 37)]
## A mecha's collision nodes that make its outline, and the build slot each
## belongs to (for its rcs_factor) and the lost part that takes it away.
const OUTLINE_NODES := [
	{"node": "CoreCollision", "slot": "core", "lost": "core"},
	{"node": "HeadCollision", "slot": "head", "lost": "head"},
	{"node": "LeftShoulderCollision", "slot": "shoulders", "lost": "left_shoulder"},
	{"node": "RightShoulderCollision", "slot": "shoulders", "lost": "right_shoulder"},
	{"node": "ChassisSingleCollision", "slot": "chassis", "lost": "chassis"},
	{"node": "ChassisLeftCollision", "slot": "chassis", "lost": "chassis"},
	{"node": "ChassisRightCollision", "slot": "chassis", "lost": "chassis"},
]
## Straight ahead of a mecha at rest is -y, so the line from an observer
## there to the mecha runs +y.
const FRONT := Vector2.DOWN

static var _reference := -1.0


## How wide `points`, turned by `xform`'s rotation and scale, are across
## `direction` (the line from the observer to the mecha).
static func facing_width(points: PackedVector2Array, xform: Transform2D, direction: Vector2) -> float:
	if points.size() < 2 or direction.is_zero_approx():
		return 0.0
	var across := direction.normalized().orthogonal()
	var low := INF
	var high := -INF
	for point in points:
		var along := across.dot(xform.basis_xform(point))
		low = minf(low, along)
		high = maxf(high, along)
	return high - low


## The largest of `part_rcs` plus RCS_OTHERS times the rest.
static func combine(part_rcs: Array) -> float:
	var largest := 0.0
	var total := 0.0
	for value in part_rcs:
		total += float(value)
		largest = maxf(largest, float(value))
	return largest + RCS_OTHERS * (total - largest)


## The part outlines a mecha shows a radar, for Mecha.rcs_outlines: one entry
## per collision node with a shape, {node, points (its own space), factor,
## lost}.
static func outlines_of(mecha) -> Array:
	var found := []
	var build = mecha.get("build")
	if not build is Dictionary:
		return found
	for entry in OUTLINE_NODES:
		var node := mecha.get_node_or_null(entry.node) as CollisionPolygon2D
		var part = build.get(entry.slot)
		if node == null or not part or node.polygon.size() < 3:
			continue
		var factor = part.get("rcs_factor")
		found.append({"node": node, "points": node.polygon.duplicate(),
				"factor": float(factor) if (factor is float or factor is int) else 1.0, "lost": entry.lost})
	return found


## `mecha`'s RCS (px) seen from `from`.
static func of_mecha(mecha, from: Vector2) -> float:
	var direction: Vector2 = mecha.global_position - from
	if direction.is_zero_approx():
		direction = FRONT.rotated(mecha.global_rotation)
	var parts := []
	for entry in mecha.rcs_outlines():
		if mecha.is_part_lost(entry.lost) or not is_instance_valid(entry.node):
			continue
		parts.append(facing_width(entry.points, entry.node.global_transform, direction) * entry.factor)
	return combine(parts)


## A build's RCS (px) at rest, from its part resources (slot -> part, as
## Mecha.build): the core's, the shoulders' and the chassis' outlines and the
## head's HEAD_OUTLINE, each times its rcs_factor. `direction` is the line from
## the observer in the mecha's own frame: FRONT for straight ahead.
static func of_build(build: Dictionary, direction := FRONT) -> float:
	var parts := []
	var core = build.get("core")
	if core:
		parts.append(_part_width(core, core.get_collision(), direction))
	var head = build.get("head")
	if head:
		parts.append(_part_width(head, HEAD_OUTLINE, direction))
	var shoulders = build.get("shoulders")
	if shoulders:
		for side in [Mecha.SIDE.LEFT, Mecha.SIDE.RIGHT]:
			parts.append(_part_width(shoulders, shoulders.get_collision(side), direction))
	var chassis = build.get("chassis")
	if chassis:
		if chassis.is_legs:
			for side in [Mecha.SIDE.LEFT, Mecha.SIDE.RIGHT]:
				parts.append(_part_width(chassis, chassis.get_collision(side), direction))
		else:
			parts.append(_part_width(chassis, chassis.get_collision(), direction))
	return combine(parts)


static func _part_width(part, outline, direction: Vector2) -> float:
	var points := Mecha.collision_shape_of(outline)
	var factor = part.get("rcs_factor")
	return facing_width(points, Transform2D.IDENTITY, direction) * (float(factor) if (factor is float or factor is int) else 1.0)


## PlayerProgress.DEFAULT_MECHA's RCS from straight ahead, worked out once.
static func reference_rcs() -> float:
	if _reference <= 0.0:
		var build := {}
		for slot in ["core", "head", "shoulders", "chassis"]:
			var id = PlayerProgress.DEFAULT_MECHA.get(slot)
			if id:
				build[slot] = PartManager.get_part(slot, id)
		_reference = maxf(of_build(build), 1.0)
	return _reference


## `mecha`'s RCS from `from` over RCS_REFERENCE, not clamped.
static func relative(mecha, from: Vector2) -> float:
	return of_mecha(mecha, from) / reference_rcs()


## The RCS multiplier on a lock's rate: the relative RCS, clamped to
## MULT_MIN..MULT_MAX.
static func mult(mecha, from: Vector2) -> float:
	return clampf(relative(mecha, from), MULT_MIN, MULT_MAX)


## What a sweep reports a body of relative RCS `value` as (SWEEP_KINDS).
static func sweep_kind(value: float) -> String:
	for row in SWEEP_KINDS:
		if value >= float(row.min):
			return row.kind
	return SWEEP_KINDS[-1].kind
