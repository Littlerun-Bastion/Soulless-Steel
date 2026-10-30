shader_type particles;

// Grains for sand limbs. One shader, two uses:
// - Shed grains (death_burst off): spawn on a random point of a random limb
//   chain, drift on a curl-noise flow field, and fade out.
// - Death burst (death_burst on): spawn along the limbs and inside the body,
//   blow away from the body, then slow, drift on the flow field, shrink and
//   fade. Each grain stretches along its velocity, so the first frames read
//   as streaks and the tail end as loose sand.
// Positions are world space (the GPUParticles2D uses local_coords = false).

const int MAX_POINTS = 64;  // must match MAX_POINTS in SandBody.gd

uniform vec2 points[64];    // limb chains, world space, limb by limb
uniform int limb_count = 0;
uniform int points_per_limb = 8;
uniform float intensity = 0.2;
uniform float agitation = 0.0;  // hit flash, 0..1
uniform bool death_burst = false;
uniform vec2 burst_origin = vec2(0.0);
uniform vec2 body_tip = vec2(0.0);
uniform vec2 body_back_l = vec2(0.0);
uniform vec2 body_back_r = vec2(0.0);
uniform float burst_speed = 1100.0;
uniform float scatter_time = 1.4;  // seconds until the last grain is gone
uniform vec4 grain_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rnd(inout uint s) {
	s = hash_u(s);
	return float(s & 0x00FFFFFFu) / 16777216.0;
}

float potential(vec2 p, float t) {
	return sin(p.x * 0.011 + t * 0.6) * cos(p.y * 0.013 - t * 0.4)
			+ 0.5 * sin((p.x - p.y) * 0.021 + t);
}

// Curl of a scalar field: a swirling flow with no sinks, so grains never clump.
vec2 curl(vec2 p, float t) {
	float e = 2.0;
	float dx = potential(p + vec2(e, 0.0), t) - potential(p - vec2(e, 0.0), t);
	float dy = potential(p + vec2(0.0, e), t) - potential(p - vec2(0.0, e), t);
	return vec2(dy, -dx) / (2.0 * e) * 50.0;
}

void start() {
	uint s = hash_u(INDEX * 747796405u + NUMBER * 2891336453u + RANDOM_SEED);
	vec2 pos = burst_origin;
	if (limb_count > 0) {
		int limb = min(int(rnd(s) * float(limb_count)), limb_count - 1);
		float f = rnd(s) * float(points_per_limb - 1);
		int i = int(floor(f));
		int base = limb * points_per_limb;
		pos = mix(points[base + i], points[base + min(i + 1, points_per_limb - 1)], fract(f));
	}
	if (death_burst && rnd(s) < 0.45) {
		float u = rnd(s);
		float v = rnd(s);
		if (u + v > 1.0) {
			u = 1.0 - u;
			v = 1.0 - v;
		}
		pos = body_tip + (body_back_l - body_tip) * u + (body_back_r - body_tip) * v;
	}
	pos += (vec2(rnd(s), rnd(s)) - 0.5) * 6.0;

	float size = mix(0.4, 0.95, rnd(s));
	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(pos, 0.0, 1.0));

	vec2 vel;
	if (death_burst) {
		vec2 away = pos - burst_origin;
		float d = length(away);
		vec2 dir = d > 0.01 ? away / d : vec2(1.0, 0.0);
		dir = normalize(dir + (vec2(rnd(s), rnd(s)) - 0.5) * 0.6);
		vel = dir * burst_speed * mix(0.3, 1.0, rnd(s)) * (0.5 + d / 250.0);
	} else {
		vel = (vec2(rnd(s), rnd(s)) - 0.5) * 40.0;
	}
	VELOCITY = vec3(vel, 0.0);
	COLOR = vec4(grain_color.rgb * mix(0.7, 1.5, rnd(s)), 1.0);
	CUSTOM = vec4(0.0, size, scatter_time * mix(0.4, 1.0, rnd(s)), 0.0);
}

void process() {
	CUSTOM.x += DELTA;
	float age = CUSTOM.x;
	if (death_burst) {
		float life = min(age / CUSTOM.z, 1.0);
		ACTIVE = life < 1.0;
		vec2 drift = curl(TRANSFORM[3].xy, TIME) * 60.0;
		VELOCITY.xy = VELOCITY.xy * exp(-4.5 * DELTA) + drift * (1.0 - exp(-2.0 * DELTA));
		float speed = length(VELOCITY.xy);
		vec2 dir = speed > 0.01 ? VELOCITY.xy / speed : vec2(1.0, 0.0);
		float size = CUSTOM.y * (1.0 - 0.6 * life);
		TRANSFORM[0].xy = dir * size * (1.0 + speed / 160.0);
		TRANSFORM[1].xy = vec2(-dir.y, dir.x) * size;
		COLOR.a = 1.0 - smoothstep(0.3, 1.0, life);
	} else {
		vec2 drift = curl(TRANSFORM[3].xy, TIME) * mix(20.0, 70.0, intensity) * (1.0 + agitation * 4.0);
		VELOCITY.xy = mix(VELOCITY.xy, drift, 1.0 - exp(-3.0 * DELTA));
		float life = age / LIFETIME;
		COLOR.a = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.5, 1.0, life));
	}
}
