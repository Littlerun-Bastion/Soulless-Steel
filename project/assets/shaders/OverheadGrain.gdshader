// The city grain (see CityGrain.gdshader) for overhead meshes: pipe bridges
// over roads, strut frames, canopies and shelters, drawn above mechas. Within
// fade_radius of fade_centre (the player, set every frame by
// OverheadMeshFade.gd) the mesh fades to ghost_alpha, so the player is never
// hidden under one. The other mechas the player can see (ghosts: world px and
// a weight, the mecha's own visibility, ghost_count of them) fade the mesh
// within ghost_radius of them by that weight, so a canopy never hides a mecha
// standing under it.
//
// Set on a parent node; the meshes use it through use_parent_material.
shader_type canvas_item;

const int MAX_GHOSTS = 16;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float grain_scale = 600.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec2 fade_centre = vec2(1e9, 1e9);
uniform float fade_radius = 600.0;
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.25;
uniform vec3 ghosts[16];
uniform int ghost_count = 0;
uniform float ghost_radius = 300.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float g = texture(grain, world_pos / grain_scale).r * 0.6
			+ texture(grain, world_pos / (grain_scale * 0.17)).r * 0.4;
	COLOR.rgb *= mix(1.0, g * 2.0, grain_strength);
	float d = distance(world_pos, fade_centre);
	float keep = mix(ghost_alpha, 1.0, smoothstep(fade_radius * 0.7, fade_radius, d));
	for (int i = 0; i < MAX_GHOSTS; i++) {
		if (i >= ghost_count) {
			break;
		}
		float t = smoothstep(ghost_radius * 0.7, ghost_radius, distance(world_pos, ghosts[i].xy));
		keep = min(keep, mix(1.0, mix(ghost_alpha, 1.0, t), ghosts[i].z));
	}
	COLOR.a *= keep;
}
