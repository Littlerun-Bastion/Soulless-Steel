extends EntityBody
class_name CystBody

# Placeholder look for a Cyst until there's art: a lumpy organic mound with
# veins and glowing pores. It breathes slowly while asleep, and faster, with
# brighter pores, once awake; dead, it's torn open and dark. length is its
# diameter.

const OUTLINE_POINTS := 28
const PORES := [Vector2(0.18, -0.2), Vector2(-0.22, -0.1), Vector2(0.05, 0.25),
		Vector2(-0.1, 0.12), Vector2(0.28, 0.12)]

var awake := false
var _time := 0.0


func update_motion(_motion: Vector2, dt: float) -> void:
	if not dead:
		_time += dt * (3.0 if awake else 1.0)
	queue_redraw()


func _draw() -> void:
	var r := length * 0.5
	var shell := shell_color.lerp(Color.WHITE, flash)
	var ridge := ridge_color.lerp(Color.WHITE, flash)
	if dead:
		shell = shell.darkened(0.45)
		ridge = ridge.darkened(0.45)
	var breath := 1.0 if dead else 1.0 + sin(_time * 2.0) * 0.03
	var outline := PackedVector2Array()
	for k in OUTLINE_POINTS:
		var a := TAU * k / OUTLINE_POINTS
		var lump := 0.88 + 0.12 * sin(a * 5.0 + 1.3) * cos(a * 3.0)
		outline.append(Vector2.from_angle(a) * r * lump * breath)
	draw_colored_polygon(outline, shell)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, ridge, 3.0)
	for v in 6:
		var a := TAU * v / 6 + 0.4
		draw_line(Vector2.from_angle(a) * r * 0.15, Vector2.from_angle(a + 0.25) * r * 0.8, ridge, 4.0)
	if dead:
		# Burst open.
		var hole := PackedVector2Array()
		for k in 10:
			var a := TAU * k / 10
			hole.append(Vector2.from_angle(a) * r * (0.32 + 0.1 * sin(a * 3.0)))
		draw_colored_polygon(hole, Color(0.05, 0.04, 0.04))
		return
	var glow := eye_color.lerp(Color.WHITE, flash)
	glow.a = (0.75 if awake else 0.4) + 0.25 * sin(_time * 3.0)
	for pore in PORES:
		draw_circle(pore * length, r * 0.07, glow)
