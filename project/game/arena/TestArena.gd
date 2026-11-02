extends "res://game/expedition/Expedition.gd"

# TestArena: a small block (database/maps/test_arena.tscn) for trying NPC
# navigation, vehicles and buildings, opened from the main menu's Arena Mode
# button. It runs on Expedition's systems (route grid, vehicle field, NPC
# behaviour) without its stakes: nothing is lost on death or when leaving, and
# extracting just goes back to the main menu. There is no director and there
# are no Entities. One NPC of each generic design is put on the map, plus
# EXTRA_TANKS more of the tank build; an NPC that dies or extracts is replaced
# by one of the same design RESPAWN_TIME s later, at a random spawn zone.

const RESPAWN_TIME := 5.0
const EXTRA_TANKS := 1

# Enemy -> the design it was made from, for its replacement.
var _designs := {}
var _next_name := 0


func _ready() -> void:
	FrameSpikeDetector.mark("scene_load:TestArena")
	randomize()
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)
	_setup_exits()
	_setup_triggers()
	_setup_wrecks()
	_setup_entities()
	_add_player()
	_setup_heatmap()
	IntroAnimation.play("Entrance")
	await _prewarm_fx()
	_spawn_lineup()
	set_mechas_block_status(true)
	if Debug.get_setting("skip_intro"):
		await get_tree().create_timer(.01).timeout
		IntroAnimation.stop_animation()
	_setup_mission()


# One NPC of each generic design, and extra tanks.
func _spawn_lineup() -> void:
	var tank_design := {}
	for npc in NPCManager.NPCS:
		var design: Dictionary = NPCManager.get_design_data(npc)
		if _spawn(design).movement_type == "tank":
			tank_design = design
	if not tank_design.is_empty():
		for i in EXTRA_TANKS:
			_spawn(tank_design)


func _spawn(design: Dictionary, pos = null) -> Mecha:
	var enemy := add_enemy(design, "Test_%d" % _next_name, pos)
	_next_name += 1
	_designs[enemy] = design
	return enemy


# ---- Expedition overrides: no stakes ----

func _begin_stakes() -> void:
	pass


func _on_player_lost_health() -> void:
	ShaderEffects.damage_burst_effect()


func _on_player_destroyed() -> String:
	return "TEST ARENA"


func _show_death_screen(game_over_text: String) -> void:
	GameOver.killed(game_over_text)


func _on_player_extracted(_mecha) -> void:
	_remove_extracted_player()
	TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")


func _setup_mission() -> void:
	var mission = MissionData.new()
	mission.mission_name = "Test Arena"
	mission.add_objective("extract", "Reach an exit to leave", 1)
	MissionManager.start_default_mission(mission)


# A dead or extracted NPC is replaced by one of the same design.
func _before_mecha_removed(mecha) -> void:
	super._before_mecha_removed(mecha)
	if mecha == player or not _designs.has(mecha):
		return
	var design: Dictionary = _designs[mecha]
	_designs.erase(mecha)
	await get_tree().create_timer(RESPAWN_TIME, false).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var zones := get_spawn_zones()
	_spawn(design, zones.pick_random().global_position if not zones.is_empty() else null)
