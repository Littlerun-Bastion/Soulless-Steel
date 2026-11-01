// Ground for a whole map: four seamless textures blended by one painted mask,
// then multiplied by a painted macro tone texture that carries the map's
// large-scale light and dark, plus one finer noise layer that breaks the
// macro texture up close.
//
// The mask is RGB: R = snow, G = sand, B = dirt & rocks. Cracked earth has no
// channel; it takes whatever weight the other three leave. Where the three add
// up to more than 1, they are scaled down to sum to 1.
//
// The mask and the macro tone are sampled in the node's local space, where the
// ground polygon runs from (0, 0) to map_size. The macro tone averages 0.5, so
// multiplying by twice its value keeps the ground's average brightness.
// Textures and the fine noise are sampled in world space.
shader_type canvas_item;

uniform sampler2D ground_mask : filter_linear, repeat_disable;
uniform sampler2D macro_tone : filter_linear, repeat_disable;
uniform sampler2D tex_snow : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cracked : filter_linear_mipmap, repeat_enable;
uniform sampler2D tone_noise : filter_linear, repeat_enable;

uniform vec2 map_size = vec2(50000.0);
uniform float tile_size = 4096.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 1.0;
uniform float tone_scale = 930.0;
uniform float tone_strength : hint_range(0.0, 1.0) = 0.15;

varying vec2 local_pos;
varying vec2 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 map_uv = local_pos / map_size;
	vec3 m = texture(ground_mask, map_uv).rgb;
	float painted = m.r + m.g + m.b;
	vec4 w = painted > 1.0 ? vec4(m / painted, 0.0) : vec4(m, 1.0 - painted);

	vec2 uv = world_pos / tile_size;
	vec3 col = texture(tex_snow, uv).rgb * w.r
			+ texture(tex_sand, uv).rgb * w.g
			+ texture(tex_dirt, uv).rgb * w.b
			+ texture(tex_cracked, uv).rgb * w.a;

	float macro = texture(macro_tone, map_uv).r * 2.0;
	float fine = texture(tone_noise, world_pos / tone_scale).r * 2.0;
	col *= mix(1.0, macro, macro_strength) * mix(1.0, fine, tone_strength);
	COLOR = vec4(col, 1.0);
}
