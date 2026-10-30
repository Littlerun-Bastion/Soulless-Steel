class_name DashArrow
extends Node2D

## One dash direction around the player's mecha, drawn as a chevron that
## points away from the mecha (up, before the node's rotation).
##   fill     G5, rises from the back of the chevron to its tip as the
##            thruster recharges (percent 0 -> 1)
##   outline  a child DashArrow with outline = true: S1 G4, 3px outside
##            the chevron
## Replaces the thruster_arrow sprites (0.7 scale) and their shader.
## Lines are antialiased because the arrows turn with the mecha.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const HALF_WIDTH := 28.0
const HALF_HEIGHT := 14.0
const THICKNESS := 8.0
const OUTLINE_GAP := 3.0

## How much of the chevron is filled, 0 to 1.
var percent := 1.0:
	set(value):
		percent = clampf(value, 0.0, 1.0)
		queue_redraw()
## Draw the outline instead of the fill.
@export var outline := false:
	set(value):
		outline = value
		queue_redraw()


## The chevron, tip up, centred on the origin.
static func chevron() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -HALF_HEIGHT), Vector2(HALF_WIDTH, HALF_HEIGHT),
		Vector2(HALF_WIDTH - THICKNESS, HALF_HEIGHT), Vector2(0, -HALF_HEIGHT + THICKNESS),
		Vector2(-HALF_WIDTH + THICKNESS, HALF_HEIGHT), Vector2(-HALF_WIDTH, HALF_HEIGHT),
	])


## The filled part of the chevron at a given percent (empty at 0).
static func fill_polygons(amount: float) -> Array:
	if amount <= 0.0:
		return []
	var top := HALF_HEIGHT - 2.0 * HALF_HEIGHT * minf(amount, 1.0)
	var band := PackedVector2Array([
		Vector2(-HALF_WIDTH - 1, top), Vector2(HALF_WIDTH + 1, top),
		Vector2(HALF_WIDTH + 1, HALF_HEIGHT + 1), Vector2(-HALF_WIDTH - 1, HALF_HEIGHT + 1),
	])
	return Geometry2D.intersect_polygons(chevron(), band)


func _draw() -> void:
	if outline:
		for poly in Geometry2D.offset_polygon(chevron(), OUTLINE_GAP, Geometry2D.JOIN_MITER):
			var closed: PackedVector2Array = poly
			closed.append(poly[0])
			draw_polyline(closed, THEME.get_color(&"g4", &"MechTokens"), 1.0, true)
		return
	for poly in fill_polygons(percent):
		draw_colored_polygon(poly, THEME.get_color(&"g5", &"MechTokens"))
