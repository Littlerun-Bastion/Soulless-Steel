extends ColorRect

# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
func play_transition(from_value, to_value, duration):
	self.material.set_shader_param("noiseQuality", from_value)
	$Tween.interpolate_property(self.material, "shader_param/noiseQuality", from_value, to_value, duration)
	$Tween.start()
