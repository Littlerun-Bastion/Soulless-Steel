class_name SalvageField
extends Node2D

# The map's salvage sources: world objects the player can see and take
# salvage from (solar panels on a roof, a generator in a yard, a bus).
# Every item a mecha picks up on the map comes from one. Sources are not
# nodes: the field keeps them in arrays and a grid, as VehicleField does for
# vehicles, and makes a node only for the sources near the player.
#
# Where sources come from:
#   sources       the generator's SalvageSpawnSet (kind, position, outline
#                 box, the roof it is on, an amount, whether it is a vehicle)
#   wrecks        every vehicle_wreck in the VehicleField, and every car
#                 destroyed during the expedition (vehicle_destroyed): a
#                 "car_wreck" whose pieces are picked up; none in the map's
#                 border band (MapBounds)
#   add_source()  anything else (tests, scripted scenes)
# A source on a roof (building >= 0) whose building is gutted or collapsed is
# left out: its roof is gone. A vehicle source follows its vehicle when the
# vehicle is pushed, and is left out when the VehicleField has no vehicle at
# its spot (PropSpawner.kept_share thinned it, or a CLEAR zone removed it).
#
# Loot: each kind has a SalvageLoot table, LOOT_DIR/<kind>.tres. A source
# rolls its loot the first time the player comes within NODE_RADIUS (seeded
# by loot_seed and the source's index, so a map seed gives the same loot),
# into an Inventory the field keeps for the rest of the expedition. Nothing
# is saved.
#
# Near the player: every UPDATE_FRAMES physics frames, each source with
# something left within NODE_RADIUS gets a node: a SalvageSource (a
# LootContainer: Search opens the loot window) or, for PICKUP_KINDS, a
# SalvagePickup (Interact puts the pieces straight into the cargo). Each has
# an InteractArea of the outline box grown by INTERACT_MARGIN, so the
# interact prompt goes to the nearest source in range (InteractPrompt). A
# node more than NODE_RADIUS + NODE_SLACK away is freed (never while its
# window is open).
#
# Empty: a source whose inventory is empty (once its window closes, or once
# a pickup is taken) stays in the world but loses its node, its prompt and
# its HUD bracket for the rest of the expedition (source_emptied).
#
# HUD: visible_sources() gives the sources the player sees, worked out every
# SIGHT_FRAMES physics frames, by the rules that show a mecha
# (Player.can_see_point): not through walls, not in the dark past the view
# circle; a source on a roof shows when its roof is in sight. Loot containers
# that are nodes of their own (wrecks of dead mechas, carcasses, crates)
# join the list too, with an EXTERNAL_BOX outline. HudSalvage draws them.

const KIND_NAMES := {
	"bus": "BUS", "tank": "TANK", "military_vehicle": "MILITARY VEHICLE",
	"container_truck": "CONTAINER TRUCK", "shipping_container": "SHIPPING CONTAINER",
	"tanker": "TANKER", "dump_truck": "DUMP TRUCK",
	"solar_panels": "SOLAR PANELS", "roof_ac": "AC UNITS",
	"diesel_generator": "DIESEL GENERATOR", "transformer": "TRANSFORMER",
	"electric_motor": "ELECTRIC MOTOR", "industrial_pump": "INDUSTRIAL PUMP",
	"control_cabinet": "CONTROL CABINET", "valve_assembly": "VALVES",
	"oil_drums": "OIL DRUMS", "cable_drum": "CABLE DRUM", "tractor": "TRACTOR",
	"relay_mast": "RELAY MAST", "rubble": "RUBBLE", "car_wreck": "WRECKED CAR",
}
const PICKUP_KINDS := ["car_wreck"]
const WRECK_KIND := "car_wreck"
const LOOT_DIR := "res://database/loot-tables/sources/"
const CELL_SIZE := 2000.0
const NODE_RADIUS := 1500.0
const NODE_SLACK := 500.0
const UPDATE_FRAMES := 10
## How far (px) past its outline box a source can be used from.
const INTERACT_MARGIN := 160.0
const SIGHT_FRAMES := 4
## How near (px) a vehicle source's spawn point must be to a vehicle's.
const VEHICLE_MATCH := 60.0
## Outline (px) given to loot containers that are nodes of their own.
const EXTERNAL_BOX := Vector2(220, 220)
## Inventory width of a source's loot window; its height grows to fit.
const GRID_WIDTH := 6
const GRID_MIN_HEIGHT := 4

enum { UNTOUCHED, ROLLED, EMPTY }

signal source_added(index: int)
signal source_emptied(index: int)

@export var sources: SalvageSpawnSet
@export var vehicle_field_path: NodePath
@export var building_field_path: NodePath
## Seeds every source's loot roll.
@export var loot_seed := 1

var _kind := PackedStringArray()
var _pos := PackedVector2Array()
var _rot := PackedFloat32Array()
var _size := PackedVector2Array()
var _building := PackedInt32Array()
var _amount := PackedInt32Array()
var _vehicle := PackedInt32Array()
var _state := PackedByteArray()
var _inv: Array = []
var _cells := {}
var _nodes := {}
var _loot := {}
var _vehicles: VehicleField = null
var _buildings: BuildingField = null
var _built := false
var _player: Node2D = null
var _visible: Array[Dictionary] = []
var _visible_frame := -1000
var _visible_for: Node2D = null


func _ready() -> void:
	add_to_group("salvage_field")
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_build.call_deferred()


static func find(node: Node) -> SalvageField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("salvage_field") as SalvageField


func is_built() -> bool:
	return _built


func source_count() -> int:
	return _pos.size()


func kind_of(i: int) -> String:
	return _kind[i]


func is_empty(i: int) -> bool:
	return _state[i] == EMPTY


func node_of(i: int) -> Node:
	var node: Node = _nodes.get(i)
	return node if is_instance_valid(node) else null


## The source's inventory, rolled now if it wasn't yet.
func inventory_of(i: int) -> Inventory:
	_ensure_rolled(i)
	return _inv[i]


## Source i's position (global), following its vehicle if it has one.
func source_position(i: int) -> Vector2:
	if _vehicle[i] >= 0 and _vehicles != null:
		return _vehicles.vehicle_transform(_vehicle[i]).origin
	return _pos[i]


func source_rotation(i: int) -> float:
	if _vehicle[i] >= 0 and _vehicles != null:
		return _vehicles.vehicle_transform(_vehicle[i]).get_rotation()
	return _rot[i]


## Source i's outline box corners, global.
func source_corners(i: int) -> PackedVector2Array:
	var half := _size[i] * 0.5
	var xf := Transform2D(source_rotation(i), source_position(i))
	return PackedVector2Array([xf * Vector2(-half.x, -half.y), xf * Vector2(half.x, -half.y),
			xf * Vector2(half.x, half.y), xf * Vector2(-half.x, half.y)])


static func display_name_of(kind: String) -> String:
	return KIND_NAMES.get(kind, kind.to_upper().replace("_", " "))


## Adds a source (global position and rotation, outline box size in px).
## `building` is the roof it is on (-1: the ground), `vehicle` the
## VehicleField vehicle it is (-1: none). `stacks`, if given, is its loot
## instead of a roll.
func add_source(kind: String, pos: Vector2, rot: float, size: Vector2, building := -1, amount := 0,
		vehicle := -1, stacks: Array = []) -> int:
	var i := _pos.size()
	_kind.append(kind)
	_pos.append(pos)
	_rot.append(rot)
	_size.append(size)
	_building.append(building)
	_amount.append(amount)
	_vehicle.append(vehicle)
	_state.append(UNTOUCHED)
	_inv.append(null)
	_file(i)
	if not stacks.is_empty():
		_fill(i, stacks)
	source_added.emit(i)
	return i


## Marks a source empty (as if the player took everything).
func empty_source(i: int) -> void:
	if _state[i] == EMPTY:
		return
	_state[i] = EMPTY
	_free_node(i)
	source_emptied.emit(i)


func _build() -> void:
	_vehicles = get_node_or_null(vehicle_field_path) as VehicleField
	_buildings = get_node_or_null(building_field_path) as BuildingField
	if _vehicles != null and not _vehicles.is_built():
		get_tree().create_timer(0.1, true, true).timeout.connect(_build, CONNECT_ONE_SHOT)
		return
	if sources != null:
		for k in sources.count():
			var building: int = sources.building[k] if k < sources.building.size() else -1
			if building >= 0 and _buildings != null and _roof_gone(building):
				continue
			var pos := to_global(sources.position[k])
			var vehicle := -1
			if k < sources.vehicle.size() and sources.vehicle[k] == 1 and _vehicles != null:
				vehicle = _vehicle_at(pos)
				if vehicle < 0:
					continue
			add_source(sources.kind_name(k), pos, sources.rotation[k] + global_rotation, sources.size[k],
					building, sources.amount[k] if k < sources.amount.size() else 0, vehicle)
	if _vehicles != null:
		for v in _vehicles.vehicle_count():
			if _vehicles.vehicle_kind(v) == "vehicle_wreck" or _vehicles.is_destroyed(v):
				_add_wreck(v)
		_vehicles.vehicle_destroyed.connect(_on_vehicle_destroyed)
	_built = true


# The VehicleField vehicle parked at a global position (within VEHICLE_MATCH
# px), or -1. Uses the field's grid, not a walk of every vehicle.
func _vehicle_at(pos: Vector2) -> int:
	var best := -1
	var best_d := VEHICLE_MATCH
	for v in _vehicles.vehicles_near(pos, VEHICLE_MATCH):
		var d := _vehicles.vehicle_transform(v).origin.distance_to(pos)
		if d < best_d:
			best = v
			best_d = d
	return best


func _roof_gone(building: int) -> bool:
	var state := _buildings.state_of(building)
	return state == BuildingFootprints.GUTTED or state == BuildingFootprints.COLLAPSED


func _add_wreck(v: int) -> void:
	var xf := _vehicles.vehicle_transform(v)
	# No source in the map's border band: nothing can reach it.
	var bounds := MapBounds.find(self)
	if bounds != null and not bounds.is_in_play_area(xf.origin):
		return
	add_source(WRECK_KIND, xf.origin, xf.get_rotation(), _vehicles.vehicle_size(v), -1, 0, v)


func _on_vehicle_destroyed(v: int, _by: Node) -> void:
	if _vehicles.vehicle_kind(v) != "vehicle_wreck":
		_add_wreck(v)


func _physics_process(_delta: float) -> void:
	if not _built or Engine.get_physics_frames() % UPDATE_FRAMES != 0:
		return
	var player := _find_player()
	var near := {}
	if player != null:
		var at := player.global_position
		for i in _ids_in(Rect2(at, Vector2.ZERO).grow(NODE_RADIUS)):
			if _state[i] == EMPTY:
				continue
			if source_position(i).distance_to(at) <= NODE_RADIUS:
				near[i] = true
				if node_of(i) == null:
					_make_node(i)
	for i in _nodes.keys():
		var node := node_of(i)
		if node == null:
			_nodes.erase(i)
			continue
		if node.get("is_open") == true:
			continue
		if _state[i] == ROLLED and (_inv[i] as Inventory).is_empty():
			empty_source(i)
			continue
		var far: bool = player == null or source_position(i).distance_to(player.global_position) > NODE_RADIUS + NODE_SLACK
		if not near.has(i) and far:
			_free_node(i)
		elif _vehicle[i] >= 0:
			(node as Node2D).global_position = source_position(i)
			(node as Node2D).global_rotation = source_rotation(i)


# ---- Sight (for the HUD) ----

## The sources `player` sees now, as {"index" (-1 for a node of its own),
## "node", "corners" (global outline), "name", "at" (global centre)},
## worked out every SIGHT_FRAMES physics frames.
func visible_sources(player: Node2D) -> Array[Dictionary]:
	var frame := Engine.get_physics_frames()
	if player == _visible_for and frame - _visible_frame < SIGHT_FRAMES:
		return _visible
	_visible_frame = frame
	_visible_for = player
	_visible = []
	if player == null or not player.has_method("can_see_point"):
		return _visible
	var screen := MapSenses.screen_rect(self)
	var reach: float = player.sight_radius()
	var area := Rect2(player.global_position, Vector2.ZERO).grow(reach).intersection(screen.grow(EXTERNAL_BOX.x))
	for i in _ids_in(area):
		if _state[i] == EMPTY:
			continue
		var corners := source_corners(i)
		if not _rect_of(corners).intersects(screen):
			continue
		var at := source_position(i)
		if player.can_see_point(at, _building[i] >= 0, _size[i].length() * 0.5):
			_visible.append({"index": i, "node": node_of(i), "corners": corners,
					"name": display_name_of(_kind[i]), "at": at})
	for node in get_tree().get_nodes_in_group("loot_container"):
		if node is SalvageSource or not (node is Node2D) or not is_instance_valid(node):
			continue
		var container := node as Node2D
		var inv: Inventory = container.get("inventory")
		if inv == null or inv.is_empty():
			continue
		var at := container.global_position
		var half := EXTERNAL_BOX * 0.5
		var corners := PackedVector2Array([at - half, at + Vector2(half.x, -half.y), at + half, at + Vector2(-half.x, half.y)])
		if not _rect_of(corners).intersects(screen):
			continue
		if player.can_see_point(at, false, half.x):
			_visible.append({"index": -1, "node": container, "corners": corners,
					"name": str(container.get("display_name")), "at": at})
	return _visible


# ---- Nodes ----

func _make_node(i: int) -> void:
	_ensure_rolled(i)
	if _state[i] == EMPTY:
		return
	var node: Node2D
	if PICKUP_KINDS.has(_kind[i]):
		var pickup := SalvagePickup.new()
		pickup.inventory = _inv[i]
		pickup.display_name = display_name_of(_kind[i])
		pickup.picked_up.connect(_on_picked_up)
		pickup.source_index = i
		node = pickup
	else:
		var source := SalvageSource.new()
		var inv: Inventory = _inv[i]
		source.grid_width = inv.grid_width
		source.grid_height = inv.grid_height
		source.display_name = display_name_of(_kind[i])
		source.container_id = "salvage_%d" % i
		source.persistent = false
		source.restore(inv)
		source.source_index = i
		source.closed.connect(_on_closed)
		node = source
	node.name = "Salvage%d" % i
	var area := Area2D.new()
	area.name = "InteractArea"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size[i] + Vector2(INTERACT_MARGIN, INTERACT_MARGIN) * 2.0
	shape.shape = rect
	area.add_child(shape)
	node.add_child(area)
	add_child(node)
	node.global_position = source_position(i)
	node.global_rotation = source_rotation(i)
	_nodes[i] = node


func _free_node(i: int) -> void:
	var node := node_of(i)
	_nodes.erase(i)
	if node == null:
		return
	if is_instance_valid(_player) and _player.has_method("remove_interactable"):
		_player.remove_interactable(node)
	node.queue_free()


func _on_closed(container: LootContainer) -> void:
	var source := container as SalvageSource
	if source != null and source.inventory != null and source.inventory.is_empty():
		empty_source(source.source_index)


func _on_picked_up(pickup: SalvagePickup, _moved: int) -> void:
	if pickup.inventory == null or pickup.inventory.is_empty():
		empty_source(pickup.source_index)


# ---- Loot ----

func _ensure_rolled(i: int) -> void:
	if _state[i] != UNTOUCHED:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([loot_seed, i, _kind[i], _pos[i]])
	var table := _loot_for(_kind[i])
	_fill(i, table.roll(_amount[i], rng) if table != null else [])


func _fill(i: int, stacks: Array) -> void:
	var cells := 0
	var widest := GRID_WIDTH
	for stack in stacks:
		var item: item_data = (stack as item_stack).item as item_data
		if item != null:
			cells += item.width() * item.height()
			widest = maxi(widest, maxi(item.width(), item.height()))
	var inv := Inventory.new()
	inv.initialize_grid(widest, maxi(GRID_MIN_HEIGHT, ceili(cells * 1.4 / widest)))
	var left := inv.add_stacks_bulk(stacks)
	while not left.is_empty() and inv.grid_height < 64:
		inv.grow_to(inv.grid_width, inv.grid_height + 2)
		left = inv.add_stacks_bulk(left)
	_inv[i] = inv
	_state[i] = EMPTY if inv.is_empty() else ROLLED
	if _state[i] == EMPTY:
		_free_node(i)
		source_emptied.emit(i)


func _loot_for(kind: String) -> SalvageLoot:
	if not _loot.has(kind):
		var path := LOOT_DIR + kind + ".tres"
		_loot[kind] = load(path) as SalvageLoot if ResourceLoader.exists(path) else null
	return _loot[kind]


# ---- Grid ----

func _file(i: int) -> void:
	var key := _cell_of(_pos[i])
	if not _cells.has(key):
		_cells[key] = PackedInt32Array()
	_cells[key].append(i)


func _ids_in(rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0 := _cell_of(rect.position - Vector2(CELL_SIZE, CELL_SIZE) * 0.25)
	var c1 := _cell_of(rect.end + Vector2(CELL_SIZE, CELL_SIZE) * 0.25)
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var list: PackedInt32Array = _cells.get(Vector2i(cx, cy), PackedInt32Array())
			out.append_array(list)
	return out


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))


static func _rect_of(points: PackedVector2Array) -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return r


func _find_player() -> Node2D:
	if is_instance_valid(_player) and _player.is_inside_tree() and _player.get("is_dead") != true:
		return _player
	_player = null
	for mech in get_tree().get_nodes_in_group("mecha"):
		if mech is Node2D and mech.has_method("is_player") and mech.is_player() and mech.get("is_dead") != true:
			_player = mech
			break
	return _player
