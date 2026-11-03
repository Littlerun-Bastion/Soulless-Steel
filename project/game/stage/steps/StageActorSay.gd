class_name StageActorSay
extends StageStep

## A stage actor speaks in the world: a speech box over it for `seconds`
## (Mecha.say, heard whatever the distance), with its callsign, and a bark
## line in Local. The step moves on when the box goes; with `wait` off it
## moves on at once and the box stays up while the next steps run (two
## actors talking over each other, someone speaking while walking).
## StageSay (the bottom dialogue box) is the other way to show a line. An
## actor that isn't found or can't speak is skipped.

@export var actor := ""
@export_multiline var text := ""
@export var seconds := 2.5
@export var wait := true

var _elapsed := 0.0


func _start() -> void:
	var speaker := director.find_actor(actor)
	if speaker == null or not speaker.has_method("say"):
		_finish()
		return
	speaker.say(text, seconds, true)
	_elapsed = 0.0
	if not wait:
		_finish()


func _process(dt: float) -> void:
	if not is_running():
		return
	_elapsed += dt
	if _elapsed >= seconds:
		_finish()
