class_name HudContacts
extends Control

## Ping contacts on the HUD (ContactStore, reveal "ping"): an S1 corner
## bracket where a ward or drone last put a mecha or Entity, with its kind
## under it, drawn through walls and darkness. The device reports every
## couple of seconds, so a marker jumps rather than tracks. Once the device
## loses the body, the marker stays where it was last put and fades out over
## ContactStore.GHOST_TIME. Vision contacts need nothing here: the player's
## view shows the body itself (Player._update_view), or HudVisionOutlines
## outlines it.
##
## A ping off screen (or too near the edge for its bracket and label,
## BRACKET_ROOM) is an arrow at the screen's edge instead, pointing from
## the middle of the screen toward it, with its kind and distance from the
## player beside it ("MECH 120M"); it fades the same way. Wards and drones see
## further than the screen shows, so most pings are arrows.
##
## Debug setting "all_contacts": every contact of every mecha is drawn too,
## sight included, on screen only. The player's own other contacts are
## brackets in G4; other mechas' are crosses in G3 labelled
## "<kind> · <owner>", to show what each NPC knows.
##
## Bracket and arrow G5, labels LabelMeta (MechTheme). The labels are a fixed
## pool.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const BRACKET_HALF := 24.0
const CROSS_HALF := 10.0
const LABEL_GAP := 6.0
## Debug markers this far (px) outside the screen are not drawn.
const EDGE := 40.0
## Edge arrows: how far (px) inside the screen's edge they sit (inside the
## exit marker's, ExitMarker.EDGE_MARGIN), their size, and how far their
## label sits back toward the middle.
const ARROW_MARGIN := Vector2(70, 70)
const ARROW_SIZE := 18.0
const ARROW_LABEL_GAP := 40.0
## A ping keeps its bracket only this far (px) inside the screen's edge,
## room for the bracket and its label; nearer the edge it is an arrow.
const BRACKET_ROOM := 56.0
const PX_PER_METRE := 20.0
const MAX_LABELS := 32

var player = null
var mechas: Array = []

# What is drawn this frame: {"at", "color", "alpha", "cross", "arrow", "dir",
# "text"}. An arrow's "at" is its place on the screen's edge.
var _marks: Array[Dictionary] = []
var _labels: Array[Label] = []
var _drawn := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in MAX_LABELS:
		var label := MechUI.label(&"LabelMeta")
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)


func setup(player_ref, mechas_ref: Array) -> void:
	player = player_ref
	mechas = mechas_ref


func player_died() -> void:
	player = null
	_marks.clear()
	_show_labels()
	queue_redraw()


## The markers on show: {"at" (screen px), "alpha", "text", "cross", "arrow",
## "dir"}.
func get_marks() -> Array[Dictionary]:
	return _marks


## Where a ray from the middle of an area of this size, going in dir, meets a
## rectangle ARROW_MARGIN inside its edges.
static func edge_point(area: Vector2, dir: Vector2) -> Vector2:
	var center := area / 2.0
	var half := center - ARROW_MARGIN
	var tx := INF if is_zero_approx(dir.x) else half.x / absf(dir.x)
	var ty := INF if is_zero_approx(dir.y) else half.y / absf(dir.y)
	return center + dir * minf(tx, ty)


func _process(_delta: float) -> void:
	_marks.clear()
	if is_instance_valid(player):
		_collect()
	_show_labels()
	if not _marks.is_empty() or _drawn > 0:
		queue_redraw()


func _collect() -> void:
	var to_screen: Transform2D = player.get_viewport().get_canvas_transform()
	var bright := THEME.get_color(&"g5", &"MechTokens")
	var screen := get_viewport_rect().size
	for contact in player.contacts.query({"reveal": "ping"}):
		var at: Vector2 = to_screen * contact.position
		var alpha: float = 1.0 - player.contacts.ghost_fade(contact)
		var kind: String = contact.kind.to_upper()
		if Rect2(Vector2.ZERO, screen).grow(-BRACKET_ROOM).has_point(at):
			_add(at, bright, alpha, false, kind)
			continue
		var dir := (at - screen / 2.0).normalized()
		var metres := roundi(player.global_position.distance_to(contact.position) / PX_PER_METRE)
		_marks.append({"at": edge_point(screen, dir).round(), "color": bright, "alpha": alpha,
				"cross": false, "arrow": true, "dir": dir, "text": "%s %dM" % [kind, metres]})
	if not Debug.get_setting("all_contacts"):
		return
	var dim := THEME.get_color(&"g4", &"MechTokens")
	var faint := THEME.get_color(&"g3", &"MechTokens")
	for mecha in mechas:
		if not is_instance_valid(mecha):
			continue
		var store: ContactStore = mecha.contacts
		var own: bool = mecha == player
		for contact in store.get_all():
			if own and contact.reveal == "ping":
				continue
			var text: String = contact.kind.to_upper()
			if not own:
				text += " · " + str(mecha.mecha_name)
			_add(to_screen * contact.position, dim if own else faint, 1.0 - store.ghost_fade(contact),
					not own, text)


func _add(at: Vector2, color: Color, alpha: float, cross: bool, text: String) -> void:
	var screen := get_viewport_rect().size
	if at.x < -EDGE or at.y < -EDGE or at.x > screen.x + EDGE or at.y > screen.y + EDGE:
		return
	_marks.append({"at": at.round(), "color": color, "alpha": alpha, "cross": cross, "arrow": false,
			"dir": Vector2.ZERO, "text": text})


func _show_labels() -> void:
	for i in _labels.size():
		var label := _labels[i]
		if i >= _marks.size():
			label.visible = false
			continue
		var mark := _marks[i]
		if label.text != mark.text:
			label.text = mark.text
			label.reset_size()
		if mark.arrow:
			var back: Vector2 = mark.at - mark.dir * ARROW_LABEL_GAP
			label.position = (back - label.size * 0.5).floor()
		else:
			var below: float = CROSS_HALF if mark.cross else BRACKET_HALF
			label.position = (mark.at + Vector2(-label.size.x * 0.5, below + LABEL_GAP)).floor()
		label.modulate.a = mark.alpha
		label.visible = true


func _draw() -> void:
	_drawn = _marks.size()
	var s1 := float(THEME.get_constant(&"s1", &"MechTokens"))
	for mark in _marks:
		var color: Color = mark.color
		color.a = mark.alpha
		var at: Vector2 = mark.at
		if mark.arrow:
			# The exit marker's arrow shape, smaller.
			var dir: Vector2 = mark.dir
			var side := dir.orthogonal() * ARROW_SIZE * 0.75
			var back := at - dir * ARROW_SIZE * 0.5
			draw_colored_polygon(PackedVector2Array([at + dir * ARROW_SIZE, back + side,
					at - dir * ARROW_SIZE * 0.05, back - side]), color)
		elif mark.cross:
			var h := CROSS_HALF
			draw_line(at + Vector2(-h, -h), at + Vector2(h, h), color, s1)
			draw_line(at + Vector2(-h, h), at + Vector2(h, -h), color, s1)
		else:
			var lines := Reticle.bracket_lines(BRACKET_HALF)
			for i in lines.size():
				lines[i] += at
			draw_multiline(lines, color, s1)
