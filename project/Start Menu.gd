extends Control
var parallaxMult = 30.0

func _ready():
	pass
	
func _input(event):
	if event is InputEventMouseMotion:
		var viewport_size = get_viewport().size
		var mouse_x = event.position.x
		var mouse_y = event.position.y
		var relative_x = (mouse_x - (viewport_size.x/2)) / (viewport_size.x/2)
		var relative_y = (mouse_y - (viewport_size.y/2)) / (viewport_size.y/2)
		$ParallaxBackground/GridLayer.motion_offset.x = parallaxMult * relative_x
		$ParallaxBackground/GridLayer.motion_offset.y = parallaxMult * relative_y

func _on_launch_system_button_pressed():
	get_tree().change_scene("res://game/arena/Arena.tscn")


func _on_exit_system_button_pressed():
	get_tree().quit()


