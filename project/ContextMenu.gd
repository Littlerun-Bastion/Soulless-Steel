extends PanelContainer
class_name ContextMenu


#   id -- String    stable name, for debugging and later lookups
#   label -- String    button text
#   priority -- int       lower sorts first (default 0)
#   group -- String    a separator is drawn where the group changes
#   visible_if -- Callable  (context) -> bool; false hides the action
#   enabled_if -- Callable  (context) -> String; non-empty = disabled, shown as the reason
#   run -- Callable  (context) -> void

const MECH_THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const EDGE_MARGIN := 15.0

var _list: VBoxContainer
var _context: Dictionary = {}


func _ready() -> void:
	theme = MECH_THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	_list = VBoxContainer.new()
	add_child(_list)
	hide()


func is_open() -> bool:
	return visible


func is_mouse_over() -> bool:
	return visible and get_global_rect().has_point(get_viewport().get_mouse_position())


# actions arrive already filtered and sorted by MechOS.
func open(actions: Array, context: Dictionary, at: Vector2) -> void:
	_context = context
	for child in _list.get_children():
		# remove_child first so old buttons don't count towards the new size
		_list.remove_child(child)
		child.queue_free()

	var last_group = null
	for action in actions:
		var group: String = action.get("group", "")
		if last_group != null and group != last_group:
			_list.add_child(HSeparator.new())
		last_group = group
		_list.add_child(_make_button(action))

	show()
	reset_size()
	_place(at)


func close() -> void:
	hide()
	_context = {}


# Called from MechOS._input while the menu is open. Returns true if the event was used up
func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed("escape"):
		close()
		return true
	if event is InputEventMouseButton and event.pressed:
		if is_mouse_over():
			return false
		close()
		# Left-click outside only closes. Right-click outside falls through, so a new menu can open where the player clicked.
		return event.button_index != MOUSE_BUTTON_RIGHT
	return false


func _make_button(action: Dictionary) -> Button:
	var button := Button.new()
	button.text = action.get("label", "?")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var reason := _disabled_reason(action, _context)
	if reason != "":
		button.disabled = true
		button.text += "  [%s]" % reason
	button.pressed.connect(_on_action_pressed.bind(action))
	return button


func _disabled_reason(action: Dictionary, context: Dictionary) -> String:
	var enabled_if = action.get("enabled_if")
	if enabled_if is Callable:
		return str(enabled_if.call(context))
	return ""


func _on_action_pressed(action: Dictionary) -> void:
	var context := _context
	close()
	# Check again: the target may have changed or gone since the menu opened.
	var source = context.get("source")
	if source == null or not is_instance_valid(source):
		return
	var visible_if = action.get("visible_if")
	if visible_if is Callable and not visible_if.call(context):
		return
	if _disabled_reason(action, context) != "":
		return
	var run = action.get("run")
	if run is Callable:
		run.call(context)


# Open at the cursor; flip left/up when there's no room, then keep the whole menu inside the screen edges.
func _place(at: Vector2) -> void:
	var screen := get_viewport_rect().size
	var pos := at
	if pos.x + size.x > screen.x - EDGE_MARGIN:
		pos.x = at.x - size.x
	if pos.y + size.y > screen.y - EDGE_MARGIN:
		pos.y = at.y - size.y
	pos.x = clampf(pos.x, EDGE_MARGIN, screen.x - EDGE_MARGIN - size.x)
	pos.y = clampf(pos.y, EDGE_MARGIN, screen.y - EDGE_MARGIN - size.y)
	position = pos
