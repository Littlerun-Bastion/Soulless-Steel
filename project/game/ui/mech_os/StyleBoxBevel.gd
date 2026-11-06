@tool
class_name StyleBoxBevel
extends StyleBox

## A 1999 bevel on whole pixels: a face with a light edge and a shadow edge.
## Raised: light on the top and left, shadow on the bottom and right.
## Sunken swaps them. Each edge is `width` pixels (S1 or S2); the bottom and
## right edges are drawn last, so they own the two corners they share.

@export var face_color := Color(0.541, 0.541, 0.541, 1):
	set(value):
		face_color = value
		emit_changed()

@export var light_color := Color(0.839, 0.839, 0.839, 1):
	set(value):
		light_color = value
		emit_changed()

@export var shadow_color := Color(0.102, 0.102, 0.102, 1):
	set(value):
		shadow_color = value
		emit_changed()

# Stroke weight in pixels. Use 1 (S1) or 2 (S2).
@export_range(1, 2) var width := 2:
	set(value):
		width = value
		emit_changed()

@export var sunken := false:
	set(value):
		sunken = value
		emit_changed()

## False draws only the top and bottom edges (a bar across a page).
@export var sides := true:
	set(value):
		sides = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	if face_color.a > 0.0:
		RenderingServer.canvas_item_add_rect(to_canvas_item, r, face_color)
	var top_left := shadow_color if sunken else light_color
	var bottom_right := light_color if sunken else shadow_color
	var left := r.position.x
	var top := r.position.y
	var w := float(width)
	RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(left, top, r.size.x, w), top_left)
	if sides:
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(left, top, w, r.size.y), top_left)
	RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(left, r.end.y - w, r.size.x, w), bottom_right)
	if sides:
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(r.end.x - w, top, w, r.size.y), bottom_right)
