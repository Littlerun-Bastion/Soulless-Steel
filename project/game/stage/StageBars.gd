class_name StageBars
extends CanvasLayer

const BAR_LAYER := 100

@export var height_ratio := 0.12
@export var transition_time := 0.6

var _top: ColorRect
var _bottom: ColorRect
var _height := 0.0
var _tween: Tween


func _ready() -> void:
	layer = BAR_LAYER
	_top = _make_bar(false)
	_bottom = _make_bar(true)
	_apply_height(0.0)
	get_viewport().size_changed.connect(_on_viewport_resized)


func show_bars() -> Tween:
	return _tween_to(_target_height())


func hide_bars() -> Tween:
	return _tween_to(0.0)


func is_shown() -> bool:
	return _height > 0.0


func _target_height() -> float:
	return get_viewport().get_visible_rect().size.y * height_ratio


func _on_viewport_resized() -> void:
	if _height > 0.0 and (_tween == null or not _tween.is_valid()):
		_apply_height(_target_height())


func _make_bar(at_bottom: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0 if at_bottom else 0.0
	bar.anchor_bottom = 1.0 if at_bottom else 0.0
	add_child(bar)
	return bar


func _apply_height(value: float) -> void:
	_height = value
	_top.offset_bottom = value
	_bottom.offset_top = -value


func _tween_to(value: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(_apply_height, _height, value, transition_time)
	return _tween
