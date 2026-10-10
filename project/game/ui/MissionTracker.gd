extends VBoxContainer
class_name MissionTracker

# HUD panel (top-right) showing the active mission and its objectives with
# progress, e.g. "[ ] ELIMINATE ENEMIES  1/3". Follows MissionManager's
# signals, so it updates as kills and extraction are reported. Hidden while
# there's no mission.

const DONE_COLOR := Color(0.55, 0.55, 0.55)

@onready var title_label: Label = $Title
@onready var objective_list: VBoxContainer = $Objectives


func _ready() -> void:
	MissionManager.mission_started.connect(_on_mission_changed)
	MissionManager.objective_updated.connect(_on_mission_changed)
	MissionManager.mission_completed.connect(_on_mission_changed)
	refresh()


func refresh() -> void:
	var mission = MissionManager.current_mission
	visible = mission != null
	if mission == null:
		return
	var title: String = mission.mission_name
	if mission.is_contract:
		title = "CONTRACT: " + title
	if mission.completed:
		title += "  [COMPLETE]"
	title_label.text = title

	for child in objective_list.get_children():
		objective_list.remove_child(child)
		child.queue_free()
	for obj in mission.objectives:
		var line := Label.new()
		line.theme = title_label.theme
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.text = format_objective(obj)
		if obj.completed:
			line.modulate = DONE_COLOR
		objective_list.add_child(line)


static func format_objective(obj) -> String:
	var mark := "[X]" if obj.completed else "[ ]"
	var text: String = "%s %s" % [mark, obj.description]
	if obj.target_amount > 1:
		text += "  %d/%d" % [mini(obj.current_amount, obj.target_amount), obj.target_amount]
	return text


func _on_mission_changed(_what) -> void:
	refresh()
