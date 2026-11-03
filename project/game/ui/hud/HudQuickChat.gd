class_name HudQuickChat
extends PanelContainer

## The quick chat menu. The quick_chat key (T) opens it; 1 to 5 send that
## preset (LocalPilots.QUICK_CHAT) to Local as a broadcast from the player,
## true or not; the key again or Esc closes it, and so does sending. It
## doesn't open while controls are locked (cutscenes), the player is paused
## or dead, or the free cursor is held. PlayerHUD hands it input first
## (handle_input), so Esc closes the menu without opening the pause menu.
## HudPanel, title LabelMetaBright, presets LabelBody.

const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]

var player = null
var local: LocalPilots = null

var _title: Label


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := MechUI.vbox(&"TightStack")
	_title = MechUI.label(&"LabelMetaBright")
	rows.add_child(_title)
	for i in LocalPilots.QUICK_CHAT.size():
		var preset: Dictionary = LocalPilots.QUICK_CHAT[i]
		rows.add_child(MechUI.label(&"LabelBody", "%d  %s" % [i + 1, str(preset.text).to_upper()]))
	add_child(rows)
	MechUI.ignore_mouse(self)
	visible = false


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	close()


func open() -> void:
	_title.text = "QUICK CHAT [%s]" % MechUI.key_name("quick_chat")
	visible = true


func close() -> void:
	visible = false


## Sends preset `index` (0-based) as the player, and closes. Returns the
## Local entry ({} if nothing was sent).
func send(index: int) -> Dictionary:
	close()
	if local == null or not is_instance_valid(player) or index < 0 or index >= LocalPilots.QUICK_CHAT.size():
		return {}
	return local.broadcast(player, LocalPilots.QUICK_CHAT[index].kind)


## Takes the keys the menu uses; true if it used `event`.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("quick_chat"):
		if visible:
			close()
		elif _can_open():
			open()
		else:
			return false
		return true
	if not visible:
		return false
	if event.is_action_pressed("escape"):
		close()
		return true
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		var key: Key = key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		var index := NUMBER_KEYS.find(key)
		if index >= 0:
			send(index)
			return true
	return false


func _can_open() -> bool:
	if not is_instance_valid(player) or local == null:
		return false
	return not (player.controls_locked or player.paused or player.is_dead or MouseManager.free_cursor_held)
