extends MechWindow
class_name LocalWindow

## LOC: Local Pilots (LocalPilots.current). The header has the player's
## reputation and callsign: the callsign can be changed in the Hangar
## (Enter or leaving the field saves it) and is read-only in the field,
## where it shows ANONYMOUS too if the player deployed Anonymous. Below, the
## roster of the pilots in Local (Anonymous ones are never on it) and the
## whole log, newest line at the bottom. Out of the field the log is the last
## match's and the roster says so.

const ROSTER_WIDTH := 240

var _reputation: Label
var _callsign: LineEdit
var _anonymous: Label
var _roster_title: Label
var _roster: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _local: LocalPilots = null


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	var column := MechUI.vbox(&"PaneStack")
	content.add_child(column)

	var header := MechUI.hbox(&"BarRow")
	header.add_child(MechUI.label(&"LabelMeta", "REPUTATION"))
	_reputation = MechUI.label(&"LabelBodyBright")
	header.add_child(_reputation)
	header.add_child(MechUI.spacer())
	header.add_child(MechUI.label(&"LabelMeta", "CALLSIGN"))
	_callsign = LineEdit.new()
	_callsign.max_length = PlayerProgress.MAX_CALLSIGN_LENGTH
	_callsign.custom_minimum_size.x = 200
	_callsign.text_submitted.connect(_on_callsign_submitted)
	_callsign.focus_exited.connect(_on_callsign_left)
	header.add_child(_callsign)
	_anonymous = MechUI.label(&"LabelMetaBright", "ANONYMOUS")
	header.add_child(_anonymous)
	column.add_child(MechUI.pane(&"PaneHeader", header))

	var columns := MechUI.hbox(&"PaneRow")
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)
	var roster_pane := MechUI.pane(&"PaneDivider")
	roster_pane.custom_minimum_size.x = ROSTER_WIDTH
	columns.add_child(roster_pane)
	var roster_column := MechUI.vbox(&"PaneStack")
	roster_pane.add_child(roster_column)
	_roster_title = MechUI.label(&"LabelMeta")
	roster_column.add_child(MechUI.pane(&"PaneHeader", _roster_title))
	var roster_area := MechUI.scroll_box(&"TightStack")
	roster_column.add_child(roster_area[0])
	_roster = roster_area[1]

	var log_column := MechUI.vbox(&"PaneStack")
	log_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(log_column)
	log_column.add_child(MechUI.pane(&"PaneHeader", MechUI.label(&"LabelMeta", "LOG")))
	var area := MechUI.scroll_box(&"TightStack")
	_scroll = area[0]
	_list = area[1]
	log_column.add_child(_scroll)
	_empty = MechUI.label(&"LabelMeta", "NO MESSAGES")
	_list.add_child(_empty)

	PlayerProgress.local_profile_changed.connect(_refresh_header)
	_local = LocalPilots.current
	if _local != null:
		_local.message.connect(_on_message)
		_local.roster_changed.connect(_refresh_roster)
	_refresh_header()
	_refresh_roster()
	_rebuild_log()


## The roster names and log lines on show (for tests).
func get_roster() -> Array[String]:
	var names: Array[String] = []
	for child in _roster.get_children():
		if child is Label and not child.is_queued_for_deletion():
			names.append(child.text)
	return names


func get_log_lines() -> Array[String]:
	var lines: Array[String] = []
	for child in _list.get_children():
		if child != _empty and not child.is_queued_for_deletion():
			lines.append(child.text)
	return lines


func get_reputation_text() -> String:
	return _reputation.text


func is_callsign_editable() -> bool:
	return _callsign.editable


func _in_field() -> bool:
	return _local != null and _local.active


func _refresh_header() -> void:
	_reputation.text = "%+d" % PlayerProgress.get_reputation() if PlayerProgress.get_reputation() != 0 else "0"
	var player = MechOS.player_ref
	var in_field := _in_field()
	_callsign.editable = not in_field
	if not _callsign.has_focus():
		_callsign.text = player.callsign if in_field and is_instance_valid(player) and player is Mecha else PlayerProgress.get_callsign()
	_anonymous.visible = in_field and is_instance_valid(player) and player is Mecha and player.is_anonymous


func _refresh_roster() -> void:
	MechUI.clear(_roster)
	if not _in_field():
		_roster_title.text = "ROSTER"
		_roster.add_child(MechUI.label(&"LabelMeta", "NOT IN THE FIELD"))
		return
	var names := _local.get_roster()
	_roster_title.text = "ROSTER · %d" % names.size()
	for callsign in names:
		_roster.add_child(MechUI.label(&"LabelBody", callsign))


func _rebuild_log() -> void:
	for child in _list.get_children():
		if child != _empty:
			_list.remove_child(child)
			child.queue_free()
	if _local != null:
		for entry in _local.get_log():
			_list.add_child(_make_line(entry))
	_empty.visible = _list.get_child_count() == 1
	MechUI.scroll_to_end(_scroll)


func _on_message(entry: Dictionary) -> void:
	# Follow new lines only if the player hasn't scrolled up to read.
	var bar := _scroll.get_v_scroll_bar()
	var at_end := _scroll.scroll_vertical >= int(bar.max_value - bar.page) - 4
	_list.add_child(_make_line(entry))
	_empty.visible = false
	if _list.get_child_count() > LocalPilots.MAX_LOG + 1:
		var oldest := _list.get_child(1)
		_list.remove_child(oldest)
		oldest.queue_free()
	if at_end:
		MechUI.scroll_to_end(_scroll)


func _make_line(entry: Dictionary) -> Label:
	return MechUI.label(&"LabelMeta" if entry.bark else &"LabelBody", LocalPilots.format(entry), true)


func _on_callsign_submitted(text: String) -> void:
	_save_callsign(text)
	_callsign.release_focus()


func _on_callsign_left() -> void:
	_save_callsign(_callsign.text)


func _save_callsign(text: String) -> void:
	if not _callsign.editable:
		return
	var before := PlayerProgress.get_callsign()
	PlayerProgress.set_callsign(text)
	if PlayerProgress.get_callsign() != before:
		MechLog.write("LOC", "Callsign set to %s" % PlayerProgress.get_callsign(), MechLog.Kind.LOCAL)
	_callsign.text = PlayerProgress.get_callsign()
