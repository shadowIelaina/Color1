shader_type canvas_item;

// 2.5D 俯视角水体 —— 黑白版水波着色器
// 与 water.gdshader 同款波纹，只输出灰度（黑 -> 白）。

uniform float dark_level : hint_range(0.0, 1.0) = 0.05;
uniform float light_level : hint_range(0.0, 1.0) = 0.95;

uniform float wave_speed : hint_range(0.0, 2.0) = 0.45;
uniform float wave_strength : hint_range(0.0, 0.6) = 0.24;
uniform float large_wave_scale : hint_range(1.0, 300.0) = 96.0;
uniform float small_ripple_scale : hint_range(1.0, 300.0) = 24.0;
uniform float ground_flatten : hint_range(0.2, 1.0) = 0.55;

varying vec2 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2 p = world_pos;
	p.y /= ground_flatten;

	float t = TIME * wave_speed;
	vec2 big = p / large_wave_scale;
	vec2 small = p / small_ripple_scale;

	float h = 0.0;
	h += sin(big.x * 6.28318 + t * 1.30 + sin(big.y * 6.28318 + t * 0.50));
	h += 0.55 * sin(big.y * 6.28318 - t * 1.75);
	h += 0.40 * sin((big.x + big.y) * 3.14159 + t * 1.05);
	h += 0.30 * sin((big.x - big.y) * 4.18879 - t * 0.85);
	h += 0.22 * sin(big.x * 12.56637 + t * 2.10);
	h /= 2.47;

	float r = 0.0;
	r += 0.5 * sin(small.x * 6.28318 + t * 2.40);
	r += 0.5 * sin(small.y * 6.28318 - t * 2.90);
	r += 0.45 * (vnoise(small * 2.0 + vec2(t * 0.50, -t * 0.35)) * 2.0 - 1.0);
	r /= 1.45;

	float field = (h + r * 0.55) * wave_strength;

	// 灰度：把高度场映射到 黑 -> 白
	float g = mix(dark_level, light_level, field * 0.5 + 0.5);

	// 波峰提亮
	float crest = smoothstep(0.08, 0.42, field);
	g = mix(g, light_level, crest * 0.5);

	// 波光闪烁
	float spark = smoothstep(0.62, 1.0, vnoise(small * 3.0 + vec2(t * 0.80, t * 0.55)));
	g = mix(g, light_level, spark * 0.18);

	COLOR = vec4(vec3(g), 1.0);
}
