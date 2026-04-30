extends Panel
class_name MechWindow

signal closed(window)
signal focused(window)

@export var window_title: String = "Window"
@export var min_size: Vector2 = Vector2(300, 200)
@export var app_id: String = ""  # matches taskbar button ID

# Resize handle size in pixels
const RESIZE_MARGIN := 6

var is_dragging := false
var is_resizing := false
var drag_offset := Vector2.ZERO
var resize_dir := Vector2.ZERO  # which edges are being dragged

var titlebar_focused_style: StyleBoxFlat = preload("res://game/ui/mech_os/window_titlebar_focused.tres")
var titlebar_unfocused_style: StyleBoxFlat = preload("res://game/ui/mech_os/window_titlebar_unfocused.tres")

@onready var title_bar: Panel = $TitleBar
@onready var title_label: Label = $TitleBar/HBox/TitleLabel
@onready var close_button: Button = $TitleBar/HBox/CloseButton
@onready var content: Control = $Content


func _ready() -> void:
	title_label.text = window_title
	close_button.pressed.connect(_on_close_pressed)
	custom_minimum_size = min_size
	# Ensure we get input
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_close_pressed() -> void:
	emit_signal("closed", self)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			emit_signal("focused", self)
			
			# Check if we're on a resize edge
			resize_dir = _get_resize_direction(event.position)
			if resize_dir != Vector2.ZERO:
				is_resizing = true
				get_viewport().set_input_as_handled()
				return
			
			# Check if we're on the title bar
			if _is_over_title_bar(event.position):
				if _is_over_close_button(event.global_position):
					return
				is_dragging = true
				drag_offset = event.position
				get_viewport().set_input_as_handled()
		else:
			is_dragging = false
			is_resizing = false
	
	elif event is InputEventMouseMotion:
		if is_dragging:
			position += event.relative
			_clamp_to_parent()
			get_viewport().set_input_as_handled()
		elif is_resizing:
			_apply_resize(event.relative)
			get_viewport().set_input_as_handled()
		else:
			# Update cursor shape based on hover position
			var dir = _get_resize_direction(event.position)
			_update_cursor(dir)


func _is_over_title_bar(pos: Vector2) -> bool:
	if title_bar == null:
		return false
	return pos.y < title_bar.size.y


func _get_resize_direction(pos: Vector2) -> Vector2:
	var dir := Vector2.ZERO
	if pos.x < RESIZE_MARGIN:
		dir.x = -1
	elif pos.x > size.x - RESIZE_MARGIN:
		dir.x = 1
	if pos.y < RESIZE_MARGIN:
		dir.y = -1
	elif pos.y > size.y - RESIZE_MARGIN:
		dir.y = 1
	return dir


func _apply_resize(relative: Vector2) -> void:
	var new_pos := position
	var new_size := size
	
	if resize_dir.x < 0:
		# Dragging left edge
		var delta = min(relative.x, new_size.x - min_size.x)
		new_pos.x += delta
		new_size.x -= delta
	elif resize_dir.x > 0:
		new_size.x += relative.x
	
	if resize_dir.y < 0:
		# Dragging top edge
		var delta = min(relative.y, new_size.y - min_size.y)
		new_pos.y += delta
		new_size.y -= delta
	elif resize_dir.y > 0:
		new_size.y += relative.y
	
	# Enforce minimum
	new_size.x = max(new_size.x, min_size.x)
	new_size.y = max(new_size.y, min_size.y)
	
	position = new_pos
	size = new_size


func _clamp_to_parent() -> void:
	var parent_size := get_parent_control().size if get_parent_control() else get_viewport_rect().size
	position.x = clamp(position.x, 0, parent_size.x - 60)
	position.y = clamp(position.y, 0, parent_size.y - 40)


func _update_cursor(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	elif dir == Vector2(1, 0) or dir == Vector2(-1, 0):
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	elif dir == Vector2(0, 1) or dir == Vector2(0, -1):
		mouse_default_cursor_shape = Control.CURSOR_VSIZE
	elif dir == Vector2(1, 1) or dir == Vector2(-1, -1):
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	elif dir == Vector2(1, -1) or dir == Vector2(-1, 1):
		mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		
func _is_over_close_button(global_pos: Vector2) -> bool:
	if close_button == null:
		return false
	return close_button.get_global_rect().has_point(global_pos)

func set_focused(is_focused: bool) -> void:
	if is_focused:
		title_bar.add_theme_stylebox_override("panel", titlebar_focused_style)
		title_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1.0))
	else:
		title_bar.add_theme_stylebox_override("panel", titlebar_unfocused_style)
		title_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
