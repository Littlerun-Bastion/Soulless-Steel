extends Node2D

## The radar ring around the player's mecha: S1 G4, RADIUS px. The tracks
## sit on and outside it (PlayerRadar). Placeholder radius.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const RADIUS := 140.0


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 128, THEME.get_color(&"g4", &"MechTokens"), 1.0, true)
