shader_type canvas_item;

uniform sampler2D noiseTex;

void fragment() {
	float noise = texture(noiseTex, UV + vec2(cos(TIME*.2)*.5,sin(TIME*8.0)*.01)).r*.02;
	COLOR = texture(TEXTURE, UV - vec2(noise, noise)/2.0);
}
