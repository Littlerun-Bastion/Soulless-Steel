extends CanvasLayer

# The observer arena's control panel, at the right of the screen, built in
# code from MechTheme variations (MechUI), as the SYS window is. It keeps
# running while the game is paused, and runs the arena's camera and the
# clicks on the map that it doesn't take itself (ObserverArena.update_camera,
# handle_world_input).
#
#   SPAWN NPC   personality type, generic design (NPCManager.NPCS: number,
#               default personality, chassis), squad size 1 to 3, skill (AUTO:
#               drawn for the type, Personality.SKILL_RANGES); PLACE NPC puts
#               one (or a squad) at each click until cancelled
#   DUMMY       PLACE DUMMY; for the selected dummy: stand or patrol (SET
#               PATROL adds a point per click), its light, firing every N s at
#               a clicked point or at the selected NPC, and its Flag
#   EVENTS      each arms one event, set off where the map is clicked next
#   TIME        pause, and the game speed
#   OVERLAYS    sight, cone, tracks, wedges, locks, sweeps, think tags,
#               barks (ObserverOverlay), and the NPCs' ai_overlay lines
#   SELECTION   what is selected, its skill (an NPC), following it (F),
#               deleting it, clearing all
# A right click or Esc ends a click mode.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const DUMMY_SCRIPT := preload("res://game/arena/observer/ObserverDummy.gd")
const LAYER := 6
const WIDTH := 400.0
const MARGIN := 16.0
const TYPES := ["scavenger", "rat", "guardian", "professional", "hunter"]
const EVENTS := [
	["CAR ALARM", "car_alarm"],
	["LOUD NOISE", "noise"],
	["ROUND AT NPC", "round"],
	["WARD", "ward"],
	["DRONE", "drone"],
	["SWEEP", "sweep"],
]
const MENU_SCENE := "res://game/start_menu/StartMenu.tscn"

var arena = null
var npc_type_index := TYPES.find("professional")
var npc_design := 0
var squad_size := 1
## The skill new NPCs get (0..1), or -1: AUTO, drawn for their type.
var spawn_skill := -1.0
## How much one press changes a skill.
const SKILL_STEP := 0.1

var _frame: PanelContainer = null
var _status: Label = null
var _buttons := {}
var _labels := {}
var _last_usec := 0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = THEME
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var area := MechUI.scroll_box(&"StatsColumn")
	_frame = MechUI.pane(&"HudPanel", area[0])
	_frame.position = Vector2(1920.0 - WIDTH - MARGIN, MARGIN)
	_frame.size = Vector2(WIDTH, 1080.0 - MARGIN * 2.0)
	root.add_child(_frame)
	var box: VBoxContainer = area[1]
	_build_header(box)
	_build_spawn(box)
	_build_dummy(box)
	_build_events(box)
	_build_time(box)
	_build_overlays(box)
	_build_selection(box)
	box.add_child(MechUI.label(&"LabelDim", "WASD / EDGES PAN (SHIFT FASTER) · WHEEL ZOOM · LMB SELECT OR PLACE · RMB CANCELS · F FOLLOW", true))
	if arena != null:
		arena.selection_changed.connect(refresh)
	_last_usec = Time.get_ticks_usec()
	refresh()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := float(now - _last_usec) / 1000000.0
	_last_usec = now
	if arena == null or not is_instance_valid(arena):
		return
	var mouse := _frame.get_viewport().get_mouse_position()
	arena.update_camera(minf(real_dt, 0.1), _frame.get_global_rect().has_point(mouse))
	_refresh_dummy_label()


func _unhandled_input(event: InputEvent) -> void:
	if arena != null and arena.handle_world_input(event):
		get_viewport().set_input_as_handled()


func npc_type() -> String:
	return TYPES[npc_type_index]


## "2 · SCAVENGER · CRAWLER_C-TYPE_CHASSIS": a generic design's number,
## default personality and chassis.
static func design_label(index: int) -> String:
	var npc: Dictionary = NPCManager.NPCS[index]
	var chassis: Array = npc.get("chassis", [])
	return "%d · %s · %s" % [index + 1, str(npc.get("personality", "")).to_upper(),
			(str(chassis[0]) if not chassis.is_empty() else "-").to_upper()]


# ---- Building ----

func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var group := MechUI.vbox(&"StatGroup")
	group.add_child(MechUI.label(&"LabelMetaBright", title))
	group.add_child(HSeparator.new())
	parent.add_child(group)
	return group


func _row(parent: VBoxContainer, title: String) -> HBoxContainer:
	var row := MechUI.hbox(&"BarRow")
	var name_label := MechUI.label(&"LabelMeta", title)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	parent.add_child(row)
	return row


func _button(key: String, text: String, on_press: Callable, toggle := false, variation := &"") -> Button:
	var button := MechUI.button(text, variation if variation != &"" else (&"Tab" if toggle else &""))
	button.toggle_mode = toggle
	button.pressed.connect(on_press)
	_buttons[key] = button
	return button


func _build_header(box: VBoxContainer) -> void:
	var row := MechUI.hbox(&"BarRow")
	var title := MechUI.label(&"LabelMetaBright", "OBSERVER ARENA")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_button("menu", "MENU", _on_menu))
	box.add_child(row)
	_status = MechUI.label(&"LabelBody", "", true)
	box.add_child(_status)


func _build_spawn(box: VBoxContainer) -> void:
	var group := _section(box, "SPAWN NPC")
	_row(group, "TYPE").add_child(_button("type", "", _cycle_type))
	_row(group, "DESIGN").add_child(_button("design", "", _cycle_design))
	var size_row := _row(group, "SQUAD SIZE")
	_labels["squad"] = MechUI.label(&"LabelBody")
	size_row.add_child(_labels["squad"])
	size_row.add_child(_button("squad_down", "-", _change_squad_size.bind(-1)))
	size_row.add_child(_button("squad_up", "+", _change_squad_size.bind(1)))
	var skill_row := _row(group, "SKILL")
	_labels["spawn_skill"] = MechUI.label(&"LabelBody")
	skill_row.add_child(_labels["spawn_skill"])
	skill_row.add_child(_button("spawn_skill_down", "-", _change_spawn_skill.bind(-SKILL_STEP)))
	skill_row.add_child(_button("spawn_skill_up", "+", _change_spawn_skill.bind(SKILL_STEP)))
	group.add_child(_button("place_npc", "PLACE NPC", _toggle_mode.bind("npc"), true))


func _build_dummy(box: VBoxContainer) -> void:
	var group := _section(box, "DUMMY")
	group.add_child(_button("place_dummy", "PLACE DUMMY", _toggle_mode.bind("dummy"), true))
	_labels["dummy"] = MechUI.label(&"LabelBody")
	group.add_child(_labels["dummy"])
	_row(group, "MOVE").add_child(_button("move", "", _with_dummy.bind(_cycle_move)))
	var patrol := _row(group, "PATROL")
	patrol.add_child(_button("set_patrol", "SET POINTS", _toggle_mode.bind("patrol"), true))
	patrol.add_child(_button("clear_patrol", "CLEAR", _with_dummy.bind(_clear_patrol)))
	_row(group, "LIGHT").add_child(_button("light", "", _with_dummy.bind(_cycle_light)))
	var fire := _row(group, "FIRE")
	fire.add_child(_button("fire", "", _with_dummy.bind(_cycle_fire)))
	fire.add_child(_button("fire_point", "SET POINT", _toggle_mode.bind("fire_point"), true))
	var every := _row(group, "EVERY")
	_labels["interval"] = MechUI.label(&"LabelBody")
	every.add_child(_labels["interval"])
	every.add_child(_button("interval_down", "-", _with_dummy.bind(_change_interval.bind(-1.0))))
	every.add_child(_button("interval_up", "+", _with_dummy.bind(_change_interval.bind(1.0))))
	_row(group, "FLAG").add_child(_button("flag", "", _with_dummy.bind(_toggle_flag), true))


func _build_events(box: VBoxContainer) -> void:
	var group := _section(box, "EVENTS AT THE CURSOR")
	for i in range(0, EVENTS.size(), 2):
		var row := MechUI.hbox(&"BarRow")
		for j in range(i, mini(i + 2, EVENTS.size())):
			var event_name: String = EVENTS[j][1]
			var button := _button("event:" + event_name, EVENTS[j][0], _toggle_mode.bind("event:" + event_name), true)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(button)
		group.add_child(row)


func _build_time(box: VBoxContainer) -> void:
	var group := _section(box, "TIME")
	var row := MechUI.hbox(&"BarRow")
	row.add_child(_button("pause", "PAUSE", _toggle_pause, true))
	var speeds: Array = arena.SPEEDS if arena != null else []
	for value in speeds:
		var speed_value: float = value
		row.add_child(_button("speed:%s" % str(speed_value), "%s×" % MechUI.fmt(speed_value), _set_speed.bind(speed_value), true))
	group.add_child(row)


func _build_overlays(box: VBoxContainer) -> void:
	var group := _section(box, "OVERLAYS")
	for entry in [["SIGHT", "show_sight"], ["CONE", "show_cone"], ["TRACKS", "show_tracks"],
			["WEDGES", "show_wedges"], ["LOCKS", "show_locks"], ["SWEEPS", "show_sweeps"], ["THINK TAGS", "show_tags"],
			["BARKS", "show_barks"]]:
		var property: String = entry[1]
		_row(group, entry[0]).add_child(_button("overlay:" + property, "", _toggle_overlay.bind(property), true))
	_row(group, "AI LINES").add_child(_button("ai_lines", "", _toggle_ai_lines, true))


func _build_selection(box: VBoxContainer) -> void:
	var group := _section(box, "SELECTION")
	_labels["selected"] = MechUI.label(&"LabelBody")
	group.add_child(_labels["selected"])
	var skill_row := _row(group, "SKILL")
	_labels["skill"] = MechUI.label(&"LabelBody")
	skill_row.add_child(_labels["skill"])
	skill_row.add_child(_button("skill_down", "-", _change_skill.bind(-SKILL_STEP)))
	skill_row.add_child(_button("skill_up", "+", _change_skill.bind(SKILL_STEP)))
	var row := MechUI.hbox(&"BarRow")
	row.add_child(_button("follow", "FOLLOW [F]", _toggle_follow, true))
	row.add_child(_button("delete", "DELETE", _delete_selected))
	row.add_child(_button("clear", "CLEAR ALL", _clear_all))
	group.add_child(row)


# ---- Behaviour ----

func _cycle_type() -> void:
	npc_type_index = (npc_type_index + 1) % TYPES.size()
	refresh()


func _cycle_design() -> void:
	npc_design = (npc_design + 1) % NPCManager.NPCS.size()
	refresh()


func _change_squad_size(step: int) -> void:
	squad_size = clampi(squad_size + step, 1, 3)
	refresh()


# AUTO (-1) below 0, then 0 to 1 in SKILL_STEPs.
func _change_spawn_skill(step: float) -> void:
	if spawn_skill < 0.0:
		spawn_skill = 0.0 if step > 0.0 else -1.0
	else:
		var next := snappedf(spawn_skill + step, SKILL_STEP)
		spawn_skill = -1.0 if next < 0.0 else minf(next, 1.0)
	refresh()


# The selected NPC's skill, overriding its type's draw.
func _change_skill(step: float) -> void:
	var npc = arena.selected_npc
	if not is_instance_valid(npc) or npc.personality == null:
		return
	npc.personality.skill = clampf(snappedf(npc.personality.skill + step, SKILL_STEP), 0.0, 1.0)
	refresh()


func _cycle_move(control) -> void:
	control.set_move((int(control.move) + 1) % DUMMY_SCRIPT.Move.size())


func _clear_patrol(control) -> void:
	control.clear_patrol()


func _cycle_light(control) -> void:
	control.set_light((int(control.light) + 1) % DUMMY_SCRIPT.Light.size())


func _cycle_fire(control) -> void:
	control.set_fire((int(control.fire) + 1) % DUMMY_SCRIPT.Fire.size())


func _change_interval(control, step: float) -> void:
	control.fire_interval = clampf(control.fire_interval + step, DUMMY_SCRIPT.MIN_INTERVAL, DUMMY_SCRIPT.MAX_INTERVAL)


func _toggle_flag(control) -> void:
	control.set_flag(not control.dummy.is_flagged())


func _toggle_pause() -> void:
	arena.set_paused(not arena.game_paused)


func _set_speed(value: float) -> void:
	arena.set_speed(value)


func _toggle_overlay(property: String) -> void:
	arena.overlay.set(property, not bool(arena.overlay.get(property)))
	refresh()


func _toggle_ai_lines() -> void:
	arena.set_ai_lines(not arena.ai_lines_on())
	refresh()


func _toggle_follow() -> void:
	arena.toggle_follow()


func _delete_selected() -> void:
	arena.remove_mecha(arena.selected)


func _clear_all() -> void:
	arena.clear_all()

func _toggle_mode(mode: String) -> void:
	arena.set_place_mode("" if arena.place_mode == mode else mode)


func _with_dummy(change: Callable) -> void:
	var control = arena.dummy_control(arena.selected_dummy)
	if control == null:
		return
	change.call(control)
	refresh()


func _on_menu() -> void:
	TransitionManager.transition_to(MENU_SCENE, "Rebooting System...")


func refresh() -> void:
	if arena == null or not is_instance_valid(arena) or _status == null:
		return
	_buttons["type"].text = npc_type().to_upper()
	_buttons["design"].text = design_label(npc_design)
	_labels["squad"].text = str(squad_size)
	_labels["spawn_skill"].text = "AUTO" if spawn_skill < 0.0 else MechUI.fmt(spawn_skill)
	var npc = arena.selected_npc
	var has_npc: bool = is_instance_valid(npc) and npc.personality != null
	_labels["skill"].text = MechUI.fmt(snappedf(npc.personality.skill, 0.01)) if has_npc else "-"
	_buttons["skill_down"].disabled = not has_npc
	_buttons["skill_up"].disabled = not has_npc
	for key in _buttons:
		if key.begins_with("event:") or key in ["place_npc", "place_dummy", "set_patrol", "fire_point"]:
			var mode: String = {"place_npc": "npc", "place_dummy": "dummy", "set_patrol": "patrol",
					"fire_point": "fire_point"}.get(key, key)
			_buttons[key].set_pressed_no_signal(arena.place_mode == mode)
		elif key.begins_with("speed:"):
			_buttons[key].set_pressed_no_signal(is_equal_approx(float(key.trim_prefix("speed:")), arena.speed))
		elif key.begins_with("overlay:"):
			var on := bool(arena.overlay.get(key.trim_prefix("overlay:")))
			_buttons[key].set_pressed_no_signal(on)
			_buttons[key].text = "ON" if on else "OFF"
	_buttons["pause"].set_pressed_no_signal(arena.game_paused)
	_buttons["ai_lines"].set_pressed_no_signal(arena.ai_lines_on())
	_buttons["ai_lines"].text = "ON" if arena.ai_lines_on() else "OFF"
	_buttons["follow"].set_pressed_no_signal(arena.following)
	_status.text = _status_text()
	_labels["selected"].text = _name_of(arena.selected)
	_refresh_dummy_label()


func _refresh_dummy_label() -> void:
	var control = arena.dummy_control(arena.selected_dummy)
	var has := control != null
	_labels["dummy"].text = ("SELECTED: " + _name_of(arena.selected_dummy)) if has else "NO DUMMY SELECTED"
	for key in ["move", "set_patrol", "clear_patrol", "light", "fire", "fire_point", "interval_down", "interval_up", "flag"]:
		_buttons[key].disabled = not has
	if not has:
		_buttons["move"].text = "-"
		_buttons["light"].text = "-"
		_buttons["fire"].text = "-"
		_buttons["flag"].text = "-"
		_labels["interval"].text = "-"
		return
	_buttons["move"].text = ["STAND", "PATROL"][control.move]
	_buttons["light"].text = ["OFF", "ON", "FLASH"][control.light]
	_buttons["fire"].text = ["OFF", "AT POINT", "AT NPC"][control.fire]
	_labels["interval"].text = "%s S" % MechUI.fmt(control.fire_interval)
	var flagged: bool = control.dummy.is_flagged()
	_buttons["flag"].set_pressed_no_signal(flagged)
	_buttons["flag"].text = "UP" if flagged else "DOWN"


func _status_text() -> String:
	var mode: String = arena.place_mode
	if mode == "":
		return "PAUSED" if arena.game_paused else "%s× SPEED" % MechUI.fmt(arena.speed)
	if mode.begins_with("event:"):
		var event_name := mode.trim_prefix("event:")
		for entry in EVENTS:
			if entry[1] == event_name:
				return "CLICK THE MAP: %s · RMB CANCELS" % entry[0]
	return "CLICK THE MAP: %s · RMB CANCELS" % {"npc": "PLACE NPC", "dummy": "PLACE DUMMY",
			"patrol": "ADD PATROL POINTS", "fire_point": "SET FIRE POINT"}.get(mode, mode.to_upper())


func _name_of(mecha) -> String:
	if not is_instance_valid(mecha):
		return "NOTHING SELECTED"
	var text: String = str(mecha.mecha_name)
	var callsign = mecha.get("callsign")
	if callsign is String and callsign != "":
		text += " · " + callsign
	return text.to_upper()
