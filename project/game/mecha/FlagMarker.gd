class_name FlagMarker
extends Node2D

## The emergency Flag's marker on a mecha (Mecha.enter_flagged_state), drawn
## by the engine in the monochrome palette until there is a sprite for it.
##   entry    a white flash over the hull and a ring thrown outward
##            (FLASH_TIME, RING_TIME)
##   flagged  a broken ring round the mecha with four chevrons pointing in,
##            pulsing once a heartbeat (Mecha.FLAG_HEARTBEAT_TIME)
## It stays level while the mecha turns, draws over it unshaded (it reads in
## the dark and at combat range) and, as the mecha's child, fades with it
## when the mecha is out of sight. The mecha frees it when it dies.

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

var _age := 0.0


func _ready() -> void:
	z_index = 10
	light_mask = 0
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded


func _process(delta: float) -> void:
	_age += delta
	global_rotation = 0.0
	queue_redraw()


func _draw() -> void:
	var flash := 1.0 - clampf(_age / FLASH_TIME, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, FLASH_RADIUS, Color(G6, 0.7 * flash))
	var ring := clampf(_age / RING_TIME, 0.0, 1.0)
	if ring < 1.0:
		draw_arc(Vector2.ZERO, RADIUS + RING_REACH * ring, 0.0, TAU, 64,
				Color(G6, 1.0 - ring), maxf(WIDTH * (1.0 - ring), 2.0))

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
