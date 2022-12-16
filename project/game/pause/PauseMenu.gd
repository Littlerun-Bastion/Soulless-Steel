extends CanvasLayer

signal pause_toggle

onready var ViewContainer = $ViewportContainer/Viewport/Control

func _ready():
	$ViewportContainer.hide()
	ViewContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_paused():
	return $ViewportContainer.visible


func toggle_pause():
	$ViewportContainer.visible = not $ViewportContainer.visible
	$ParallaxBackground/GridLayer.visible = not $ParallaxBackground/GridLayer.visible
	$ParallaxBackground/GridLayer2.visible = not $ParallaxBackground/GridLayer2.visible
	if $ViewportContainer.visible:
		ViewContainer.mouse_filter = Control.MOUSE_FILTER_STOP
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		ShaderEffects.play_transition(0, 1000, 2.0)
	else:
		ViewContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	emit_signal("pause_toggle", $ViewportContainer.visible)

func _on_Button_mouse_entered():
	AudioManager.play_sfx("select")


func _on_Quit_pressed():
	AudioManager.play_sfx("back")
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/start_menu/StartMenu.tscn")


func _on_Resume_pressed():
	AudioManager.play_sfx("confirm")
	toggle_pause()

