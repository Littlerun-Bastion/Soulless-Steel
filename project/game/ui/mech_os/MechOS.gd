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


func _ready() -> void:
	layer = 10  # above game world, below pause menu
	drag_manager = DragManager.new()
	add_child(drag_manager)
	drag_manager.setup(drag_layer)
	_register_apps()

func _process(_delta: float) -> void:
	if not is_active:
		return
	
	var was_over := mouse_over_window
	mouse_over_window = _is_mouse_over_any_window()
	
	if mouse_over_window and not was_over:
		MouseManager.show_cursor()
	elif not mouse_over_window and was_over:
		MouseManager.hide_cursor()


	
func _input(event: InputEvent) -> void:
	if not is_active:
		return
	if drag_manager.handle_input(event):
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
	# If already open, just focus it
	if open_windows.has(app_id):
		focus_window(open_windows[app_id])
		return open_windows[app_id]
	
	# Check registry
	if not app_registry.has(app_id):
		push_error("MechOS: Unknown app_id '%s'" % app_id)
		return null
	
	var scene: PackedScene = app_registry[app_id]
	var window: MechWindow = scene.instantiate()
	window.app_id = app_id
	
	window_layer.add_child(window)
	window.size = window.min_size
	open_windows[app_id] = window
	
	# Connect signals
	window.closed.connect(_on_window_closed)
	window.focused.connect(_on_window_focused)
	
	# Center it on screen
	_center_window(window)
	focus_window(window)
	
	return window

func close_app(app_id: String) -> void:
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
		if mouse_over_window:
			mouse_over_window = false
			MouseManager.hide_cursor()


func close_all() -> void:
	for app_id in open_windows.keys():
		close_app(app_id)
	if mouse_over_window:
		mouse_over_window = false
		MouseManager.hide_cursor()
		

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
		window.set_customize(true)  # TODO: remove once hangar zone controls this
	return window
