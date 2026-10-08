shader_type canvas_item;

// 2.5D 俯视角水体 —— 写实版
// 高度场 = 方向性涌浪 + fBm 毛细波纹；对高度场求梯度得到法线，
// 再做 Blinn-Phong 光照（漫反射明暗 + 太阳高光 + 波峰泡沫），
// 比单纯「高度 -> 颜色」更接近真实水面的光影。

uniform vec4 deep_color : source_color = vec4(0.03, 0.22, 0.38, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.13, 0.48, 0.64, 1.0);
uniform vec4 foam_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);

// 指向太阳的方向（单位向量，顶视图近似 z>0）
uniform vec3 sun_dir = vec3(0.5, 0.5, 0.7071);

uniform float wave_speed : hint_range(0.0, 2.0) = 0.30;
uniform float wave_strength : hint_range(0.0, 0.6) = 0.24;
uniform float large_wave_scale : hint_range(1.0, 300.0) = 96.0;
uniform float small_ripple_scale : hint_range(1.0, 300.0) = 24.0;

// 斜视角地面压扁：<1 时把 Y 向波纹压缩成椭圆，贴合 2.5D 地面（约 0.55）
uniform float ground_flatten : hint_range(0.2, 1.0) = 0.55;

uniform float foam_amount : hint_range(0.0, 1.0) = 0.35;
uniform float specular_strength : hint_range(0.0, 3.0) = 1.2;
uniform float specular_power : hint_range(4.0, 256.0) = 80.0;

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

// 分形值噪声：逐层旋转 + 放大，避免轴向对齐的网格感，结果约 [0,1]
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = rot * (p * 2.03) + vec2(11.31, 7.17);
		a *= 0.5;
	}
	return v;
}

// Bayer 8x8 有序抖动矩阵（0..63）。有序抖动比白噪声更均匀，
// 用更小的幅度就能把 8-bit 量化出的「分层」色带打散。
const float BAYER8[64] = float[64](
	0.0, 32.0, 8.0, 40.0, 2.0, 34.0, 10.0, 42.0,
	48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
	12.0, 44.0, 4.0, 36.0, 14.0, 46.0, 6.0, 38.0,
	60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
	3.0, 35.0, 11.0, 43.0, 1.0, 33.0, 9.0, 41.0,
	51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
	15.0, 47.0, 7.0, 39.0, 13.0, 45.0, 5.0, 37.0,
	63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
);

// 高度场（法线求梯度时会多次采样，故抽成函数）
float height_field(vec2 p, float t) {
	// 方向性涌浪：沿主导风向传播的大波浪
	vec2 d1 = normalize(vec2(0.35, 0.94));
	vec2 d2 = normalize(vec2(0.92, -0.39));
	vec2 d3 = normalize(vec2(0.10, 0.995));
	float k = 6.28318 / large_wave_scale;
	float swell = 0.0;
	swell += sin(dot(p, d1) * k * 1.10 + t * 1.00);
	swell += 0.60 * sin(dot(p, d2) * k * 1.90 + t * 0.72);
	swell += 0.40 * sin(dot(p, d3) * k * 3.10 - t * 1.15);
	swell /= 1.70;

	// 毛细波纹（各向同性 fBm 细浪）
	float cap = fbm(p / small_ripple_scale + vec2(t * 0.55, -t * 0.40));

	return swell + (cap - 0.5) * 0.35;
}

void vertex() {
	// TileMapLayer 按象限分块绘制，VERTEX 在每个象限会重置为局部原点，
	// 直接用 VERTEX 会造成象限之间出现明显分界线。
	// MODEL_MATRIX 已包含象限偏移，乘上它得到连续的世界坐标。
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = world_pos;
	p.y /= ground_flatten;
	float t = TIME * wave_speed;

	float h = height_field(p, t);

	// 法线：对高度场做中心差分
	// e 取得较大可把高频毛细波纹平滑掉，让明暗与反光主要随大波浪（涌浪）走，
	// 避免水面显得过于细碎。
	float e = 4.0;
	float hL = height_field(p + vec2(-e, 0.0), t);
	float hR = height_field(p + vec2(e, 0.0), t);
	float hD = height_field(p + vec2(0.0, -e), t);
	float hU = height_field(p + vec2(0.0, e), t);
	float nscale = wave_strength * 9.0;
	vec3 n = normalize(vec3((hL - hR) * nscale, (hD - hU) * nscale, 1.0));

	// 高度 -> 深度映射（波谷深、波峰浅）
	float height01 = clamp(h * 0.5 + 0.5, 0.0, 1.0);
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, height01);

	// Blinn-Phong 光照
	vec3 L = normalize(sun_dir);
	vec3 V = vec3(0.0, 0.0, 1.0);
	float NdotL = clamp(dot(n, L), 0.0, 1.0);
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(n, H), 0.0, 1.0);

	vec3 col = base * (0.62 + 0.38 * NdotL);
	col += foam_color.rgb * pow(NdotH, specular_power) * specular_strength * 0.6;

	// 波峰泡沫：高处 + 高频噪声打破，成斑驳泡沫
	float crest = smoothstep(0.72, 1.0, height01);
	float foam_noise = fbm(p * 0.16 + vec2(-t * 0.30, t * 0.20));
	float foam = crest * smoothstep(0.45, 0.85, foam_noise);
	col = mix(col, foam_color.rgb, foam * foam_amount);

	// 8-bit 色带抖动：用 Bayer 8x8 有序抖动把量化误差重新分配，打散「分层」色带。
	ivec2 bp = ivec2(mod(FRAGCOORD.xy, 8.0));
	float dither = (BAYER8[bp.y * 8 + bp.x] / 64.0 - 0.5) * (1.0 / 255.0);
	col += dither;
	col = clamp(col, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
