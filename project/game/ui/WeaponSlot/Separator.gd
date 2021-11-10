tool
extends Control

const HEIGHT = 50
const EDGE_WIDTH = 9
const MIDDLE_WIDTH = 50
const LINE_WIDTH = 4
const COLOR = Color(1,1,1)

func _draw():
	draw_line(Vector2(0,HEIGHT), Vector2(EDGE_WIDTH + LINE_WIDTH/2.0, HEIGHT), COLOR, LINE_WIDTH, true)
	draw_line(Vector2(EDGE_WIDTH, HEIGHT), Vector2(EDGE_WIDTH + MIDDLE_WIDTH, 0), COLOR, LINE_WIDTH, true)
	draw_line(Vector2(-LINE_WIDTH/2.0 + EDGE_WIDTH + MIDDLE_WIDTH, 0), Vector2(2*EDGE_WIDTH + MIDDLE_WIDTH, 0), COLOR, LINE_WIDTH, true)
