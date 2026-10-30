extends Node2D

## The radar ring around the player's mecha: S1 G4, RADIUS px.
## pulse shrinks it for the refresh animation (PlayerRadar tweens it) while
## the line stays 1px.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const RADIUS := 75.0

var pulse := 1.0:
	set(value):
		pulse = value
		queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS * pulse, 0.0, TAU, 96, THEME.get_color(&"g4", &"MechTokens"), 1.0, true)
