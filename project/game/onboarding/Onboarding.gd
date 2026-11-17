class_name Onboarding
extends "res://game/expedition/Expedition.gd"

const SCENE_PATH := "res://game/onboarding/Onboarding.tscn"
const MENU_PATH := "res://game/start_menu/StartMenu.tscn"
const STAGE := "onboarding"
const DONE_FLAG := "onboarding_done"
const TROBAIRITZ := "Trobairitz"
const TROBAIRITZ_DEAD := "trobairitz_dead"
const CALM_NOISE_QUALITY := 5000.0

@export_multiline var boot_text := "\n".join([
	"SURFACE ACTIVITY VEHICLE NEURALOS - EMERGENCY RESTART",
	"HunterOS ver. 1.02 LN // RECOVERY MODE",
	"LAST SESSION ........... TERMINATED ABNORMALLY",
	"PILOT VITALS ........... UNSTABLE",
	"HULL INTEGRITY ......... CRITICAL",
	"PRIMARY SYSTEMS ........ OFFLINE",
	"SAFETY FLAG ............ RAISED (AUTO)",
	"DISTRESS BEACON ........ BROADCASTING",
	"---Waiting for a reply---",
])
@export_multiline var boot_card := "SURFACE ACTIVITY VEHICLE NEURALOS - EMERGENCY RESTART\n\n\n\nHold on, Pilot. Someone may be listening."
@export var boot_commands: Array[String] = ["/startup --recovery", "/diag --all", "/beacon --broadcast"]
@export var boot_text_inset := Vector2(100, 72)

@onready var TrobairitzStart: Marker2D = $TrobairitzStart

var trobairitz: Mecha = null


static func is_due() -> bool:
	return StoryDirector.get_flag(DONE_FLAG, true) == false


func _ready() -> void:
	FrameSpikeDetector.mark("scene_load:Onboarding")
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(CALM_NOISE_QUALITY, CALM_NOISE_QUALITY, 5.0)
	_setup_sight_lighting()
	_setup_exits()
	_setup_triggers()
	_setup_wrecks()
	_setup_entities()
	_add_player()
	player.keeps_view_in_scenes = true
	PlayerHUD.go_dark()
	player.systems_repaired.connect(PlayerHUD.boot)
	_setup_heatmap()
	player.hides_flag_marker = true
	player.cripple_systems()
	_add_trobairitz()
	IntroAnimation.inset_text(boot_text_inset)
	IntroAnimation.play_retold("Entrance", boot_text, boot_card, boot_commands)
	await _prewarm_fx()
	set_mechas_block_status(true)
	if Debug.get_setting("skip_intro"):
		await get_tree().create_timer(.01).timeout
		IntroAnimation.stop_animation()


func _add_trobairitz() -> void:
	var design = NPCManager.get_design_data(NPCManager.get_special_npc(TROBAIRITZ))
	trobairitz = add_enemy(design, TROBAIRITZ, TrobairitzStart.global_position)
	trobairitz.hides_debug_state = true
	trobairitz.component_damaged.connect(_on_trobairitz_damaged)


func _on_trobairitz_damaged(_part_name, _component_name, _hp, _max_hp) -> void:
	if trobairitz.get_last_attacker() != player:
		return
	trobairitz.component_damaged.disconnect(_on_trobairitz_damaged)
	if is_instance_valid(current_stage):
		current_stage.abort.call_deferred()


func _leave_body(mecha) -> void:
	if mecha == trobairitz:
		StoryDirector.set_flag(TROBAIRITZ_DEAD, true)
	super(mecha)


func _on_IntroAnimation_animation_ending() -> void:
	super()
	ShaderEffects.end_transitions()
	var stage := play_stage(STAGE)
	if stage != null:
		stage.finished.connect(_setup_mission, CONNECT_ONE_SHOT)
		stage.finished.connect(_stop_hiding_the_flag, CONNECT_ONE_SHOT)


func _stop_hiding_the_flag() -> void:
	if is_instance_valid(player):
		player.hides_flag_marker = false


func _setup_mission() -> void:
	var mission := MissionData.new()
	mission.mission_name = "Get to Safety"
	mission.add_objective("extract", "Reach an exit and extract", 1)
	MissionManager.start_default_mission(mission)


func _on_player_extracted(_mecha) -> void:
	StoryDirector.set_flag(DONE_FLAG, true)
	MissionManager.report_extraction()
	_remove_extracted_player()
	TransitionManager.transition_to(MENU_PATH, "Rebooting System...")


func _on_player_destroyed() -> String:
	return ""


func _show_death_screen(_game_over_text: String) -> void:
	TransitionManager.transition_to(SCENE_PATH, "Rebooting System...")
