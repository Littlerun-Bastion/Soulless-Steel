class_name PilotNetLogo
extends Control

## pilot.net's emblem in its new look: four wings round a body, like a moth
## seen from above, in the theme's greys (MechTokens). It sits beside the
## "pilot.net" wordmark (a Label) and is drawn at whole pixels in the middle
## of the control.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const SIZE := Vector2(40, 32)
## Each wing: its corners in a SIZE box, and its MechTokens grey.
const WINGS := [
	[[Vector2(19, 15), Vector2(3, 2), Vector2(1, 12), Vector2(15, 17)], "g6"],
	[[Vector2(21, 15), Vector2(37, 2), Vector2(39, 12), Vector2(25, 17)], "g5"],
	[[Vector2(18, 18), Vector2(6, 26), Vector2(11, 30), Vector2(19, 21)], "g4"],
	[[Vector2(22, 18), Vector2(34, 26), Vector2(29, 30), Vector2(21, 21)], "g5"],
]
const BODY := Rect2(19, 11, 3, 14)
const BODY_GREY := "g6"


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var origin := ((size - SIZE) / 2.0).floor()
	for wing in WINGS:
		var points := PackedVector2Array()
		for point in wing[0]:
			points.append(origin + point)
		draw_colored_polygon(points, THEME.get_color(wing[1], "MechTokens"))
	draw_rect(Rect2(origin + BODY.position, BODY.size), THEME.get_color(BODY_GREY, "MechTokens"))
