extends TestSuite

# ExpeditionRunTest plays the Expedition mode end to end on the real map
# (Expedition.tscn, big_map) with the real player, enemies and director:
#   - a successful run: spawn with the saved mecha and cargo, shoot an enemy,
#     kill it, loot its wreck, extract through an exit, and the cargo is home
#   - dying: everything brought out is lost, the game-over screen says what
#   - pausing and resuming; quitting from the pause menu (warned first)
#     abandons the run
#   - Entities: Stalker packs spawn away from the player, NPCs fight them,
#     gunfire reaches them, the intro freeze holds them, kills count, and a
#     dead one leaves a carcass of bio salvage to loot
#
# Enemies and Entities are frozen after spawning and the director stopped, so
# the player isn't attacked at random and results don't depend on luck. Scene
# changes (Continue, Return) are captured, not performed (TransitionManager).

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
	await case("Entities roam the map", _test_entities_spawned)
	await case("NPCs and Stalkers fight", _test_npcs_fight_entities)
	await case("gunfire reaches Entities", _test_entities_hear)
	await case("the intro freeze holds Entities too", _test_entities_freeze)
	await case("killing an Entity counts for the player", _test_entity_kill)
	await case("a dead Entity leaves a carcass of bio salvage", _test_carcass_loot)
	await case("an Entity killed mid-collision leaves its carcass cleanly", _test_kill_in_collision)
	await case("pausing and resuming", _test_pause)
	await case("quitting from the pause menu abandons the expedition", _test_abandon)

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
	_freeze_world()


func _freeze_world() -> void:
	for enemy in _enemies():
		enemy.set_pause(true)
	for entity in _scene.get_entities():
		entity.set_pause(true)


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
	var marker: ExitMarker = _scene.PlayerHUD.exit_marker
	check(marker.exits.size() == 4 and marker.visible, "the HUD points to the nearest of the map's 4 exits")
	check(marker.nearest != null and marker.nearest.global_position.distance_to(player.global_position) > 9000.0,
			"no exit next to the spawn any more: the nearest is out at the map's edge")
	check(player.mech_inventory.get_stacks().any(func(s): return s.item == SALVAGE), "cargo still holds what was packed")
	check(MissionManager.current_mission != null, "a mission is running")
	# The site comes from the map (Map.site_name), Helwan unless it says otherwise.
	var map: Node = _scene.get_node("Map")
	check_eq(_scene.get_site_name(), "Helwan", "the run takes place at the map's site")
	check_eq(_scene.PlayerHUD.top_strip.get("_site"), "HELWAN", "the HUD shows the site")
	map.site_name = "Test Ridge"
	check_eq(_scene.get_site_name(), "Test Ridge", "a map can name its own site")
	map.site_name = ""
	check_eq(_scene.get_site_name(), "Helwan", "a map with no site name falls back to Helwan")
	map.site_name = "Helwan"


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
	player.global_position = _scene.get_node("Map/Exits/Exit_W").global_position
	var extracted := await wait_until(func(): return not PlayerProgress.is_in_expedition(), 20.0)
	if not check(extracted, "standing on an exit extracts"):
		return
	check_eq(PlayerProgress.get_mech_inventory().get_stacks().size(), carried, "the cargo came home")
	var summary = _find_child_of_type(ExtractionSummary)
	check(summary != null and summary.visible, "the extraction summary shows")
	if summary != null:
		check(SALVAGE.display_name in summary.get_text(), "the summary lists the cargo")
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
	var shown := await wait_until(func():
		var s = _find_child_of_type(ExtractionSummary)
		return s != null and s.visible, 10.0)
	check(shown, "the written-off debrief shows")
	var summary = _find_child_of_type(ExtractionSummary)
	if summary != null:
		var text: String = summary.get_text()
		check(SALVAGE.display_name in text and "WRITTEN OFF" in text, "it lists what was lost as written off")
		check(not PlayerProgress.has_loss_report(), "the loss isn't reported again in the main menu")
		summary.continue_button.pressed.emit()
		await wait_frames()
		check(TransitionManager.captured.has("res://game/start_menu/StartMenu.tscn"), "Return goes to the main menu")

# ---- Entities ----

func _stalkers() -> Array:
	return _scene.get_entities().filter(func(e): return e is Stalker and not e.is_dead)


func _test_entities_spawned() -> void:
	var director = _scene.ExpeditionDirector
	var stalkers := _stalkers()
	check(stalkers.size() >= director.min_initial_packs * director.min_pack_size,
			"at least %d packs of %d (%d Stalkers)" % [director.min_initial_packs, director.min_pack_size, stalkers.size()])
	var spitters: Array = _scene.get_entities().filter(func(e): return e is Spitter)
	var brutes: Array = _scene.get_entities().filter(func(e): return e is Brute)
	check(spitters.size() >= director.min_initial_spitters and spitters.size() <= director.max_initial_spitters,
			"%d-%d Spitters (%d)" % [director.min_initial_spitters, director.max_initial_spitters, spitters.size()])
	check(brutes.size() <= 1, "at most one Brute to start with (%d)" % brutes.size())
	var cysts: Array = _scene.get_entities().filter(func(e): return e is Cyst)
	var sites: Array = _scene.get_cyst_sites()
	check(not sites.is_empty() and cysts.size() == sites.size(), "a Cyst on each of the map's %d sites (%d)" % [sites.size(), cysts.size()])
	for cyst in cysts:
		check(sites.any(func(s): return s.global_position.distance_to(cyst.global_position) < 1.0), "%s sits on a site" % cyst.name)
		check(not cyst.awake and cyst.guards.is_empty(), "%s is asleep at the start" % cyst.name)
	var player_pos: Vector2 = _player().global_position
	# Spawns are at least min_entity_distance_from_player away; pack members spread 250 around theirs.
	var nearest := INF
	for entity in _scene.get_entities():
		nearest = minf(nearest, entity.global_position.distance_to(player_pos))
	check(nearest > director.min_entity_distance_from_player - 400.0, "none spawn on top of the player (nearest %d)" % int(nearest))
	check(stalkers.all(func(s): return s.pack != null and s.pack.members.size() >= director.min_pack_size), "each is in a pack")
	check(_scene.Entities.get_index() < _scene.Mechas.get_index(), "drawn under the mechas")


# A Stalker bites an NPC: the NPC turns on it (and Stalkers always count as
# fair game, no flags or grudges needed).
func _test_npcs_fight_entities() -> void:
	var enemy = _enemies()[0]
	var stalker: Stalker = _stalkers()[0]
	# Behind it (mechas face -Y), where a bite always gets through.
	stalker.global_position = enemy.global_position + Vector2(0, 300).rotated(enemy.global_rotation)
	# NPC fire makes an idle Stalker hunt the NPC. (First, while the NPC is
	# sure to be alive: the bites below can take out its cockpit. And the
	# Stalker may already have been after something when the world froze.)
	stalker.lose_target()
	stalker._set_state(Stalker.State.WANDER)
	stalker.take_hit(1.0, 5, Vector2.ZERO, {"body": enemy, "name": enemy.mecha_name})
	check(stalker.target == enemy, "a shot Stalker hunts its shooter")
	stalker.lose_target()
	# And the other way round: a bitten NPC turns on the Stalker.
	var damaged := [0]
	enemy.component_damaged.connect(func(_p, _c, _hp, _max): damaged[0] += 1)
	for _i in 4:
		EntityAttack.hit_mecha(stalker, enemy, 1, 2)
	check(enemy.most_recent_attacker == stalker and enemy.under_fire_timer > 0.0, "the NPC knows it's under attack")
	# Whatever it was after before the world froze, it re-picks now.
	enemy.valid_target = false
	enemy._last_target_eval_ms = -100000
	enemy.check_for_targets(2000, 2000)
	check(enemy.valid_target == stalker, "the NPC targets the Stalker")
	check(damaged[0] > 0, "the bites damaged the NPC")


func _test_entities_hear() -> void:
	var stalker: Stalker = _stalkers()[0]
	stalker.set_pause(false)
	stalker.lose_target()
	_scene._on_mecha_made_sound({
		"volume_type": "loud", "type": "gunshot", "source": null,
		"position": stalker.global_position + Vector2(600, 0), "max_distance": 1500.0,
	})
	check_eq(stalker.state, Stalker.State.INVESTIGATE, "the Stalker goes to look")
	stalker.set_pause(true)


func _test_entities_freeze() -> void:
	for stalker in _stalkers():
		stalker.paused = false
	_scene.set_mechas_block_status(true)
	check(_stalkers().all(func(s): return s.paused), "every Entity is frozen with the mechas")
	_player().set_pause(false)  # the freeze includes the player; later cases need it moving


func _test_entity_kill() -> void:
	var stalker: Stalker = _stalkers()[0]
	var kills_before: int = _scene.player_kills.size()
	stalker.take_hit(100.0, 5, Vector2.ZERO, {"body": _player(), "name": "Player"})
	check(stalker.is_dead, "the Stalker died")
	check(not _scene.get_entities().has(stalker), "it's off the scene's Entity list")
	check(_scene.player_kills.size() == kills_before + 1 and _scene.player_kills[-1] == "Stalker", "the kill counts for the player")
	check_eq(_scene.ExpeditionDirector.entity_kills, 1, "the director counts it")


func _test_carcass_loot() -> void:
	await wait_frames(2)  # carcasses land a frame after a death (the previous case's)
	var stalker: Stalker = _stalkers()[0]
	var where := stalker.global_position
	var carcasses_before: int = _scene.Carcasses.get_child_count()
	var ref: WeakRef = weakref(stalker)
	stalker.take_hit(100.0, 5, Vector2.ZERO, {"body": _player(), "name": "Player"})
	await wait_frames(2)
	check(_scene.Carcasses.get_child_count() == carcasses_before + 1, "a carcass is left behind")
	check(ref.get_ref() == null, "the Stalker itself is gone (the carcass is the corpse)")
	var carcass: Carcass = _scene.Carcasses.get_children()[-1]
	check(carcass.global_position.distance_to(where) < 1.0, "where it died")
	check(not carcass.inventory.is_empty(), "with bio salvage in it")
	check(carcass.inventory.get_stacks().all(func(s): return "bio" in s.item.tags), "only bio salvage")
	var cargo: Inventory = _player().mech_inventory
	var cargo_before := cargo.get_stacks().size()
	var take_all := _action("inventory", "take_all")
	var ctx := {"type": "inventory", "inventory": carcass.inventory}
	check(take_all["visible_if"].call(ctx), "Take all offered on the carcass")
	take_all["run"].call(ctx)
	check(cargo.get_stacks().size() > cargo_before, "the bio salvage is in the cargo")
	check(_scene.Carcasses.get_index() < _scene.Mechas.get_index(), "carcasses are drawn under the mechas")


# A bullet kills from inside the physics engine's collision callback (its
# Area2D's body_shape_entered), where adding a carcass (it has its own
# interact area) straight away is an engine error. Same here, with a plain
# Area2D doing the killing.
func _test_kill_in_collision() -> void:
	await wait_frames(2)  # carcasses land a frame after a death (earlier cases')
	var stalker: Stalker = _stalkers()[0]
	var carcasses_before: int = _scene.Carcasses.get_child_count()
	var player := _player()
	# Weak: the Stalker is freed once its carcass takes over.
	var ref: WeakRef = weakref(stalker)
	var killer := Area2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 60.0
	killer.add_child(shape)
	killer.global_position = stalker.global_position
	killer.body_entered.connect(func(body):
		if body == ref.get_ref():
			body.take_hit(100.0, 5, Vector2.ZERO, {"body": player, "name": "Player"}))
	_scene.add_child(killer)
	var died := await wait_until(func(): return ref.get_ref() == null or ref.get_ref().is_dead, 2.0)
	check(died, "killed from inside a collision callback")
	await wait_frames(2)
	check(_scene.Carcasses.get_child_count() == carcasses_before + 1, "its carcass still appears")
	killer.queue_free()


# ---- Abandoning ----

func _test_pause() -> void:
	var pause = _scene.PauseMenu
	var player := _player()
	pause.toggle_pause()
	check(pause.is_paused(), "the pause menu opens")
	check(player.paused, "the player is frozen while paused")
	check(not MouseManager.is_aiming(), "the mouse is a pointer in the menu")
	pause._on_Resume_pressed()
	check(not pause.is_paused() and not player.paused, "Resume goes back to the fight")
	check(MouseManager.is_aiming(), "aiming again")


# Quitting from the pause menu warns first, then leaves (the scene change
# frees the Expedition, which abandons the run).
func _test_abandon() -> void:
	check(PlayerProgress.is_in_expedition(), "in a run")
	var pause = _scene.PauseMenu
	pause.toggle_pause()
	pause._on_Quit_pressed()
	check(pause.QuitWarning.visible and "lost" in pause.QuitWarning.text, "the first Quit warns what will be lost")
	check(TransitionManager.captured.is_empty(), "and doesn't leave yet")
	pause._on_Quit_pressed()
	check_eq(TransitionManager.captured, ["res://game/start_menu/StartMenu.tscn"], "the second Quit leaves for the main menu")
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
