extends CanvasLayer

@onready var VCREffect = $VCREffect

var tweens = []

func enable():
	VCREffect.show()


func disable():
	VCREffect.hide()


func play_transition(from_value, to_value, duration):
	var tween = get_tree().create_tween()
	VCREffect.material.set_shader_parameter("noiseQuality", from_value)
	tween.tween_property(VCREffect.material, "shader_param/noiseQuality", to_value, duration)
	tweens.append(tween)


func reset_shader_effect(mode):
	for tween in tweens:
		tween.kill()
	tweens = []
	if mode == "arena":
		set_shader_params(0.05, 0.0, 2000.0, 0.0, 0.026, 0.002, 0.48, 0.002, 0.492, 0.0)
	elif mode == "gameover":
		set_shader_params(0.05, 0.0, 866.0, 0.001, 0.026, 0.006, 1.0, 0.0073, 0.97, 0.0)
	elif mode == "score_screen":
		set_shader_params(0.022, 0.002, 3900.0, 0.001, 0.373, 0.002, 0.133, 0.002, 0.12, 0.0)
	elif mode == "main_menu":
		set_shader_params(0.01, 0.002, 5000.0, 0, 0.373, 0.002, 0.133, 0.002, 0.13, .2)
	else:
		push_error("Not a valid shader mode:" + str(mode))


func set_shader_params(bar_range, bar_intensity, noise_quality, noise_intensity,\
					color_intensity, red_multiplier, red_intensity,\
					green_multiplier, green_intensity, warp_amount):
	VCREffect.material.set_shader_parameter("barRange", bar_range)
	VCREffect.material.set_shader_parameter("barOffsetIntensity", bar_intensity)
	VCREffect.material.set_shader_parameter("noiseQuality", noise_quality)
	VCREffect.material.set_shader_parameter("noiseIntensity", noise_intensity)
	VCREffect.material.set_shader_parameter("colorOffsetIntensity", color_intensity)
	VCREffect.material.set_shader_parameter("redMultiplier", red_multiplier)
	VCREffect.material.set_shader_parameter("redIntensity", red_intensity)
	VCREffect.material.set_shader_parameter("greenMultiplier", green_multiplier)
	VCREffect.material.set_shader_parameter("greenIntensity", green_intensity)
	VCREffect.material.set_shader_parameter("warpAmount", warp_amount)


func update_shader_effect(player):
	if not $Tween.is_active():
		#Noise Intensity
		var target_noise = ((player.max_hp - player.hp)/float(player.max_hp)) * 0.0035
		var value = lerp(VCREffect.material.get_shader_parameter("noiseIntensity"), target_noise, .9)
		VCREffect.material.set_shader_parameter("noiseIntensity", value)
		#Color Offset Intensity
		value = lerp(VCREffect.material.get_shader_parameter("colorOffsetIntensity"), 0.175, .9)
		VCREffect.material.set_shader_parameter("colorOffsetIntensity", value)

func damage_burst_effect():
	if not $Tween.is_active():
		$Tween.interpolate_property(VCREffect.material, "shader_param/noiseIntensity", null, 0.02, .1)
		$Tween.interpolate_property(VCREffect.material, "shader_param/colorOffsetIntensity", null, 1.2, .1)
		$Tween.start()
