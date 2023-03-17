@tool
extends Control

const HEIGHT = 12
const MIDDLE_WIDTH = 180
const RIGHT_WIDTH = 16
const LINE_WIDTH = 4
const COLOR = Color(1,1,1)

func _draw():
# warning-ignore-all:integer_division
	draw_line(Vector2(LINE_WIDTH/2,-HEIGHT),Vector2(LINE_WIDTH/2, 0),COLOR,LINE_WIDTH)
	draw_line(Vector2(0, 0),Vector2(MIDDLE_WIDTH, 0),COLOR,LINE_WIDTH)
	draw_line(Vector2(MIDDLE_WIDTH - 2, 1),Vector2(MIDDLE_WIDTH + RIGHT_WIDTH - 2, -HEIGHT),COLOR,LINE_WIDTH)
