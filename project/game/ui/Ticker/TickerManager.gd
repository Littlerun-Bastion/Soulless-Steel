extends Node

signal new_message


func new_message(text_data):
	emit_signal("new_message", text_data)
