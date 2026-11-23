class_name StageShowFlagMarker
extends StageStep

## Puts an actor's hidden Flag marker on the screen, with its pop
## (Mecha.show_flag_marker). The step moves on at once.

@export var actor := ""


func _start() -> void:
	_show()
	_finish()


func _skip_to_end() -> void:
	_show()
	_finish()


func _show() -> void:
	var mecha = director.find_actor(actor)
	if mecha != null and mecha.has_method("show_flag_marker"):
		mecha.show_flag_marker()
