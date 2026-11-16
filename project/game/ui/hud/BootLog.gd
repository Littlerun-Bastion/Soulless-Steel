class_name BootLog
extends Label

## Lines typed out a character at a time, with a key click every few.

const CHARS_PER_SECOND := 90.0
const CLICK_EVERY := 4

var _typed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible_characters = 0


func add_line(line: String) -> void:
	text = line if text == "" else text + "\n" + line


func clear_log() -> void:
	text = ""
	_typed = 0.0
	visible_characters = 0


func is_typing() -> bool:
	return visible_characters < get_total_character_count()


func _process(dt: float) -> void:
	var total := get_total_character_count()
	if visible_characters >= total:
		return
	var before := int(_typed)
	_typed = minf(_typed + CHARS_PER_SECOND * dt, total)
	visible_characters = int(_typed)
	if int(_typed) / CLICK_EVERY != before / CLICK_EVERY:
		AudioManager.play_sfx("keystroke_light")
