shader_type canvas_item;
render_mode unshaded;

// The inside edge of a sprite's opaque area in line_color; the rest clear
// (HudVisionOutlines). The line is `width` texels wide, passed in the draw's
// modulate red channel as a fraction of max_width so each sprite can have
// its own.

uniform vec4 line_color : source_color = vec4(1.0);
uniform float max_width = 32.0;
uniform float alpha_cut = 0.5;

varying float width;

void vertex() {
	width = COLOR.r * max_width;
}

void fragment() {
	if (texture(TEXTURE, UV).a < alpha_cut) {
		discard;
	}
	vec2 reach = TEXTURE_PIXEL_SIZE * width;
	float least = 1.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.7853982;
		vec2 at = UV + vec2(cos(angle), sin(angle)) * reach;
		float alpha = 0.0;
		if (at.x >= 0.0 && at.y >= 0.0 && at.x <= 1.0 && at.y <= 1.0) {
			alpha = texture(TEXTURE, at).a;
		}
		least = min(least, alpha);
	}
	if (least >= alpha_cut) {
		discard;
	}
	COLOR = line_color;
}
