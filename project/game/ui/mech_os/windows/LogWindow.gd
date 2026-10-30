extends MechWindow
class_name LogWindow

## LOG: the MechOS system log (MechLog), newest line at the bottom.
## Tabs filter by kind. Critical lines are bright and start with "!".

const FILTERS := [
	{"label": "ALL", "kind": -1},
	{"label": "COMBAT", "kind": MechLog.Kind.COMBAT},
	{"label": "LOOT", "kind": MechLog.Kind.LOOT},
	{"label": "SYSTEM", "kind": MechLog.Kind.SYSTEM},
]

var _filter := -1
var _tabs := ButtonGroup.new()
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	var column := MechUI.vbox(&"PaneStack")
	content.add_child(column)

	var tab_row := MechUI.hbox(&"TabRow")
	for filter in FILTERS:
		var tab := MechUI.button(filter.label, &"Tab")
		tab.toggle_mode = true
		tab.button_group = _tabs
		tab.button_pressed = filter.kind == _filter
		tab.pressed.connect(set_filter.bind(filter.kind))
		tab_row.add_child(tab)
	column.add_child(MechUI.pane(&"PaneHeader", tab_row))

	var area := MechUI.scroll_box(&"TightStack")
	_scroll = area[0]
	_list = area[1]
	column.add_child(_scroll)
	_empty = MechUI.label(&"LabelMeta", "NO ENTRIES")
	_list.add_child(_empty)

	MechLog.feed.line_added.connect(_on_line_added)
	MechLog.feed.cleared.connect(_rebuild)
	_rebuild()


## -1 = all kinds, else a MechLog.Kind.
func set_filter(kind: int) -> void:
	_filter = kind
	_rebuild()


## The lines on show, as text (for tests and copying).
func get_visible_lines() -> Array:
	var result := []
	for child in _list.get_children():
		if child != _empty and not child.is_queued_for_deletion():
			result.append(child.text)
	return result


func _rebuild() -> void:
	for child in _list.get_children():
		if child != _empty:
			_list.remove_child(child)
			child.queue_free()
	for line in MechLog.lines:
		if _shows(line):
			_list.add_child(_make_line(line))
	_empty.visible = _list.get_child_count() == 1
	MechUI.scroll_to_end(_scroll)


func _on_line_added(line: Dictionary) -> void:
	if not _shows(line):
		return
	# Follow new lines only if the player hasn't scrolled up to read.
	var bar := _scroll.get_v_scroll_bar()
	var at_end := _scroll.scroll_vertical >= int(bar.max_value - bar.page) - 4
	_list.add_child(_make_line(line))
	_empty.visible = false
	if _list.get_child_count() > MechLog.MAX_LINES + 1:
		var oldest := _list.get_child(1)
		_list.remove_child(oldest)
		oldest.queue_free()
	if at_end:
		MechUI.scroll_to_end(_scroll)


func _shows(line: Dictionary) -> bool:
	return _filter == -1 or line.kind == _filter


func _make_line(line: Dictionary) -> Label:
	var node := MechUI.label(&"LabelBodyBright" if line.critical else &"LabelBody", MechLog.format(line), true)
	return node
