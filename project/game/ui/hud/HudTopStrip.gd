class_name HudTopStrip
extends CanvasLayer

## The text on the black strip along the top of the screen while in a run:
##   left   HELWAN // GRID C3 · [ALT] OS
##   right  T+18:42 · −10°C
## The strip itself is MechOS's top bar (layer 10); this layer sits just
## above it so the text shows. The grid square is the player's cell in a
## 5 x 5 grid over the map bounds (A–E across, 1–5 down), the same grid the
## Deployments survey will use. Without a site (Arena), only the OS hint shows.
## The run clock stops while the game is paused.

const GRID := 5
const PAD := 15
const STRIP_HEIGHT := 30

var player = null
var elapsed := 0.0
var _site := ""
var _bounds := Rect2()

var _site_label: Label
var _detail_label: Label
var _right_label: Label


func _ready() -> void:
	layer = 11
	var strip := Control.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_left = PAD
	strip.offset_right = -PAD
	strip.offset_bottom = STRIP_HEIGHT
	strip.theme = preload("res://game/ui/mech_os/MechTheme.tres")
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	var left := MechUI.hbox(&"TabRow")
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_site_label = MechUI.label(&"LabelMetaBright")
	_detail_label = MechUI.label(&"LabelMeta")
	for label in [_site_label, _detail_label]:
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		left.add_child(label)
	strip.add_child(left)

	_right_label = MechUI.label(&"LabelMeta")
	_right_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_right_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip.add_child(_right_label)
	MechUI.ignore_mouse(strip)
	_refresh_left()


func setup(player_ref) -> void:
	player = player_ref
	elapsed = 0.0


## The site name and the map area the grid covers (world coordinates).
func set_site(site_name: String, bounds: Rect2) -> void:
	_site = site_name.to_upper()
	_bounds = bounds
	_refresh_left()


func player_died() -> void:
	player = null


## "C3" for a position, "" without bounds.
func grid_square(pos: Vector2) -> String:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return ""
	var rel := (pos - _bounds.position) / _bounds.size
	var col := clampi(int(rel.x * GRID), 0, GRID - 1)
	var row := clampi(int(rel.y * GRID), 0, GRID - 1)
	return "%s%d" % [char(65 + col), row + 1]


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	elapsed += delta
	_refresh_left()
	var total := int(elapsed)
	_right_label.text = "T+%02d:%02d · %d°C" % [total / 60, total % 60, roundi(player.AMBIENT_TEMP)]


func _refresh_left() -> void:
	if _site_label == null:
		return
	var hint := "[%s] OS" % MechUI.key_name("free_cursor") if InputMap.has_action("free_cursor") else "[ALT] OS"
	_site_label.text = _site
	_site_label.visible = _site != ""
	var square := grid_square(player.global_position) if is_instance_valid(player) and _site != "" else ""
	_detail_label.text = ("// GRID %s · %s" % [square, hint]) if square != "" else hint
