extends "res://game/combat/CombatScene.gd"

# Arena is the ladder game mode: a small map loaded by name through
# ArenaManager, a fixed set of opponents (Challenge / Exhibition / Tutorial),
# and a payout screen on extraction. Expedition (game/expedition/) is the
# big-map living-world mode.
#
# Combat plumbing shared with Expedition (effects, deaths, pause, extraction,
# triggers, intro, prewarm, debug cam) lives in game/combat/CombatScene.gd.


var is_tutorial := false
var trigger_data


func _ready():
	randomize()

	setup_arena()

	add_player()
	if ArenaManager.mode == "Challenge":
		for enemy in ArenaManager.current_challengers:
			var enemy_design = NPCManager.get_design_data(NPCManager.get_special_npc(enemy))
			add_enemy(enemy_design, enemy)
	elif ArenaManager.mode == "Exhibition":
		for enemy in ArenaManager.exhibitioner_count:
			var enemy_design = NPCManager.get_design_data(NPCManager.get_random_npc())
			add_enemy(enemy_design, enemy)
	elif ArenaManager.mode == "Tutorial":
		var enemy_design = NPCManager.get_design_data(NPCManager.get_random_npc())
		add_enemy(enemy_design, 1)

	_setup_exits()

	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)

	set_mechas_block_status(true)
	_setup_heatmap()

	if Debug.get_setting("use_debug_cam"):
		activate_debug_cam()
	setup_inventory_layer(player)
	_setup_mission()

	if is_tutorial:
		IntroAnimation.play("simEntrance")
	else:
		IntroAnimation.play("Entrance")

	# Compile FX shader pipelines while the intro covers the screen and all
	# mechas are frozen, so the first shot doesn't stall (see CombatScene).
	await _prewarm_fx()

	# Must come after the freeze — stop_animation fires the ending signal
	# that unfreezes everyone.
	if Debug.get_setting("skip_intro"):
		await get_tree().create_timer(.01).timeout
		IntroAnimation.stop_animation()


func setup_arena():
	var arena_data = ArenaManager.get_current_map()

	is_tutorial = arena_data.is_tutorial

	var data_bg = arena_data.get_bg()
	$BG.texture = data_bg.texture
	$BG.position = data_bg.position
	$BG.scale = data_bg.scale

	for child in arena_data.get_bushes():
		$Bushes.add_child(child.duplicate(7))
	for child in arena_data.get_props():
		$Props.add_child(child.duplicate(7))
	for child in arena_data.get_walls():
		$Walls.add_child(child.duplicate(7))
	for child in arena_data.get_start_positions():
		$StartPositions.add_child(child.duplicate(7))
	for child in arena_data.get_exits():
		$Exits.add_child(child.duplicate(7))
	for child in arena_data.get_trees():
		$Trees.add_child(child.duplicate(7))
	for child in arena_data.get_buildings():
		$Buildings.add_child(child.duplicate(7))
	for child in arena_data.get_texts():
		$Texts.add_child(child.duplicate(7))
	for child in arena_data.get_triggers():
		var obj = child.duplicate(7)
		$Triggers.add_child(obj)
		obj.connect("trigger_entered",Callable(self,"_on_player_trigger_entered"))

	$NavigationPolygon.navpoly = arena_data.get_navigation_polygon()

func setup_inventory_layer(_player) -> void:
	# Get the Control node that actually has the InventoryUI.gd script
	# Wire up data refs
	player.mech_inventory = PlayerProgress.get_mech_inventory()


func add_player():
	player = PLAYER.instantiate()
	Mechas.add_child(player)
	player.setup(self)
	player.position = get_start_position(0)
	_connect_mecha_signals(player)
	player.connect("lost_health", Callable(self,"_on_player_lost_health"))
	player.connect("mecha_extracted", Callable(self,"_on_player_mech_extracted"))
	all_mechas.push_back(player)
	PlayerHUD.setup(player, all_mechas)
	MechOS.set_player(player)


func add_enemy(design_data, enemy_name):
	var enemy = ENEMY.instantiate()
	Mechas.add_child(enemy)
	enemy.position = get_random_start_position([0])
	_connect_mecha_signals(enemy)
	all_mechas.push_back(enemy)
	enemy.setup(self, design_data, enemy_name)


func get_random_start_position(exclude_idx := []):
	var offset = 500
	var rand_offset = Vector2(randf_range(-offset, offset), randf_range(-offset, offset))
	var n_pos = $StartPositions.get_child_count()
	var idx = randi()%n_pos
	while exclude_idx.has(idx):
		idx = randi()%n_pos
	return get_start_position(idx) + rand_offset


func get_start_position(idx):
	return $StartPositions.get_child(idx).position


func get_random_position():
	var w = $BG.texture.get_width()*$BG.scale.x
	var h = $BG.texture.get_height()*$BG.scale.y
	var point = Vector2(randf_range(-w/2, w/2),\
						randf_range(-h/2, h/2)) - $BG.position
	var poly = $NavigationPolygon.navpoly.get_outline(0)
	while not Geometry2D.is_point_in_polygon(point, poly):
		point = Vector2(randf_range(-w/2, w/2),\
							randf_range(-h/2, h/2)) - $BG.position
	return point


# CombatScene hook: the tutorial runs without ambient music.
func _plays_ambience() -> bool:
	return not is_tutorial


func _on_player_mech_extracted(playerMech):
	MissionManager.report_extraction()
	if is_tutorial:
		TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")
	else:
		var right_arm_ammo_cost = 0.0
		if player.get_max_ammo("arm_weapon_right") and player.get_ammo_cost("arm_weapon_right"):
			right_arm_ammo_cost = (player.get_max_ammo("arm_weapon_right") - player.get_total_ammo("arm_weapon_right")) * player.get_ammo_cost("arm_weapon_right")

		var left_arm_ammo_cost = 0.0
		if player.get_max_ammo("arm_weapon_left") and player.get_ammo_cost("arm_weapon_left"):
			left_arm_ammo_cost = (player.get_max_ammo("arm_weapon_left") - player.get_total_ammo("arm_weapon_left")) * player.get_ammo_cost("arm_weapon_left")

		var right_shoulder_ammo_cost = 0.0
		if player.get_max_ammo("shoulder_weapon_right") and player.get_ammo_cost("shoulder_weapon_right"):
			right_shoulder_ammo_cost = (player.get_max_ammo("shoulder_weapon_right") - player.get_total_ammo("shoulder_weapon_right")) * player.get_ammo_cost("shoulder_weapon_right")

		var left_shoulder_ammo_cost = 0.0
		if player.get_max_ammo("shoulder_weapon_left") and player.get_ammo_cost("shoulder_weapon_left"):
			left_shoulder_ammo_cost = (player.get_max_ammo("shoulder_weapon_left") - player.get_total_ammo("shoulder_weapon_left")) * player.get_ammo_cost("shoulder_weapon_left")
		if Debug.get_setting("verbose_logging"):
			print("Player Extracted! Kills: " + str(player_kills))

		var total_ammo_cost = right_arm_ammo_cost + left_arm_ammo_cost + right_shoulder_ammo_cost + left_shoulder_ammo_cost

		var payout = 0
		if ArenaManager.tier == "Civ-Grade":
			payout = ArenaManager.CIV_GRADE_PAYOUT
		elif ArenaManager.tier == "Mil-Grade":
			payout = ArenaManager.MIL_GRADE_PAYOUT
		elif ArenaManager.tier == "State-Of-The-Art":
			payout = ArenaManager.SOA_GRADE_PAYOUT

		var conduct_kill_deduction = player_kills.size() * payout
		var conduct_downs_reward = player_downs.size() * payout * 0.25
		if conduct_kill_deduction > 0:
			conduct_downs_reward = 0
			payout = 0
		var conduct = conduct_downs_reward - conduct_kill_deduction

		var total_payout = (payout * 1.5) + conduct - total_ammo_cost

		ArenaManager.last_match = {
			"mode": ArenaManager.mode,
			"tier": ArenaManager.tier,
			"payout": payout,
			"total_payout": total_payout,
			"win": true,
			"downs": player_downs,
			"kills": player_kills,
			"conduct": conduct,
			"conduct_kill_deduction": conduct_kill_deduction,
			"conduct_downs_reward": conduct_downs_reward,
			"damage_taken": playerMech.max_hp - playerMech.hp,
			"right_arm_ammo_cost": right_arm_ammo_cost,
			"left_arm_ammo_cost": left_arm_ammo_cost,
			"right_shoulder_ammo_cost": right_shoulder_ammo_cost,
			"left_shoulder_ammo_cost": left_shoulder_ammo_cost,
			"total_ammo_cost": total_ammo_cost,
		}
		if ArenaManager.mode == "Exhibition" or ArenaManager.mode == "Challenge":
			# Credit now, not when the Ladder screen opens, so the payout can't
			# depend on UI. Ladder only displays last_match.
			PlayerProgress.add_money(total_payout)
			TransitionManager.transition_to("res://game/ui/ladder/Ladder.tscn", "Downloading Data...")
			ArenaManager.last_match_unread = true
		elif ArenaManager.mode == "Tutorial":
			TransitionManager.transition_to("res://StartMenu.tscn", "Downloading Data...")


#---TRIGGERS---

func tutorial1():
	var tutorial_text = PlayerHUD.get_node("SubViewportContainer/SubViewport/Tutorial")
	tutorial_text.play("t1")

func _setup_mission() -> void:
	var mission = MissionData.new()
	mission.mission_name = "Survive and Extract"
	mission.add_objective("kill", "Eliminate enemies", 3)
	mission.add_objective("extract", "Extract from the arena", 1)
	MissionManager.start_mission(mission)
