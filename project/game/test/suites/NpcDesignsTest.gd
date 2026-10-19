extends TestSuite

# NpcDesignsTest: every enemy design (database/npcs: the generic list and each
# special NPC) names parts that exist (or tags that match some part), has a
# combat behaviour and personality the AI knows, and builds a complete mecha.
# A typo in an enemy design otherwise only shows up when that enemy spawns.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const BEHAVIOUR_PATH := "res://game/mecha/enemy_logic/behaviours/"
const DESIGN_SLOTS := ["head", "core", "shoulders", "generator", "chipset", "chassis", "thruster",
		"arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]
const PERSONALITIES := ["professional", "scavenger", "guardian", "hunter", "rat"]


func run_tests() -> void:
	await case("NPCs are loaded", _test_loaded)
	await case("every design names real parts", _test_parts_exist)
	await case("every NPC has a known behaviour and personality", _test_behaviour)
	await case("every design builds a complete mecha", _test_builds)


func _all_npcs() -> Array:
	var npcs := []
	for npc in NPCManager.NPCS:
		npcs.append(npc)
	for npc in NPCManager.SPECIAL_NPCS:
		npcs.append(npc)
	return npcs


func _npc_label(npc, index: int) -> String:
	if npc is Resource:
		return "special NPC '%s'" % npc.mecha_name
	return "generic NPC #%d" % index


func _test_loaded() -> void:
	check(NPCManager.NPCS.size() > 0, "generic NPCs loaded (%d)" % NPCManager.NPCS.size())
	check(NPCManager.SPECIAL_NPCS.size() > 0, "special NPCs loaded (%d)" % NPCManager.SPECIAL_NPCS.size())


func _test_parts_exist() -> void:
	var npcs := _all_npcs()
	for i in npcs.size():
		var npc = npcs[i]
		for slot in DESIGN_SLOTS:
			var part_type: String = slot.trim_suffix("_left").trim_suffix("_right")
			var wanted: Array = Array(npc[slot])
			if wanted.is_empty():
				continue  # empty slot
			var label := "%s %s %s" % [_npc_label(npc, i), slot, str(wanted)]
			if PartManager.is_valid_part(part_type, wanted[0]):
				continue
			check(not PartManager.get_parts_by_tags(part_type, wanted).is_empty(), "%s: no part has that id or those tags" % label)


func _test_behaviour() -> void:
	var npcs := _all_npcs()
	for i in npcs.size():
		var npc = npcs[i]
		var label := _npc_label(npc, i)
		var behaviour := str(npc.get("combat_behaviour") if npc is Resource else npc.get("combat_behaviour", "default"))
		check(FileAccess.file_exists(BEHAVIOUR_PATH + behaviour + ".gd"), "%s: behaviour '%s' exists" % [label, behaviour])
		if npc is Dictionary and npc.has("personality"):
			check(npc["personality"] in PERSONALITIES, "%s: personality '%s' is known" % [label, npc["personality"]])


func _test_builds() -> void:
	var npcs := _all_npcs()
	for i in npcs.size():
		var npc = npcs[i]
		var label := _npc_label(npc, i)
		var design: Dictionary = NPCManager.get_design_data(npc)
		check(PlayerProgress.missing_parts(design).is_empty(),
				"%s has every required part (missing %s)" % [label, str(PlayerProgress.missing_parts(design))])
		var mecha: Mecha = MECHA.instantiate()
		mecha.mech_inventory = Inventory.new()
		add_child(mecha)
		mecha.set_parts_from_design(design)
		for slot in DESIGN_SLOTS:
			if typeof(design.get(slot)) == TYPE_STRING:
				check(mecha.build[slot] != null and mecha.build[slot].part_id == design[slot], "%s: %s equipped" % [label, slot])
		mecha.queue_free()
	await wait_frames()
