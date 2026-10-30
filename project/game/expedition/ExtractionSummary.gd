extends CanvasLayer
class_name ExtractionSummary

# The debrief after an Expedition run, as a MechOS-style window:
#   header   EXTRACTION COMPLETE, then the exit, run time and kills
#   columns  CONTRACT (the mission and its objectives),
#            RECOVERED (what came home), DAMAGE REPORT (each part's state)
#   footer   RETURN TO HUB (emits `continued`; Expedition goes to the menu)
#
# Two ways in:
#   show_summary(...)      a real extraction.
#   show_written_off(...)  the player's mecha was destroyed. The fiction:
#                          the pilot (an AVIS Entity that doesn't know it)
#                          crawls the wreck to an exit, so this is an ordinary
#                          extraction screen, except everything in RECOVERED
#                          and DAMAGE REPORT is WRITTEN OFF. Nothing on it says
#                          the pilot died. Expedition shows it after the
#                          death fade to black.

signal continued

const WINDOW := preload("res://game/ui/mech_os/MechWindow.tscn")
const WINDOW_SIZE := Vector2(1120, 600)
const PARTS := {"core": "CORE", "head": "HEAD", "left_shoulder": "L SHOULDER",
	"right_shoulder": "R SHOULDER", "chassis": "CHASSIS"}
const STATE_WORDS := {3: "OK", 2: "DAMAGED", 1: "CRITICAL", 0: "DESTROYED", -1: "LOST"}
const WRITTEN_OFF := "WRITTEN OFF"
const BOOT_TIME := 1.5   # seconds for the screen to come back after a death
const WRITE_OFF_NOTE := "Frame beyond repair. A standard mecha has been issued. Your stash and credits are safe."

var window: MechWindow
var title_label: Label
var continue_button: Button

var _details_label: Label
var _contract_box: VBoxContainer
var _recovered_box: VBoxContainer
var _damage_box: VBoxContainer


func _ready() -> void:
	layer = 98
	_build()
	hide()


## A real extraction. cargo: item names (PlayerProgress.describe_cargo).
## details (all optional): "exit" ("EXIT C5"), "time" (seconds),
## "damage" (part -> state, from collect_damage).
func show_summary(cargo: Array, kills: int, mission, details: Dictionary = {}) -> void:
	_fill_header(kills, details)
	_fill_contract(mission)
	MechUI.clear(_recovered_box)
	if cargo.is_empty():
		_recovered_box.add_child(MechUI.label(&"LabelDim", "Nothing"))
	for item in cargo:
		_recovered_box.add_child(MechUI.label(&"LabelBody", str(item), true))
	MechUI.clear(_damage_box)
	var damage: Dictionary = details.get("damage", {})
	for part in PARTS:
		var state: int = damage.get(part, 3)
		_damage_box.add_child(_line(PARTS[part], STATE_WORDS.get(state, "OK"), state <= 1))
	MechLog.write("DEP", "Extraction complete")
	_open()


## The mecha went down: the same screen, everything written off.
## report: PlayerProgress's loss report ("mecha": part names, "cargo": item names).
func show_written_off(report: Dictionary, kills: int, mission, details: Dictionary = {}) -> void:
	_fill_header(kills, details)
	_fill_contract(mission)
	MechUI.clear(_recovered_box)
	var items: Array = report.get("cargo", [])
	if items.is_empty():
		_recovered_box.add_child(MechUI.label(&"LabelDim", "Nothing"))
	for item in items:
		_recovered_box.add_child(_line(str(item), WRITTEN_OFF, true))
	MechUI.clear(_damage_box)
	# The fitted parts by name; the frame's sections if there's no list.
	var parts: Array = report.get("mecha", [])
	if parts.is_empty():
		parts = PARTS.values()
	for part_name in parts:
		_damage_box.add_child(_line(str(part_name), WRITTEN_OFF, true))
	_damage_box.add_child(MechUI.label(&"LabelMeta", WRITE_OFF_NOTE, true))
	MechLog.write("DEP", "Frame written off", MechLog.Kind.SYSTEM, true)
	_open(true)


## Every text on the window, one per line (tests, logs).
func get_text() -> String:
	var lines := []
	for label in window.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text != "":
			lines.append(label.text)
	return "\n".join(lines)


## Each part's damage state on a live mecha (see WireframeDisplay.part_state).
static func collect_damage(mecha) -> Dictionary:
	var result := {}
	if mecha == null or not ("components" in mecha):
		return result
	for part in PARTS:
		result[part] = WireframeDisplay.part_state(mecha.components, part)
	return result


## The run as plain text (kept for logs and older tests).
static func format_summary(cargo: Array, kills: int, mission) -> String:
	var lines := []
	lines.append("Cargo secured: " + (", ".join(cargo) if not cargo.is_empty() else "nothing"))
	lines.append("Kills: %d" % kills)
	if mission != null:
		var heading: String = ("Contract: " if mission.is_contract else "Mission: ") + mission.mission_name
		heading += " - COMPLETE" if mission.completed else " - incomplete"
		lines.append("")
		lines.append(heading)
		for obj in mission.objectives:
			lines.append("  " + MissionTracker.format_objective(obj))
	return "\n".join(lines)


# ---- building -----------------------------------------------------------

func _build() -> void:
	window = WINDOW.instantiate()
	window.window_title = "DEBRIEF"
	window.min_size = WINDOW_SIZE
	add_child(window)
	window.closable = false
	window.size = WINDOW_SIZE
	window.set_focused(true)
	window.content.theme_type_variation = &"WindowContentFlush"

	var column := MechUI.vbox(&"PaneStack")
	window.content.add_child(column)

	var header := MechUI.vbox(&"TightStack")
	title_label = MechUI.label(&"LabelDisplay", "EXTRACTION COMPLETE")
	_details_label = MechUI.label(&"LabelMeta")
	header.add_child(title_label)
	header.add_child(_details_label)
	column.add_child(MechUI.pane(&"PaneHeader", header))

	var row := MechUI.hbox(&"PaneRow")
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	_contract_box = _column(row, "CONTRACT", true)
	_recovered_box = _column(row, "RECOVERED", true)
	_damage_box = _column(row, "DAMAGE REPORT", false)

	var footer := MechUI.hbox(&"BarRow")
	footer.add_child(MechUI.spacer())
	continue_button = MechUI.button("RETURN TO HUB", &"ButtonPrimary")
	continue_button.custom_minimum_size.y = 40
	continue_button.pressed.connect(_on_continue_pressed)
	footer.add_child(continue_button)
	column.add_child(MechUI.pane(&"PaneFooter", footer))


# One of the three columns: a divider on its right unless it's the last.
func _column(row: HBoxContainer, title: String, divided: bool) -> VBoxContainer:
	var holder: Control = MechUI.pane(&"PaneDivider") if divided else MechUI.vbox(&"PaneStack")
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_stretch_ratio = 1.0
	var area := MechUI.scroll_box(&"StatGroup")
	holder.add_child(area[0])
	var box: VBoxContainer = area[1]
	box.add_child(MechUI.label(&"LabelMetaBright", title))
	box.add_child(HSeparator.new())
	var lines := MechUI.vbox(&"TightStack")
	box.add_child(lines)
	row.add_child(holder)
	return lines


func _line(name_text: String, value: String, bright: bool) -> HBoxContainer:
	var line := MechUI.hbox(&"BarRow")
	var name_label := MechUI.label(&"LabelBody", name_text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name_label)
	line.add_child(MechUI.label(&"LabelMetaBright" if bright else &"LabelMeta", value))
	return line


# ---- filling ------------------------------------------------------------

func _fill_header(kills: int, details: Dictionary) -> void:
	title_label.text = "EXTRACTION COMPLETE"
	var parts := []
	if details.has("exit"):
		parts.append(str(details.exit))
	if details.has("time"):
		var total := int(details.time)
		parts.append("T+%02d:%02d" % [total / 60, total % 60])
	parts.append("%d KILL%s" % [kills, "" if kills == 1 else "S"])
	_details_label.text = " · ".join(parts)


func _fill_contract(mission) -> void:
	MechUI.clear(_contract_box)
	if mission == null:
		_contract_box.add_child(MechUI.label(&"LabelDim", "None"))
		return
	var heading: String = ("CONTRACT: " if mission.is_contract else "") + str(mission.mission_name).to_upper()
	_contract_box.add_child(MechUI.label(&"LabelBodyBright", heading, true))
	for obj in mission.objectives:
		var line := MechUI.label(&"LabelDim" if obj.completed else &"LabelBody", MissionTracker.format_objective(obj), true)
		_contract_box.add_child(line)
	_contract_box.add_child(MechUI.label(&"LabelMetaBright" if mission.completed else &"LabelMeta",
			"COMPLETE" if mission.completed else "INCOMPLETE"))


# from_black: the death fade has left the screen black (ShaderEffects sits
# above this layer), so boot the picture back in, or nothing shows and the
# button can't be seen to click.
func _open(from_black := false) -> void:
	if from_black:
		var fx := get_node_or_null("/root/ShaderEffects")
		if fx:
			fx.reset_shader_effect("arena")
			fx.play_transition(0.0, 5000.0, BOOT_TIME)
	MouseManager.force_pointer(true)
	var screen := window.get_viewport_rect().size
	window.position = ((screen - window.size) * 0.5).floor()
	continue_button.disabled = false
	show()


func _on_continue_pressed() -> void:
	AudioManager.play_sfx("confirm")
	continue_button.disabled = true
	continued.emit()
