@tool
class_name StyleBoxBands
extends StyleBox

## Flat bands of colour from top to bottom, in place of a gradient (the
## Memorial Wall's "glossy" bars and buttons are a 1 px light line, a lighter
## top half and a darker bottom half). On whole pixels:
##   colors, heights   band i is colors[i], heights[i] px tall; a height of 0
##                     shares the rows the fixed bands leave, evenly
##   border            border_width px of border_color round the bands
##   corners           corner_radius px, pixel-stepped, on the top corners
##                     (round_top) and the bottom ones (round_bottom)
##   open_bottom       no border along the bottom, and the shape drawn
##                     extend_bottom px lower (a tab that joins the page under
##                     it)
##   shadow            the shape again in shadow_color, shadow_offset px away,
##                     behind it (a hard shadow, no blur)

@export var colors := PackedColorArray([Color(0.102, 0.102, 0.102, 1)]):
	set(value):
		colors = value
		emit_changed()

@export var heights := PackedInt32Array([0]):
	set(value):
		heights = value
		emit_changed()

@export var border_color := Color(0.227, 0.227, 0.227, 1):
	set(value):
		border_color = value
		emit_changed()

## Stroke weight in pixels: 0 (none), 1 (S1) or 2 (S2).
@export_range(0, 2) var border_width := 1:
	set(value):
		border_width = value
		emit_changed()

@export_range(0, 16) var corner_radius := 0:
	set(value):
		corner_radius = value
		emit_changed()

@export var round_top := true:
	set(value):
		round_top = value
		emit_changed()

@export var round_bottom := true:
	set(value):
		round_bottom = value
		emit_changed()

@export var open_bottom := false:
	set(value):
		open_bottom = value
		emit_changed()

@export_range(0, 4) var extend_bottom := 0:
	set(value):
		extend_bottom = value
		emit_changed()

@export var shadow_color := Color(0, 0, 0, 0):
	set(value):
		shadow_color = value
		emit_changed()

@export var shadow_offset := Vector2i.ZERO:
	set(value):
		shadow_offset = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var area := Rect2i(Vector2i(rect.position.round()), Vector2i(rect.size.round()))
	area.size.y += extend_bottom
	if area.size.x <= 0 or area.size.y <= 0:
		return
	var bottom_radius := 0 if open_bottom or not round_bottom else corner_radius
	var top_radius := corner_radius if round_top else 0
	if shadow_offset != Vector2i.ZERO and shadow_color.a > 0.0:
		_shape(to_canvas_item, Rect2i(area.position + shadow_offset, area.size), top_radius, bottom_radius,
				PackedColorArray([shadow_color]), PackedInt32Array([0]))
	if border_width <= 0 or border_color.a <= 0.0:
		_shape(to_canvas_item, area, top_radius, bottom_radius, colors, heights)
		return
	_shape(to_canvas_item, area, top_radius, bottom_radius, PackedColorArray([border_color]), PackedInt32Array([0]))
	var inner := Rect2i(area.position + Vector2i(border_width, border_width),
			area.size - Vector2i(border_width * 2, border_width if open_bottom else border_width * 2))
	_shape(to_canvas_item, inner, maxi(top_radius - border_width, 0), maxi(bottom_radius - border_width, 0), colors, heights)


# Fills a shape with stepped corners, band by band: corner rows one at a
# time, the straight rows of a band as one rect.
func _shape(item: RID, area: Rect2i, top_radius: int, bottom_radius: int, band_colors: PackedColorArray,
		band_heights: PackedInt32Array) -> void:
	if area.size.x <= 0 or area.size.y <= 0 or band_colors.is_empty():
		return
	for band in bands(area.size.y, band_colors.size(), band_heights):
		var color: Color = band_colors[int(band[2])]
		var y: int = band[0]
		var band_end: int = band[1]
		while y < band_end:
			var inset := _inset(y, area.size.y, top_radius, bottom_radius)
			if inset == 0:
				var run_end := y
				while run_end < band_end and _inset(run_end, area.size.y, top_radius, bottom_radius) == 0:
					run_end += 1
				RenderingServer.canvas_item_add_rect(item, Rect2(area.position.x, area.position.y + y, area.size.x, run_end - y), color)
				y = run_end
			else:
				if area.size.x - inset * 2 > 0:
					RenderingServer.canvas_item_add_rect(item,
							Rect2(area.position.x + inset, area.position.y + y, area.size.x - inset * 2, 1), color)
				y += 1


## The bands' rows for a shape height px tall: [[from, to, colour index]].
## Fixed heights come first; a 0 height shares what's left (the last of them
## takes any odd row).
static func bands(height: int, count: int, band_heights: PackedInt32Array) -> Array:
	var fixed := 0
	var flexible := 0
	for i in count:
		var h := band_heights[i] if i < band_heights.size() else 0
		if h > 0:
			fixed += h
		else:
			flexible += 1
	var left := maxi(height - fixed, 0)
	var share := floori(left / float(flexible)) if flexible > 0 else 0
	var rows := []
	var y := 0
	var seen := 0
	for i in count:
		var h := band_heights[i] if i < band_heights.size() else 0
		if h <= 0:
			seen += 1
			h = share if seen < flexible else left - share * (flexible - 1)
		var end := mini(y + h, height)
		if end > y:
			rows.append([y, end, i])
		y = end
	if y < height and not rows.is_empty():
		rows[-1][1] = height
	return rows


func _inset(y: int, height: int, top_radius: int, bottom_radius: int) -> int:
	if y < top_radius:
		return corner_inset(top_radius, y)
	var from_bottom := height - 1 - y
	if from_bottom < bottom_radius:
		return corner_inset(bottom_radius, from_bottom)
	return 0


## How far row `row` of a corner of radius r is set in (row 0 the outermost).
static func corner_inset(r: int, row: int) -> int:
	var dy := float(r) - row - 0.5
	var dx := sqrt(maxf(r * r - dy * dy, 0.0))
	return int(roundf(r - dx))
