extends TestSuite

# ExpeditionRunTest plays the Expedition mode end to end on the real map
# (Expedition.tscn, big_map) with the real player, enemies and director:
#   - a successful run: spawn with the saved mecha and cargo, shoot an enemy,
#     kill it, loot its wreck, extract through an exit, and the cargo is home
#   - dying: everything brought out is lost, the game-over screen says what
#   - leaving mid-run (quit, closing the scene) abandons the run
#
# Enemies are frozen after spawning and the director stopped, so the player
# isn't attacked at random and results don't depend on luck. Scene changes
# (Continue, Return) are captured, not performed (TransitionManager).

const EXPEDITION := preload("res://game/expedition/Expedition.tscn")
const SALVAGE := preload("res://database/items/salvage/servo_assembly.tres")

var _scene = null
var _saved_skip_intro = null


func _init() -> void:
	slow = true
	time_scale = 2.0  # projectiles must not skip past their target


func run_tests() -> void:
	_saved_skip_intro = Debug.debug_settings.get("skip_intro")
	Debug.debug_settings["skip_intro"] = true

	await _start_expedition()
	await case("the expedition starts", _test_start)
	await case("player weapons damage an enemy", _test_shooting)
	await case("a destroyed enemy leaves a wreck with loot", _test_kill_and_wreck)
	await case("no part swaps or recycling mid-run", _test_field_rules)
	await case("extracting brings the cargo home", _test_extract)
	await _close_expedition()

	await _start_expedition()
	await case("dying loses the mecha and cargo", _test_death)
	await _close_expedition()

	await _start_expedition()
	await case("leaving mid-run abandons the expedition", _test_abandon)

	Debug.debug_settings["skip_intro"] = _saved_skip_intro


# ---- Setup ----

# Fresh progress with a known cargo, then the real Expedition scene.
func _start_expedition() -> void:
	PlayerProgress.reset()
	# A saved cargo is already sized (by the core, in the Hangar).
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 8)
	cargo.add_stack_anywhere(item_stack.from_generic(SALVAGE))
	PlayerProgress.set_mech_inventory(cargo)
	TransitionManager.captured.clear()
	_scene = EXPEDITION.instantiate()
	add_child(_scene)
	# The director populates the world after the FX prewarm.
	var populated := await wait_until(func(): return _enemies().size() > 0, 20.0)
	check(populated, "enemies spawned")
	_scene.ExpeditionDirector.set_process(false)
	await wait_frames(2)
	for enemy in _enemies():
		enemy.set_pause(true)


func _close_expedition() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		await wait_frames(2)
	_scene = null


func _player() -> Mecha:
	return _scene.player if is_instance_valid(_scene) else null


func _enemies() -> Array:
	if not is_instance_valid(_scene):
		return []
	return _scene.all_mechas.filter(func(m): return is_instance_valid(m) and m != _scene.player and not m.is_dead)


func _action(target_type: String, id: String) -> Dictionary:
	for action in MechOS.context_actions.get(target_type, []):
		if action.get("id") == id:
			return action
	return {}


# ---- A successful run ----

func _test_start() -> void:
	var player := _player()
	check(player != null, "player spawned")
	check(PlayerProgress.is_in_expedition(), "the run has begun (stakes on)")
	check_eq(player.build.arm_weapon_left.part_id, PlayerProgress.DEFAULT_MECHA["arm_weapon_left"], "player has the saved mecha")
	check(player.mech_inventory == PlayerProgress.get_mech_inventory(), "player carries the saved cargo")
	check(player.mech_inventory.get_stacks().any(func(s): return s.item == SALVAGE), "cargo still holds what was packed")
	check(MissionManager.current_mission != null, "a mission is running")


# The player shoots the left arm; as each shot leaves the barrel the enemy is
# put in its path (shots have random spread), so the real projectile has to
# fly, collide and deal damage for this to pass.
func _test_shooting() -> void:
	var player := _player()
	var enemy: Mecha = _enemies()[0]
	# The player only fires in aim mode, and turns toward the mouse; hold it
	# still (paused) so the aim doesn't wander.
	MouseManager.force_pointer(false)
	check(MouseManager.is_aiming(), "aim mode is on in combat")
	player.set_pause(true)
	var shots := [0]
	var into_line_of_fire := func(_mecha, args, _weapon):
		shots[0] += 1
		enemy.global_position = args["pos"] + args["dir"] * 400.0
	player.create_projectile.connect(into_line_of_fire)
	# Projectiles hit a component (armour panel, actuator...) and either
	# penetrate and damage it or deflect; keep firing until one gets through.
	var hits := []
	enemy.component_damaged.connect(func(part, component, hp, max_hp): hits.append([part, component, hp, max_hp]))
	var hit := await wait_until(func():
		player.shoot("arm_weapon_left")
		return not hits.is_empty(), 6.0)
	player.create_projectile.disconnect(into_line_of_fire)
	check(shots[0] > 0, "the player's weapon fires")
	check(hit, "a player projectile damaged one of the enemy's components (%d shots)" % shots[0])
	if hit:
		check(hits[0][2] < hits[0][3], "the component lost hp (%s %s: %s/%s)" % hits[0])
		var source = enemy.last_damage_source
		check(typeof(source) == TYPE_DICTIONARY and source.get("name") == "Player", "the damage is credited to the player")
	player.set_pause(false)


func _test_kill_and_wreck() -> void:
	var enemy: Mecha = _enemies()[0]
	var wrecks_before: int = _scene.Wrecks.get_child_count()
	var kills_before: int = _scene.player_kills.size()
	var enemy_name: String = enemy.mecha_name
	enemy.last_damage_source = {"body": _player(), "name": "Player"}
	enemy.die({"name": "Player"}, "test")
	var wrecked := await wait_until(func(): return _scene.Wrecks.get_child_count() > wrecks_before, 8.0)
	if not check(wrecked, "a wreck appears where the enemy died"):
		return
	# (The shooting case can already have finished another enemy off.)
	check(_scene.player_kills.size() > kills_before and enemy_name in _scene.player_kills, "the kill counts for the player")
	var wreck = _scene.Wrecks.get_children()[-1]
	# Salvage is random (30% per part); make sure there's something to take.
	if wreck.inventory.is_empty():
		wreck.populate_stacks([item_stack.from_generic(SALVAGE)])
	var cargo: Inventory = _player().mech_inventory
	var cargo_before := cargo.get_stacks().size()
	var loot: int = wreck.inventory.get_stacks().size()
	var take_all := _action("inventory", "take_all")
	var ctx := {"type": "inventory", "inventory": wreck.inventory}
	check(take_all["visible_if"].call(ctx), "Take all offered on the wreck")
	take_all["run"].call(ctx)
	check(cargo.get_stacks().size() > cargo_before, "loot moved into the cargo (%d items in the wreck)" % loot)


func _test_field_rules() -> void:
	var equipment = MechOS.open_app("equipment")
	check(equipment != null and not equipment.can_customize, "equipment is view-only in the field")
	MechOS.close_app("equipment")
	var cargo: Inventory = _player().mech_inventory
	var stack: item_stack = cargo.get_stacks()[0]
	check(not PlayerProgress.can_recycle(stack), "nothing can be recycled mid-run")
	check(not MechOS.recycling_enabled, "no Recycle in the menus")


func _test_extract() -> void:
	var player := _player()
	var carried: int = player.mech_inventory.get_stacks().size()
	player.global_position = _scene.get_node("Map/Exits/Exit_Test").global_position
	var extracted := await wait_until(func(): return not PlayerProgress.is_in_expedition(), 20.0)
	if not check(extracted, "standing on an exit extracts"):
		return
	check_eq(PlayerProgress.get_mech_inventory().get_stacks().size(), carried, "the cargo came home")
	var summary = _find_child_of_type(ExtractionSummary)
	check(summary != null and summary.visible, "the extraction summary shows")
	if summary != null:
		check(SALVAGE.display_name in summary.body_label.text, "the summary lists the cargo")
		summary.continue_button.pressed.emit()
		await wait_frames()
		check(TransitionManager.captured.has("res://game/start_menu/StartMenu.tscn"), "Continue returns to the main menu")
	check(_scene.player == null, "the mecha left the map")


# ---- Dying ----

func _test_death() -> void:
	var player := _player()
	player.die({"name": "Test"}, "test")
	var lost := await wait_until(func(): return not PlayerProgress.is_in_expedition(), 10.0)
	if not check(lost, "dying ends the run"):
		return
	check(PlayerProgress.get_mech_inventory().is_empty(), "the cargo is lost")
	check(PlayerProgress.get_current_mecha() == PlayerProgress.DEFAULT_MECHA, "back to the default mecha")
	var shown := await wait_until(func(): return _scene.GameOver.get_node("SubViewportContainer").visible, 10.0)
	check(shown, "the game-over screen shows")
	check(SALVAGE.display_name in _scene.GameOver.LossLabel.text, "it says what was lost")
	check(not PlayerProgress.has_loss_report(), "the loss isn't reported again in the main menu")
	_scene.GameOver._on_ReturnButton_pressed()
	check(TransitionManager.captured.has("res://game/start_menu/StartMenu.tscn"), "Return goes to the main menu")


# ---- Abandoning ----

func _test_abandon() -> void:
	check(PlayerProgress.is_in_expedition(), "in a run")
	await _close_expedition()
	check(not PlayerProgress.is_in_expedition(), "leaving ended the run")
	check(PlayerProgress.get_mech_inventory().is_empty(), "the cargo is lost")
	var report := PlayerProgress.take_loss_report()
	check_eq(report.get("reason"), PlayerProgress.LOSS_ABANDONED, "the main menu will report it as abandoned")


func _find_child_of_type(type) -> Node:
	if not is_instance_valid(_scene):
		return null
	for child in _scene.get_children():
		if is_instance_of(child, type):
			return child
	return null
