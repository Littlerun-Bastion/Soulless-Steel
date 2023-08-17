shader_type canvas_item;

uniform float show_percent : hint_range(0.0, 1.0, 0.001);

void fragment() {
	COLOR = texture(TEXTURE, UV);
	if (UV.y < 1.0 - show_percent) {
		COLOR.a = 0.0;
	}
}
