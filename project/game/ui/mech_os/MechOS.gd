extends CanvasLayer

# Registry of available apps: app_id -> PackedScene
var app_registry: Dictionary = {}

# Currently open windows: app_id -> MechWindow instance
var open_windows: Dictionary = {}

# The control node that holds all windows
@onready var window_layer: Control = $WindowLayer
@onready var taskbar: Panel = $Taskbar
@onready var drag_layer: Control = $DragLayer


var is_active: bool = true
var drag_manager: DragManager = null
var mouse_over_window: bool = false
var player_ref: Node = null

# Whether the equipment window lets parts be swapped. Expedition turns this
# off (no part swaps mid-run); the Hangar zone will control it later.
var equipment_customizable: bool = true

var context_menu: ContextMenu = null
var context_actions: Dictionary = {}
var _rmb_armed: bool = false


func _ready() -> void:
	layer = 10  # above game world, below pause menu
	drag_manager = DragManager.new()
	add_child(drag_manager)
	drag_manager.setup(drag_layer)
	_register_apps()
	context_menu = ContextMenu.new()
	add_child(context_menu)  # last child, so it draws above windows and the drag layer
	_register_context_actions()
	MouseManager.cursor_mode_changed.connect(_on_cursor_mode_changed)
	_on_cursor_mode_changed(MouseManager.cursor_mode)

#func _process(_delta: float) -> void:
#	if not is_active:
#		return
#	
#	var was_over := mouse_over_window
##	mouse_over_window = _is_mouse_over_any_window()
	
#	if mouse_over_window and not was_over:
##		MouseManager.show_cursor()
#	elif not mouse_over_window and was_over:
#		MouseManager.hide_cursor()

func _input(event: InputEvent) -> void:
	if not is_active or MouseManager.is_aiming():
		return

	if context_menu.is_open():
		if context_menu.handle_input(event):
			get_viewport().set_input_as_handled()
			return
		if context_menu.is_mouse_over():
			return  # leave it for the menu's buttons (stops drags starting underneath)

	if drag_manager.handle_input(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_rmb_armed = true
		elif _rmb_armed:
			_rmb_armed = false
			if _open_context_menu():
				get_viewport().set_input_as_handled()


func _register_apps() -> void:
	# Register window scenes here
	# Example:
	# register_app("inventory", preload("res://game/ui/mech_os/windows/InventoryWindow.tscn"))
	# register_app("hangar", preload("res://game/ui/mech_os/windows/DeploymentsWindow.tscn"))
	
	register_app("test", preload("res://game/ui/mech_os/windows/TestWindow.tscn"), "TST")
	register_app("equipment", preload("res://game/ui/mech_os/windows/EquipmentWindow.tscn"), "EQP")
	pass


func register_app(app_id: String, scene: PackedScene, label: String = "") -> void:
	app_registry[app_id] = scene
	if label != "":
		taskbar.add_app_button(app_id, label)

func open_app(app_id: String) -> MechWindow:
	if open_windows.has(app_id):
		focus_window(open_windows[app_id])
		return open_windows[app_id]
	
	if not app_registry.has(app_id):
		push_error("MechOS: Unknown app_id '%s'" % app_id)
		return null
	
	var scene: PackedScene = app_registry[app_id]
	var window: MechWindow = scene.instantiate()
	window.app_id = app_id
	
	window_layer.add_child(window)
	window.size = window.min_size
	
	open_windows[app_id] = window
	
	window.closed.connect(_on_window_closed)
	window.focused.connect(_on_window_focused)
	
	# Auto-setup for windows that need the player reference
	if window.has_method("setup") and player_ref != null:
		if window is EquipmentWindow:
			window.setup(player_ref)
			window.set_customize(equipment_customizable)
	
	_center_window(window)
	focus_window(window)
	
	return window

func close_app(app_id: String) -> void:
	context_menu.close()
	if not open_windows.has(app_id):
		return
	var window = open_windows[app_id]
	drag_manager.unregister_window(window)
	open_windows.erase(app_id)
	window.queue_free()


func toggle_app(app_id: String) -> void:
	if open_windows.has(app_id):
		close_app(app_id)
	else:
		open_app(app_id)


func focus_window(window: MechWindow) -> void:
	for app_id in open_windows:
		open_windows[app_id].set_focused(false)
	window.move_to_front()
	window.set_focused(true)


func is_app_open(app_id: String) -> bool:
	return open_windows.has(app_id)

func set_active(active: bool) -> void:
	is_active = active
	visible = active
	if not active:
		close_all()
		#if mouse_over_window:
		#	mouse_over_window = false
		#	MouseManager.hide_cursor()


func close_all() -> void:
	context_menu.close()
	drag_manager.cancel_drag()
	for app_id in open_windows.keys():
		close_app(app_id)
	#if mouse_over_window:
	#	mouse_over_window = false
	#	MouseManager.hide_cursor()
		

func _is_mouse_over_any_window() -> bool:
	var mouse_pos := get_viewport().get_mouse_position()
	
	# Check taskbar
	if taskbar.get_global_rect().has_point(mouse_pos):
		return true
	
	# Check open windows
	for app_id in open_windows:
		var window: MechWindow = open_windows[app_id]
		if window.visible and window.get_global_rect().has_point(mouse_pos):
			return true
	
	return false

func _on_window_closed(window: MechWindow) -> void:
	context_menu.close()
	drag_manager.unregister_window(window)
	if open_windows.has(window.app_id):
		open_windows.erase(window.app_id)
	window.queue_free()

func _on_window_focused(window: MechWindow) -> void:
	focus_window(window)


func _center_window(window: MechWindow) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	window.position = (screen_size - window.size) * 0.5

func open_inventory(app_id: String, inv: Inventory, title: String) -> MechWindow:
	if open_windows.has(app_id):
		focus_window(open_windows[app_id])
		return open_windows[app_id]
	
	var scene: PackedScene = preload("res://game/ui/mech_os/windows/InventoryWindow.tscn")
	var window = scene.instantiate()
	window.app_id = app_id
	
	window_layer.add_child(window)
	window.size = window.min_size
	
	open_windows[app_id] = window
	
	window.closed.connect(_on_window_closed)
	window.focused.connect(_on_window_focused)
	
	window.setup(inv, title)
	_center_window(window)
	focus_window(window)
	
	return window
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_all()
#
func open_equipment(mecha: Mecha) -> MechWindow:
	var window = open_app("equipment")
	if window != null and window.has_method("setup"):
		window.setup(mecha)
		window.set_customize(equipment_customizable)
	return window
	
func set_player(player: Node) -> void:
	player_ref = player


func set_equipment_customizable(enabled: bool) -> void:
	equipment_customizable = enabled
	if open_windows.has("equipment"):
		open_windows["equipment"].set_customize(enabled)

# In AIM the mouse belongs to the mech: windows and taskbar ignore it.
func _on_cursor_mode_changed(_mode) -> void:
	var behaviour := Control.MOUSE_BEHAVIOR_DISABLED if MouseManager.is_aiming() \
		else Control.MOUSE_BEHAVIOR_INHERITED
	window_layer.mouse_behavior_recursive = behaviour
	taskbar.mouse_behavior_recursive = behaviour
	if MouseManager.is_aiming():
		context_menu.close()
		drag_manager.cancel_drag()
		_rmb_armed = false

#Context Menu Functions

func register_context_action(target_type: String, action: Dictionary) -> void:
	if not context_actions.has(target_type):
		context_actions[target_type] = []
	context_actions[target_type].append(action)


func _open_context_menu() -> bool:
	var mouse_pos := get_viewport().get_mouse_position()
	var context := _find_context_target(mouse_pos)
	if context.is_empty():
		return false
	context["screen_pos"] = mouse_pos
	var actions := _get_context_actions(context)
	if actions.is_empty():
		return false
	context_menu.open(actions, context, mouse_pos)
	return true


# Walk up from the hovered Control; the first node that claims the click wins.
func _find_context_target(global_pos: Vector2) -> Dictionary:
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null:
		if node.has_method("get_context_target"):
			var target: Dictionary = node.get_context_target(global_pos)
			if not target.is_empty():
				target["source"] = node
				return target
		node = node.get_parent()
	return {}


func _get_context_actions(context: Dictionary) -> Array:
	var result: Array = []
	for action in context_actions.get(context["type"], []):
		var visible_if = action.get("visible_if")
		if visible_if is Callable and not visible_if.call(context):
			continue
		result.append(action)
	result.sort_custom(func(a, b): return a.get("priority", 0) < b.get("priority", 0))
	return result


func _register_context_actions() -> void:
	register_context_action("window", {
		"id": "centre", "label": "Centre", "priority": 10,
		"run": func(ctx): _center_window(ctx["target"]),
	})
	# TODO: remove once real disabled actions exist. Tests the disabled state.
	register_context_action("window", {
		"id": "debug_disabled", "label": "Test", "priority": 50,
		"enabled_if": func(_ctx): return "NOT AVAILABLE",
	})
	register_context_action("window", {
		"id": "close", "label": "Close", "priority": 100, "group": "close",
		"run": func(ctx): close_app(ctx["target"].app_id),
	})
