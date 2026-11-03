class_name HudWorldLabels
extends Control

## Labels over mechas, drawn on the HUD at their screen positions so the text
## stays sharp at any camera zoom and isn't tinted by the IR view:
##   - Name tags: the callsign over every mecha the player can see (shown by
##     the player's view, Player._update_view), except the player's own and
##     Anonymous pilots. On screen only. LabelMeta.
##   - Speech boxes (Mecha.say, through CombatScene): the speaker's name
##     ("Unknown" when Anonymous) over its line, in a HudPrompt frame (S1
##     G5, G1 fill), for the line's time. A box shows over its speaker even
##     when the speaker is hidden behind a wall or in a building: hearing
##     someone gives them away. A mecha with a box up shows no tag.
## Tags and boxes are fixed pools. A new line from a speaker replaces its
## box; when every box is in use the one closest to running out is reused.

## Screen px above the mecha's centre.
const TAG_OFFSET := Vector2(0, -90)
const BOX_OFFSET := Vector2(0, -100)
## A line wider than this (px) wraps.
const BOX_WIDTH := 320.0
const EDGE := 15.0
const MAX_TAGS := 24
const MAX_BOXES := 6

var player = null
var mechas: Array = []

var _tags: Array[Label] = []
# {"panel", "name", "text", "mecha", "time"}
var _boxes: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in MAX_TAGS:
		var tag := MechUI.label(&"LabelMeta")
		tag.visible = false
		add_child(tag)
		_tags.append(tag)
	for i in MAX_BOXES:
		var column := MechUI.vbox(&"TightStack")
		var name_label := MechUI.label(&"LabelMetaBright")
		var text_label := MechUI.label(&"LabelBody")
		column.add_child(name_label)
		column.add_child(text_label)
		var panel := MechUI.pane(&"HudPrompt", column)
		panel.visible = false
		add_child(panel)
		_boxes.append({"panel": panel, "name": name_label, "text": text_label, "mecha": null, "time": 0.0})
	MechUI.ignore_mouse(self)


func setup(player_ref, mechas_ref: Array) -> void:
	player = player_ref
	mechas = mechas_ref


func player_died() -> void:
	player = null
	for tag in _tags:
		tag.visible = false
	for box in _boxes:
		box.time = 0.0
		box.panel.visible = false


func show_speech(mecha, text: String, seconds: float) -> void:
	var box := _box_for(mecha)
	box.mecha = mecha
	box.time = seconds
	box.name.text = LocalPilots.name_of(mecha)
	var label: Label = box.text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 0.0
	label.text = text
	if label.get_minimum_size().x > BOX_WIDTH:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = BOX_WIDTH
	box.panel.reset_size()
	box.panel.visible = true


## The line `mecha` is saying, "" if none.
func get_speech(mecha) -> String:
	for box in _boxes:
		if box.mecha == mecha and box.time > 0.0:
			return box.text.text
	return ""


## The name tags on show.
func get_tags() -> Array[String]:
	var shown: Array[String] = []
	for tag in _tags:
		if tag.visible:
			shown.append(tag.text)
	return shown


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var to_screen: Transform2D = player.get_viewport().get_canvas_transform()
	var speaking := {}
	for box in _boxes:
		if box.time <= 0.0:
			continue
		box.time -= delta
		if box.time <= 0.0 or not is_instance_valid(box.mecha):
			box.time = 0.0
			box.panel.visible = false
			continue
		speaking[box.mecha] = true
		var panel: PanelContainer = box.panel
		_place(panel, to_screen * box.mecha.global_position + BOX_OFFSET, true)
	var used := 0
	for mecha in mechas:
		if used >= _tags.size():
			break
		if not _shows_tag(mecha) or speaking.has(mecha):
			continue
		var at: Vector2 = to_screen * mecha.global_position + TAG_OFFSET
		if not get_viewport_rect().has_point(at):
			continue
		var tag := _tags[used]
		var callsign := LocalPilots.name_of(mecha)
		if tag.text != callsign:
			tag.text = callsign
			tag.reset_size()
		_place(tag, at, false)
		tag.visible = true
		used += 1
	for i in range(used, _tags.size()):
		_tags[i].visible = false


func _shows_tag(mecha) -> bool:
	if not is_instance_valid(mecha) or mecha == player or mecha.is_dead or mecha.is_anonymous:
		return false
	return not player.is_hidden_from_view(mecha) and mecha.modulate.a > 0.5


func _box_for(mecha) -> Dictionary:
	var pick: Dictionary = _boxes[0]
	for box in _boxes:
		if box.mecha == mecha and box.time > 0.0:
			return box
		if box.time < pick.time:
			pick = box
	return pick


# Centres `node` on `at`, its bottom edge there; boxes stay on screen.
func _place(node: Control, at: Vector2, keep_on_screen: bool) -> void:
	var pos := Vector2(at.x - node.size.x * 0.5, at.y - node.size.y)
	if keep_on_screen:
		var screen := get_viewport_rect().size
		pos.x = clampf(pos.x, EDGE, screen.x - node.size.x - EDGE)
		pos.y = clampf(pos.y, EDGE + 30.0, screen.y - node.size.y - EDGE)
	node.position = pos.floor()
