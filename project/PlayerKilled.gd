extends CanvasLayer


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	$Label.visible = false
	$ReturnButton.visible = false
	$VCREffect.visible = false
	pass # Replace with function body.

func killed():
	yield(get_tree().create_timer(4.0), "timeout")
	$Label.visible = true
	$ReturnButton.visible = true
	$VCREffect.visible = true
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_ReturnButton_pressed():
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://StartMenu.tscn")
