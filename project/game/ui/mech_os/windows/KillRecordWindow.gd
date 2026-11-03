extends MechWindow
class_name KillRecordWindow

## A wreck's kill record (KillRecord), opened beside its loot window
## (MechOS.open_kill_record) and closed with it. Read-only:
##   KILLED BY  the killer's callsign, "Unknown", or a creature's species
##   WEAPON     the weapon, or UNKNOWN
##   FIRED FROM how far and which way the killer was from the wreck, or
##              UNKNOWN
## then WHAT IT KNEW: the dead mecha's contacts at the end, one line each
## ("MECH · SIGHT · 40 M NW · LIVE", "STALKER · WARD · 120 M S · 6S OLD"), at
## most MAX_CONTACT_LINES, or NOTHING.

const MAX_CONTACT_LINES := 12

var _rows: VBoxContainer
var _contacts: VBoxContainer
var _record := {}


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	var column := MechUI.vbox(&"PaneStack")
	content.add_child(column)
	_rows = MechUI.vbox(&"TightStack")
	column.add_child(MechUI.pane(&"PaneHeader", _rows))
	column.add_child(MechUI.pane(&"PaneHeader", MechUI.label(&"LabelMeta", "WHAT IT KNEW")))
	var area := MechUI.scroll_box(&"TightStack")
	column.add_child(area[0])
	_contacts = area[1]
	_rebuild()


func setup(record: Dictionary) -> void:
	_record = record
	if is_node_ready():
		_rebuild()


## The lines shown, top to bottom, for tests.
func get_lines() -> Array[String]:
	var lines: Array[String] = []
	for box in [_rows, _contacts]:
		for row in box.get_children():
			var parts: Array[String] = []
			for label in row.find_children("*", "Label", true, false):
				parts.append((label as Label).text)
			if row is Label:
				parts.append((row as Label).text)
			lines.append(" ".join(parts))
	return lines


func _rebuild() -> void:
	MechUI.clear(_rows)
	MechUI.clear(_contacts)
	var at: Vector2 = _record.get("position", Vector2.ZERO)
	var weapon: String = str(_record.get("weapon", ""))
	var from = _record.get("killer_position")
	_add_row("KILLED BY", str(_record.get("killer", KillRecord.UNKNOWN)))
	_add_row("WEAPON", weapon if weapon != "" else "UNKNOWN")
	_add_row("FIRED FROM", KillRecord.bearing(at, from) if from is Vector2 else "UNKNOWN")
	var contacts: Array = _record.get("contacts", [])
	if contacts.is_empty():
		_contacts.add_child(MechUI.label(&"LabelMeta", "NOTHING"))
	for contact in contacts.slice(0, MAX_CONTACT_LINES):
		var state: String = "LIVE" if contact.live else "%dS OLD" % roundi(float(contact.age))
		var line := " · ".join([str(contact.kind).to_upper(), str(contact.source).to_upper(),
				KillRecord.bearing(at, contact.position), state])
		_contacts.add_child(MechUI.label(&"LabelBody" if contact.live else &"LabelDim", line))
	if contacts.size() > MAX_CONTACT_LINES:
		_contacts.add_child(MechUI.label(&"LabelMeta", "+%d MORE" % (contacts.size() - MAX_CONTACT_LINES)))


func _add_row(key: String, value: String) -> void:
	var row := MechUI.hbox(&"BarRow")
	var name_label := MechUI.label(&"LabelMeta", key)
	name_label.custom_minimum_size.x = 120
	row.add_child(name_label)
	row.add_child(MechUI.label(&"LabelBodyBright", value))
	_rows.add_child(row)
