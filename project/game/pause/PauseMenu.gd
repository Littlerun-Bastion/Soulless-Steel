extends CanvasLayer

signal pause_toggle

@onready var ViewContainer = $SubViewportContainer/SubViewport/Control
@onready var ResumeButton = $SubViewportContainer/SubViewport/Control/MarginContainer/VBoxContainer/Resume
@onready var QuitButton = $SubViewportContainer/SubViewport/Control/MarginContainer/VBoxContainer/Quit
@onready var QuitWarning = $SubViewportContainer/SubViewport/Control/QuitWarning

# When set (Expedition), the first Quit press only shows this warning and a
# second press quits. Empty = quit straight away (Arena).
var quit_warning := ""
var _quit_armed := false


func _ready():
	$SubViewportContainer.hide()
	disable()


func is_paused():
	return $SubViewportContainer.visible


func enable():
	MouseManager.force_pointer(true)
	ShaderEffects.play_transition(0, 1000, 2.0)
	ResumeButton.disabled = false
	QuitButton.disabled = false


func disable():
	ResumeButton.disabled = true
	QuitButton.disabled = true


func toggle_pause():
	_disarm_quit()
	$SubViewportContainer.visible = not $SubViewportContainer.visible
	$ParallaxBackground/GridLayer.visible = not $ParallaxBackground/GridLayer.visible
	$ParallaxBackground/GridLayer2.visible = not $ParallaxBackground/GridLayer2.visible
	if $SubViewportContainer.visible:
		AudioManager.play_sfx("pause")
		enable()
	else:
		AudioManager.play_sfx("unpause")
		MouseManager.force_pointer(false)
		disable()
	
	emit_signal("pause_toggle", $SubViewportContainer.visible)


func _on_Button_mouse_entered():
	if is_paused():
		AudioManager.play_sfx("select")


func _on_Quit_pressed():
	if quit_warning != "" and not _quit_armed:
		_quit_armed = true
		QuitWarning.text = quit_warning + "\nPress Quit again to confirm."
		QuitWarning.visible = true
		AudioManager.play_sfx("select")
		return
	AudioManager.play_sfx("back")
	TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")


func _on_Resume_pressed():
	AudioManager.play_sfx("confirm")
	toggle_pause()


func _disarm_quit():
	_quit_armed = false
	if QuitWarning:
		QuitWarning.visible = false
