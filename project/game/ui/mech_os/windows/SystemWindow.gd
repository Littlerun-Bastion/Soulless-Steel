extends MechWindow
class_name SystemWindow

## SYS: settings, controls, save and quit.
## Works on the options Profile already saves (volume, fullscreen, screen
## shake), so changes apply at once and persist. CRT and UI-scale settings
## from the spec wait until those options exist.

const VOLUME_STEP := 0.1
const AUDIO := [
	{"label": "MASTER", "option": "master_volume"},
	{"label": "MUSIC", "option": "bgm_volume"},
	{"label": "EFFECTS", "option": "sfx_volume"},
]
const TOGGLES := [
	{"label": "FULLSCREEN", "option": "fullscreen"},
	{"label": "SCREEN SHAKE", "option": "screen_shake"},
]
## Input actions shown under CONTROLS (missing ones are skipped).
const CONTROLS := [
	{"label": "FREE CURSOR", "action": "free_cursor"},
	{"label": "INTERACT", "action": "interact"},
	{"label": "CARGO", "action": "toggle_inventory"},
	{"label": "MESSENGER", "action": "toggle_messenger"},
	{"label": "LEFT ARM", "action": "arm_weapon_left_shoot"},
	{"label": "RIGHT ARM", "action": "arm_weapon_right_shoot"},
	{"label": "RELOAD MODE", "action": "reload_mode"},
]
const QUIT_CONFIRM := "CONFIRM: QUIT ABANDONS THE EXPEDITION"

var _volume_rows: Dictionary = {}  # option -> {"bar": StatBar, "value": Label}
var _toggle_buttons: Dictionary = {}  # option -> Button
var quit_button: Button


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	var column := MechUI.vbox(&"PaneStack")
	content.add_child(column)

	var area := MechUI.scroll_box(&"StatsColumn")
	column.add_child(area[0])
	var sections: VBoxContainer = area[1]
	sections.add_child(_section("DISPLAY", _toggle_rows()))
	sections.add_child(_section("AUDIO", _volume_rows_list()))
	sections.add_child(_section("CONTROLS", _control_rows()))

	var actions := MechUI.hbox(&"BarRow")
	var save := MechUI.button("SAVE")
	save.pressed.connect(_on_save_pressed)
	quit_button = MechUI.button("QUIT TO DESKTOP")
	quit_button.pressed.connect(_on_quit_pressed)
	actions.add_child(save)
	actions.add_child(MechUI.spacer())
	actions.add_child(quit_button)
	column.add_child(MechUI.pane(&"PaneFooter", actions))
	_refresh()


## Sets a volume option (0..1), applies it to its bus and saves.
func set_volume(option: String, value: float) -> void:
	value = clampf(snappedf(value, VOLUME_STEP), 0.0, 1.0)
	Profile.set_option(option, value, true)
	var buses := {"master_volume": AudioManager.MASTER_BUS,
			"bgm_volume": AudioManager.BGM_BUS, "sfx_volume": AudioManager.SFX_BUS}
	AudioManager.set_bus_volume(buses[option], value)
	_refresh()


func set_toggle(option: String, enabled: bool) -> void:
	Profile.set_option(option, enabled, true)
	if option == "fullscreen":
		Global.apply_window_mode()
	_refresh()


# ---- building -----------------------------------------------------------

func _section(title: String, rows: Array) -> VBoxContainer:
	var group := MechUI.vbox(&"StatGroup")
	group.add_child(MechUI.label(&"LabelMetaBright", title))
	group.add_child(HSeparator.new())
	for row in rows:
		group.add_child(row)
	return group


func _toggle_rows() -> Array:
	var rows := []
	for toggle in TOGGLES:
		var row := MechUI.hbox()
		row.add_child(MechUI.label(&"LabelMeta", toggle.label))
		row.add_child(MechUI.spacer())
		var button := MechUI.button("", &"Tab")
		button.toggle_mode = true
		button.toggled.connect(func(on): set_toggle(toggle.option, on))
		row.add_child(button)
		_toggle_buttons[toggle.option] = button
		rows.append(row)
	return rows


func _volume_rows_list() -> Array:
	var rows := []
	for audio in AUDIO:
		var row := MechUI.vbox(&"StatRow")
		var line := MechUI.hbox(&"BarRow")
		var name_label := MechUI.label(&"LabelMeta", audio.label)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := MechUI.label(&"LabelBody")
		var down := MechUI.button("-")
		down.pressed.connect(func(): set_volume(audio.option, Profile.get_option(audio.option) - VOLUME_STEP))
		var up := MechUI.button("+")
		up.pressed.connect(func(): set_volume(audio.option, Profile.get_option(audio.option) + VOLUME_STEP))
		line.add_child(name_label)
		line.add_child(value)
		line.add_child(down)
		line.add_child(up)
		var bar := StatBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		row.add_child(bar)
		_volume_rows[audio.option] = {"bar": bar, "value": value}
		rows.append(row)
	return rows


func _control_rows() -> Array:
	var rows := []
	for control in CONTROLS:
		if not InputMap.has_action(control.action):
			continue
		var row := MechUI.hbox()
		row.add_child(MechUI.label(&"LabelMeta", control.label))
		row.add_child(MechUI.spacer())
		row.add_child(MechUI.label(&"LabelBody", MechUI.key_name(control.action)))
		rows.append(row)
	return rows


# ---- behaviour ----------------------------------------------------------

func _refresh() -> void:
	for option in _volume_rows:
		var value := float(Profile.get_option(option))
		_volume_rows[option].bar.ratio = value
		_volume_rows[option].value.text = "%d%%" % roundi(value * 100.0)
	for option in _toggle_buttons:
		var on := bool(Profile.get_option(option))
		var button: Button = _toggle_buttons[option]
		button.set_pressed_no_signal(on)
		button.text = "ON" if on else "OFF"


func _on_save_pressed() -> void:
	FileManager.save_game()
	MechLog.write("SYS", "Profile saved")
	AudioManager.play_sfx("confirm")


# Mid-expedition, quitting abandons the run: the first click only asks.
func _on_quit_pressed() -> void:
	if PlayerProgress.is_in_expedition() and quit_button.text != QUIT_CONFIRM:
		quit_button.text = QUIT_CONFIRM
		AudioManager.play_sfx("back")
		return
	FileManager.save_and_quit()
