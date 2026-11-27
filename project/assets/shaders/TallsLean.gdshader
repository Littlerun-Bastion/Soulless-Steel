// The overhead grain (see OverheadGrain.gdshader) for the talls meshes:
// things that stand well above the roofs (crane masts and jibs, pylons,
// minarets, the upper floors of building frames), drawn above everything
// else on the map.
//
// Every vertex carries its height in metres in UV.x (MapMeshFile). With
// `lean` on, each vertex is shifted away from camera_centre (the centre of
// the screen in world px, set every frame by TallsLean.gd) by
//   shift = (vertex - camera_centre) * h / (eye_m - h)
// which is where a camera eye_m above the screen centre would see a point h
// above the ground: tops lean outward from the centre of the view, as in a
// real top-down view. h is clamped to max_height_m (well below eye_m). The
// generator's render_preview.py uses the same rule and eye height.
//
// Within fade_radius of fade_centre (the player) the mesh fades to
// ghost_alpha, so a jib over the player never hides it. The distance is
// taken at the vertex's ground position and at its drawn position, the
// nearer of the two. The other mechas the player can see (ghosts: world px
// and a weight, the mecha's own visibility, ghost_count of them) fade the
// mesh where it is drawn within ghost_radius of them, so a leaning top never
// hides a mecha far from the tall thing's foot.
//
// Grain is sampled at the ground position, so it stays put on the object
// while the camera moves. On a side face (a quad from an edge at one height
// to the same edge higher up) every point of a vertical line has one ground
// position, so there the height is added across the edge as well, at the
// ground's scale (PX_PER_M px per metre), and the wall gets grain both ways.
// A side face is told apart by its ground positions: across the screen they
// change in one direction only (a top or a span changes in two).
//
// Set on a parent node; the meshes use it through use_parent_material.
shader_type canvas_item;

const float PX_PER_M = 20.0;
const int MAX_GHOSTS = 16;
// A triangle is a side face when the area its ground positions sweep per
// screen pixel is below this share of their squared rate of change.
const float SIDE_SHARE = 0.02;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float grain_scale = 600.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.3;
uniform bool lean = false;
uniform vec2 camera_centre = vec2(0.0, 0.0);
uniform float eye_m = 150.0;
uniform float max_height_m = 100.0;
uniform vec2 fade_centre = vec2(1e9, 1e9);
uniform float fade_radius = 600.0;
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.25;
uniform vec3 ghosts[16];
uniform int ghost_count = 0;
uniform float ghost_radius = 300.0;

varying vec2 ground_pos;
varying vec2 drawn_pos;
varying float height_m;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float h = clamp(UV.x, 0.0, max_height_m);
	vec2 shift = lean ? (world - camera_centre) * (h / (eye_m - h)) : vec2(0.0);
	ground_pos = world;
	drawn_pos = world + shift;
	height_m = h;
	VERTEX += inverse(mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy)) * shift;
}

void fragment() {
	vec2 gx = dFdx(ground_pos);
	vec2 gy = dFdy(ground_pos);
	float rate = dot(gx, gx) + dot(gy, gy);
	vec2 grain_pos = ground_pos;
	if (abs(gx.x * gy.y - gx.y * gy.x) < SIDE_SHARE * rate) {
		vec2 along = normalize(dot(gx, gx) > dot(gy, gy) ? gx : gy);
		if (along.x < 0.0 || (along.x == 0.0 && along.y < 0.0)) {
			along = -along;
		}
		grain_pos += vec2(-along.y, along.x) * height_m * PX_PER_M;
	}
	float g = texture(grain, grain_pos / grain_scale).r * 0.6
			+ texture(grain, grain_pos / (grain_scale * 0.17)).r * 0.4;
	COLOR.rgb *= mix(1.0, g * 2.0, grain_strength);
	float d = min(distance(ground_pos, fade_centre), distance(drawn_pos, fade_centre));
	float keep = mix(ghost_alpha, 1.0, smoothstep(fade_radius * 0.7, fade_radius, d));
	for (int i = 0; i < MAX_GHOSTS; i++) {
		if (i >= ghost_count) {
			break;
		}
		float t = smoothstep(ghost_radius * 0.7, ghost_radius, distance(drawn_pos, ghosts[i].xy));
		keep = min(keep, mix(1.0, mix(ghost_alpha, 1.0, t), ghosts[i].z));
	}
	COLOR.a *= keep;
}
