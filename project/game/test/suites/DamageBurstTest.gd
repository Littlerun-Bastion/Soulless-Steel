extends TestSuite

const NOISE := "noiseIntensity"
const COLOR_OFFSET := "colorOffsetIntensity"


func run_tests() -> void:
	await case("a hit glitches the screen", _test_hit_glitches)


func _test_hit_glitches() -> void:
	ShaderEffects.reset_shader_effect("arena")
	var material: ShaderMaterial = ShaderEffects.VCREffect.material
	var calm_noise: float = material.get_shader_parameter(NOISE)
	var calm_offset: float = material.get_shader_parameter(COLOR_OFFSET)

	ShaderEffects.damage_burst_effect()
	var glitched := await wait_until(func(): return material.get_shader_parameter(NOISE) > calm_noise, 2.0)

	check(glitched, "the picture gets noisy")
	check(material.get_shader_parameter(COLOR_OFFSET) > calm_offset, "and its colours split")
	ShaderEffects.reset_shader_effect("arena")
