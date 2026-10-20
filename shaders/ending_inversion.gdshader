shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float inversion : hint_range(0.0, 1.0) = 0.0;
uniform float shock : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5);

void fragment() {
	vec2 delta = SCREEN_UV - center;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float distance_from_center = length(delta * aspect);
	float front = shock * 1.5;
	float ring = exp(-abs(distance_from_center - front) * 55.0) * sin(shock * 3.14159);
	vec2 uv = SCREEN_UV + normalize(delta + vec2(0.0001)) * ring * 0.012;
	vec3 original = texture(screen_texture, uv).rgb;
	float gray = dot(original, vec3(0.2126, 0.7152, 0.0722));
	float wipe = smoothstep(distance_from_center - 0.1, distance_from_center + 0.1, inversion * 2.0);
	if (inversion < 0.0001) { wipe = 0.0; }
	vec3 negative = vec3(1.0 - gray);
	COLOR = vec4(mix(original, negative, wipe), 1.0);
}
