@tool
class_name StyleBoxDashed
extends StyleBox

@export var bg_color := Color(0, 0, 0, 0):
	set(value):
		bg_color = value
		emit_changed()

@export var border_color := Color(0.227, 0.227, 0.227, 1):
	set(value):
		border_color = value
		emit_changed()

# Stroke weight in pixels. Use 1 (S1) or 2 (S2).
@export_range(1, 3) var border_width := 1:
	set(value):
		border_width = value
		emit_changed()

@export_range(1, 16) var dash_length := 4:
	set(value):
		dash_length = value
		emit_changed()

@export_range(1, 16) var gap_length := 3:
	set(value):
		gap_length = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())

	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_rect(to_canvas_item, r, bg_color)

	if border_color.a <= 0.0:
		return

	var left := int(r.position.x)
	var top := int(r.position.y)
	var right := int(r.end.x)
	var bottom := int(r.end.y)
	var w := border_width

	_dash_row(to_canvas_item, left, right, top, w)
	_dash_row(to_canvas_item, left, right, bottom - w, w)
	_dash_column(to_canvas_item, top, bottom, left, w)
	_dash_column(to_canvas_item, top, bottom, right - w, w)


func _dash_row(canvas_item: RID, from_x: int, to_x: int, y: int, w: int) -> void:
	var x := from_x
	while x < to_x:
		var length := mini(dash_length, to_x - x)
		RenderingServer.canvas_item_add_rect(canvas_item, Rect2(x, y, length, w), border_color)
		x += dash_length + gap_length


func _dash_column(canvas_item: RID, from_y: int, to_y: int, x: int, w: int) -> void:
	var y := from_y
	while y < to_y:
		var length := mini(dash_length, to_y - y)
		RenderingServer.canvas_item_add_rect(canvas_item, Rect2(x, y, w, length), border_color)
		y += dash_length + gap_length
