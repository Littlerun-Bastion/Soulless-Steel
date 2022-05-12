extends Control


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

var scroll_speed = 20.0
var mouse_hovered = false


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _process(delta):
	if mouse_hovered and scroll_speed <= 70:
		scroll_speed += 0.1
	elif scroll_speed >= 20:
		scroll_speed -= 0.1
	$ParallaxBackground.scroll_offset.x += scroll_speed * delta

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
