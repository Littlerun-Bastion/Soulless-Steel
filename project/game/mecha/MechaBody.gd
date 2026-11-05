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
##
## A part that comes off a live mecha (Mecha.lose_part) leaves a body of just
## that part (copy_parts_from, not solid), shed beside it. A part the mecha
## lost before it died isn't shown, so it isn't copied.
##
## Coyotes scavenge from a body (Coyote): a shoulder (as a shield) or an arm
## weapon (as a gun), from the body or its debris on the ground, a wreck's or
## a live mecha's lost part alike. Every body is in SCAVENGE_GROUP for them
## to find. takeable_slots() lists what's there; part_look() copies how a
## part looks, for carrying (look_of); take_part() removes it (a shoulder
## takes its arm weapon with it) and says what it was: its part id, its main
## sprite, and for a shoulder its front armour.
##
## parts_changed fires when parts come off (shed) or are taken (take_part):
## a Wreck lists its shed parts from it (Wreck.unsalvageable).

signal parts_changed

## Every body, for scavengers to find.
const SCAVENGE_GROUP := "mecha_body"
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
## What a Coyote can take from a body.
const TAKEABLE := ["left_shoulder", "right_shoulder", "arm_weapon_left", "arm_weapon_right"]

## Parts that came off, including arm weapons that went with a shoulder.
var shed_slots: Array[String] = []
## Parts taken from the body or its debris (take_part).
var taken_slots: Array[String] = []
## Slot (SHED_OPTIONS) -> the part id it carried (both shoulders carry the
## one shoulders part), and for each shoulder its front armour ({level,
## pips}), from the mecha (copy_from).
var part_ids := {}
var shoulder_armor := {}
## What makes the body solid (copy_from).
var solid: StaticBody2D = null
var _parts := {}  # part -> copied top-level nodes
var _shapes := {}  # part -> its CollisionPolygon2D copies in solid
var _debris := {}  # part -> the Debris node it was shed into
# Weapon slot -> its glow layer on the mecha ({texture, material, transform}),
# not drawn on the body (glow goes dark) but given back to a carried gun
# (part_look).
var _glows := {}
var _material_copies := {}
var _heat_materials: Array[ShaderMaterial] = []
var _start_heat := START_HEAT
var _age := 0.0
var _refresh := 0.0
static var _heat_shaders := {}


func _ready() -> void:
	add_to_group(SCAVENGE_GROUP)


func copy_from(mecha: Node2D) -> void:
	_copy_parts(mecha, [])
	_copy_shapes(mecha)
	_set_heat(_start_heat)


## Only these parts (PART_NODES values), with no solid body: a part that came
## off a live mecha.
func copy_parts_from(mecha: Node2D, parts: Array) -> void:
	_copy_parts(mecha, parts)
	_set_heat(_start_heat)


# The mecha's drawn parts (all of them for an empty `only`), and what a
# scavenger needs to know about them.
func _copy_parts(mecha: Node2D, only: Array) -> void:
	rotation = mecha.global_rotation
	scale = mecha.global_scale
	_start_heat = maxf(START_HEAT, float(mecha.get("shader_heat_value")))
	for child in mecha.get_children():
		var part: String = PART_NODES.get(String(child.name), "")
		if part == "" or (not only.is_empty() and not part in only):
			continue
		var copy := _copy(child)
		if copy == null:
			continue
		var glow := child.get_node_or_null("Glow") as Sprite2D
		if glow != null and glow.texture != null:
			_glows[part] = {"texture": glow.texture, "material": glow.material, "transform": glow.transform}
		add_child(copy)
		if not _parts.has(part):
			_parts[part] = []
		_parts[part].append(copy)
	var build = mecha.get("build")
	if build is Dictionary:
		for slot in ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right", "head"]:
			if build.get(slot):
				part_ids[slot] = str(build[slot].part_id)
		if build.get("shoulders"):
			for slot in ["left_shoulder", "right_shoulder"]:
				part_ids[slot] = str(build.shoulders.part_id)
				var front: Dictionary = mecha.armor[slot].front
				shoulder_armor[slot] = {"level": int(front.level), "pips": int(front.pips)}


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
		var part: String = SOLID_SHAPES[shape_name]
		if source == null or source.disabled or _area(source.polygon) < 1.0 \
				or (mecha.has_method("is_part_lost") and mecha.is_part_lost(part)):
			continue
		var shape := CollisionPolygon2D.new()
		shape.name = shape_name
		shape.polygon = source.polygon
		shape.transform = source.transform
		solid.add_child(shape)
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
		if part in shed_slots or part in taken_slots:
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
	for part in [slot] + SHED_WITH.get(slot, []):
		if _parts.has(part):
			_debris[part] = debris
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
	parts_changed.emit()
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
	if mecha.has_method("is_part_lost") and mecha.is_part_lost(slot):
		return false
	var part = mecha.build.get("shoulders" if slot in ["left_shoulder", "right_shoulder"] else slot)
	return true if part else false


## What a Coyote could take here: TAKEABLE parts on the body or its debris,
## with a sprite, not taken yet.
func takeable_slots() -> Array[String]:
	var found: Array[String] = []
	for slot in TAKEABLE:
		if slot in taken_slots or not part_ids.has(slot) or not _parts.has(slot):
			continue
		for node in _parts[slot]:
			if is_instance_valid(node) and _has_texture(node):
				found.append(slot)
				break
	return found


## Where a part is now (world): on the body, or where its debris lies.
func part_position(slot: String) -> Vector2:
	for node in _parts.get(slot, []):
		if is_instance_valid(node):
			return node.global_position
	return global_position


## Takes a part off the body or its debris (a shoulder takes its arm weapon
## with it). Returns {"slot", "part_id", "texture", "material"} (its main
## sprite's) and, for a shoulder, "armor" (its front {level, pips}); {} if it
## isn't there to take.
func take_part(slot: String) -> Dictionary:
	if not slot in takeable_slots():
		return {}
	var sprite := _sprite_of(slot)
	var taken := {"slot": slot, "part_id": part_ids[slot], "texture": sprite.texture if sprite != null else null,
			"material": sprite.material if sprite != null else null}
	if shoulder_armor.has(slot):
		taken["armor"] = shoulder_armor[slot].duplicate()
	for part in [slot] + SHED_WITH.get(slot, []):
		if part in taken_slots:
			continue
		taken_slots.append(part)
		for shape in _shapes.get(part, []):
			if is_instance_valid(shape):
				shape.queue_free()
		_shapes.erase(part)
		for node in _parts.get(part, []):
			if is_instance_valid(node):
				node.queue_free()
		var debris = _debris.get(part)
		if is_instance_valid(debris) and debris.get_children().all(func(n): return n.is_queued_for_deletion()):
			debris.queue_free()
	parts_changed.emit()
	return taken


# The first drawn sprite of a part: its main sprite.
func _sprite_of(slot: String) -> Sprite2D:
	for node in _parts.get(slot, []):
		if not is_instance_valid(node):
			continue
		if node is Sprite2D and node.texture != null:
			return node
		for child in node.find_children("*", "Sprite2D", true, false):
			if child.texture != null:
				return child
	return null


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


## A cold copy of one part's look, for a scavenger to carry (Coyote): the
## drawn nodes of `node` (a mecha's part node, or a body's copy of one), each
## layer's material copied with its heat at ambient (cold_material); its glow
## layer too with with_glow (a weapon that heats up as it fires).
##
## The look is a plain Node2D holding the copy (its "part" meta), the part's
## mount at its origin, facing -Y as mecha parts do: the copy keeps its scale
## and mirroring (a right-hand weapon is mirrored, scale.x -1) but not its
## pose. The copy sits under its own root because Godot reads a mirrored
## node's transform back as a turn of PI with scale.y flipped: turning that
## node itself would flip it end over end. Turn the look instead.
##
## Its "reach" meta is how far it extends ahead of the mount (-Y): a
## weapon's far end. Null if nothing of it is drawn.
static func look_of(node: Node, with_glow := false) -> Node2D:
	if node == null or not is_instance_valid(node):
		return null
	var skipped := SKIPPED.filter(func(n): return n != "Glow") if with_glow else SKIPPED
	var part := _copy_node(node, cold_material, skipped)
	if part == null:
		return null
	if part is Sprite2D:
		# A single-sprite part (a shoulder) under its own holder, so the
		# holder is what's mirrored and the sprite keeps its offset.
		var holder := Node2D.new()
		holder.name = part.name
		holder.transform = part.transform
		part.transform = Transform2D.IDENTITY
		holder.add_child(part)
		part = holder
	var mirrored := part.transform.determinant() < 0.0
	var size := Vector2(part.transform.x.length(), part.transform.y.length())
	part.transform = Transform2D(Vector2(-size.x if mirrored else size.x, 0.0), Vector2(0.0, size.y), Vector2.ZERO)
	var look := Node2D.new()
	look.name = "Look"
	look.add_child(part)
	look.set_meta("part", part)
	look.set_meta("reach", _reach(look))
	return look


## The look (look_of) of a part still on this body or its debris; null if it
## isn't there. with_glow gives a weapon back the glow layer it had on the
## mecha, which the body itself doesn't draw.
func part_look(slot: String, with_glow := false) -> Node2D:
	for node in _parts.get(slot, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and _has_texture(node):
			var look := look_of(node, with_glow)
			if look != null and with_glow and _glows.has(slot):
				var glow := Sprite2D.new()
				glow.name = "Glow"
				glow.texture = _glows[slot].texture
				glow.material = cold_material(_glows[slot].material)
				glow.transform = _glows[slot].transform
				(look.get_meta("part") as Node).add_child(glow)
			return look
	return null


## A part's material for carrying off: its own copy, with the heat shader's
## heat at ambient (0), as a body's parts go once cool.
static func cold_material(material: Material) -> Material:
	if not material is ShaderMaterial:
		return material
	var copy: ShaderMaterial = material.duplicate()
	if _has_heat(copy.shader):
		copy.set_shader_parameter("heat", 0.0)
	return copy


# How far ahead (-Y) of the look's origin its sprites reach.
static func _reach(look: Node2D) -> float:
	var furthest := 0.0
	for sprite in look.find_children("*", "Sprite2D", true, false):
		if (sprite as Sprite2D).texture == null:
			continue
		var xform := Transform2D.IDENTITY
		var at: Node = sprite
		while at != look:
			xform = (at as Node2D).transform * xform
			at = at.get_parent()
		var rect: Rect2 = (sprite as Sprite2D).get_rect()
		for corner in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)]:
			furthest = maxf(furthest, -(xform * corner).y)
	return furthest


# A plain copy of a mecha's Node2D or Sprite2D and its drawn children; no
# scripts, particles, lights or collisions.
func _copy(node: Node) -> Node2D:
	return _copy_node(node, _copy_material)


# The copy, each material through copy_material, leaving out `skipped`.
static func _copy_node(node: Node, copy_material: Callable, skipped: Array = SKIPPED) -> Node2D:
	var cls := node.get_class()
	if (cls != "Node2D" and cls != "Sprite2D") or String(node.name) in skipped or not node.visible:
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
	copy.material = copy_material.call(node.material)
	for child in node.get_children():
		var child_copy := _copy_node(child, copy_material, skipped)
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
