extends TestSuite

# SalvageSourcesTest: salvage sources in the world (SalvageField) and their
# HUD brackets (HudSalvage). A bracket shows for a source in sight and not
# for one behind a wall; the label shows only within 30 m; the interact
# prompt goes to the nearest source in range; an emptied source loses its
# bracket and its prompt; a roof source shows over walls and goes with a
# gutted roof; a destroyed car leaves pieces that are picked up straight into
# the cargo; a vehicle source follows its vehicle; loot follows the kind's
# table, solar panels by their modules.

const PLAYER := preload("res://game/mecha/player/Player.tscn")
const HATCHBACK := preload("res://assets/images/map/props/vehicle_hatchback.png")

# A wall between the player at the origin and anything south of y 250.
const WALL_BLOCK := [Vector2(-300, 150), Vector2(300, 150), Vector2(300, 250), Vector2(-300, 250)]
# A building north-east of the player, for roof sources.
const ROOF_BLOCK := [Vector2(150, -350), Vector2(450, -350), Vector2(450, -150), Vector2(150, -150)]


class FakeArena extends Node2D:
	var mechas: Array = []
	func get_mechas() -> Array:
		return mechas


var _arena: FakeArena = null
var _player: Mecha = null
var _salvage: SalvageField = null
var _hud: HudSalvage = null


func run_tests() -> void:
	await case("a bracket shows for a source in sight, not one behind a wall", _test_sight)
	await case("the label shows only within 30 m", _test_label)
	await case("the prompt goes to the nearest source in range", _test_prompt)
	await case("an emptied source loses its bracket and prompt", _test_emptied)
	await case("a roof source shows over walls, and goes with a gutted roof", _test_roof)
	await case("a destroyed car leaves pieces that are picked up", _test_wreck_pickup)
	await case("a vehicle source follows its vehicle", _test_vehicle_source)
	await case("loot follows the kind's table, solar by modules", _test_loot)
	await case("a dead Entity's carcass is picked up, not searched", _test_carcass_pickup)
	await case("every source kind has a loot table that gives something", _test_tables)


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	if is_instance_valid(_hud):
		_hud.queue_free()
		_hud = null
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)


func _item(id: String, size := [1, 1], stack := 4) -> item_data:
	var item := item_data.new()
	item.id = id
	item.display_name = id.capitalize()
	item.item_size = size
	item.max_stack = stack
	item.weight = 0.02
	return item


func _loot(item: item_data, count := Vector2i(2, 2), per_amount := 0) -> SalvageLoot:
	var entry := SalvageLootEntry.new()
	entry.item = item
	entry.count = count
	entry.per_amount = per_amount
	var loot := SalvageLoot.new()
	loot.entries = [entry]
	return loot


# The world: buildings (with ruin states), a SalvageField (with the
# generator's spawn set, if any), a still player at the origin with its
# light off, and the HUD layer.
func _setup(buildings: Array = [], states: Array = [], spawns: SalvageSpawnSet = null, loot := {}) -> void:
	if not buildings.is_empty():
		var footprints := BuildingFootprints.new()
		var starts := PackedInt32Array([0])
		for b in buildings:
			footprints.points.append_array(PackedVector2Array(b))
			starts.append(footprints.points.size())
		footprints.starts = starts
		footprints.state = PackedByteArray(states)
		var field := BuildingField.new()
		field.name = "BuildingField"
		field.footprints = footprints
		_arena.add_child(field)
	_salvage = SalvageField.new()
	_salvage.sources = spawns
	_salvage.building_field_path = NodePath("../BuildingField")
	for kind in loot:
		_salvage._loot[kind] = loot[kind]
	_arena.add_child(_salvage)
	_player = PLAYER.instantiate()
	_player.mech_inventory = Inventory.new()
	_player.mecha_name = "Player"
	_arena.add_child(_player)
	_player.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	_player.global_rotation = 0.0
	_player.set_illuminator(false)
	_player.set_physics_process(false)
	_arena.mechas.append(_player)
	_hud = HudSalvage.new()
	add_child(_hud)
	_hud.setup(_player)
	await wait_frames(3)


func _source(kind: String, pos: Vector2, size := Vector2(60, 60), building := -1, stacks: Array = []) -> int:
	if stacks.is_empty():
		stacks = [item_stack.from_generic(_item("scrap_test"), 2)]
	return _salvage.add_source(kind, pos, 0.0, size, building, 0, -1, stacks)


func _seen() -> Array:
	var out := []
	for s in _salvage.visible_sources(_player):
		out.append(s.index)
	return out


func _marked(index: int) -> Dictionary:
	for mark in _hud.get_marks():
		if mark.index == index:
			return mark
	return {}


func _update() -> void:
	# A sight check is cached for a few frames and the field streams nodes
	# every few; wait past both.
	await wait_frames(SalvageField.UPDATE_FRAMES + SalvageField.SIGHT_FRAMES + 2)


func _test_sight() -> void:
	await _setup([WALL_BLOCK])
	var open := _source("diesel_generator", Vector2(300, -50))
	var behind := _source("diesel_generator", Vector2(0, 340))
	await _update()
	var seen := _seen()
	check(seen.has(open), "the generator in the open is in sight")
	check(not seen.has(behind), "the one behind the wall isn't")
	var mark := _marked(open)
	check(not mark.is_empty(), "the HUD brackets the one in sight")
	check(_marked(behind).is_empty(), "and not the one behind the wall")
	if not mark.is_empty():
		var rect: Rect2 = mark.rect
		var on_screen := Rect2(_player.get_viewport().get_canvas_transform() * Vector2(270, -80), Vector2.ZERO)
		on_screen = on_screen.expand(_player.get_viewport().get_canvas_transform() * Vector2(330, -20))
		check(rect.size.x > on_screen.size.x and rect.size.x <= on_screen.size.x + HudSalvage.PAD * 2.0 + 1.0,
				"the bracket fits the outline plus the pad (%.0f px wide for a %.0f px box)" % [rect.size.x, on_screen.size.x])
	var far := _source("diesel_generator", Vector2(-3000, 0))
	await _update()
	check(not _seen().has(far), "a dark source past the view circle's lit part isn't in sight")
	var huge := _source("solar_panels", Vector2(300, 100), Vector2(7400, 3000))
	await _update()
	check(_seen().has(huge), "a solar array bigger than the screen is in sight")
	check(_marked(huge).is_empty(), "but gets no bracket: only a stray corner of it would show")


func _test_label() -> void:
	await _setup()
	var near := _source("solar_panels", Vector2(300, 0))
	var far := _source("shipping_container", Vector2(-650, 0), Vector2(500, 500))
	await _update()
	var near_mark := _marked(near)
	var far_mark := _marked(far)
	check(not near_mark.is_empty() and near_mark.text == "SOLAR PANELS", "a source within 30 m has its name")
	check(not far_mark.is_empty(), "the big one 32 m off is bracketed")
	check(not far_mark.is_empty() and far_mark.text == "", "but has no label")


func _test_prompt() -> void:
	await _setup()
	var nearer := _source("transformer", Vector2(150, 0))
	var farther := _source("control_cabinet", Vector2(-260, 0))
	await _update()
	await wait_frames(3)
	check(_salvage.node_of(nearer) != null and _salvage.node_of(farther) != null, "both sources near the player have nodes")
	var thing = _player.get_closest_interactable()
	check(thing != null and thing.get("source_index") == nearer, "the nearest source is the one to use")
	check(thing != null and str(thing.get("display_name")) == "TRANSFORMER", "named for the prompt")
	var prompt := InteractPrompt.new()
	add_child(prompt)
	prompt.setup(_player)
	await wait_frames(2)
	check(prompt.get_text().contains("SEARCH") and prompt.get_text().contains("TRANSFORMER"),
			"the prompt reads %s" % prompt.get_text())
	prompt.queue_free()


func _test_emptied() -> void:
	await _setup()
	var i := _source("oil_drums", Vector2(200, 0))
	await _update()
	check(_seen().has(i) and not _marked(i).is_empty(), "bracketed while full")
	var inv := _salvage.inventory_of(i)
	for stack in inv.get_stacks():
		inv.remove_item_stack(stack)
	await _update()
	await wait_frames(2)
	check(_salvage.is_empty(i), "the field marks it empty")
	check(_salvage.node_of(i) == null, "its node (and so its prompt) is gone")
	check(not _seen().has(i) and _marked(i).is_empty(), "and so is its bracket")
	check(_player.get_closest_interactable() == null, "nothing left to use")


func _test_roof() -> void:
	var spawns := SalvageSpawnSet.new()
	spawns.kinds = PackedStringArray(["roof_ac"])
	for b in [0, 1]:
		spawns.kind.append(0)
		spawns.position.append(Vector2(300, -250) if b == 0 else Vector2(300, 2250))
		spawns.rotation.append(0.0)
		spawns.size.append(Vector2(80, 60))
		spawns.building.append(b)
		spawns.amount.append(3)
		spawns.vehicle.append(0)
	var gutted := [Vector2(150, 1850), Vector2(450, 1850), Vector2(450, 2350), Vector2(150, 2350)]
	await _setup([ROOF_BLOCK, gutted], [BuildingFootprints.INTACT, BuildingFootprints.GUTTED], spawns,
			{"roof_ac": _loot(_item("air_conditioner_test", [1, 2], 2))})
	await wait_frames(2)
	check_eq(_salvage.source_count(), 1, "the source on the gutted roof is left out")
	await _update()
	check(_seen().has(0), "the roof's AC units show from outside, walls and all")


func _vehicle_world() -> VehicleField:
	var spawn_set := PropSpawnSet.new()
	spawn_set.kinds = PackedStringArray(["vehicle"])
	spawn_set.kind = PackedByteArray([0])
	spawn_set.position = PackedVector2Array([Vector2(250, 0)])
	spawn_set.rotation = PackedFloat32Array([0.0])
	spawn_set.size = PackedVector2Array([Vector2(80, 40)])
	spawn_set.variant = PackedInt32Array([0])
	var spawner := PropSpawner.new()
	spawner.name = "PropSpawner"
	spawner.spawn_set = spawn_set
	_arena.add_child(spawner)
	var layer := PropSpriteLayer.new()
	layer.name = "Vehicles"
	layer.kinds = PackedStringArray(["vehicle"])
	layer.textures = {"vehicle": [HATCHBACK]}
	layer.spans = {"vehicle": PackedFloat32Array([1.0])}
	layer.spawner_path = NodePath("../PropSpawner")
	_arena.add_child(layer)
	var vehicles := VehicleField.new()
	vehicles.name = "VehicleField"
	vehicles.spawner_path = NodePath("../PropSpawner")
	vehicles.layer_path = NodePath("../Vehicles")
	vehicles.kinds = PackedStringArray(["vehicle"])
	vehicles.masses = {"vehicle": PackedFloat32Array([950.0])}
	vehicles.shot_blocks = {"vehicle": PackedFloat32Array([0.5])}
	vehicles.stream = false
	_arena.add_child(vehicles)
	return vehicles


func _test_wreck_pickup() -> void:
	var vehicles := _vehicle_world()
	await get_tree().physics_frame
	_salvage = null
	var field := SalvageField.new()
	field.vehicle_field_path = NodePath("../VehicleField")
	field._loot["car_wreck"] = _loot(_item("scrap_metal_test", [1, 1], 10), Vector2i(3, 3))
	_arena.add_child(field)
	_salvage = field
	await wait_frames(4)
	check(field.is_built() and field.source_count() == 0, "a parked car is no source")
	vehicles.damage(0, 1000.0)
	await wait_frames(2)
	check_eq(field.source_count(), 1, "the destroyed car becomes one")
	check_eq(field.kind_of(0), "car_wreck", "a wrecked car")
	var player: Mecha = PLAYER.instantiate()
	player.mech_inventory = Inventory.new()
	player.mecha_name = "Player"
	_arena.add_child(player)
	player.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	player.set_physics_process(false)
	player.global_position = Vector2(100, 0)
	await wait_frames(SalvageField.UPDATE_FRAMES + 4)
	var thing = player.get_closest_interactable()
	check(thing is SalvagePickup, "its pieces are a pickup, not a container")
	if not thing is SalvagePickup:
		return
	check_eq(str(thing.interact_verb), "PICK UP", "the prompt says PICK UP")
	var before := player.mech_inventory.get_stacks().size()
	thing.interact(player)
	await wait_frames(2)
	var after := player.mech_inventory.get_stacks()
	check(after.size() > before, "the pieces are in the cargo")
	var count := 0
	for stack in after:
		if stack.item != null and stack.item.id == "scrap_metal_test":
			count += stack.quantity
	check_eq(count, 3, "all three")
	check(field.is_empty(0) and field.node_of(0) == null, "the wreck is empty and has no prompt")


func _test_vehicle_source() -> void:
	var vehicles := _vehicle_world()
	var spawns := SalvageSpawnSet.new()
	spawns.kinds = PackedStringArray(["bus"])
	spawns.kind = PackedByteArray([0])
	spawns.position = PackedVector2Array([Vector2(250, 0)])
	spawns.rotation = PackedFloat32Array([0.0])
	spawns.size = PackedVector2Array([Vector2(80, 40)])
	spawns.building = PackedInt32Array([-1])
	spawns.amount = PackedInt32Array([0])
	spawns.vehicle = PackedByteArray([1])
	var field := SalvageField.new()
	field.sources = spawns
	field.vehicle_field_path = NodePath("../VehicleField")
	_arena.add_child(field)
	await wait_frames(4)
	check_eq(field.source_count(), 1, "the bus is a source")
	check(field.source_position(0).distance_to(Vector2(250, 0)) < 1.0, "where it is parked")
	vehicles._pos[0] = Vector2(600, 100)
	vehicles._rot[0] = 0.5
	check(field.source_position(0).distance_to(Vector2(600, 100)) < 1.0, "and where it is after a push")
	check(absf(field.source_rotation(0) - 0.5) < 0.01, "turned with it")


func _test_carcass_pickup() -> void:
	await _setup()
	var carcass: Carcass = load("res://game/entities/Carcass.tscn").instantiate()
	carcass.setup("Coyote", [item_stack.from_generic(_item("entity_residue_test", [1, 1], 20), 5)])
	carcass.opens_window = false
	carcass.position = Vector2(150, 0)
	_arena.add_child(carcass)
	await _update()
	var seen := _salvage.visible_sources(_player)
	check(seen.size() == 1 and seen[0].node == carcass, "the carcass is bracketed as a source")
	check_eq(str(carcass.get("interact_verb")), "PICK UP", "its prompt says PICK UP")
	carcass.interact(_player)
	var count := 0
	for stack in _player.mech_inventory.get_stacks():
		if stack.item != null and stack.item.id == "entity_residue_test":
			count += stack.quantity
	check_eq(count, 5, "the residue goes straight into the cargo")
	check(not carcass.is_open, "no window opens")
	check_eq(carcass.state, Wreck.State.EMPTY, "the carcass is empty")
	await _update()
	check(_salvage.visible_sources(_player).is_empty(), "and loses its bracket")


func _test_tables() -> void:
	var kinds: Array = SalvageField.KIND_NAMES.keys()
	var generated := "res://assets/maps/helwan/salvage.res"
	if ResourceLoader.exists(generated):
		var spawns := load(generated) as SalvageSpawnSet
		if spawns != null:
			for k in spawns.kinds:
				if not kinds.has(k):
					kinds.append(k)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bad := []
	var empty := []
	for kind in kinds:
		var path: String = SalvageField.LOOT_DIR + kind + ".tres"
		var table := load(path) as SalvageLoot if ResourceLoader.exists(path) else null
		if table == null:
			bad.append(kind)
			continue
		var got := 0
		for k in 20:
			got += table.roll(8, rng).size()
		if got == 0:
			empty.append(kind)
	check(bad.is_empty(), "every kind has a SalvageLoot table (missing: %s)" % str(bad))
	check(empty.is_empty(), "every table gives something in 20 rolls (empty: %s)" % str(empty))


func _test_loot() -> void:
	var panel := _item("solar_panel_test", [1, 2], 4)
	var loot := _loot(panel, Vector2i(1, 12), 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var total := func(stacks: Array) -> int:
		var n := 0
		for s in stacks:
			n += (s as item_stack).quantity
		return n
	check_eq(total.call(loot.roll(30, rng)), 7, "30 intact modules give 7 panels")
	check_eq(total.call(loot.roll(100, rng)), 12, "never more than 12 per search")
	check_eq(total.call(loot.roll(2, rng)), 1, "a small set gives at least one")
	var stacks: Array = loot.roll(30, rng)
	check(stacks.size() == 2 and (stacks[0] as item_stack).quantity == 4, "7 panels come as stacks of 4 and 3")
	var chance := SalvageLootEntry.new()
	chance.item = panel
	chance.chance = 0.0
	check_eq(chance.roll_count(10, rng), 0, "an entry at chance 0 gives nothing")
	# A container: exactly one of its entries, by weight.
	var container := SalvageLoot.new()
	container.pick_one = true
	var steel := _loot(_item("bulk_steel_test", [3, 3], 1), Vector2i(1, 1)).entries[0]
	var cable := _loot(_item("cable_drum_test", [2, 2], 1), Vector2i(1, 1)).entries[0]
	steel.chance = 0.75
	cable.chance = 0.25
	container.entries = [steel, cable]
	var steel_count := 0
	var one_each := true
	for k in 400:
		var got := container.roll(0, rng)
		one_each = one_each and got.size() == 1
		if got.size() == 1 and (got[0] as item_stack).item.id == "bulk_steel_test":
			steel_count += 1
	check(one_each, "a pick-one table always gives exactly one entry")
	check(steel_count > 250 and steel_count < 350, "by weight (bulk steel %d of 400 at 0.75)" % steel_count)
