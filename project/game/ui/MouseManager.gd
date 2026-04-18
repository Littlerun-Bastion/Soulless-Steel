extends Node

const INVISIBLE_CURSOR = preload("res://assets/images/ui/invisible_cursor.png")

var cursor_layer: CanvasLayer
var cursor_sprite: Sprite2D
var cursor_visible: bool = true

func _ready() -> void:
	cursor_layer = CanvasLayer.new()
	cursor_layer.layer = 98
	add_child(cursor_layer)
	
	cursor_sprite = Sprite2D.new()
	cursor_sprite.texture = preload("res://assets/images/ui/menu/cursor_none.png")  # your cursor image
	cursor_sprite.centered = false  # anchor top-left to mouse pos so the click lands where the tip points
	cursor_layer.add_child(cursor_sprite)
	
	# Always hide the hardware cursor — software cursor replaces it
	Input.set_custom_mouse_cursor(INVISIBLE_CURSOR)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _process(_delta: float) -> void:
	cursor_sprite.global_position = get_viewport().get_mouse_position()
	cursor_sprite.visible = cursor_visible


func show_cursor() -> void:
	cursor_visible = true


func hide_cursor() -> void:
	cursor_visible = false
