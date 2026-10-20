extends RefCounted
class_name EntityAttack

# How an Entity's bite, ram or acid hurts a mecha: through the same armour
# and component system a projectile uses (Mecha.armor_check, then
# damage_component), so facing matters. A pen 2 bite gets through rear
# armour (level 1) but only chips the sides and front, which is why Stalkers
# circle round behind their prey.

# Parts an attack can land on, with how likely each is. Shoulders only count
# on the side the attacker is on.
const PART_WEIGHTS := {"core": 4.0, "chassis": 3.0, "shoulder": 2.0, "head": 1.0}


# Returns true when the hit got through the armour and damaged a component.
static func hit_mecha(attacker: Node2D, mecha: Node2D, damage: int, pen: int, knockback := 0.0) -> bool:
	if not is_instance_valid(mecha) or mecha.is_dead:
		return false
	var to_attacker: Vector2 = (attacker.global_position - mecha.global_position).normalized()
	if to_attacker == Vector2.ZERO:
		to_attacker = Vector2.UP
	var dir := -to_attacker
	var impact := find_impact(attacker, mecha)
	var part: String = impact.get("part", "")
	var impact_point: Vector2 = impact.get("point", mecha.global_position + to_attacker * 60.0)
	if part == "":
		part = pick_part(mecha, to_attacker)

	var result: Dictionary = mecha.armor_check(part, impact_point, dir, pen, damage)
	if result.penetrated:
		# Before the damage: a cockpit kill inside damage_component() reads it.
		mecha.last_damage_source = {"body": attacker, "name": attacker.mecha_name}
		mecha.last_damage_weapon = attacker.mecha_name
		if result.component_name != "":
			mecha.damage_component(result.part_name, result.component_name, damage)
	mecha.add_decal(0, impact_point, "bullet_hole", Vector2(40, 40))
	if knockback > 0.0:
		mecha.knockback(knockback, dir, true)
	if mecha.has_method("on_attacked_by"):
		mecha.on_attacked_by(attacker)
	return result.penetrated and result.component_name != ""


# Every living mecha whose hull is within reach of center takes the hit
# (a Brute's stomp, a Spitter's acid splash). Returns the mechas hit.
const HULL_REACH := 90.0  # a mecha's hull reaches about this far from its centre

static func hit_mechas_near(attacker: Node2D, mechas: Array, center: Vector2, reach: float,
		damage: int, pen: int, knockback := 0.0) -> Array:
	var hit := []
	for mecha in mechas:
		if not is_instance_valid(mecha) or mecha.is_dead:
			continue
		if mecha.global_position.distance_to(center) <= reach + HULL_REACH:
			hit_mecha(attacker, mecha, damage, pen, knockback)
			hit.append(mecha)
	return hit


# Where the attack lands, the way a projectile finds it: a ray from the
# attacker to the mecha's centre, and the part and surface point it meets
# (armour angles then come out as they would for a shot). {} when the ray
# can't reach the hull (attacker inside it, a wall in between, a shield):
# then a part is picked by weight instead.
const IMPACT_PARTS := ["head", "core", "chassis", "left_shoulder", "right_shoulder"]

static func find_impact(attacker: Node2D, mecha: Node2D) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = mecha.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(attacker.global_position, mecha.global_position)
	var exclude: Array[RID] = []
	if attacker is CollisionObject2D:
		exclude.append(attacker.get_rid())
	for _i in 4:  # see past other Entities in the way
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if result.is_empty():
			return {}
		if result.collider == mecha:
			var part: String = mecha.get_part_name_from_shape(result.shape)
			if part in IMPACT_PARTS:
				return {"part": part, "point": result.position}
			return {}
		if not result.collider is Entity:
			return {}
		exclude.append(result.rid)
	return {}


# A part on the side of the mecha the attacker is on, weighted by size.
static func pick_part(mecha: Node2D, to_attacker: Vector2) -> String:
	var right := Vector2(1, 0).rotated(mecha.global_rotation)
	var shoulder := "right_shoulder" if to_attacker.dot(right) > 0.0 else "left_shoulder"
	var options := {}
	for key in PART_WEIGHTS:
		var part_name: String = shoulder if key == "shoulder" else key
		if mecha.armor.has(part_name):
			options[part_name] = PART_WEIGHTS[key]
	if options.is_empty():
		return "core"
	var total := 0.0
	for weight in options.values():
		total += weight
	var pick := randf() * total
	for part_name in options:
		pick -= options[part_name]
		if pick < 0.0:
			return part_name
	return options.keys()[-1]


# Which armour face of the mecha an attacker at this position would hit.
static func facing_toward(mecha: Node2D, attacker_position: Vector2) -> String:
	return mecha.get_global_facing_from_angle(attacker_position)
