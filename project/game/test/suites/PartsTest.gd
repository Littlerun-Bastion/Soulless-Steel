extends TestSuite

# PartsTest: every part in the game (database/parts, as PartManager loads it)
# has the data the game relies on, equips onto a real mecha, and every weapon
# fires a projectile. A new or edited part that breaks any of this fails here
# before it can break a fight.
#
# Data that's missing but harmless (no price, no description) is listed as a
# note at the end, not a failure.

const MECHA := preload("res://game/mecha/Mecha.tscn")

# PartManager part type -> the design slot it goes in.
const SLOTS := {
	"head": "head", "core": "core", "shoulders": "shoulders", "chassis": "chassis",
	"generator": "generator", "chipset": "chipset", "thruster": "thruster",
	"arm_weapon": "arm_weapon_left", "shoulder_weapon": "shoulder_weapon_left",
}

const VISIBLE_TYPES := ["head", "core", "shoulders", "chassis", "arm_weapon", "shoulder_weapon"]

var _mecha: Mecha = null
var _notes: Array[String] = []


func run_tests() -> void:
	_mecha = MECHA.instantiate()
	_mecha.mech_inventory = Inventory.new()
	add_child(_mecha)
	_mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	await wait_frames()

	await case("every part has its data", _test_part_data)
	await case("every part equips onto a mecha", _test_equip)
	await case("every weapon fires", _test_weapons_fire)
	await case("weapons swapped on the same mecha still fire", _test_weapon_swaps)

	for note in _notes:
		print("    note: " + note)


func _all_parts() -> Array:
	var result := []
	for part_type in SLOTS:
		for part_id in PartManager.get_parts(part_type):
			result.append([part_type, part_id])
	return result


func _test_part_data() -> void:
	var parts := _all_parts()
	check(parts.size() > 40, "PartManager loaded the parts (%d)" % parts.size())
	for entry in parts:
		var part = PartManager.get_part(entry[0], entry[1])
		var label := "%s %s" % entry
		check(str(part.get("part_name")) != "", "%s has a name" % label)
		# Parts drawn on the mecha need an image; internal ones (generator,
		# chipset, thruster) only use it as an icon.
		if entry[0] in VISIBLE_TYPES:
			check(part.get("image") is Texture2D, "%s has an image" % label)
		elif not part.get("image") is Texture2D:
			_notes.append("%s has no icon image" % label)
		var weight = part.get("weight")
		check(typeof(weight) in [TYPE_INT, TYPE_FLOAT] and weight >= 0.0, "%s has a weight" % label)
		var size = part.get("item_size")
		check(size is Array and size.size() == 2 and int(size[0]) > 0 and int(size[1]) > 0,
				"%s has a cargo size" % label)
		if float(part.get("price")) <= 0.0:
			_notes.append("%s has no price" % label)
		if str(part.get("description")) == "":
			_notes.append("%s has no description" % label)


func _test_equip() -> void:
	for entry in _all_parts():
		var part_type: String = entry[0]
		var part_id: String = entry[1]
		var design := _design_with(part_type, part_id)
		_mecha.set_parts_from_design(design)
		var slot: String = SLOTS[part_type]
		var equipped = _mecha.build.get(slot)
		check(equipped != null and equipped.part_id == part_id, "%s %s equips into %s" % [part_type, part_id, slot])
	_mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)


func _test_weapons_fire() -> void:
	for part_type in ["arm_weapon", "shoulder_weapon"]:
		for part_id in PartManager.get_parts(part_type):
			await _check_fires(part_type, part_id)
	_mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)


# Equips the weapon on a fresh mecha (as every fight builds one) and pulls the
# trigger until it emits a projectile (spool-up weapons need a few tries).
func _check_fires(part_type: String, part_id: String) -> void:
	var slot: String = SLOTS[part_type]
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	add_child(mecha)
	mecha.set_parts_from_design(_design_with(part_type, part_id))
	var weapon = mecha.build[slot]
	if weapon.is_melee:
		check(mecha.get_weapon_part(slot).has_method("light_attack"), "%s (melee) can attack" % part_id)
		mecha.queue_free()
		return
	check(weapon.projectile is PackedScene, "%s has a projectile" % part_id)
	var shots := []
	mecha.create_projectile.connect(func(_mecha_ref, args, _weapon_id): shots.append(args))
	mecha.battery = 1000000.0
	var fired := await wait_until(func():
		mecha.shoot(slot)
		return not shots.is_empty(), 3.0)
	mecha.queue_free()
	if check(fired, "%s fires" % part_id):
		var projectile = shots[0].get("projectile")
		var instance = projectile.instantiate() if projectile is PackedScene else null
		check(instance != null, "%s projectile instances" % part_id)
		if instance != null:
			instance.free()


# One mecha, every arm weapon in turn, firing each: a weapon with fewer
# barrels than the one before used to crash on its first shot (WeaponNode
# kept the old barrel index).
func _test_weapon_swaps() -> void:
	var mecha: Mecha = MECHA.instantiate()
	mecha.mech_inventory = Inventory.new()
	add_child(mecha)
	mecha.battery = 1000000.0
	var shots := []
	mecha.create_projectile.connect(func(_m, args, _w): shots.append(args))
	var weapons: Array = PartManager.get_parts("arm_weapon").keys()
	for part_id in weapons + weapons:  # twice, so every weapon follows another
		mecha.set_parts_from_design(_design_with("arm_weapon", part_id))
		if mecha.build["arm_weapon_left"].is_melee:
			continue
		shots.clear()
		var fired := await wait_until(func():
			mecha.shoot("arm_weapon_left")
			return not shots.is_empty(), 3.0)
		check(fired, "%s fires after a swap" % part_id)
	mecha.queue_free()
	await wait_frames()


# The default mecha with one part swapped in. Shoulder weapons need a core
# with a shoulder mount, so one is fitted if the default core has none.
func _design_with(part_type: String, part_id: String) -> Dictionary:
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design[SLOTS[part_type]] = part_id
	if part_type == "shoulder_weapon" and not PartManager.get_part("core", design["core"]).has_left_shoulder:
		for core_id in PartManager.get_parts("core"):
			if PartManager.get_part("core", core_id).has_left_shoulder:
				design["core"] = core_id
				break
	return design
