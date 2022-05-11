extends ParallaxBackground

var scroll_speed = 20.0
var mouse_hovered = false

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

func _process(delta):
	if mouse_hovered == true and scroll_speed <= 70:
		scroll_speed += 0.1
	elif scroll_speed >= 20:
		scroll_speed -= 0.1
	scroll_offset.x += scroll_speed * delta

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass



func _on_launch_system_button_mouse_entered():
	mouse_hovered = true


func _on_launch_system_button_mouse_exited():
	mouse_hovered = false


func _on_exit_system_button_mouse_entered():
	mouse_hovered = true


func _on_exit_system_button_mouse_exited():
	mouse_hovered = true
