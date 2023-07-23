shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void light() {
	LIGHT = texture(SCREEN_TEXTURE, SCREEN_UV) * (LIGHT_COLOR.r)*LIGHT_COLOR.a;
}
