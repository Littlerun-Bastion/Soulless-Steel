class_name MechaBody
extends Node2D

## What a destroyed mecha leaves on the map: its own body in its last pose.
## A Wreck draws one as its hull (Wreck.copy_mecha_visuals); in modes without
## wrecks CombatScene leaves one on its own, with no loot.
##
## copy_from() copies every part the mecha draws (chassis of any type, core,
## head and head port, shoulders, arm and shoulder weapons, and the bullet
## holes on them), each layer it needs (Main and Sub, with its heat shader
## material), at its last position and rotation and in the mecha's draw
## order. Glow layers go dark. The body starts hot (START_HEAT, or the mecha's
## own heat if hotter) and cools to ambient over COOL_TIME s through its heat
## shader parameter, like a ScrapPart (ScrapPart.set_heat_parameters).
##
## The body is solid (Solid, a StaticBody2D with copies of the mecha's own
## part collision shapes): mechas and Entities can't walk through it, and it
## stops shots, lasers and blasts (they treat it like any solid obstacle), so
## a wreck is cover. NPCs steer round it and won't fire through it.
##
## One or two parts come off (choose_shed, then shed): each is thrown a short
## way and stays on the ground by the body as debris. A shoulder comes off
## with the arm weapon it carries. Debris isn't solid: a part's shape goes
## when the part comes off.
##
## Use: new(), position it, copy_from(mecha) while the mecha is still valid,
## add it to the tree, then shed() the parts choose_shed() picked.

## Mecha child -> the part (design slot, or "core"/"chassis") it draws.
const PART_NODES := {
	"Chassis": "chassis",
	"Core": "core",
	"HeadPort": "core",
	"Head": "head",
	"ArmWeaponLeft": "arm_weapon_left",
	"ArmWeaponRight": "arm_weapon_right",
	"ShoulderWeaponLeft": "shoulder_weapon_left",
	"ShoulderWeaponRight": "shoulder_weapon_right",
	"LeftShoulder": "left_shoulder",
	"RightShoulder": "right_shoulder",
	"CoreDecals": "core",
}
## Mecha collision shape -> the part it belongs to, for the solid body.
const SOLID_SHAPES := {
	"CoreCollision": "core",
	"HeadCollision": "head",
	"LeftShoulderCollision": "left_shoulder",
	"RightShoulderCollision": "right_shoulder",
	"ChassisSingleCollision": "chassis",
	"ChassisLeftCollision": "chassis",
	"ChassisRightCollision": "chassis",
}
## Children not copied: glow layers (dark on a wreck), hidden projectiles
## and melee hitboxes.
const SKIPPED := ["Glow", "SprintGlow", "Projectile", "MeleeHitboxes"]
## Parts that can come off; never the core or the chassis.
const SHED_OPTIONS := ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left",
		"shoulder_weapon_right", "head", "left_shoulder", "right_shoulder"]
## A shoulder takes its arm weapon with it.
const SHED_WITH := {"left_shoulder": ["arm_weapon_left"], "right_shoulder": ["arm_weapon_right"]}
## Placeholders.
const START_HEAT := 200.0
const COOL_TIME := 60.0
const HEAT_REFRESH := 0.25
const SHED_TWO_CHANCE := 0.5
const SHED_DISTANCE := Vector2(120, 260)
const SHED_SPIN := 1.5
const SHED_TIME := 0.45
## How many stripped armour pips one destroyed component counts as when
## choosing what comes off.
const DESTROYED_WEIGHT := 2

## Parts that came off, including arm weapons that went with a shoulder.
var shed_slots: Array[String] = []
## What makes the body solid (copy_from).
var solid: StaticBody2D = null
var _parts := {}  # part -> copied top-level nodes
var _shapes := {}  # part -> its CollisionPolygon2D copies in solid
var _material_copies := {}
var _heat_materials: Array[ShaderMaterial] = []
var _start_heat := START_HEAT
var _age := 0.0
var _refresh := 0.0
static var _heat_shaders := {}


func copy_from(mecha: Node2D) -> void:
	rotation = mecha.global_rotation
	scale = mecha.global_scale
	_start_heat = maxf(START_HEAT, float(mecha.get("shader_heat_value")))
	for child in mecha.get_children():
		var part: String = PART_NODES.get(String(child.name), "")
		if part == "":
			continue
		var copy := _copy(child)
		if copy == null:
			continue
		add_child(copy)
		if not _parts.has(part):
			_parts[part] = []
		_parts[part].append(copy)
	_copy_shapes(mecha)
	_set_heat(_start_heat)


func _notification(what: int) -> void:
	# Freed before the deferred add_child ran: the solid body was never ours.
	if what == NOTIFICATION_PREDELETE and solid != null and solid.get_parent() == null:
		solid.free()


## The parts the solid body still has a shape for.
func get_solid_parts() -> Array[String]:
	var found: Array[String] = []
	for part in _shapes:
		if not _shapes[part].is_empty():
			found.append(part)
	return found


# The solid body goes in deferred: a death can come inside a physics callback
# (a contact-fused round's body_shape_entered), where adding shapes fails.
func _copy_shapes(mecha: Node2D) -> void:
	solid = StaticBody2D.new()
	solid.name = "Solid"
	add_child.call_deferred(solid)
	for shape_name in SOLID_SHAPES:
		var source := mecha.get_node_or_null(shape_name) as CollisionPolygon2D
		if source == null or source.disabled or _area(source.polygon) < 1.0:
			continue
		var shape := CollisionPolygon2D.new()
		shape.name = shape_name
		shape.polygon = source.polygon
		shape.transform = source.transform
		solid.add_child(shape)
		var part: String = SOLID_SHAPES[shape_name]
		if not _shapes.has(part):
			_shapes[part] = []
		_shapes[part].append(shape)


static func _area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		twice += a.x * b.y - b.x * a.y
	return absf(twice) * 0.5


func _process(delta: float) -> void:
	_age += delta
	_refresh -= delta
	if _refresh > 0.0 and _age < COOL_TIME:
		return
	_refresh = HEAT_REFRESH
	_set_heat(get_heat())
	if _age >= COOL_TIME:
		set_process(false)


## The heat shader value now: from the start heat down to ambient (0).
func get_heat() -> float:
	return lerpf(_start_heat, 0.0, clampf(_age / COOL_TIME, 0.0, 1.0))


## Parts drawn on the body (not come off) with at least one sprite.
func get_part_slots() -> Array[String]:
	var found: Array[String] = []
	for part in _parts:
		if part in shed_slots:
			continue
		for node in _parts[part]:
			if _has_texture(node):
				found.append(part)
				break
	return found


## Throws `slot`'s part off the body (animated, or straight to where it
## lands), to lie on the ground beside it. Returns where it came off, in
## global coordinates, for an explosion.
func shed(slot: String, animate := true) -> Vector2:
	var nodes := []
	for part in [slot] + SHED_WITH.get(slot, []):
		for shape in _shapes.get(part, []):
			if solid.is_inside_tree():
				shape.queue_free()
			else:
				solid.remove_child(shape)
				shape.free()
		_shapes.erase(part)
		if _parts.has(part) and not part in shed_slots:
			nodes.append_array(_parts[part])
			shed_slots.append(part)
	if nodes.is_empty():
		return global_position
	var centre := Vector2.ZERO
	for node in nodes:
		centre += node.position
	centre /= nodes.size()
	var debris := Node2D.new()
	debris.name = "Debris"
	debris.position = centre
	add_child(debris)
	move_child(debris, 0)
	for node in nodes:
		remove_child(node)
		node.position -= centre
		debris.add_child(node)
	var out := centre.normalized() if centre.length() > 1.0 else Vector2.RIGHT.rotated(randf() * TAU)
	var lands := centre + out.rotated(randf_range(-0.6, 0.6)) * randf_range(SHED_DISTANCE.x, SHED_DISTANCE.y)
	var spin := randf_range(-SHED_SPIN, SHED_SPIN)
	if animate and is_inside_tree():
		var tween := debris.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(debris, "position", lands, SHED_TIME)
		tween.tween_property(debris, "rotation", spin, SHED_TIME)
	else:
		debris.position = lands
		debris.rotation = spin
	return to_global(centre) if is_inside_tree() else global_position + centre


## The one or two parts that come off `mecha`. Those that took the most
## damage (destroyed components, stripped armour) go first; parts whose
## weapon is in the wreck's loot go last, so a weapon still on the wreck is
## one the player can salvage; ties are random. Never the core or chassis.
static func choose_shed(mecha, loot: Array = [], rng: RandomNumberGenerator = null) -> Array[String]:
	var count := 2 if _randf(rng) < SHED_TWO_CHANCE else 1
	var in_loot := slots_in_loot(mecha, loot)
	var options := []
	for slot in SHED_OPTIONS:
		if _is_fitted(mecha, slot):
			options.append({"slot": slot, "loot": slot in in_loot, "damage": damage_of(mecha, slot), "roll": _randf(rng)})
	options.sort_custom(func(a, b):
		if a.loot != b.loot:
			return not a.loot
		if a.damage != b.damage:
			return a.damage > b.damage
		return a.roll < b.roll)
	var chosen: Array[String] = []
	for option in options:
		if chosen.size() >= count:
			break
		if _goes_with(option.slot, chosen):
			continue
		chosen.append(option.slot)
	return chosen


## The design slots whose weapon dropped intact into `loot` (WreckLoot), and
## the shoulders that carry one.
static func slots_in_loot(mecha, loot: Array) -> Array:
	var found := []
	for stack in loot:
		if not stack is item_stack or stack.kind != item_stack.ItemKind.PART:
			continue
		for slot in WreckLoot.WEAPON_SLOTS:
			var part = mecha.build.get(slot)
			if part and not slot in found and str(part.part_id) == stack.item_id \
					and WreckLoot.part_type_of(slot) == stack.item_type:
				found.append(slot)
				break
	for shoulder in SHED_WITH:
		for slot in SHED_WITH[shoulder]:
			if slot in found:
				found.append(shoulder)
	return found


## How badly a part was hit: stripped armour pips plus destroyed components
## (DESTROYED_WEIGHT each). Arm weapons count their weapon feed, shoulder
## weapons the components they add to the core.
static func damage_of(mecha, slot: String) -> int:
	match slot:
		"head", "left_shoulder", "right_shoulder":
			var damage := 0
			for facing in mecha.armor[slot]:
				damage += maxi(3 - int(mecha.armor[slot][facing].pips), 0)
			for comp in mecha.components[slot].values():
				if comp.disabled:
					damage += DESTROYED_WEIGHT
			return damage
		"arm_weapon_left", "arm_weapon_right":
			var shoulder := "left_shoulder" if slot == "arm_weapon_left" else "right_shoulder"
			var feed: Dictionary = mecha.components[shoulder].get("weapon_feed", {})
			return DESTROYED_WEIGHT if feed.get("disabled", false) else 0
		_:
			var weapon = mecha.build.get(slot)
			var damage := 0
			if weapon and "additional_components" in weapon and weapon.additional_components:
				for comp_data in weapon.additional_components:
					var comp: Dictionary = mecha.components.core.get(comp_data.name, {})
					if comp.get("disabled", false):
						damage += DESTROYED_WEIGHT
			return damage


static func _is_fitted(mecha, slot: String) -> bool:
	var part = mecha.build.get("shoulders" if slot in ["left_shoulder", "right_shoulder"] else slot)
	return true if part else false


static func _goes_with(slot: String, chosen: Array) -> bool:
	for other in chosen:
		if slot in SHED_WITH.get(other, []) or other in SHED_WITH.get(slot, []):
			return true
	return false


static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()


static func _has_texture(node: Node) -> bool:
	if node is Sprite2D and node.texture != null:
		return true
	for child in node.get_children():
		if _has_texture(child):
			return true
	return false


# A plain copy of a mecha's Node2D or Sprite2D and its drawn children; no
# scripts, particles, lights or collisions.
func _copy(node: Node) -> Node2D:
	var cls := node.get_class()
	if (cls != "Node2D" and cls != "Sprite2D") or String(node.name) in SKIPPED or not node.visible:
		return null
	var copy: Node2D
	if node is Sprite2D:
		var sprite := Sprite2D.new()
		sprite.texture = node.texture
		sprite.centered = node.centered
		sprite.offset = node.offset
		sprite.flip_h = node.flip_h
		sprite.flip_v = node.flip_v
		sprite.hframes = node.hframes
		sprite.vframes = node.vframes
		sprite.frame = node.frame
		sprite.region_enabled = node.region_enabled
		sprite.region_rect = node.region_rect
		copy = sprite
	else:
		copy = Node2D.new()
	copy.name = node.name
	copy.transform = node.transform
	copy.z_index = node.z_index
	copy.z_as_relative = node.z_as_relative
	copy.show_behind_parent = node.show_behind_parent
	copy.modulate = node.modulate
	copy.self_modulate = node.self_modulate
	copy.light_mask = node.light_mask
	copy.texture_filter = node.texture_filter
	copy.material = _copy_material(node.material)
	for child in node.get_children():
		var child_copy := _copy(child)
		if child_copy != null:
			copy.add_child(child_copy)
	return copy


# One copy per source material, so the body cools on its own; materials
# without a heat parameter are shared.
func _copy_material(mat: Material) -> Material:
	if not mat is ShaderMaterial:
		return mat
	if _material_copies.has(mat):
		return _material_copies[mat]
	var copy: ShaderMaterial = mat.duplicate(false)
	_material_copies[mat] = copy
	if _has_heat(copy.shader):
		_heat_materials.append(copy)
	return copy


static func _has_heat(shader: Shader) -> bool:
	if shader == null:
		return false
	if not _heat_shaders.has(shader):
		_heat_shaders[shader] = shader.get_shader_uniform_list().any(func(u): return u.name == "heat")
	return _heat_shaders[shader]


func _set_heat(heat: float) -> void:
	for mat in _heat_materials:
		mat.set_shader_parameter("heat", heat)
