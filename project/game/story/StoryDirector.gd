extends Node

# StoryDirector tracks where the player currently is in the story.
#
# State:
#   - chapter / beat : the player's current position in the main story
#   - history        : every "chapter/beat" id the player has reached, in order
#   - flags          : free-form story facts (choices made, NPCs met, etc.)
#
# Persisted through Profile.get_save_data / set_save_data under "story".
#
# Other systems talk to the StoryDirector with two shared dictionary shapes,
# so missions, messenger replies and map triggers all speak the same language:
#
#   effects    = {"advance": "chapter/beat", "flags": {"met_volk": true}}
#   conditions = {"reached": "chapter/beat" or "chapter",
#                 "not_reached": "chapter/beat" or "chapter",
#                 "flags": {"met_volk": true}}
#
# Hooks currently wired in:
#   - MissionData.story_effects       applied when MissionManager completes it
#   - messenger reply "story_effects" applied when the player picks the reply
#   - messenger reply "requires"      hides the reply until conditions are met
#   - map_trigger named "story:..."   routed by CombatScene (Arena and Expedition), see handle_trigger()
#
# Testing:
#   - debug_7 (F7) prints the current story state
#   - game/test/StoryDirectorTest.tscn runs self-checks (F6 in the editor)
#   - set autosave = false to change state without writing the profile

signal beat_changed(chapter, beat)
signal flag_changed(flag_name, value)
signal state_changed  # any change: advance, flag, reset or load

const START_CHAPTER := "prologue"
const START_BEAT := "start"

var chapter: String = START_CHAPTER
var beat: String = START_BEAT
var history: Array = []
var flags: Dictionary = {}

var autosave := true


func _ready() -> void:
	_record_history()
	MissionManager.mission_completed.connect(_on_mission_completed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_7"):
		print(get_debug_text())


# ---- Position ----

func advance_to(new_chapter: String, new_beat: String, should_save := true) -> void:
	if new_chapter == "" or new_beat == "":
		push_error("StoryDirector.advance_to needs both chapter and beat, got '%s/%s'" % [new_chapter, new_beat])
		return
	if new_chapter == chapter and new_beat == beat:
		return
	chapter = new_chapter
	beat = new_beat
	_record_history()
	_log("now at " + get_position_id())
	beat_changed.emit(chapter, beat)
	state_changed.emit()
	if should_save:
		_save()


func get_position_id() -> String:
	return _make_id(chapter, beat)


func is_at(check_chapter: String, check_beat := "") -> bool:
	if check_chapter != chapter:
		return false
	return check_beat == "" or check_beat == beat


# Leave check_beat empty to ask about the chapter as a whole.
func has_reached(check_chapter: String, check_beat := "") -> bool:
	if check_beat == "":
		for id in history:
			if id.begins_with(check_chapter + "/"):
				return true
		return false
	return history.has(_make_id(check_chapter, check_beat))


# ---- Flags ----

func set_flag(flag_name: String, value = true, should_save := true) -> void:
	if flags.has(flag_name) and flags[flag_name] == value:
		return
	flags[flag_name] = value
	_log("flag " + flag_name + " = " + str(value))
	flag_changed.emit(flag_name, value)
	state_changed.emit()
	if should_save:
		_save()


func get_flag(flag_name: String, default = null):
	return flags.get(flag_name, default)


func has_flag(flag_name: String) -> bool:
	return flags.has(flag_name) and flags[flag_name]


# ---- Shared effects / conditions (see header) ----

func apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	var flag_values: Dictionary = effects.get("flags", {})
	for flag_name in flag_values:
		set_flag(flag_name, flag_values[flag_name], false)
	if effects.has("advance"):
		var parts := _split_id(effects["advance"])
		advance_to(parts[0], parts[1], false)
	_save()


# An empty dictionary always passes.
func meets(conditions: Dictionary) -> bool:
	if conditions.has("reached"):
		var parts := _split_id(conditions["reached"])
		if not has_reached(parts[0], parts[1]):
			return false
	if conditions.has("not_reached"):
		var parts := _split_id(conditions["not_reached"])
		if has_reached(parts[0], parts[1]):
			return false
	var flag_values: Dictionary = conditions.get("flags", {})
	for flag_name in flag_values:
		if get_flag(flag_name, false) != flag_values[flag_name]:
			return false
	return true


# Map triggers named "story:<command>" land here via Arena. Commands:
#   "advance=chapter/beat"  moves the story
#   "flag=name"             sets flag to true
func handle_trigger(command: String) -> void:
	var pair := command.split("=", true, 1)
	if pair.size() != 2:
		push_error("Invalid story trigger: " + command)
		return
	match pair[0]:
		"advance":
			apply_effects({"advance": pair[1]})
		"flag":
			apply_effects({"flags": {pair[1]: true}})
		_:
			push_error("Unknown story trigger command: " + command)


func _on_mission_completed(mission) -> void:
	_log("mission completed: " + mission.mission_name)
	apply_effects(mission.story_effects)


# ---- Save / reset ----

func reset(should_save := true) -> void:
	chapter = START_CHAPTER
	beat = START_BEAT
	history.clear()
	flags.clear()
	_record_history()
	_log("reset")
	beat_changed.emit(chapter, beat)
	state_changed.emit()
	if should_save:
		_save()


func get_save_data() -> Dictionary:
	return {
		"chapter": chapter,
		"beat": beat,
		"history": history.duplicate(),
		"flags": flags.duplicate(true),
	}


func set_save_data(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	chapter = str(data.get("chapter", START_CHAPTER))
	beat = str(data.get("beat", START_BEAT))
	history = Array(data.get("history", [])).duplicate()
	flags = Dictionary(data.get("flags", {})).duplicate(true)
	_record_history()
	beat_changed.emit(chapter, beat)
	state_changed.emit()


# ---- Debug ----

func get_debug_text() -> String:
	return "[StoryDirector] at %s\n  history: %s\n  flags: %s" % [
		get_position_id(), str(history), str(flags)]


# ---- Internals ----

func _save() -> void:
	if autosave:
		FileManager.save_profile()


func _log(text: String) -> void:
	if Debug.get_setting("verbose_logging"):
		print("[StoryDirector] ", text)


func _record_history() -> void:
	var id := get_position_id()
	if not history.has(id):
		history.append(id)


func _make_id(c: String, b: String) -> String:
	return c + "/" + b


# "chapter/beat" -> ["chapter", "beat"]; "chapter" -> ["chapter", ""]
func _split_id(id: String) -> Array:
	var parts := id.split("/", true, 1)
	return [parts[0], parts[1] if parts.size() > 1 else ""]
