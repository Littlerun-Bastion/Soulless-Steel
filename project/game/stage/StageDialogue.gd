class_name StageDialogue
extends CanvasLayer

const DIALOGUE_LAYER := 101
const BOTTOM_GAP := 6.0
const MIN_WIDTH := 520.0
const MAX_WIDTH_RATIO := 0.7
const SPEAKER_SIZE := 20
const BODY_SIZE := 24
const HINT_SIZE := 16

@export var reveal_speed := 38.0
@export var hint_text := "[ press any key ]"

var _box: PanelContainer
var _speaker: Label
var _body: Label
var _hint: Label
var _revealing := false
var _expects_input := true


func _ready() -> void:
	layer = DIALOGUE_LAYER
	_build()
	clear()
	get_viewport().size_changed.connect(_layout)


func say(speaker_name: String, text: String, expects_input := true) -> void:
	_expects_input = expects_input
	_speaker.text = speaker_name
	_body.text = text
	_body.visible_ratio = 0.0
	_revealing = text != ""
	_hint.visible = false
	_box.visible = true
	_layout()


func is_revealing() -> bool:
	return _revealing


func finish_reveal() -> void:
	_body.visible_ratio = 1.0
	_revealing = false
	_hint.visible = _expects_input


func clear() -> void:
	_revealing = false
	_box.visible = false
	_speaker.text = ""
	_body.text = ""
	_hint.visible = false


func get_box() -> PanelContainer:
	return _box


func get_body_label() -> Label:
	return _body


func get_speaker_label() -> Label:
	return _speaker


func get_hint_label() -> Label:
	return _hint


func _build() -> void:
	_box = PanelContainer.new()
	_box.name = "Box"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	style.set_content_margin_all(8.0)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	_box.add_theme_stylebox_override("panel", style)
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_box)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	_box.add_child(column)

	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	_speaker = _make_label("Speaker", SPEAKER_SIZE, heading)
	_speaker.modulate = Color(0.55, 0.9, 0.75)
	_speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint = _make_label("Hint", HINT_SIZE, heading)
	_hint.text = hint_text
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.45)

	_body = _make_label("Body", BODY_SIZE, column)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layout()


func _make_label(label_name: String, font_size: int, parent: Control) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var natural := _body.get_theme_font("font").get_string_size(_body.text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
	_body.custom_minimum_size.x = clampf(natural, MIN_WIDTH, screen.x * MAX_WIDTH_RATIO)
	_box.offset_left = 0.0
	_box.offset_right = 0.0
	_box.offset_top = -BOTTOM_GAP
	_box.offset_bottom = -BOTTOM_GAP
	_box.reset_size()


func _process(dt: float) -> void:
	if not _revealing:
		return
	_body.visible_ratio = minf(_body.visible_ratio + dt * reveal_speed / maxf(_body.text.length(), 1.0), 1.0)
	if _body.visible_ratio >= 1.0:
		finish_reveal()
