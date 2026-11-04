class_name StageActorFlag
extends StageStep

## Sets a stage actor's Flag: raised (by choice, or the emergency state with
## `emergency`, as the tutorial's player starts) or lowered (with the usual
## wind-up; with `instant`, down at once). The step moves on at once. An
## actor that isn't found or has no Flag is skipped.

@export var actor := ""
@export var raised := true
@export var emergency := false
@export var instant := false


func _start() -> void:
	var mecha = director.find_actor(actor)
	if mecha == null or not mecha.has_method("raise_flag"):
		_finish()
		return
	if raised:
		if emergency:
			mecha.enter_flagged_state()
		else:
			mecha.raise_flag(true)
	elif mecha.is_flagged():
		mecha.lower_flag()
		if instant:
			mecha.flag_lowering = 0.0
			mecha._finish_lowering()
	_finish()
