extends CanvasLayer
class_name ExtractionSummary

# Shown after a successful extraction in Expedition: what the player brought
# home (cargo), kills this run, and how the mission went. Continue emits
# `continued`; Expedition then returns to the main menu.

signal continued

@onready var title_label: Label = $Center/Panel/Box/Title
@onready var body_label: Label = $Center/Panel/Box/Body
@onready var continue_button: Button = $Center/Panel/Box/Continue


func _ready() -> void:
	hide()
	continue_button.pressed.connect(_on_continue_pressed)


# cargo: item names (PlayerProgress.describe_cargo); kills: player kills this
# run; mission: MissionManager.current_mission (may be null).
func show_summary(cargo: Array, kills: int, mission) -> void:
	title_label.text = "EXTRACTION COMPLETE"
	body_label.text = format_summary(cargo, kills, mission)
	MouseManager.force_pointer(true)
	show()
	continue_button.grab_focus()


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


func _on_continue_pressed() -> void:
	AudioManager.play_sfx("confirm")
	continue_button.disabled = true
	continued.emit()
