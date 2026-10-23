class_name StageDialogue
extends CanvasLayer

const DIALOGUE_LAYER := 101
const SIDE_MARGIN := 160.0
const SPEAKER_GAP := 8.0

@export var bottom_margin_ratio := 0.145
@export var reveal_speed := 38.0
@export var hint_text := "[ press any key ]"

var _box: Control
var _speaker: Label
var _body: Label
var _hint: Label
var _revealing := false


func _ready() -> void:
	layer = DIALOGUE_LAYER
	_build()
	clear()
	get_viewport().size_changed.connect(_layout)


func say(speaker_name: String, text: String) -> void:
	_speaker.text = speaker_name
	_speaker.visible = speaker_name != ""
	_body.text = text
	_body.visible_ratio = 0.0
	_revealing = text != ""
	_hint.visible = false
	_box.visible = true


func is_revealing() -> bool:
	return _revealing


func finish_reveal() -> void:
	_body.visible_ratio = 1.0
	_revealing = false
	_hint.visible = true


func clear() -> void:
	_revealing = false
	_box.visible = false
	_speaker.text = ""
	_body.text = ""
	_hint.visible = false


func get_body_label() -> Label:
	return _body


func get_speaker_label() -> Label:
	return _speaker


func get_hint_label() -> Label:
	return _hint


func _build() -> void:
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_box)

	_speaker = _make_label("Speaker")
	_speaker.modulate = Color(0.55, 0.9, 0.75)

	_body = _make_label("Body")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_hint = _make_label("Hint")
	_hint.text = hint_text
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.45)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_layout()


func _make_label(label_name: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	_box.add_child(label)
	return label


func _layout() -> void:
	var base := -get_viewport().get_visible_rect().size.y * bottom_margin_ratio
	var line := _body.get_line_height()
	_place(_speaker, base - line * 2.0 - SPEAKER_GAP, line)
	_place(_body, base - line, line * 2.0)
	_place(_hint, base, line)


func _place(label: Label, top: float, height: float) -> void:
	label.offset_left = SIDE_MARGIN
	label.offset_right = -SIDE_MARGIN
	label.offset_top = top
	label.offset_bottom = top + height


func _process(dt: float) -> void:
	if not _revealing:
		return
	_body.visible_ratio = minf(_body.visible_ratio + dt * reveal_speed / maxf(_body.text.length(), 1.0), 1.0)
	if _body.visible_ratio >= 1.0:
		_revealing = false
		_hint.visible = true
