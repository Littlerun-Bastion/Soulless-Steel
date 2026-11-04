extends "res://game/expedition/Expedition.gd"

# TestArena: a small block (database/maps/test_arena.tscn) for trying NPC
# navigation, vehicles and buildings, opened from the main menu's Arena Mode
# button. It runs on Expedition's systems (route grid, vehicle field, NPC
# behaviour) without its stakes: nothing is lost on death or when leaving, and
# extracting just goes back to the main menu. There is no director and there
# are no Entities. One NPC of each generic design is put on the map, plus
# EXTRA_TANKS more of the tank build; an NPC that dies or extracts is replaced
# by one of the same design RESPAWN_TIME s later, at a random spawn zone.
#
# F5 (debug_5) opens a weapon picker: every shoulder weapon, with buttons to
# fit it to the player's left or right shoulder, and every internal bay part
# with a FIT button (free the cursor to click).

const RESPAWN_TIME := 5.0
const EXTRA_TANKS := 1
## Members of the squad the arena spawns (not replaced when they die), and
## companions the player starts with (Expedition.add_companion; not replaced
## either).
const SQUAD_SIZE := 2
const STARTING_COMPANIONS := 1
const MECH_THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const PICKER_LAYER := 5
const PICKER_MARGIN := 40.0

# Enemy -> the design it was made from, for its replacement.
var _designs := {}
var _next_name := 0
var _weapon_picker: CanvasLayer = null


func _ready() -> void:
	FrameSpikeDetector.mark("scene_load:TestArena")
	randomize()
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)
	_setup_sight_lighting()
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


# One NPC of each generic design, with the personalities dealt round so every
# type is on the map; extra tanks; one squad (SQUAD_SIZE), tagged; and the
# player's starting companions.
func _spawn_lineup() -> void:
	var tank_design := {}
	var types: Array = NPCManager.PERSONALITY_WEIGHTS.keys()
	var k := 0
	for npc in NPCManager.NPCS:
		var design: Dictionary = NPCManager.get_design_data(npc, types[k % types.size()])
		k += 1
		if _spawn(design).movement_type == "tank":
			tank_design = design
	if not tank_design.is_empty():
		for i in EXTRA_TANKS:
			_spawn(tank_design)
	add_squad(SQUAD_SIZE, "Squad")
	for i in STARTING_COMPANIONS:
		add_companion()


func _spawn(design: Dictionary, pos = null) -> Mecha:
	var enemy := add_enemy(design, "Test_%d" % _next_name, pos)
	_next_name += 1
	_designs[enemy] = design
	return enemy


# ---- Weapon picker ----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_5"):
		toggle_weapon_picker()
		get_viewport().set_input_as_handled()


func toggle_weapon_picker() -> void:
	if is_instance_valid(_weapon_picker):
		_weapon_picker.queue_free()
		_weapon_picker = null
		return
	_weapon_picker = CanvasLayer.new()
	_weapon_picker.layer = PICKER_LAYER
	var root := Control.new()
	root.theme = MECH_THEME
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(PICKER_MARGIN, PICKER_MARGIN)
	_weapon_picker.add_child(root)
	var rows := MechUI.vbox(&"ListRows")
	rows.add_child(MechUI.label(&"LabelMetaBright", "SHOULDER WEAPONS · F5"))
	var names: Array = PartManager.get_parts("shoulder_weapon").keys()
	names.sort()
	names.append(false)
	for part_name in names:
		var row := MechUI.hbox(&"BarRow")
		var name_label := MechUI.label(&"LabelBody", str(part_name) if part_name else "EMPTY")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		for side in [Mecha.SIDE.LEFT, Mecha.SIDE.RIGHT]:
			var button := MechUI.button("L" if side == Mecha.SIDE.LEFT else "R")
			button.pressed.connect(equip_shoulder_weapon.bind(part_name, side))
			row.add_child(button)
		rows.add_child(row)
	rows.add_child(MechUI.label(&"LabelMetaBright", "INTERNAL BAY"))
	var internals: Array = PartManager.get_parts("internal").keys()
	internals.sort()
	internals.append(false)
	for part_name in internals:
		var row := MechUI.hbox(&"BarRow")
		var name_label := MechUI.label(&"LabelBody", str(part_name) if part_name else "EMPTY")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var button := MechUI.button("FIT")
		button.pressed.connect(equip_internal.bind(part_name))
		row.add_child(button)
		rows.add_child(row)
	root.add_child(MechUI.pane(&"HudPanel", rows))
	add_child(_weapon_picker)


# Fits a shoulder weapon (false: none) to the player.
func equip_shoulder_weapon(part_name, side: int) -> void:
	if not is_instance_valid(player):
		return
	player.cancel_designating()
	player.set_shoulder_weapon(part_name, side)
	player.refresh_dynamic_components()


# Fits an internal bay part (false: none) to the player, with full charges.
func equip_internal(part_name) -> void:
	if not is_instance_valid(player):
		return
	player.cancel_internal()
	player.set_internal(part_name)


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
