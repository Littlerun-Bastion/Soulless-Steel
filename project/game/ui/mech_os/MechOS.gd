extends CanvasLayer

# Registry of available apps: app_id -> PackedScene
var app_registry: Dictionary = {}

# Currently open windows: app_id -> MechWindow instance
var open_windows: Dictionary = {}

# The control node that holds all windows
@onready var window_layer: Control = $WindowLayer
@onready var taskbar: Panel = $Taskbar

var is_active: bool = true


func _ready() -> void:
	layer = 10  # above game world, below pause menu
	_register_apps()


func _register_apps() -> void:
	# Register window scenes here
	# Example:
	# register_app("inventory", preload("res://game/ui/mech_os/windows/InventoryWindow.tscn"))
	# register_app("hangar", preload("res://game/ui/mech_os/windows/DeploymentsWindow.tscn"))
	
	register_app("test", preload("res://game/ui/mech_os/windows/TestWindow.tscn"), "TST")
	
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


func close_all() -> void:
	for app_id in open_windows.keys():
		close_app(app_id)


func _on_window_closed(window: MechWindow) -> void:
	if open_windows.has(window.app_id):
		open_windows.erase(window.app_id)
	window.queue_free()


func _on_window_focused(window: MechWindow) -> void:
	focus_window(window)


func _center_window(window: MechWindow) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	window.position = (screen_size - window.size) * 0.5
