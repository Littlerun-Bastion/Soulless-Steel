extends Node2D
class_name TickSwarmBody

# The look of a tick swarm: every mote on the ground drawn in one pass (one
# _draw for the whole swarm, no node per mote), pale white glows on the
# black, white and grey palette. On the ground they pulse and flicker at
# random (TickSwarm sets each mote's flicker); a brood's pulse and flicker
# more slowly and more brightly. Unshaded, so they glow in the dark. Only
# redrawn while on screen.
#
# What the Entity uses: flash (0..1, white when hit), dead, update_motion()
# and die(), like any Entity body. A killed swarm's Carcass shows
# make_corpse(): a few dead ticks clumped where it was.

## Placeholders.
const MOTE_SIZE := 3.5
const GLOW_SIZE := 2.8          # the glow's radius, in mote sizes
const BRIGHTNESS := 0.7
const BROOD_BRIGHTNESS := 1.0
const PULSE_SPEED := 2.6        # radians per second
const BROOD_PULSE_SPEED := 1.1
const PULSE_DEPTH := 0.35
const OFF_SCREEN_MARGIN := 200.0
const CORE_COLOR := Color(0.92, 0.92, 0.92)
const GLOW_COLOR := Color(1.0, 1.0, 1.0)

var flash := 0.0
var dead := false
var swarm: TickSwarm = null


func _ready() -> void:
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded


func update_motion(_velocity: Vector2, _dt: float) -> void:
	pass


func die() -> void:
	dead = true
	flash = 0.0


## What a Carcass shows for a killed swarm: its motes are gone, so a fixed
## clump of dead ticks.
func make_corpse() -> Node2D:
	return DeadMotes.new()


class DeadMotes extends Node2D:
	var dead := true
	const POINTS := [Vector2(0, 0), Vector2(9, 4), Vector2(-7, 6), Vector2(4, -8), Vector2(-10, -3),
			Vector2(13, -5), Vector2(-3, 12)]
	const COLOR := Color(0.45, 0.45, 0.45)

	func _draw() -> void:
		for point in POINTS:
			draw_circle(point, MOTE_SIZE, COLOR)


func _process(_delta: float) -> void:
	if swarm == null or not is_inside_tree():
		return
	var profile_start := FrameProfiler.start()
	if MapSenses.screen_rect(self, OFF_SCREEN_MARGIN + swarm.patch_radius).has_point(global_position):
		queue_redraw()
	FrameProfiler.add("tick_swarms", profile_start)


func _draw() -> void:
	if swarm == null:
		return
	var brood := swarm.brood
	var base := BROOD_BRIGHTNESS if brood else BRIGHTNESS
	var speed := BROOD_PULSE_SPEED if brood else PULSE_SPEED
	var size := MOTE_SIZE * (1.15 if brood else 1.0)
	for mote in swarm.get_motes():
		var pulse := 1.0 - PULSE_DEPTH * (0.5 + 0.5 * sin(mote.phase * speed))
		var bright := clampf(base * pulse * (1.0 - mote.flicker) + flash, 0.0, 1.0)
		if dead:
			bright *= 0.6
		draw_circle(mote.pos, size * GLOW_SIZE, Color(GLOW_COLOR, 0.16 * bright))
		draw_circle(mote.pos, size, Color(CORE_COLOR, bright))
		draw_circle(mote.pos, size * 0.45, Color(GLOW_COLOR, bright))
