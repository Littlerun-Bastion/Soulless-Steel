extends CanvasLayer

@onready var ReturnButton = $SubViewportContainer/SubViewport/Control/ReturnButton
@onready var LossLabel = $SubViewportContainer/SubViewport/Control/LossLabel

func _ready():
	disable()


func enable():
	MouseManager.force_pointer(true)
	$SubViewportContainer.visible = true
	ShaderEffects.reset_shader_effect("gameover")
	ReturnButton.disabled = false


func disable():
	$SubViewportContainer.visible = false
	ReturnButton.disabled = true


# loss_text: what the player lost (Expedition), shown above the prompt.
func killed(loss_text := ""):
	LossLabel.text = loss_text
	LossLabel.visible = loss_text != ""
	enable()


func _on_ReturnButton_pressed():
	TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")
