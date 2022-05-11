extends ParallaxBackground

var scroll_speed = 20.0
var mouse_hovered = false


func _process(delta):
	if mouse_hovered and scroll_speed <= 70:
		scroll_speed += 0.1
	elif scroll_speed >= 20:
		scroll_speed -= 0.1
	scroll_offset.x += scroll_speed * delta


func _on_launch_system_button_mouse_entered():
	mouse_hovered = true


func _on_launch_system_button_mouse_exited():
	mouse_hovered = false


func _on_exit_system_button_mouse_entered():
	mouse_hovered = true


func _on_exit_system_button_mouse_exited():
	mouse_hovered = true
