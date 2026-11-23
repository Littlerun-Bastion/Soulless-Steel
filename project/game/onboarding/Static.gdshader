shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float grain = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / grain);
	float noise = hash(cell + floor(TIME * 30.0));
	float roll = step(0.97, fract(FRAGCOORD.y / 180.0 - TIME * 0.7));
	COLOR = vec4(vec3(mix(noise, 1.0, roll * 0.4)), amount * 0.55);
}
