extends Control
class_name GridLines

var cols: int = 0
var rows: int = 0
var cell_size: int = 70
var line_color: Color = Color(1, 1, 1, 0.25) 

func setup(cols_in: int, rows_in: int, cell_size_in: int) -> void:
	cols = cols_in
	rows = rows_in
	cell_size = cell_size_in

	custom_minimum_size = Vector2(cols * cell_size, rows * cell_size)
	size = custom_minimum_size

	queue_redraw()


func _draw() -> void:
	if cols <= 0 or rows <= 0:
		return

	var w = cols * cell_size
	var h = rows * cell_size
	var offset = 0.5
	for x in range(cols + 1):
		var x_px = x * cell_size + offset
		draw_line(Vector2(x_px, 0), Vector2(x_px, h), line_color, 1.0)
	for y in range(rows + 1):
		var y_px = y * cell_size + offset
		draw_line(Vector2(0, y_px), Vector2(w, y_px), line_color, 1.0)

#i can't believe this is the best way of doing this, this is so dumb
