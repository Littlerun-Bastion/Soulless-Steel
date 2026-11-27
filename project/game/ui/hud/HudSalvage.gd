class_name HudSalvage
extends Control

## Salvage sources on the HUD: an S1 corner bracket in G4 round every source
## the player sees (SalvageField.visible_sources: not through walls, not in
## the dark past the view circle; a roof source when its roof is in sight).
## The bracket fits the source's outline on screen, PAD px out on each side,
## so it has no fixed size. A source whose bracket would be wider or taller
## than the screen (a big solar array, a roof's spread of AC boxes, seen up
## close) gets none: only a stray corner of it would show. Contacts' brackets (HudContacts) are G5, so a
## salvage bracket never reads as a contact. Within LABEL_RANGE of the
## player the source's name is under its bracket (LabelMeta, G4); farther
## sources show only the bracket. Brackets show on screen only, with no edge
## arrows. The nearest source in reach gets the normal interact prompt
## (InteractPrompt), not drawn here.
##
## The labels are a fixed pool.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const PAD := 8.0
## 30 m.
const LABEL_RANGE := 600.0
const LABEL_GAP := 4.0
const MAX_LABELS := 24

var player = null

# What is drawn this frame: {"rect" (screen px), "text", "index", "node"}.
var _marks: Array[Dictionary] = []
var _labels: Array[Label] = []
var _drawn := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := THEME.get_color(&"g4", &"MechTokens")
	for i in MAX_LABELS:
		var label := MechUI.label(&"LabelMeta")
		label.add_theme_color_override(&"font_color", color)
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	_marks.clear()
	_show_labels()
	queue_redraw()


## The brackets on show: {"rect" (screen px), "text" ("" past LABEL_RANGE),
## "index" (the SalvageField source, -1 for a container node), "node"}.
func get_marks() -> Array[Dictionary]:
	return _marks


func _process(_delta: float) -> void:
	_marks.clear()
	if is_instance_valid(player) and player.get("is_dead") != true:
		_collect()
	_show_labels()
	if not _marks.is_empty() or _drawn > 0:
		queue_redraw()


func _collect() -> void:
	var field := SalvageField.find(player)
	if field == null:
		return
	var to_screen: Transform2D = player.get_viewport().get_canvas_transform()
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	for source in field.visible_sources(player):
		var corners: PackedVector2Array = source.corners
		var rect := Rect2(to_screen * corners[0], Vector2.ZERO)
		for k in range(1, corners.size()):
			rect = rect.expand(to_screen * corners[k])
		rect = rect.grow(PAD)
		if not rect.intersects(screen) or rect.size.x > screen.size.x or rect.size.y > screen.size.y:
			continue
		var at: Vector2 = source.at
		var near: bool = player.global_position.distance_to(at) <= LABEL_RANGE
		_marks.append({"rect": rect, "text": str(source.name) if near else "",
				"index": source.index, "node": source.node})


func _show_labels() -> void:
	var used := 0
	for mark in _marks:
		if mark.text == "" or used >= _labels.size():
			continue
		var label := _labels[used]
		used += 1
		if label.text != mark.text:
			label.text = mark.text
			label.reset_size()
		var rect: Rect2 = mark.rect
		label.position = Vector2(rect.get_center().x - label.size.x * 0.5, rect.end.y + LABEL_GAP).floor()
		label.visible = true
	for i in range(used, _labels.size()):
		_labels[i].visible = false


func _draw() -> void:
	_drawn = _marks.size()
	if _marks.is_empty():
		return
	var s1 := float(THEME.get_constant(&"s1", &"MechTokens"))
	var color := THEME.get_color(&"g4", &"MechTokens")
	var lines := PackedVector2Array()
	for mark in _marks:
		lines.append_array(Reticle.bracket_rect_lines(mark.rect))
	draw_multiline(lines, color, s1)
