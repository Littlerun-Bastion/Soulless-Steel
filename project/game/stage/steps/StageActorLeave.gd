class_name StageActorLeave
extends StageStep

@export var actor := ""


func _start() -> void:
	var leaver = director.find_actor(actor)
	if leaver != null and leaver.has_method("leave_map"):
		leaver.leave_map()
	_finish()
