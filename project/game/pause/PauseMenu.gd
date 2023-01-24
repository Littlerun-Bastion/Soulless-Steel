extends CanvasLayer

signal pause_toggle

onready var ViewContainer = $ViewportContainer/Viewport/Control
onready var ResumeButton = $ViewportContainer/Viewport/Control/MarginContainer/VBoxContainer/Resume
onready var QuitButton = $ViewportContainer/Viewport/Control/MarginContainer/VBoxContainer/Quit

func _ready():
	$ViewportContainer.hide()
	disable()

func is_paused():
	return $ViewportContainer.visible


func enable():
	ViewContainer.mouse_filter = Control.MOUSE_FILTER_STOP
	MouseManager.show_cursor()
	ShaderEffects.play_transition(0, 1000, 2.0)
	ResumeButton.disabled = false
	QuitButton.disabled = false
	


func disable():
	ResumeButton.disabled = true
	QuitButton.disabled = true
	ViewContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle_pause():
	$ViewportContainer.visible = not $ViewportContainer.visible
	$ParallaxBackground/GridLayer.visible = not $ParallaxBackground/GridLayer.visible
	$ParallaxBackground/GridLayer2.visible = not $ParallaxBackground/GridLayer2.visible
	if $ViewportContainer.visible:
		enable()
	else:
		MouseManager.hide_cursor()
		disable()

	
	emit_signal("pause_toggle", $ViewportContainer.visible)

func _on_Button_mouse_entered():
	if is_paused():
		AudioManager.play_sfx("select")


func _on_Quit_pressed():
	AudioManager.play_sfx("back")
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/start_menu/StartMenuDemo.tscn")


func _on_Resume_pressed():
	AudioManager.play_sfx("confirm")
	toggle_pause()

