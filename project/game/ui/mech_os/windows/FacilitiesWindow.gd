extends MechWindow
class_name FacilitiesWindow

## FAC: the Hangar's facilities (Facilities). Hangar only.
## One section per facility: its level, what it does now and at the next
## level, what that costs (materials had / needed, credits) and UPGRADE, or
## why it can't be bought yet.

var upgrade_buttons: Dictionary = {}  # facility id -> Button
var reason_labels: Dictionary = {}    # facility id -> Label

var _sections: Dictionary = {}        # facility id -> VBoxContainer (rebuilt on refresh)
var _refresh_queued := false


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	var area := MechUI.scroll_box(&"StatsColumn")
	content.add_child(area[0])
	var column: VBoxContainer = area[1]
	for id in Facilities.ALL:
		var section := MechUI.vbox(&"StatGroup")
		column.add_child(section)
		_sections[id] = section
	PlayerProgress.facilities_changed.connect(_queue_refresh)
	PlayerProgress.materials_changed.connect(_queue_refresh.unbind(1))
	PlayerProgress.money_changed.connect(_queue_refresh.unbind(1))
	refresh()


func refresh() -> void:
	_refresh_queued = false
	for id in Facilities.ALL:
		_fill(id)


## Every text in one facility's section (tests).
func get_text(id: String) -> String:
	var lines := []
	for label in _sections[id].find_children("*", "Label", true, false):
		if not label.is_queued_for_deletion() and label.text != "":
			lines.append(label.text)
	return "\n".join(lines)


func _fill(id: String) -> void:
	var section: VBoxContainer = _sections[id]
	MechUI.clear(section)
	var at := Facilities.level(id)
	section.add_child(MechUI.label(&"LabelMetaBright", "%s · %s" % [Facilities.display_name(id).to_upper(), Facilities.level_name(at)]))
	section.add_child(HSeparator.new())
	section.add_child(_row("NOW", Facilities.describe(id, at)))
	var cost := Facilities.next_cost(id)
	if not cost.is_empty():
		section.add_child(_row("NEXT · " + Facilities.level_name(at + 1), Facilities.describe(id, at + 1)))
		for material_id in Materials.ids():
			if cost.materials.has(material_id):
				var have := PlayerProgress.get_material_count(material_id)
				section.add_child(_row(Materials.display_name(material_id).to_upper(),
						"%d / %d" % [have, cost.materials[material_id]], have >= cost.materials[material_id]))
		section.add_child(_row("CREDITS", "%d / %d CT" % [int(PlayerProgress.get_money()), cost.credits],
				PlayerProgress.can_afford(cost.credits)))

	var footer := MechUI.hbox(&"BarRow")
	var reason := Facilities.upgrade_block_reason(id)
	var reason_label := MechUI.label(&"LabelMeta", reason)
	reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(reason_label)
	var button := MechUI.button("UPGRADE" if at > 0 else "BUILD", &"ButtonPrimary")
	button.disabled = reason != ""
	button.visible = not cost.is_empty()
	button.pressed.connect(_on_upgrade_pressed.bind(id))
	footer.add_child(button)
	section.add_child(footer)
	upgrade_buttons[id] = button
	reason_labels[id] = reason_label


func _row(title: String, value: String, enough := true) -> HBoxContainer:
	var row := MechUI.hbox()
	row.add_child(MechUI.label(&"LabelMeta", title))
	row.add_child(MechUI.spacer())
	row.add_child(MechUI.label(&"LabelBody" if enough else &"Badge", value))
	return row


func _on_upgrade_pressed(id: String) -> void:
	if not Facilities.upgrade(id):
		AudioManager.play_sfx("back")
		refresh()
		return
	AudioManager.play_sfx("confirm")
	MechLog.write("FAC", "%s upgraded to %s" % [Facilities.display_name(id), Facilities.level_name(Facilities.level(id))])
	if id == Facilities.STASH:
		MechOS.refresh_inventory_windows()  # the stash grid grew
	refresh()


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()
