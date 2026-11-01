// Breaks up flat-coloured city meshes (concrete, roofs, linework) with two
// scales of a seamless noise texture, sampled in world space so neighbouring
// buildings don't repeat each other. The mesh's vertex colour is the base
// value; the noise multiplies it around 1.0, so the average value is kept.
//
// Speckle adds small light flecks, as on the concrete in the hand-painted
// maps.
//
// Roof meshes carry two extra values per vertex:
//   UV.x  building id (-1 for none). With use_fade on, the building's alpha
//         is read from fade_tex (one texel per id, row by row). BuildingField
//         fills in fade_tex and turns use_fade on.
//   UV.y  stripe coordinate on pitched roof faces (0 elsewhere): 10000 plus
//         the distance across the tile courses, in courses. One dark line is
//         drawn per course. Lines fade out as they get thinner than a pixel,
//         so zoomed-out roofs don't shimmer.
//
// Set on a parent node; the meshes use it through use_parent_material.
shader_type canvas_item;

const float STRIPE_BASE = 10000.0;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float grain_scale = 600.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.4;
uniform float speckle_scale = 45.0;
uniform float speckle_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool use_fade = false;
uniform sampler2D fade_tex : filter_nearest, repeat_disable;
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.45;
uniform float stripe_width : hint_range(0.0, 0.5) = 0.18;

varying vec2 world_pos;
varying flat float building_id;
varying float stripe;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	building_id = UV.x;
	stripe = UV.y;
}

void fragment() {
	float g = texture(grain, world_pos / grain_scale).r * 0.6
			+ texture(grain, world_pos / (grain_scale * 0.17)).r * 0.4;
	COLOR.rgb *= mix(1.0, g * 2.0, grain_strength);
	float s = texture(grain, world_pos / speckle_scale + vec2(0.37, 0.61)).r;
	COLOR.rgb += vec3(smoothstep(0.74, 0.8, s) * speckle_strength);
	if (stripe > 1.0) {
		float t = stripe - STRIPE_BASE;
		float w = fwidth(t);
		float d = abs(fract(t) - 0.5) * 2.0;
		float line = smoothstep(1.0 - stripe_width - w, 1.0 - stripe_width + w, d);
		float visible = clamp(1.5 - w * 3.0, 0.0, 1.0);
		COLOR.rgb *= 1.0 - line * stripe_strength * visible;
	}
	if (use_fade && building_id >= 0.0) {
		int id = int(building_id + 0.5);
		ivec2 size = textureSize(fade_tex, 0);
		COLOR.a *= texelFetch(fade_tex, ivec2(id % size.x, id / size.x), 0).r;
	}
}
