extends RefCounted
class_name EntityAttack

# How an Entity's bite, ram or acid hurts a mecha: through the same armour
# and component system a projectile uses (Mecha.armor_check, then
# damage_component), so facing matters. A pen 2 bite gets through rear
# armour (level 1) but only chips the sides and front, which is why Stalkers
# circle round behind their prey. Two hits skip the armour check:
# hit_external() goes for components bolted to the outside, and
# hit_through() always reaches a component. Neither does anything in the
# Flag's grace window (Mecha.is_in_flag_grace), and both go through
# damage_component, like a projectile's hit. A raised shield stops an attack
# that comes from outside its bubble (Mecha.shield_check, with the attack's
# pen and damage; a whip has no pen) before any of that; an attacker inside
# the bubble, or a harpoon already in (hit_through), gets past it.

# Parts an attack can land on, with how likely each is. Shoulders only count
# on the side the attacker is on.
const PART_WEIGHTS := {"core": 4.0, "chassis": 3.0, "shoulder": 2.0, "head": 1.0}


# Returns true when the hit got through the armour and damaged a component.
# `from`: where the attack comes from for the shield (a splash's centre); the
# attacker's position when null.
static func hit_mecha(attacker: Node2D, mecha: Node2D, damage: int, pen: int, knockback := 0.0, from = null) -> bool:
	if not is_instance_valid(mecha) or mecha.is_dead:
		return false
	var to_attacker: Vector2 = (attacker.global_position - mecha.global_position).normalized()
	if to_attacker == Vector2.ZERO:
		to_attacker = Vector2.UP
	var dir := -to_attacker
	var source: Vector2 = from if from is Vector2 else attacker.global_position
	if mecha.shield_check(source, pen, damage) != "":
		_stopped_by_shield(attacker, mecha, dir, knockback)
		return false
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
			mecha.damage_component(result.part_name, result.component_name, damage, dir)
	mecha.add_decal(0, impact_point, "bullet_hole", Vector2(40, 40))
	if knockback > 0.0:
		mecha.knockback(knockback, dir, true)
	if mecha.has_method("on_attacked_by"):
		mecha.on_attacked_by(attacker)
	return result.penetrated and result.component_name != ""


# A hit that goes for what's bolted to the outside (a Coyote's whip):
# optics, antennae, radiators, nozzles, weapon feeds, tracks. Those sit on
# top of the armour, so the hit doesn't have to get through it; it damages a
# living external component of the part it lands on, or of another part on
# that side if that one has none left. Returns true if it damaged one.
static func hit_external(attacker: Node2D, mecha: Node2D, damage: int, knockback := 0.0) -> bool:
	if not is_instance_valid(mecha) or mecha.is_dead:
		return false
	var to_attacker := _to_attacker(attacker, mecha)
	if mecha.shield_check(attacker.global_position, 0, damage) != "":
		_stopped_by_shield(attacker, mecha, -to_attacker, knockback)
		return false
	var impact := find_impact(attacker, mecha)
	var first: String = impact.get("part", pick_part(mecha, to_attacker))
	var impact_point: Vector2 = impact.get("point", mecha.global_position + to_attacker * 60.0)
	var damaged := false
	if not mecha.is_in_flag_grace():
		var parts: Array = [first]
		for part_name in _side_parts(mecha, to_attacker):
			if part_name not in parts:
				parts.append(part_name)
		for part_name in parts:
			var exposed: Array = mecha.get_eligible_components(part_name, "", false)
			if exposed.is_empty():
				continue
			_credit(attacker, mecha)
			mecha.damage_component(part_name, mecha.select_component_by_weight(part_name, exposed), damage, -to_attacker)
			damaged = true
			break
	struck(attacker, mecha, impact_point, -to_attacker, knockback)
	return damaged


# A hit that always gets through (a Fisher's buried harpoon drawing on it):
# no armour check, a random part (weighted as PART_WEIGHTS, either side),
# then a random living component of it, inside or out. Returns true if it
# damaged one.
static func hit_through(attacker: Node2D, mecha: Node2D, damage: int) -> bool:
	if not is_instance_valid(mecha) or mecha.is_dead or mecha.is_in_flag_grace():
		return false
	var options := {}
	for part_name in mecha.armor:
		if mecha.get_eligible_components(part_name, "", true).is_empty():
			continue
		var key: String = "shoulder" if part_name.ends_with("shoulder") else part_name
		options[part_name] = PART_WEIGHTS.get(key, 1.0)
	if options.is_empty():
		return false
	var part_name: String = _weighted_pick(options)
	var eligible: Array = mecha.get_eligible_components(part_name, "", true)
	_credit(attacker, mecha)
	var dir := -_to_attacker(attacker, mecha)
	mecha.damage_component(part_name, mecha.select_component_by_weight(part_name, eligible), damage, dir)
	if mecha.has_method("on_attacked_by"):
		mecha.on_attacked_by(attacker)
	return true


static func _to_attacker(attacker: Node2D, mecha: Node2D) -> Vector2:
	var to_attacker: Vector2 = (attacker.global_position - mecha.global_position).normalized()
	return to_attacker if to_attacker != Vector2.ZERO else Vector2.UP


# Who gets the blame: set before the damage, since a cockpit kill inside
# damage_component() reads it.
static func _credit(attacker: Node2D, mecha: Node2D) -> void:
	mecha.last_damage_source = {"body": attacker, "name": attacker.mecha_name}
	mecha.last_damage_weapon = attacker.mecha_name


# The parts of a hit that don't depend on damage: a scuff where it landed,
# the knockback, and telling the mecha who did it (NPCs turn on it).
static func struck(attacker: Node2D, mecha: Node2D, impact_point: Vector2, dir: Vector2, knockback := 0.0) -> void:
	mecha.add_decal(0, impact_point, "bullet_hole", Vector2(40, 40))
	if knockback > 0.0:
		mecha.knockback(knockback, dir, true)
	if mecha.has_method("on_attacked_by"):
		mecha.on_attacked_by(attacker)


# A hit the shield stopped: no scuff on the hull, the rest as struck.
static func _stopped_by_shield(attacker: Node2D, mecha: Node2D, dir: Vector2, knockback: float) -> void:
	if knockback > 0.0:
		mecha.knockback(knockback, dir, true)
	if mecha.has_method("on_attacked_by"):
		mecha.on_attacked_by(attacker)


# The parts on the attacker's side of the mecha, most likely first.
static func _side_parts(mecha: Node2D, to_attacker: Vector2) -> Array:
	var right := Vector2(1, 0).rotated(mecha.global_rotation)
	var shoulder := "right_shoulder" if to_attacker.dot(right) > 0.0 else "left_shoulder"
	var parts := []
	for key in PART_WEIGHTS:
		var part_name: String = shoulder if key == "shoulder" else key
		if mecha.armor.has(part_name) and not mecha.is_part_lost(part_name):
			parts.append(part_name)
	return parts


static func _weighted_pick(options: Dictionary) -> String:
	var total := 0.0
	for weight in options.values():
		total += weight
	var pick := randf() * total
	for key in options:
		pick -= options[key]
		if pick < 0.0:
			return key
	return options.keys()[-1]


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
			hit_mecha(attacker, mecha, damage, pen, knockback, center)
			hit.append(mecha)
	return hit


# Where the attack lands, the way a projectile finds it: a ray from the
# attacker to the mecha's centre, and the part and surface point it meets
# (armour angles then come out as they would for a shot). {} when the ray
# can't reach the hull (attacker inside it, a wall in between): then a part
# is picked by weight instead. A raised shield's bubble isn't a part.
const IMPACT_PARTS := ["head", "core", "chassis", "left_shoulder", "right_shoulder"]

static func find_impact(attacker: Node2D, mecha: Node2D) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = mecha.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(attacker.global_position, mecha.global_position, MapSenses.SIGHT_MASK)
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
		if mecha.armor.has(part_name) and not mecha.is_part_lost(part_name):
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
