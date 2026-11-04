extends TestSuite

# PartLossTest: mecha parts coming off in combat (Mecha.lose_part). A
# shoulder comes off when the facing that just took a hit is at 0 pips and
# every internal component of it is destroyed, taking the weapons on its
# side: they can't fire, the HUD shows them gone, and the mecha is lighter.
# It goes up in a large explosion and lands on the ground as debris, and
# shots pass through the gap. The head comes off the same way, with the
# effect of every head component destroyed; the core and chassis never do. A
# wreck keeps lost parts missing. On extraction the debrief writes a lost
# section off (no repair bill for it) and a standard part is fitted in each
# written-off slot.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const WIREFRAME := preload("res://game/ui/WireframeDisplay.tscn")
const EXTRACTION_SUMMARY := preload("res://game/expedition/ExtractionSummary.tscn")

var _arena: Node2D = null


func run_tests() -> void:
	await case("a stripped shoulder with its insides gone comes off, with its weapons", _test_shoulder_off)
	await case("a part with armour left on that facing stays on", _test_stays_on)
	await case("shots pass through where a part was", _test_gap)
	await case("the head comes off, as if every head component were destroyed", _test_head_off)
	await case("the core and chassis never come off", _test_core_chassis)
	await case("a wreck keeps lost parts missing", _test_wreck)
	await case("the debrief writes a lost section off and fits standard parts", _test_write_off)
	await _clear_arena()


func before_each() -> void:
	await _clear_arena()
	PlayerProgress.reset()
	_arena = Node2D.new()
	add_child(_arena)


func _clear_arena() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await wait_frames(2)
	_arena = null


func _mecha(design := PlayerProgress.DEFAULT_MECHA, pos := Vector2.ZERO) -> Mecha:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(design)
	mecha.global_rotation = 0.0
	mecha.battery = 1000000.0
	return mecha


# Strips `facing` of `part` and destroys its internal components with hits
# coming in on that facing (mechas face -Y: rear is +Y).
func _knock_off(mecha: Mecha, part: String, facing := "rear") -> void:
	mecha.armor[part][facing].pips = 0
	var dir := {"rear": Vector2.UP, "front": Vector2.DOWN}.get(facing, Vector2.LEFT) as Vector2
	for comp_name in mecha.components[part].keys():
		var comp: Dictionary = mecha.components[part][comp_name]
		if "internal" in comp.tags and not comp.disabled:
			mecha.damage_component(part, comp_name, 10, dir)


func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _test_shoulder_off() -> void:
	var mecha := _mecha()
	var weight_before := mecha.get_total_weight()
	var lost := []
	mecha.part_lost.connect(func(p): lost.append(p))
	var wireframe: WireframeDisplay = WIREFRAME.instantiate()
	_arena.add_child(wireframe)
	wireframe.setup(mecha)
	var children_before := _arena.get_child_count()
	_knock_off(mecha, "left_shoulder")
	var blasts := _arena.get_children().slice(children_before).filter(func(n): return n.scene_file_path.ends_with("PartDestructionExplosion.tscn"))
	check(blasts.any(func(n): return n.scale.x > 1.0), "a large part explosion goes off")
	check(mecha.is_part_lost("left_shoulder") and lost == ["left_shoulder"], "the left shoulder came off")
	check(mecha.is_part_lost("arm_weapon_left") and mecha.is_part_lost("shoulder_weapon_left"), "with the weapons on its side")
	check(not mecha.is_part_lost("right_shoulder"), "the right one stays")
	check(not mecha.LeftShoulder.visible and not mecha.LeftArmWeapon.visible, "hidden")
	check(is_instance_valid(mecha.LeftShoulder), "not freed")
	await _physics_frames(2)
	check(mecha.get_node("LeftShoulderCollision").disabled, "its collision is off")
	check(mecha.get_total_weight() < weight_before, "the mecha is lighter (%.1f -> %.1f)" % [weight_before, mecha.get_total_weight()])
	check(mecha.disabled_systems.left_arm_weapon, "its arm weapon is offline")
	var shots := [0]
	mecha.create_projectile.connect(func(_m, _a, _w): shots[0] += 1)
	for _i in 10:
		mecha.shoot("arm_weapon_left")
		await get_tree().physics_frame
	check_eq(shots[0], 0, "and can't fire")
	check(wireframe.is_weapon_lost("arm_weapon_left"), "the HUD shows it gone")
	check(mecha.get_eligible_components("left_shoulder", "rear", true).is_empty(), "nothing picks the lost part to damage")
	check(EntityAttack.pick_part(mecha, Vector2.LEFT) != "left_shoulder", "Entities' hits don't either")
	var added := _arena.get_children()
	check(added.any(func(n): return n is MechaBody and "left_shoulder" in n.shed_slots), "the part lands on the ground as debris")
	check(not mecha.lose_part("left_shoulder"), "it can't come off twice")


func _test_stays_on() -> void:
	var mecha := _mecha()
	mecha.armor.left_shoulder.rear.pips = 1
	for comp_name in mecha.components.left_shoulder.keys():
		if "internal" in mecha.components.left_shoulder[comp_name].tags:
			mecha.damage_component("left_shoulder", comp_name, 10, Vector2.UP)
	check(not mecha.is_part_lost("left_shoulder"), "a pip left on the hit facing holds it on")
	mecha.armor.left_shoulder.front.pips = 0
	check(not mecha.is_part_lost("left_shoulder"), "a stripped other facing doesn't count")
	var pen := mecha.armor_check("left_shoulder", mecha.global_position + Vector2(-60, 100), Vector2.UP, 10, 3)
	check(pen.penetrated and mecha.is_part_lost("left_shoulder"), "the hit that strips the facing takes it off")


# A point inside the left shoulder's shape: a shot there hits it, and once
# the shoulder is off, there's no shoulder there.
func _test_gap() -> void:
	var mecha := _mecha()
	await _physics_frames(2)
	var space := _arena.get_world_2d().direct_space_state
	var spot = null
	var shape: CollisionPolygon2D = mecha.get_node("LeftShoulderCollision")
	var centre := Vector2.ZERO
	for p in shape.polygon:
		centre += p / shape.polygon.size()
	var candidates := [centre]
	for p in shape.polygon:
		candidates.append(centre.lerp(p, 0.5))
		candidates.append(centre.lerp(p, 0.8))
	for local in candidates:
		var candidate: Vector2 = shape.to_global(local)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = candidate
		var hits := space.intersect_point(query, 8)
		if hits.any(func(h): return h.collider == mecha and mecha.get_part_name_from_shape(h.shape) == "left_shoulder"):
			spot = candidate
			break
	if not check(spot != null, "a spot the shoulder covers"):
		return
	_knock_off(mecha, "left_shoulder")
	await _physics_frames(3)
	var query := PhysicsPointQueryParameters2D.new()
	query.position = spot
	check(not space.intersect_point(query, 8).any(func(h): return h.collider == mecha and mecha.get_part_name_from_shape(h.shape) == "left_shoulder"),
			"once it's off, there's no shoulder there to hit")
	var ray := PhysicsRayQueryParameters2D.create(spot + Vector2(-400, 0), spot, MapSenses.SHOT_MASK)
	var hit := space.intersect_ray(ray)
	check(hit.is_empty() or mecha.get_part_name_from_shape(hit.shape) != "left_shoulder", "a shot's ray passes the gap")


func _test_head_off() -> void:
	var mecha := _mecha()
	_knock_off(mecha, "head", "front")
	check(mecha.is_part_lost("head") and not mecha.Head.visible, "the head came off")
	check(mecha.components.head.values().all(func(c): return c.disabled), "every head component is destroyed")
	check(mecha.disabled_systems.sensors < 0.5, "so the optics are gone (sensors %.1f)" % mecha.disabled_systems.sensors)
	check(not mecha.is_dead, "the mecha lives on")


func _test_core_chassis() -> void:
	var mecha := _mecha()
	for part in ["core", "chassis"]:
		for facing in mecha.armor[part]:
			mecha.armor[part][facing].pips = 0
		for comp_name in mecha.components[part].keys():
			var comp: Dictionary = mecha.components[part][comp_name]
			if "internal" in comp.tags and not "critical" in comp.tags and comp_name != "core_shell":
				mecha.damage_component(part, comp_name, 10, Vector2.UP)
		check(not mecha.is_part_lost(part), "the %s stays on" % part)
		check(not mecha.lose_part(part), "and can't be taken off")


func _test_wreck() -> void:
	var mecha := _mecha()
	_knock_off(mecha, "right_shoulder")
	var body := MechaBody.new()
	body.copy_from(mecha)
	_arena.add_child(body)
	var slots := body.get_part_slots()
	check(not "right_shoulder" in slots and not "arm_weapon_right" in slots, "the wreck has no right shoulder or arm")
	check("left_shoulder" in slots and "arm_weapon_left" in slots, "the left ones are there")
	check(not "right_shoulder" in body.get_solid_parts(), "nor its solid shape")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var never := true
	for _i in 200:
		for slot in MechaBody.choose_shed(mecha, [], rng):
			never = never and not mecha.is_part_lost(slot)
	check(never, "and never sheds a part it already lost")
	var design := mecha.get_intact_design_data()
	check(typeof(design.arm_weapon_right) == TYPE_BOOL and typeof(design.arm_weapon_left) == TYPE_STRING, "its loot leaves the lost weapon out")


func _other_part(part_type: String, not_id: String) -> String:
	for part_id in PartManager.get_parts(part_type):
		var part = PartManager.get_part(part_type, part_id)
		if str(part_id) == not_id:
			continue
		if part_type == "arm_weapon" and (part.is_melee or part.has_designator() or part.projectile == null):
			continue
		return str(part_id)
	return ""


func _test_write_off() -> void:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design.shoulders = _other_part("shoulders", design.shoulders)
	design.arm_weapon_left = _other_part("arm_weapon", design.arm_weapon_left)
	if not check(design.shoulders != "" and design.arm_weapon_left != "", "non-standard parts to fit"):
		return
	PlayerProgress.set_current_mecha(design.duplicate(), false)
	var mecha := _mecha(design)
	mecha.armor.right_shoulder.side.pips = 1
	mecha.damage_component("core", "radiator", 1, Vector2.UP)
	var whole := RepairBill.estimate(mecha)
	_knock_off(mecha, "left_shoulder")
	var bill := RepairBill.estimate(mecha)
	var expected := 0.0
	var skip := RepairBill.written_off_slots(mecha)
	for section in ["core", "head", "chassis", "right_shoulder"]:
		expected += RepairBill.section_value(mecha, section, skip) * RepairBill.section_damage(mecha, section) * RepairBill.RATE
	check_eq(bill, int(round(expected * Facilities.repair_mult())), "no repair bill for the lost section")
	check(bill <= whole or whole == 0, "the bill doesn't grow")
	check(skip.has("shoulders") and skip.has("arm_weapon_left"), "the whole shoulders item and the arm weapon on that side are written off")
	check(not skip.has("arm_weapon_right"), "not the other side's weapon")
	var names := PlayerProgress.write_off_slots(skip, false)
	var fitted := PlayerProgress.get_current_mecha()
	check_eq(fitted.shoulders, PlayerProgress.DEFAULT_MECHA.shoulders, "standard shoulders are fitted")
	check_eq(fitted.arm_weapon_left, PlayerProgress.DEFAULT_MECHA.arm_weapon_left, "and a standard arm weapon")
	check_eq(fitted.arm_weapon_right, design.arm_weapon_right, "the rest of the mecha is kept")
	var summary: ExtractionSummary = EXTRACTION_SUMMARY.instantiate()
	add_child(summary)
	summary.show_summary([], 0, null, {"damage": ExtractionSummary.collect_damage(mecha), "repairs": bill,
			"lost": ["left_shoulder"], "written_off": names})
	var text := summary.get_text()
	check("L SHOULDER\nWRITTEN OFF" in text, "the debrief shows the section WRITTEN OFF")
	check(names.all(func(n): return str(n) + "\nWRITTEN OFF" in text), "and each part written off (%s)" % ", ".join(names))
	summary.queue_free()
