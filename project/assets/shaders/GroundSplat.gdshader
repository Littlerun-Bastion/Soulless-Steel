// Ground for a whole map: four seamless textures blended by one painted mask,
// with low-frequency noise multiplied over the result to hide the repeats.
//
// The mask is RGB: R = snow, G = sand, B = dirt & rocks. Cracked earth has no
// channel; it takes whatever weight the other three leave. Where the three add
// up to more than 1, they are scaled down to sum to 1.
//
// The mask is sampled in the node's local space, where the ground polygon runs
// from (0, 0) to map_size. Textures and tone are sampled in world space.
shader_type canvas_item;

uniform sampler2D ground_mask : filter_linear, repeat_disable;
uniform sampler2D tex_snow : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cracked : filter_linear_mipmap, repeat_enable;
uniform sampler2D tone_noise : filter_linear, repeat_enable;

uniform vec2 map_size = vec2(4000.0);
uniform float tile_size = 4096.0;
uniform float tone_scale_a = 2650.0;
uniform float tone_scale_b = 930.0;
uniform float tone_strength : hint_range(0.0, 1.0) = 0.25;

varying vec2 local_pos;
varying vec2 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 m = texture(ground_mask, local_pos / map_size).rgb;
	float painted = m.r + m.g + m.b;
	vec4 w = painted > 1.0 ? vec4(m / painted, 0.0) : vec4(m, 1.0 - painted);

	vec2 uv = world_pos / tile_size;
	vec3 col = texture(tex_snow, uv).rgb * w.r
			+ texture(tex_sand, uv).rgb * w.g
			+ texture(tex_dirt, uv).rgb * w.b
			+ texture(tex_cracked, uv).rgb * w.a;

	float tone = texture(tone_noise, world_pos / tone_scale_a).r * 0.6
			+ texture(tone_noise, world_pos / tone_scale_b).r * 0.4;
	COLOR = vec4(col * mix(1.0, tone * 2.0, tone_strength), 1.0);
}
