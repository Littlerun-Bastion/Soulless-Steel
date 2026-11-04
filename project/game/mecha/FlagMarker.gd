class_name FlagMarker
extends Node2D

## The Flag's marker on a mecha (Mecha.raise_flag, enter_flagged_state),
## drawn by the engine in the monochrome palette until there is a sprite for
## it, readable at combat range and in the dark.
##   entry      a white flash over the hull and a ring thrown outward
##              (FLASH_TIME, RING_TIME): the emergency Flag's start
##   emergency  a broken ring round the mecha with four chevrons pointing in,
##              pulsing once a heartbeat (Mecha.FLAG_HEARTBEAT_TIME)
##   voluntary  a steady ring with a flag on a pole above the mecha
##   lowering   the ring is wound down: it shortens from a full circle to
##              nothing over the wind-up (`lowering` 0 to 1), so a Flag coming
##              down can be seen coming
## It stays level while the mecha turns, draws over it unshaded and, as the
## mecha's child, fades with it when the mecha is out of sight. The mecha
## frees it when the Flag comes down or it dies.

const G6 := Color(0.949, 0.949, 0.949)
const RADIUS := 190.0
const WIDTH := 14.0
const CHEVRON := 56.0
const GAP := 0.32  # rad left open each side of a chevron
const FLASH_TIME := 0.3
const FLASH_RADIUS := 150.0
const RING_TIME := 0.6
const RING_REACH := 320.0
const PULSE_MIN := 0.45
const POLE_HEIGHT := 120.0
const FLAG_SIZE := Vector2(70.0, 44.0)

## Raised by choice (a steady ring and a flag), else the emergency look.
var voluntary := false
## 0 while the Flag is up, rising to 1 as it is lowered.
var lowering := 0.0

var _age := 0.0
var _entry := -1.0


func _ready() -> void:
	z_index = 10
	light_mask = 0
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded


## Plays the entry flash and ring (the emergency Flag's start).
func restart_entry() -> void:
	_entry = 0.0


func _process(delta: float) -> void:
	_age += delta
	if _entry >= 0.0:
		_entry += delta
	global_rotation = 0.0
	queue_redraw()


func _draw() -> void:
	if _entry >= 0.0:
		var flash := 1.0 - clampf(_entry / FLASH_TIME, 0.0, 1.0)
		if flash > 0.0:
			draw_circle(Vector2.ZERO, FLASH_RADIUS, Color(G6, 0.7 * flash))
		var ring := clampf(_entry / RING_TIME, 0.0, 1.0)
		if ring < 1.0:
			draw_arc(Vector2.ZERO, RADIUS + RING_REACH * ring, 0.0, TAU, 64,
					Color(G6, 1.0 - ring), maxf(WIDTH * (1.0 - ring), 2.0))
	if lowering > 0.0:
		# Wound down: what is left of the ring, from the top, clockwise.
		var left := clampf(1.0 - lowering, 0.0, 1.0)
		if left > 0.01:
			draw_arc(Vector2.ZERO, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * left, 64, G6, WIDTH)
		_draw_flag(Color(G6, 0.5 + 0.5 * left), left)
		return
	if voluntary:
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, G6, WIDTH)
		_draw_flag(G6, 1.0)
		return
	var beat := fposmod(_age, Mecha.FLAG_HEARTBEAT_TIME) / Mecha.FLAG_HEARTBEAT_TIME
	var color := Color(G6, lerpf(1.0, PULSE_MIN, beat))
	for i in 4:
		var at := i * PI * 0.5
		draw_arc(Vector2.ZERO, RADIUS, at + GAP, at + PI * 0.5 - GAP, 24, color, WIDTH)
		var dir := Vector2.RIGHT.rotated(at)
		var side := dir.orthogonal() * CHEVRON * 0.6
		var tip := dir * (RADIUS - CHEVRON * 0.4)
		var back := dir * (RADIUS + CHEVRON * 0.6)
		draw_polyline(PackedVector2Array([back + side, tip, back - side]), color, WIDTH)


# A flag on a pole above the ring; `raised` 1 is fully up, 0 down at the
# pole's foot.
func _draw_flag(color: Color, raised: float) -> void:
	var foot := Vector2(0.0, -RADIUS)
	var top := foot + Vector2(0.0, -POLE_HEIGHT)
	draw_line(foot, top, color, WIDTH * 0.5)
	var hoist := foot.lerp(top, raised)
	var flag := PackedVector2Array([hoist, hoist + Vector2(FLAG_SIZE.x, FLAG_SIZE.y * 0.5), hoist + Vector2(0.0, FLAG_SIZE.y)])
	draw_colored_polygon(flag, color)
