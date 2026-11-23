extends CanvasLayer

## Full-screen VCR effect (layer 99, above everything but nothing else).
## warpAmount is the CRT curve. It bends the whole screen at once: world,
## HUD, MechOS and the cursor, so what you click is always under the cursor.
## (The HUD used to curve on its own, which left MechOS flat on top of it.)

const SCREEN_CURVE := 0.15
const DAMAGED_NOISE := 0.0035
const DAMAGED_COLOUR_SPLIT := 0.175

@onready var VCREffect = $VCREffect

var tweens = []
var _calm_colour_split := 0.0

func enable():
	VCREffect.show()


func disable():
	VCREffect.hide()


func play_transition(from_value, to_value, duration):
	var tween = create_tween()
	tween.tween_method(self.change_noise_quality, from_value, to_value, duration)
	tweens.append(tween)


func change_noise_quality(value):
	VCREffect.material.set_shader_parameter("noiseQuality", value)


func end_transitions() -> void:
	for tween in tweens:
		tween.kill()
	tweens = []


func reset_shader_effect(mode):
	end_transitions()
	if mode == "arena":
		set_shader_params(0.05, 0.0, 2000.0, 0.0, 0.026, 0.002, 0.48, 0.002, 0.492, SCREEN_CURVE)
	elif mode == "gameover":
		set_shader_params(0.05, 0.0, 866.0, 0.001, 0.026, 0.006, 1.0, 0.0073, 0.97, SCREEN_CURVE)
	elif mode == "score_screen":
		set_shader_params(0.022, 0.001, 3900.0, 0.001, 0.1, 0.002, 0.133, 0.002, 0.12, SCREEN_CURVE)
	elif mode == "main_menu":
		set_shader_params(0.01, 0.001, 5000.0, 0, 0.02, 0.002, 0.133, 0.002, 0.13, .2)
	else:
		push_error("Not a valid shader mode:" + str(mode))


func set_shader_params(bar_range, bar_intensity, noise_quality, noise_intensity,\
					color_intensity, red_multiplier, red_intensity,\
					green_multiplier, green_intensity, warp_amount):
	_calm_colour_split = color_intensity
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


## The screen tears and splits in colour as the player's mecha breaks. Only
## once the transitions have ended (end_transitions); as it stands, only the
## onboarding ends them.
func update_shader_effect(player):
	if tweens.is_empty():
		var damage := 1.0 - NPCKnowledge._structural_health(player)
		var value = lerp(VCREffect.material.get_shader_parameter("noiseIntensity"), damage * DAMAGED_NOISE, .9)
		VCREffect.material.set_shader_parameter("noiseIntensity", value)
		value = lerp(VCREffect.material.get_shader_parameter("colorOffsetIntensity"), lerpf(_calm_colour_split, DAMAGED_COLOUR_SPLIT, damage), .9)
		VCREffect.material.set_shader_parameter("colorOffsetIntensity", value)

func damage_burst_effect():
	if tweens.is_empty():
		var tween = create_tween()
		tween.set_parallel()
		tween.tween_property(VCREffect.material, "shader_parameter/noiseIntensity", 0.02, .1)
		tween.tween_property(VCREffect.material, "shader_parameter/colorOffsetIntensity", 1.2, .1)
