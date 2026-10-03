shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.95, 0.4, 1.0);
uniform float outline_width : hint_range(1.0, 8.0) = 2.0;

void fragment() {
	float tex_a = texture(TEXTURE, UV).a;
	if (tex_a > 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 texel = TEXTURE_PIXEL_SIZE * outline_width;
		float max_alpha = 0.0;
		for (int i = -2; i <= 2; i++) {
			for (int j = -2; j <= 2; j++) {
				vec2 offset = vec2(float(i), float(j)) * texel;
				max_alpha = max(max_alpha, texture(TEXTURE, UV + offset).a);
			}
		}
		if (max_alpha > 0.001) {
			COLOR = outline_color;
		} else {
			COLOR = vec4(0.0);
		}
	}
}
