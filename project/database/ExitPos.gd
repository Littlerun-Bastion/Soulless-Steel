extends Position2D

signal mecha_extracting
signal extracting_cancelled

# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_Area2D_body_entered(body):
	if body is Mecha:
		emit_signal("mecha_extracting", body)


func _on_Area2D_body_exited(body):
	if body is Mecha:
		emit_signal("extracting_cancelled", body)
