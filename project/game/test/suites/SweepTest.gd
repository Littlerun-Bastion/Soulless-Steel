extends TestSuite

# SweepTest: the sensor sweep (Mecha.sweep, Player "SENSOR SWEEP", HudSweep).
# A sweep finds the living mechas and creatures in its cone and range, walls
# or not, and reports kinds and counts only; ECM shortens the range against
# that mecha; it costs heat and a cooldown; everything it finds is told it
# was swept, and the player sees "YOU WERE SWEPT"; creatures hear it (unless
# their species opts out), mechas don't; and the player aims it with the
# sweep key, widens it with the wheel (not the throttle), sweeps on release
# and cancels with reload, with the result on the HUD and in the log.

const MECHA := preload("res://game/mecha/Mecha.tscn")
const ENEMY := preload("res://game/mecha/Enemy.tscn")
const PLAYER := preload("res://game/mecha/player/Player.tscn")
const STALKER := preload("res://game/entities/Stalker.tscn")
const PLAYER_HUD := preload("res://game/ui/PlayerHUD.tscn")
const COMBAT_SCENE := preload("res://game/combat/CombatScene.gd")

# A generated building spanning x 0..400, y -200..200.
const BUILDING := [Vector2(0, -200), Vector2(400, -200), Vector2(400, 200), Vector2(0, 200)]


class FakeArena extends Node2D:
	var mechas: Array = []
	var entities: Array = []
	func get_mechas() -> Array:
		return mechas
	func get_entities() -> Array:
		return entities
	func get_lock_areas() -> Array:
		return []


var _arena: FakeArena = null
var _sweeper: Mecha = null


func run_tests() -> void:
	await case("the cone and range decide what is found", _test_cone)
	await case("walls don't block a sweep", _test_walls)
	await case("kinds and counts only", _test_counts)
	await case("ECM shortens the range against that mecha", _test_ecm)
	await case("a sweep costs heat and a cooldown", _test_cost)
	await case("what is found is told it was swept", _test_swept_signal)
	await case("creatures hear a sweep, mechas don't", _test_hearing)
	await case("the player aims, widens, sweeps and cancels", _test_player_input)
	await case("the HUD shows the aim, the result and being swept", _test_hud)
	await before_each()


func before_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	MouseManager.reset()
	await wait_frames(2)
	_arena = FakeArena.new()
	add_child(_arena)
	_sweeper = _mecha(Vector2.ZERO)
	_sweeper.global_rotation = 0.0
	await get_tree().physics_frame


func _mecha(pos: Vector2, scene: PackedScene = MECHA) -> Mecha:
	var mecha: Mecha = scene.instantiate()
	mecha.mech_inventory = Inventory.new()
	mecha.position = pos
	_arena.add_child(mecha)
	mecha.set_parts_from_design(PlayerProgress.DEFAULT_MECHA)
	mecha.set_pause(true)
	_arena.mechas.append(mecha)
	return mecha


func _stalker(pos: Vector2) -> Entity:
	var stalker: Entity = STALKER.instantiate()
	stalker.position = pos
	_arena.add_child(stalker)
	stalker.setup(_arena)
	stalker.set_pause(true)
	_arena.entities.append(stalker)
	return stalker


func _test_cone() -> void:
	var ahead := _mecha(Vector2(0, -3000))
	var off_30 := _mecha(Vector2.UP.rotated(deg_to_rad(30.0)) * 3000.0)
	var behind := _mecha(Vector2(0, 3000))
	var too_far := _mecha(Vector2(0, -(Mecha.SWEEP_RANGE + 200.0)))
	var dead := _mecha(Vector2(0, -2000))
	dead.is_dead = true
	var narrow := _sweeper.sweep_finds(Vector2.UP, 20.0)
	check(narrow.has(ahead) and not narrow.has(off_30), "a 20° cone finds what is ahead, not 30° off")
	var wide := _sweeper.sweep_finds(Vector2.UP, 90.0)
	check(wide.has(ahead) and wide.has(off_30) and not wide.has(behind), "a 90° cone finds both, not what is behind")
	var all_round := _sweeper.sweep_finds(Vector2.UP, 360.0)
	check(all_round.has(behind), "360° finds what is behind")
	check(not all_round.has(too_far), "nothing past %d m" % roundi(Mecha.SWEEP_RANGE / 20.0))
	check(not all_round.has(_sweeper), "never the sweeper itself")
	check(not all_round.has(dead), "nor the dead")
	var result := _sweeper.sweep(Vector2.UP, 1.0)
	check_eq(result.width, Mecha.SWEEP_MIN_WIDTH, "a cone is never narrower than %d°" % roundi(Mecha.SWEEP_MIN_WIDTH))


func _test_walls() -> void:
	var footprints := BuildingFootprints.new()
	footprints.points = PackedVector2Array(BUILDING)
	footprints.starts = PackedInt32Array([0, 4])
	var field := BuildingField.new()
	field.footprints = footprints
	_arena.add_child(field)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var behind_wall := _mecha(Vector2(1500, 0))
	var inside := _mecha(Vector2(200, 0))
	check(MapSenses.walls_between(_sweeper.get_world_2d(), _sweeper.global_position, behind_wall.global_position), "there is a wall in the way")
	var found := _sweeper.sweep_finds(Vector2.RIGHT, 30.0)
	check(found.has(behind_wall) and found.has(inside), "the sweep finds through it and inside the building")


func _test_counts() -> void:
	_mecha(Vector2(0, -1000))
	_mecha(Vector2(100, -2000))
	_stalker(Vector2(-100, -1500))
	_stalker(Vector2(0, -2500))
	_stalker(Vector2(0, -4000))
	var result := _sweeper.sweep(Vector2.UP, 60.0)
	check(result.ok, "it swept")
	check_eq(result.counts, {"mech": 2, "Stalker": 3}, "counts by kind")
	check_eq(result.keys().size(), 3, "and nothing else: no positions, directions or distances")
	check_eq(Mecha.describe_sweep(result.counts), "2 MECH · 3 STALKER", "as text, mechs first")
	check_eq(Mecha.describe_sweep({}), "NO RETURNS", "an empty sweep")
	check_eq(Mecha.describe_sweep({"Stalker": 1, "Brute": 2, "mech": 1}), "1 MECH · 2 BRUTE · 1 STALKER", "species by name after mechs")


func _test_ecm() -> void:
	var near := _mecha(Vector2(0, -6900))
	var far := _mecha(Vector2(0, -7100))
	near.sensor_reduction = 0.3
	far.sensor_reduction = 0.3
	var plain := _mecha(Vector2(200, -7100))
	var found := _sweeper.sweep_finds(Vector2.UP, 30.0)
	check(found.has(near), "an ECM 0.3 mecha is found within 70% of the range (350 m)")
	check(not found.has(far), "not past it: it simply isn't there")
	check(found.has(plain), "one without ECM at the same distance is")


func _test_cost() -> void:
	var heat_before := _sweeper.pending_heat_kj
	check_eq(_sweeper.can_sweep(), "", "ready")
	var result := _sweeper.sweep(Vector2.UP, 90.0)
	check(result.ok, "it sweeps")
	check_eq(_sweeper.pending_heat_kj - heat_before, Mecha.SWEEP_HEAT, "a heat spike of %d kJ" % roundi(Mecha.SWEEP_HEAT))
	check_eq(_sweeper.sweep_cooldown, Mecha.SWEEP_COOLDOWN, "and a cooldown")
	var again := _sweeper.sweep(Vector2.UP, 90.0)
	check(not again.ok and again.reason == "cooldown", "no second sweep while it cools down")
	_sweeper.set_pause(false)
	var cooled := await wait_until(func(): return _sweeper.sweep_cooldown <= 0.0, Mecha.SWEEP_COOLDOWN + 2.0)
	check(cooled, "the cooldown runs out")
	_sweeper.set_pause(true)
	_sweeper.is_dead = true
	check_eq(_sweeper.can_sweep(), "dead", "the dead don't sweep")


func _test_swept_signal() -> void:
	var caught := _mecha(Vector2(0, -2000))
	var missed := _mecha(Vector2(0, 2000))
	var npc = ENEMY.instantiate()
	npc.mech_inventory = Inventory.new()
	npc.position = Vector2(300, -3000)
	_arena.add_child(npc)
	npc.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Swept NPC")
	npc.paused = true
	var hits := {}
	for m in [caught, missed, npc]:
		m.swept.connect(func(): hits[m.get_instance_id()] = true)
	_sweeper.sweep(Vector2.UP, 45.0)
	check(hits.has(caught.get_instance_id()), "a mecha in the cone gets swept")
	check(hits.has(npc.get_instance_id()), "an NPC too (NPC code can react)")
	check(not hits.has(missed.get_instance_id()), "one outside doesn't")


func _test_hearing() -> void:
	var stalker := _stalker(Vector2(0, -3000))
	stalker.set_pause(false)
	stalker.set_physics_process(false)
	var npc = ENEMY.instantiate()
	npc.mech_inventory = Inventory.new()
	npc.position = Vector2(500, 0)
	_arena.add_child(npc)
	npc.setup(_arena, PlayerProgress.DEFAULT_MECHA, "Listener")
	npc.paused = true
	var scene = COMBAT_SCENE.new()
	scene.all_mechas = [_sweeper, npc]
	scene.all_entities = [stalker]
	_sweeper.made_sound.connect(scene._on_mecha_made_sound)
	_sweeper.sweep(Vector2.UP, 30.0)
	check_eq(stalker.state, Stalker.State.INVESTIGATE, "a creature goes to investigate the sweep")
	check(npc.senses.sounds.is_empty(), "an NPC mecha doesn't hear it")
	var deaf := _stalker(Vector2(0, -2000))
	deaf.hears_sweeps = false
	deaf.set_pause(false)
	deaf.set_physics_process(false)
	scene.all_entities = [deaf]
	_sweeper.sweep_cooldown = 0.0
	_sweeper.sweep(Vector2.UP, 30.0)
	check(deaf.state != Stalker.State.INVESTIGATE, "a species with hears_sweeps off ignores it")
	scene.free()


func _player() -> Node:
	var player = PLAYER.instantiate()
	player.mech_inventory = Inventory.new()
	player.position = Vector2(0, 500)
	_arena.add_child(player)
	player.setup(_arena)
	player.set_physics_process(false)
	player.global_rotation = 0.0
	_arena.mechas.append(player)
	MouseManager.set_aim_available(true)
	return player


func _action(action: String, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _test_player_input() -> void:
	var player = _player()
	var done := []
	var refused := []
	player.sweep_done.connect(func(result): done.append(result))
	player.sweep_refused.connect(func(reason): refused.append(reason))
	var throttle: float = player.throttle
	player._input(_action("sweep"))
	check(player.is_sweep_aiming(), "holding the sweep key aims the cone")
	player._input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	player._input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	check_eq(player.sweep_width, player.SWEEP_START_WIDTH + 2.0 * player.SWEEP_WIDTH_STEP, "the wheel widens it")
	check_eq(player.throttle, throttle, "and leaves the throttle alone")
	for i in 60:
		player._input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	check_eq(player.sweep_width, Mecha.SWEEP_MIN_WIDTH, "down to %d° at least" % roundi(Mecha.SWEEP_MIN_WIDTH))
	player._update_designators(0.0)
	var marks: Array = player.designator.marks
	check(marks.size() == 1 and marks[0].shape == "cone" and marks[0].width == Mecha.SWEEP_MIN_WIDTH, "the cone is drawn at that width")
	player._input(_action("reload_mode"))
	check(not player.is_sweep_aiming(), "reload cancels")
	check(done.is_empty() and player.sweep_cooldown == 0.0, "and nothing was swept")
	player._update_designators(0.0)
	check(player.designator.marks.is_empty(), "the cone is gone")
	player._input(_action("sweep"))
	player._input(_action("sweep", false))
	check_eq(done.size(), 1, "releasing sweeps")
	check(player.sweep_cooldown > 0.0, "and starts the cooldown")
	var last: Dictionary = MechLog.lines[MechLog.lines.size() - 1]
	check(last.source == "SNS" and str(last.text).begins_with("Sweep"), "the result is in the log")
	player._input(_action("sweep"))
	check(not player.is_sweep_aiming() and refused == ["cooldown"], "pressed while cooling down, it doesn't aim and says why")


func _test_hud() -> void:
	var player = _player()
	var hud = PLAYER_HUD.instantiate()
	add_child(hud)
	hud.setup(player, _arena.mechas)
	var sweep_hud: HudSweep = hud.hud_sweep
	player._input(_action("sweep"))
	sweep_hud._process(0.0)
	check(sweep_hud.get_text().begins_with("SWEEP %d°" % roundi(player.sweep_width)), "aiming shows the width (%s)" % sweep_hud.get_text())
	# All round, so where the (headless) cursor is doesn't matter: the
	# sweeper at the origin and one more mecha are in range.
	_mecha(player.global_position + Vector2(0, -2000))
	player.sweep_width = Mecha.SWEEP_MAX_WIDTH
	player._input(_action("sweep", false))
	sweep_hud._process(0.0)
	check(sweep_hud.get_text() == "SWEEP 360° — 2 MECH", "the result: kinds and counts (%s)" % sweep_hud.get_text())
	sweep_hud._process(HudSweep.READOUT_TIME + 0.1)
	check_eq(sweep_hud.get_text(), "", "gone after %d s" % roundi(HudSweep.READOUT_TIME))
	player._input(_action("sweep"))
	sweep_hud._process(0.0)
	check(sweep_hud.get_text().begins_with("SWEEP RECHARGING"), "while cooling down it says so")
	var npc := _mecha(player.global_position + Vector2(0, -1000))
	npc.global_rotation = PI
	npc.sweep(Vector2.DOWN, 30.0)
	hud.hud_alerts._process(0.0)
	check_eq(hud.hud_alerts.get_current(), "YOU WERE SWEPT", "an NPC's sweep that finds the player raises the alert")
	var last: Dictionary = MechLog.lines[MechLog.lines.size() - 1]
	check_eq(last.text, "You were swept", "and a log line, with no bearing")
	hud.hud_alerts._process(HudAlerts.NOTICE_TIME + 0.1)
	check_eq(hud.hud_alerts.get_current(), "", "the alert goes after %d s" % roundi(HudAlerts.NOTICE_TIME))
	hud.queue_free()
