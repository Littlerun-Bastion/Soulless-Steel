extends Node2D
class_name EntityBody

# Placeholder look for an Entity until there's art: a segmented chitin body,
# walking legs, mandibles and glowing AVIS eyes, drawn in _draw(). Forward is
# +X. The Entity drives it each frame: the leg cycle follows its speed, it
# crouches before a lunge, flashes white when hit, and collapses, legs
# curled, when it dies.

@export var length := 140.0
@export var width := 56.0
@export var leg_pairs := 3
@export var leg_length := 70.0
@export var leg_width := 6.0
@export var has_tail := true
@export var shell_color := Color(0.20, 0.22, 0.24)
@export var ridge_color := Color(0.42, 0.47, 0.48)
@export var eye_color := Color(0.35, 1.0, 0.85)
## A glowing sac on its back (Spitter); transparent = none.
@export var sac_color := Color(0, 0, 0, 0)
## Overlapping armour plates down its back (Brute).
@export var back_plates := 0

var gait := 0.0    # leg cycle, advanced by speed
var crouch := 0.0  # 0..1, squashes the body before a lunge
var flash := 0.0   # 0..1, white when hit
var dead := false

const BODY_POINTS := 20


func update_motion(motion: Vector2, dt: float) -> void:
	if not dead:
		gait = fmod(gait + motion.length() * dt * 0.035, TAU)
	queue_redraw()


func die() -> void:
	dead = true
	crouch = 0.6
	flash = 0.0
	queue_redraw()


func _draw() -> void:
	var squash := 1.0 - crouch * 0.25
	var shell := shell_color.lerp(Color.WHITE, flash)
	var ridge := ridge_color.lerp(Color.WHITE, flash)
	if dead:
		shell = shell.darkened(0.45)
		ridge = ridge.darkened(0.45)
	_draw_legs(ridge, squash)
	if has_tail:
		var sway := 0.0 if dead else sin(gait * 0.5) * width * 0.15
		draw_colored_polygon(PackedVector2Array([
			Vector2(-length * 0.4, -width * 0.2 * squash),
			Vector2(-length * 0.82, sway),
			Vector2(-length * 0.4, width * 0.2 * squash),
		]), shell)
	# Body
	var body := PackedVector2Array()
	for k in BODY_POINTS:
		var a := TAU * k / BODY_POINTS
		body.append(Vector2(cos(a) * length * 0.5, sin(a) * width * 0.5 * squash))
	draw_colored_polygon(body, shell)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, ridge, 2.0)
	# Segment ridges across the back
	for s in 3:
		var x := lerpf(-length * 0.3, length * 0.15, s / 2.0)
		draw_line(Vector2(x, -width * 0.4 * squash), Vector2(x + 8.0, width * 0.4 * squash), ridge, 3.0)
	for p in back_plates:
		var x := lerpf(-length * 0.32, length * 0.18, float(p) / maxf(back_plates - 1, 1))
		var plate_w := width * 0.42 * squash
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - length * 0.07, -plate_w), Vector2(x + length * 0.09, 0.0),
			Vector2(x - length * 0.07, plate_w), Vector2(x - length * 0.02, 0.0),
		]), ridge.darkened(0.25))
	if sac_color.a > 0.0:
		var pulse := 1.0 if dead else 1.0 + sin(gait * 0.7) * 0.06
		var sac := sac_color.darkened(0.5) if dead else sac_color.lerp(Color.WHITE, flash)
		draw_circle(Vector2(-length * 0.12, 0.0), width * 0.32 * squash * pulse, sac)
		draw_circle(Vector2(-length * 0.16, -width * 0.08), width * 0.1 * squash, sac.lightened(0.4))
	# Head and mandibles
	draw_colored_polygon(PackedVector2Array([
		Vector2(length * 0.32, -width * 0.32 * squash),
		Vector2(length * 0.62, 0.0),
		Vector2(length * 0.32, width * 0.32 * squash),
	]), shell.lightened(0.08))
	for side in [-1.0, 1.0]:
		draw_line(Vector2(length * 0.55, side * width * 0.1), Vector2(length * 0.72, side * width * 0.22), ridge, 4.0)
	if not dead:
		var eye := eye_color.lerp(Color.WHITE, flash)
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(length * 0.44, side * width * 0.14), 4.5, eye)


func _draw_legs(color: Color, squash: float) -> void:
	for i in leg_pairs:
		var t := (float(i) + 0.5) / leg_pairs
		var x := lerpf(-length * 0.28, length * 0.22, t)
		for side in [-1.0, 1.0]:
			var phase: float = gait + i * PI * 0.66 + (PI if side > 0.0 else 0.0)
			var swing := 0.0 if dead else sin(phase) * 0.45
			var hip := Vector2(x, side * width * 0.35 * squash)
			var knee_dir := Vector2(0.25 + swing, side).normalized()
			var reach := 1.0
			if dead:
				knee_dir = Vector2(0.6, side * 0.5).normalized()
				reach = 0.6
			var knee := hip + knee_dir * leg_length * 0.55
			var foot := knee + Vector2(0.55 + swing * 0.6, side * 0.35).normalized() * leg_length * 0.6 * reach
			draw_polyline(PackedVector2Array([hip, knee, foot]), color, leg_width)
