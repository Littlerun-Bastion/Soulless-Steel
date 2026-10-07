extends Node

#   aim_available true only while a combat scene is running
#   pointer_forced set by pause / game over, which always need the pointer
#   free_cursor_held true while the free_cursor action (Alt) is held

signal cursor_mode_changed(mode)

enum CursorMode { AIM, POINTER }

const INVISIBLE_CURSOR = preload("res://assets/images/ui/invisible_cursor.png")

var cursor_layer: CanvasLayer
var cursor_sprite: Sprite2D

var cursor_mode: CursorMode = CursorMode.POINTER
var aim_available: bool = false
var pointer_forced: bool = false
var free_cursor_held: bool = false


func _ready() -> void:
	cursor_layer = CanvasLayer.new()
	cursor_layer.layer = 98
	add_child(cursor_layer)

	cursor_sprite = Sprite2D.new()
	cursor_sprite.texture = preload("res://assets/images/ui/menu/cursor_none.png")
	cursor_sprite.centered = false  # anchor top-left to mouse pos so the click lands where the tip points
	cursor_layer.add_child(cursor_sprite)

	# Always hide the hardware cursor — software cursor replaces it
	Input.set_custom_mouse_cursor(INVISIBLE_CURSOR)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	_update_mode()


func _process(_delta: float) -> void:
	cursor_sprite.global_position = get_viewport().get_mouse_position()


func _input(event: InputEvent) -> void:
	if event.is_action("free_cursor") and not event.is_echo():
		free_cursor_held = event.is_pressed()
		_update_mode()


func _notification(what: int) -> void:
	#Treat losing game application focus as releasing Alt.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		free_cursor_held = false
		_update_mode()


# Called by CombatScene when the player is set up (true)
func set_aim_available(available: bool) -> void:
	aim_available = available
	_update_mode()


# Pause and game over force the pointer on, and pause turns it off again
func force_pointer(enabled: bool) -> void:
	pointer_forced = enabled
	free_cursor_held = Input.is_action_pressed("free_cursor")
	_update_mode()


# Called when a combat scene exits
func reset() -> void:
	aim_available = false
	pointer_forced = false
	free_cursor_held = false
	_update_mode()


func is_aiming() -> bool:
	return cursor_mode == CursorMode.AIM


func _update_mode() -> void:
	var new_mode := CursorMode.POINTER
	if aim_available and not pointer_forced and not free_cursor_held:
		new_mode = CursorMode.AIM

	cursor_sprite.visible = new_mode == CursorMode.POINTER

	if new_mode != cursor_mode:
		cursor_mode = new_mode
		cursor_mode_changed.emit(cursor_mode)
