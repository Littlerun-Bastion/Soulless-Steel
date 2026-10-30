class_name MechUI
extends RefCounted

## Small builders for MechOS windows that lay themselves out in code.
## Every node gets its look from a MechTheme type variation, never from
## per-node overrides.


static func label(variation: StringName, text: String = "", wrap := false) -> Label:
	var node := Label.new()
	node.theme_type_variation = variation
	node.text = text
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


## A PanelContainer with one child, e.g. pane(&"PaneHeader", title_label).
static func pane(variation: StringName, child: Control = null) -> PanelContainer:
	var node := PanelContainer.new()
	node.theme_type_variation = variation
	if child != null:
		node.add_child(child)
	return node


static func vbox(variation: StringName = &"") -> VBoxContainer:
	var node := VBoxContainer.new()
	node.theme_type_variation = variation
	return node


static func hbox(variation: StringName = &"") -> HBoxContainer:
	var node := HBoxContainer.new()
	node.theme_type_variation = variation
	return node


## Vertical scrolling only; fills the space left in its column.
static func scroll() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return node


## A scroll area with the standard 20px margin inside; returns [scroll, inner box].
static func scroll_box(box_variation: StringName = &"") -> Array:
	var area := scroll()
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"PaneMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(margin)
	var box := vbox(box_variation)
	margin.add_child(box)
	return [area, box]


static func button(text: String, variation: StringName = &"") -> Button:
	var node := Button.new()
	node.theme_type_variation = variation
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	return node


## A label pushed to the right of an HBox row: label, spacer, value.
static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)


## Scrolls to the bottom once the new content has a size.
static func scroll_to_end(area: ScrollContainer) -> void:
	await area.get_tree().process_frame
	if is_instance_valid(area):
		area.scroll_vertical = int(area.get_v_scroll_bar().max_value)


## "ALT", "E", "RMB"... for the first input bound to the action.
static func key_name(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "UNBOUND"
	var event: InputEvent = events[0]
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
	if event is InputEventKey:
		var code: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		return OS.get_keycode_string(code).to_upper()
	return event.as_text().replace(" (Physical)", "").to_upper()


## 12 -> "12", 41.25 -> "41.25": whole numbers without the ".0".
static func fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2)
