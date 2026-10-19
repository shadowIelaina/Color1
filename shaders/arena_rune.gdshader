shader_type canvas_item;
render_mode blend_add;

uniform vec4 rune_color : source_color = vec4(0.95, 0.30, 0.22, 0.7);
uniform float intensity : hint_range(0.0, 2.0) = 0.75;
uniform float ring_count : hint_range(1.0, 8.0) = 3.0;
uniform float spoke_count : hint_range(4.0, 24.0) = 12.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float bands = 0.5 + 0.5 * sin(r * ring_count * 6.28318 + TIME * 0.45);
	float spokes = pow(abs(cos(a * spoke_count * 0.5)), 10.0);
	float radial = smoothstep(1.0, 0.0, r);
	float core = smoothstep(0.22, 0.0, r);
	float alpha = (0.20 + 0.32 * bands + 0.55 * spokes + 0.55 * core) * radial * radial * intensity;
	COLOR = vec4(rune_color.rgb, rune_color.a * alpha);
}
