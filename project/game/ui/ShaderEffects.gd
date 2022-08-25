extends CanvasLayer

onready var VCREffect = $VCREffect

func play_transition(from_value, to_value, duration):
	self.material.set_shader_param("noiseQuality", from_value)
	$Tween.interpolate_property(self.material, "shader_param/noiseQuality", from_value, to_value, duration)
	$Tween.start()


func update_shader_effect(player):
	if not $Tween.is_active():
		#Noise Intensity
		var target_noise = ((player.max_hp - player.hp)/float(player.max_hp)) * 0.0035
		var value = lerp(VCREffect.material.get_shader_param("noiseIntensity"), target_noise, .9)
		VCREffect.material.set_shader_param("noiseIntensity", value)
		#Color Offset Intensity
		value = lerp(VCREffect.material.get_shader_param("colorOffsetIntensity"), 0.175, .9)
		VCREffect.material.set_shader_param("colorOffsetIntensity", value)

func damage_burst_effect():
	if not $Tween.is_active():
		$Tween.interpolate_property(VCREffect.material, "shader_param/noiseIntensity", null, 0.02, .1)
		$Tween.interpolate_property(VCREffect.material, "shader_param/colorOffsetIntensity", null, 1.2, .1)
		$Tween.start()
