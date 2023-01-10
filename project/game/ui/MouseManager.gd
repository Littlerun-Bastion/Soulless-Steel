extends Node

const INVISIBLE_CURSOR = preload("res://assets/images/ui/invisible_cursor.png")


func show_cursor():
	Input.set_custom_mouse_cursor(null)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_cursor():
	Input.set_custom_mouse_cursor(INVISIBLE_CURSOR)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
