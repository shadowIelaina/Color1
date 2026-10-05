shader_type canvas_item;

// 2.5D 俯视角水体 —— 程序化水波着色器
// 应用在纯白 TileMap 的 material 上，完全用世界坐标生成水色，无需纹理采样。

uniform vec4 deep_color : source_color = vec4(0.03, 0.22, 0.38, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.13, 0.48, 0.64, 1.0);
uniform vec4 crest_color : source_color = vec4(0.80, 0.96, 1.0, 1.0);

uniform float wave_speed : hint_range(0.0, 2.0) = 0.45;
uniform float wave_strength : hint_range(0.0, 0.6) = 0.24;
uniform float large_wave_scale : hint_range(1.0, 300.0) = 96.0;
uniform float small_ripple_scale : hint_range(1.0, 300.0) = 24.0;

// 斜视角地面压扁：<1 时把 Y 向波纹压缩成椭圆，贴合 2.5D 地面（约 0.55）
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

	// 多层不同方向、频率、速度的行波叠加 -> 水面高度场
	float h = 0.0;
	h += sin(big.x * 6.28318 + t * 1.30 + sin(big.y * 6.28318 + t * 0.50));
	h += 0.55 * sin(big.y * 6.28318 - t * 1.75);
	h += 0.40 * sin((big.x + big.y) * 3.14159 + t * 1.05);
	h += 0.30 * sin((big.x - big.y) * 4.18879 - t * 0.85);
	h += 0.22 * sin(big.x * 12.56637 + t * 2.10);
	h /= 2.47;

	// 高频细波纹 + 微噪声
	float r = 0.0;
	r += 0.5 * sin(small.x * 6.28318 + t * 2.40);
	r += 0.5 * sin(small.y * 6.28318 - t * 2.90);
	r += 0.45 * (vnoise(small * 2.0 + vec2(t * 0.50, -t * 0.35)) * 2.0 - 1.0);
	r /= 1.45;

	float field = (h + r * 0.55) * wave_strength;

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, field * 0.5 + 0.5);

	float crest = smoothstep(0.08, 0.42, field);
	col = mix(col, crest_color.rgb, crest * 0.5);

	float spark = smoothstep(0.62, 1.0, vnoise(small * 3.0 + vec2(t * 0.80, t * 0.55)));
	col += crest_color.rgb * spark * 0.18;

	COLOR = vec4(col, 1.0);
}
