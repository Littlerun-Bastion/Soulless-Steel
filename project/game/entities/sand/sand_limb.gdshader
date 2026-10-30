shader_type canvas_item;

// Drawn on a Line2D with texture_mode STRETCH: UV.x runs 0 at the root to 1
// at the tip, UV.y runs across. Two looks:
// - Flowing grains (rope off): hard-edged grain cells that scroll from root
//   to tip. The centre and root are dense; the edges and tip break up.
// - Rope (rope on): a solid, rounded strand with ridges spiralling round it,
//   like wound fibres. Used for the body tentacles and the limb braids.

uniform float flow_phase = 0.0;    // advanced by the script, so speed changes don't jump
uniform float limb_px = 150.0;     // limb length in px, keeps grains square
uniform float limb_width_px = 18.0;
uniform float grain_px = 3.0;
uniform float intensity = 0.2;     // 0 idle .. 1 hunting
uniform float seed = 0.0;
uniform vec4 grain_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform bool rope = false;
uniform vec4 highlight_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
// A bright band at pulse_pos (0..1 along the line), for energy pulses.
uniform float pulse_pos = 0.0;
uniform float pulse_strength = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;  // 0 at the centre line, 1 at the edge
	vec2 px = vec2(UV.x * limb_px, (UV.y - 0.5) * limb_width_px);
	if (rope) {
		float c = (UV.y - 0.5) * 2.0;
		float rounded = sqrt(max(1.0 - c * c, 0.0));
		// Long, shallow spirals, so a rope reads as one wound tentacle.
		float ridge = 0.5 + 0.5 * sin(px.x * 0.22 + c * 3.5 - flow_phase * 1.5 + seed);
		float speck = hash(floor(px / 2.0) + seed);
		float light = rounded * rounded * mix(0.6, 1.0, ridge) * mix(0.85, 1.0, speck);
		// Slightly grainy edges, so the ropes sit with the sand.
		float edge = step(abs(c), 0.8 + 0.2 * speck);
		float band = pulse_strength * exp(-pow((UV.x - pulse_pos) * 7.0, 2.0)) * (0.4 + 0.6 * rounded);
		vec3 rgb = mix(grain_color.rgb, highlight_color.rgb, light) + vec3(band);
		COLOR = vec4(min(rgb, vec3(1.0)), edge * grain_color.a);
	} else {
		vec2 flow = vec2(px.x - flow_phase * 60.0, px.y);
		float grain = hash(floor(flow / grain_px) + seed);
		// Clumps of grains that stream along the limb.
		float clump = value_noise(flow * vec2(0.035, 0.15) + seed) * 0.65
				+ value_noise(flow * 0.09 - seed) * 0.35;
		float core = 1.0 - across * across;
		float tip = smoothstep(1.0, 0.5, UV.x);
		float density = core * mix(0.5, 1.0, tip) * (0.7 + 0.6 * clump);
		float threshold = mix(0.5, 0.38, intensity);
		float a = step(threshold, density * (0.5 + 0.7 * grain));
		// A solid spine so the limb never looks hollow.
		a = max(a, smoothstep(0.3, 0.0, across) * tip);
		float band = pulse_strength * exp(-pow((UV.x - pulse_pos) * 7.0, 2.0));
		COLOR = vec4(min(grain_color.rgb * (0.8 + 0.5 * grain) + vec3(band * 0.8), vec3(1.0)), a * grain_color.a);
	}
}
