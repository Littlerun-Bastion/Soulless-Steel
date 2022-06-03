extends CanvasLayer


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


func _on_ReturnButton_pressed():
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://StartMenu.tscn")
