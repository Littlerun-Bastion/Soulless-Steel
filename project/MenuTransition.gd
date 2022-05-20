extends ColorRect


func play_transition(from_value, to_value, duration):
	self.material.set_shader_param("noiseQuality", from_value)
	$Tween.interpolate_property(self.material, "shader_param/noiseQuality", from_value, to_value, duration)
	$Tween.start()
